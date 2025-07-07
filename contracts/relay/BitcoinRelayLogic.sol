// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../access/AccessControlBase.sol";
import "./interfaces/IBitcoinRelay.sol";
import "bitcoin-helper-lib/contracts/libraries/BitcoinHelper.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract BitcoinRelayLogic is IBitcoinRelay,
    AccessControlBase, PausableUpgradeable, UUPSUpgradeable {

    /// @notice	Bitcoin transaction input structure following BIP-141
    /// @dev	Represents a transaction input (vin) in Bitcoin protocol.
    ///         Contains reference to previous transaction output (UTXO)
    struct TxIn {
        bytes32 hash;    // Hash of the previous transaction (txid in little-endian)
        uint32 index;    // Index of the output in the previous transaction (vout)
    }

    /// @notice	Bitcoin transaction output structure following BIP-141
    /// @dev	Represents a transaction output (vout) in Bitcoin protocol.
    ///         Contains the value and the keccak256 hash of the locking script (scriptPubKey)
    struct TxOut {
        uint64 value;            // Output value in satoshis
        bytes32 payloadHash;     // keccak256 hash of the script public key (scriptPubKey) that locks the output
    }

    /// @notice	Complete Bitcoin transaction structure following BIP-141
    /// @dev	Represents a full Bitcoin transaction with all inputs and outputs.
    ///         Follows Bitcoin protocol specification for transaction format
    struct Transaction {
        uint32 blockHeight; // Block height where transaction was included
        uint32 lockTime;    // Transaction lock time (nLockTime field)
        TxIn[] inputs;      // Array of transaction inputs (vin)
        TxOut[] outputs;    // Array of transaction outputs (vout)
    }

    /// @notice	Maximum finalization parameter for Bitcoin confirmations
    /// @dev	Roughly 3 days worth of blocks (432 blocks at ~10 minutes each).
    ///         Based on Bitcoin's consensus rules for transaction finality
    uint32 public constant MAX_FINALIZATION_PARAMETER = 432;

    /// @notice	Role identifier for authorized relayers
    /// @dev	Relayers are trusted entities that submit Bitcoin transaction proofs
    bytes32 public constant ROLE_RELAYER = keccak256("ROLE_RELAYER");

    /// @notice	Initial Bitcoin block height for the relay
    /// @dev	Sets the starting point for Bitcoin block validation.
    ///         Blocks below this height are not considered valid
    uint32 public override initialHeight;

    /// @notice	Finalization parameter for Bitcoin confirmations
    /// @dev	Number of confirmations required for transaction finality.
    ///         Must be <= MAX_FINALIZATION_PARAMETER
    uint32 public override finalizationParameter;

    /// @notice	Address of the Bitcoin light client contract
    /// @dev	External contract that provides Bitcoin block header validation.
    ///         Implements SPV (Simplified Payment Verification) protocol
    address public override btcLightClient;

    /// @notice	Mapping of transaction ID to complete transaction data
    /// @dev	Stores verified Bitcoin transactions with full input/output details.
    ///         Transaction IDs are in little-endian format (Bitcoin standard)
    mapping (bytes32 => Transaction) public transactions;

    using BitcoinHelper for bytes;
    using BitcoinHelper for bytes29;
    using TypedMemView for bytes29;
    using SafeCast for uint256;
    using SafeCast for uint64;

    modifier onlyRelayer() {
        _checkRole(ROLE_RELAYER, _msgSender());
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice	Gives a starting point for the relay
    /// @param	_admin	Default admin address
    /// @param	_governor	Governor address
    /// @param	_btcLightClient	BTC light client address
    /// @param	_initialHeight	The starting height
    /// @param	_finalizationParameter	The finalization parameter of Bitcoin
    function initialize(
        address _admin,
        address _governor,
        address _btcLightClient,
        uint32 _initialHeight,
        uint32 _finalizationParameter
    ) public initializer {
        AccessControlBase.__AccessControlBase_init(_admin, _governor);
        PausableUpgradeable.__Pausable_init();
        UUPSUpgradeable.__UUPSUpgradeable_init();

        _setRoleAdmin(ROLE_RELAYER, ROLE_GOVERNOR);

        require(_btcLightClient != address(0), "BitcoinRelay: btc light client is zero address");
        btcLightClient = _btcLightClient;
        initialHeight = _initialHeight;
        finalizationParameter = _finalizationParameter;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}

    /// @notice	Pauses the Relay
    /// @dev	Only functions with whenPaused modifier can be called
    function pauseRelay() external override onlyGovernor {
        _pause();
    }

    /// @notice	Unpauses the relay
    /// @dev	Only functions with whenNotPaused modifier can be called
    function unpauseRelay() external override onlyGovernor {
        _unpause();
    }

    /// @notice	Gets the latest submitted block height from the light client
    /// @dev	Calls the Bitcoin light client to get chain tip height
    /// @return	Latest block height from the light client
    function lastSubmittedHeight() public override view returns(uint32) {
        bytes memory result = Address.functionStaticCall(
            btcLightClient,
            abi.encodeWithSignature(
                "getChainTipHeight()"
            )
        );

        return abi.decode(result, (uint32));
    }

    /// @notice	Gets the timestamp for a specific block height
    /// @dev	Queries the Bitcoin light client for block hash and timestamp
    /// @param	_blockHeight	Block height to get timestamp for
    /// @return	Block timestamp in seconds since epoch
    function getBlockTimestamp(uint32 _blockHeight) external override view returns(uint64) {
        bytes memory result = Address.functionStaticCall(
            btcLightClient,
            abi.encodeWithSignature(
                "height2HashMap(uint32)",
                _blockHeight
            )
        );

        bytes32 blockHash = abi.decode(result, (bytes32));
        require(blockHash != bytes32(0), "BitcoinRelay: block does not exist");

        result = Address.functionStaticCall(
            btcLightClient,
            abi.encodeWithSignature(
                "getTimestamp(bytes32)",
                blockHash
            )
        );

        uint64 blockTimestamp = abi.decode(result, (uint64));
        require(blockTimestamp != 0, "BitcoinRelay: invalid block timestamp");

        return blockTimestamp;
    }

    /// @notice	Gets the block height where a specific transaction was included
    /// @dev	Returns the Bitcoin block height where the transaction was mined.
    ///         Transaction must be finalized (have sufficient confirmations) to be queryable.
    ///         Block height represents the position of the block in the Bitcoin blockchain
    /// @param	_txId	Transaction ID to get block height for (in little-endian format)
    /// @return	Block height where the transaction was included
    function getTransactionBlockHeight(bytes32 _txId) external override view returns(uint32) {
        require(transactions[_txId].blockHeight != 0, "BitcoinRelay: transaction not finalized");
        return transactions[_txId].blockHeight;
    }

    /// @notice	Gets the lock time for a specific transaction
    /// @param	_txId	Transaction ID to get lock time for
    /// @return	Transaction lock time
    function getTransactionLockTime(bytes32 _txId) external override view returns (uint32) {
        require(transactions[_txId].blockHeight != 0, "BitcoinRelay: transaction not finalized");
        return transactions[_txId].lockTime;
    }

    /// @notice	Gets the number of inputs for a specific transaction
    /// @param	_txId	Transaction ID to get input count for
    /// @return	Number of inputs in the transaction
    function getInputCount(bytes32 _txId) external override view returns (uint16) {
        Transaction storage txData = transactions[_txId];
        require(txData.blockHeight != 0, "BitcoinRelay: transaction not finalized");

        return txData.inputs.length.toUint16();
    }

    /// @notice	Gets the number of outputs for a specific transaction
    /// @param	_txId	Transaction ID to get output count for
    /// @return	Number of outputs in the transaction
    function getOutputCount(bytes32 _txId) external override view returns (uint16) {
        Transaction storage txData = transactions[_txId];
        require(txData.blockHeight != 0, "BitcoinRelay: transaction not finalized");

        return txData.outputs.length.toUint16();
    }

    /// @notice	Gets a specific input from a transaction
    /// @param	_txId	Transaction ID to get input from
    /// @param	_index	Index of the input to retrieve
    /// @return	Input transaction hash and output index
    function getTransactionInput(
        bytes32 _txId,
        uint16 _index
    ) external override view returns (bytes32, uint32) {
        Transaction storage txData = transactions[_txId];
        require(txData.blockHeight != 0, "BitcoinRelay: transaction not finalized");

        uint256 inputCount = txData.inputs.length;
        require(_index < inputCount, "BitcoinRelay: input index out of bounds");

        TxIn storage input = txData.inputs[_index];
        return (input.hash, input.index);
    }

    /// @notice	Returns a specific output from a transaction
    /// @param	_txId	Transaction ID to get output from
    /// @param	_index	Index of the output to retrieve
    /// @return	payloadHash	keccak256 hash of the script public key (scriptPubKey) that locks the output
    /// @return	value		Output value in satoshis
    function getTransactionOutput(
        bytes32 _txId,
        uint16 _index
    ) external override view returns (bytes32, uint64) {
        Transaction storage txData = transactions[_txId];
        require(txData.blockHeight != 0, "BitcoinRelay: transaction not finalized");

        uint256 outputCount = txData.outputs.length;
        require(_index < outputCount, "BitcoinRelay: output index out of bounds");

        TxOut storage output = txData.outputs[_index];
        return (output.payloadHash, output.value);
    }

    /// @notice	Finds a transaction output by script public key
    /// @dev	Searches through all outputs to find matching script hash
    /// @param	_txId	Transaction ID to search in
    /// @param	_expectedPkScript	Expected script public key to find
    /// @return	found	Whether the output was found
    /// @return	amount	Value of the found output
    /// @return	index	Index of the found output
    function findTxOutputByPkScript(
        bytes32 _txId,
        bytes calldata _expectedPkScript
    ) external override view returns (bool found, uint64 amount, uint16 index) {
        Transaction storage txData = transactions[_txId];
        require(txData.blockHeight != 0, "BitcoinRelay: transaction not finalized");

        bytes32 expectedHash = keccak256(_expectedPkScript);
        uint256 outputCount = txData.outputs.length;

        for (uint16 i = 0; i < outputCount; ++i) {
            // Only compare hashes if lengths match
            if (txData.outputs[i].payloadHash == expectedHash) {
                return (true, txData.outputs[i].value, i);
            }
        }

        return (false, 0, 0);
    }

    /// @notice	Checks if all transaction inputs come from the same script public key
    /// @dev	Validates that all input sources match the expected script hash
    /// @param	_txId	Transaction ID to check
    /// @param	_expectedPkScript	Expected script public key for all inputs
    /// @return	True if all inputs come from the expected script, false otherwise
    function areAllInputsFromPkScript(
        bytes32 _txId,
        bytes calldata _expectedPkScript
    ) external override view returns (bool) {
        Transaction storage txData = transactions[_txId];
        require(txData.blockHeight != 0, "BitcoinRelay: transaction not finalized");

        bytes32 expectedHash = keccak256(_expectedPkScript);
        uint256 inputCount = txData.inputs.length;

        for (uint256 i = 0; i < inputCount; ++i) {
            TxIn storage input = txData.inputs[i];
            Transaction storage prevTx = transactions[input.hash];

            require(prevTx.blockHeight != 0, "BitcoinRelay: referenced tx not found");
            require(input.index < prevTx.outputs.length, "BitcoinRelay: output index out of bounds");

            if (prevTx.outputs[input.index].payloadHash != expectedHash) {
                return false;
            }
        }

        return true;
    }

    /// @notice	External setter for finalizationParameter
    /// @dev	Bigger finalization parameter increases security but also increases the delay
    /// @param	_finalizationParameter	The finalization parameter of Bitcoin
    function setFinalizationParameter(uint32 _finalizationParameter) external override onlyGovernor {
        emit NewFinalizationParameter(finalizationParameter, _finalizationParameter);
        require(
            _finalizationParameter > 0 && _finalizationParameter <= MAX_FINALIZATION_PARAMETER,
            "BitcoinRelay: invalid finalization param"
        );

        finalizationParameter = _finalizationParameter;
    }

    /// @notice	Verifies and stores a Bitcoin transaction following SPV protocol
    /// @dev	Validates Merkle proof against Bitcoin block header and parses transaction data.
    ///		    Implements Simplified Payment Verification (SPV) for Bitcoin transaction validation.
    ///		    Follows Bitcoin protocol specification for transaction format and validation
    /// @param	_rawTx	Raw Bitcoin transaction bytes in network format
    /// @param	_blockHeight	Block height where transaction was included in Bitcoin blockchain
    /// @param	_merkleProof	Merkle proof for transaction inclusion (path from tx to block root)
    /// @param	_index	Index of transaction in the Merkle tree (0-based)
    /// @return	txId	Transaction ID of the verified transaction (in little-endian format)
    function verifyAndStoreTransaction(
        bytes calldata _rawTx,
        uint32 _blockHeight,
        bytes32[] calldata _merkleProof,
        uint32 _index
    ) external override whenNotPaused onlyRelayer returns (bytes32 txId) {
        require(_blockHeight >= initialHeight, "BitcoinRelay: block number below initial height");
        require(_merkleProof.length > 0, "BitcoinRelay: empty merkle proof");

        txId = BitcoinHelper.calculateTxId(_rawTx);
        require(txId != bytes32(0), "BitcoinRelay: invalid txid (zero)");

        require(
            _checkMerkleProof(txId, _blockHeight, _merkleProof, _index),
            "BitcoinRelay: transaction not finalized"
        );

        if (transactions[txId].blockHeight == 0) {
            (,  bytes29 vinView, bytes29 voutView, uint32 lockTime) = _rawTx.extractTx();
            _parseAndStoreInputs(txId, vinView);
            _parseAndStoreOutputs(txId, voutView);

            transactions[txId].blockHeight = _blockHeight;
            transactions[txId].lockTime = lockTime;

            emit TransactionSubmitted(txId, _blockHeight, lastSubmittedHeight());
        }
    }

    /// @notice	Validates Bitcoin transaction inclusion using Merkle proof
    /// @dev	Checks if transaction is included in a finalized Bitcoin block.
    ///		    Uses Merkle tree proof to verify transaction inclusion without full block data.
    ///		    Follows Bitcoin protocol specification for Merkle tree validation
    /// @param	_txId	Transaction ID in little-endian format (Bitcoin standard)
    /// @param	_blockHeight	Block height where transaction should be included
    /// @param	_merkleProof	Merkle proof path from transaction to block root (little-endian)
    /// @param	_index	Index of transaction in the Merkle tree (0-based)
    function _checkMerkleProof(
        bytes32 _txId, // In LE form
        uint32 _blockHeight,
        bytes32[] calldata _merkleProof, // In LE form
        uint32 _index
    ) internal view returns (bool) {
        // Check inclusion of the transaction
        bytes memory result = Address.functionStaticCall(
            btcLightClient,
            abi.encodeWithSignature(
                "checkTxProof(bytes32,uint32,uint32,bytes32[],uint256)",
                _txId,
                _blockHeight,
                finalizationParameter,
                _merkleProof,
                _index
            )
        );

        return abi.decode(result, (bool));
    }

    /// @notice	Parses and stores Bitcoin transaction inputs (vin)
    /// @dev	Extracts input data following Bitcoin protocol specification.
    ///		    Marks referenced UTXOs as spent and tracks spending block height.
    ///		    Handles coinbase and regular transaction inputs
    /// @param	_txId	Transaction ID to store inputs for
    /// @param	_vinView	Transaction input view from Bitcoin helper library
    function _parseAndStoreInputs(
        bytes32 _txId,
        bytes29 _vinView
    ) internal {
        uint16 inputCount = _vinView.indexCompactInt(0).toUint16();
        require(inputCount != 0, "BitcoinRelay: vin is empty");

        for (uint16 i = 0; i < inputCount; ++i) {
            (bytes32 txId, uint256 index) = _vinView.extractOutpoint(i);

            transactions[_txId].inputs.push(TxIn({
                hash: txId,
                index: uint32(index)
            }));
        }
    }

    /// @notice	Parses and stores Bitcoin transaction outputs (vout)
    /// @dev	Extracts output data following Bitcoin protocol specification.
    ///		    Stores the keccak256 hash of the script public key (scriptPubKey) for each output
    ///		    Handles script public keys (scriptPubKey) and output values in satoshis.
    ///		    Supports OP_RETURN outputs and standard payment scripts
    /// @param	_txId	Transaction ID to store outputs for
    /// @param	_voutView	Transaction output view from Bitcoin helper library
    function _parseAndStoreOutputs(
        bytes32 _txId,
        bytes29 _voutView
    ) internal {
        uint16 outputCount = _voutView.indexCompactInt(0).toUint16();
        require(outputCount != 0, "vout is empty");

        for (uint16 i = 0; i < outputCount; ++i) {
            bytes29 outputView = _voutView.indexVout(i);
            bytes29 scriptPubkeyWithLength = outputView.scriptPubkeyWithLength();
            bytes29 arbitraryData = scriptPubkeyWithLength.opReturnPayload();

            uint64 value;
            bytes memory payload;
            if(arbitraryData == TypedMemView.NULL) {
                value = outputView.value();
                payload = outputView.scriptPubkey().clone();
            } else {
                payload = arbitraryData.clone();
            }

            transactions[_txId].outputs.push(TxOut({
                value: value,
                payloadHash: keccak256(payload)
            }));
        }
    }
}
