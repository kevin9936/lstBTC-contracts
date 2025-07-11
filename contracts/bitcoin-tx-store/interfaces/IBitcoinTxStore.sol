// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @title IBitcoinTxStore
 * @dev Interface for the Bitcoin transaction store contract
 *
 * This interface defines the functions and events for the Bitcoin transaction store,
 * which provides a bridge between the native chain and Bitcoin blockchain.
 * The transaction store allows the protocol to:
 * - Verify and store Bitcoin transactions with merkle proofs
 * - Query Bitcoin transaction details and block information
 * - Validate transaction inputs and outputs
 * - Manage finality parameters for Bitcoin confirmations
 *
 * The transaction store acts as a light client for Bitcoin, enabling cross-chain
 * operations in the lstBTC protocol.
 */
interface IBitcoinTxStore {
    /// @notice Emitted when the finalization parameter is updated
    /// @param oldFinalizationParameter Previous finalization parameter
    /// @param newFinalizationParameter New finalization parameter
    event NewFinalizationParameter (
        uint32 oldFinalizationParameter,
        uint32 newFinalizationParameter
    );

    /// @notice Emitted when a Bitcoin transaction is submitted and verified
    /// @param txId Bitcoin transaction ID
    /// @param blockNumber Bitcoin block number containing the transaction
    /// @param currentBlockNumber Current Bitcoin block number at submission
    event TransactionSubmitted(
        bytes32 indexed txId,
        uint32 indexed blockNumber,
        uint32 currentBlockNumber
    );

    /// @notice Returns the initial Bitcoin block height when the transaction store was deployed
    /// @return Initial block height
    function initialHeight() external view returns(uint32);

    /// @notice Returns the last Bitcoin block height that was submitted to the transaction store
    /// @return Last submitted block height
    function lastSubmittedHeight() external view returns(uint32);

    /// @notice Returns the current finalization parameter (number of confirmations required)
    /// @return Finalization parameter
    function finalizationParameter() external view returns(uint32);

    /// @notice Returns the address of the Bitcoin light client contract
    /// @return Bitcoin light client address
    function btcLightClient() external view returns(address);

    /// @notice Returns the timestamp of a Bitcoin block
    /// @param _blockNumber Bitcoin block number
    /// @return Block timestamp
    function getBlockTimestamp(uint32 _blockNumber) external view returns(uint64);

    /// @notice Returns the block height where a Bitcoin transaction was included
    /// @param _txId Bitcoin transaction ID (in little-endian format)
    /// @return Block height where the transaction was included
    function getTransactionBlockHeight(bytes32 _txId) external view returns(uint32);

    /// @notice Returns the lock time of a Bitcoin transaction
    /// @param _txId Bitcoin transaction ID
    /// @return Transaction lock time
    function getTransactionLockTime(bytes32 _txId) external view returns(uint32);

    /// @notice Returns the number of inputs in a Bitcoin transaction
    /// @param _txId Bitcoin transaction ID
    /// @return Number of transaction inputs
    function getInputCount(bytes32 _txId) external view returns (uint16);

    /// @notice Returns the number of outputs in a Bitcoin transaction
    /// @param _txId Bitcoin transaction ID
    /// @return Number of transaction outputs
    function getOutputCount(bytes32 _txId) external view returns (uint16);

    /// @notice Returns a specific input from a Bitcoin transaction
    /// @param _txId Bitcoin transaction ID
    /// @param _index Index of the input to retrieve
    /// @return prevTxId Previous transaction ID (outpoint)
    /// @return prevTxIndex Previous transaction output index
    function getTransactionInput(
        bytes32 _txId,
        uint16 _index
    ) external view returns (bytes32, uint32);

    /// @notice Returns a specific output from a Bitcoin transaction
    /// @param _txId Bitcoin transaction ID
    /// @param _index Index of the output to retrieve
    /// @return payloadHash keccak256 hash of the script public key (scriptPubKey) that locks the output
    /// @return amount Output value in satoshis
    function getTransactionOutput(
        bytes32 _txId,
        uint16 _index
    ) external view returns (bytes32 payloadHash, uint64 amount);

    /// @notice Finds a transaction output by its public key script
    /// @param _txId Bitcoin transaction ID
    /// @param _expectedPkScript Expected public key script to search for
    /// @return found Whether the output was found
    /// @return amount Amount of the found output (in satoshis)
    /// @return index Index of the found output
    function findTxOutputByPkScript(
        bytes32 _txId,
        bytes calldata _expectedPkScript
    ) external view returns (bool found, uint64 amount, uint16 index);

    /// @notice Checks if all inputs of a transaction come from a specific public key script
    /// @param _txId Bitcoin transaction ID
    /// @param _expectedPkScript Expected public key script for all inputs
    /// @return Whether all inputs come from the expected script
    function areAllInputsFromPkScript(
        bytes32 _txId,
        bytes calldata _expectedPkScript
    ) external view returns (bool);

    /// @notice Verifies and stores a Bitcoin transaction with merkle proof
    /// @dev Only callable by authorized transaction submitters
    /// @param _rawTx Raw Bitcoin transaction bytes
    /// @param _blockNumber Bitcoin block number containing the transaction
    /// @param _merkleProof Merkle proof for transaction inclusion
    /// @param _index Index of the transaction in the block
    /// @return txId Bitcoin transaction ID
    function verifyAndStoreTransaction(
        bytes calldata _rawTx,
        uint32 _blockNumber,
        bytes32[] calldata _merkleProof,
        uint32 _index
    ) external returns (bytes32);

    /// @notice Pauses the transaction store operations
    /// @dev Only callable by admin
    function pauseTxStore() external;

    /// @notice Unpauses the transaction store operations
    /// @dev Only callable by admin
    function unpauseTxStore() external;

    /// @notice Sets the finalization parameter (number of confirmations required)
    /// @dev Only callable by admin
    /// @param _finalizationParameter New finalization parameter
    function setFinalizationParameter(uint32 _finalizationParameter) external;
}
