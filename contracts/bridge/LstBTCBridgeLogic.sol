// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./LstBTCBridgeStorage.sol";
import "./interfaces/ILstBTCBridge.sol";
import "../token/interfaces/ILstBTC.sol";
import "../access/AccessControlBase.sol";
import "../libraries/PegRequestHelper.sol";
import "../nav/interfaces/INavProvider.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../configuration/interfaces/IConfigRegistry.sol";
import "../whitelist/interfaces/IWhitelistRegistry.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title LstBTCBridgeLogic
 * @dev Main bridge contract for lstBTC protocol that handles cross-chain Bitcoin transfers
 *
 * This contract manages the core bridge functionality including:
 * - Peg-in requests (Bitcoin to lstBTC)
 * - Peg-out requests (lstBTC to Bitcoin)
 * - Transaction proof verification
 * - Batch processing of requests
 * - Fee management and treasury distribution
 * - Yield accrual and debt management
 *
 * The contract integrates with multiple components:
 * - BitcoinRelay for transaction verification
 * - WhitelistRegistry for address validation
 * - ConfigRegistry for fee configuration
 * - NavProvider for exchange rate management
 * - LstBTC token for minting/burning
 */
contract LstBTCBridgeLogic is ILstBTCBridge, LstBTCBridgeStorage,
    AccessControlBase, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    /// @notice Thrown when public key script array is empty
    error EmptyPkScriptArray();

    /// @notice Thrown when no whitelisted public key script is found
    error WhitelistedPkScriptNotFound();

    /// @notice Thrown when transaction has already been processed
    error DuplicateTransaction(bytes32 txId);

    /// @notice Thrown when input public key scripts do not match expected values
    error InputPkScriptsMismatch(bytes32 txId, bytes[] pkScripts);

    /// @notice Thrown when output public key scripts do not match expected values
    error OutputPkScriptsMismatch(bytes32 txId, bytes[] pkScripts);

    /// @notice Thrown when transaction has non-zero lock time
    error NonZeroLockTime(bytes32 txId);

    /// @notice Thrown when batch has no requests to process
    error BatchRequestsEmpty();

    /// @notice Thrown when batch request length exceeds bounds
    error BatchRequestLengthOutOfBounds(uint256 requestLength);

    /// @notice Thrown when batch is not found for the custodian
    error BatchNotFound(uint32 custodianId);

    /// @notice Thrown when a pending batch already exists for the custodian
    error PendingBatchFound(uint32 custodianId, uint32 batchId);

    /// @notice Thrown when no peg-in requests to settle in the batch
    error NoPegInToSettle(uint32 custodianId, uint32 batchId);

    /// @notice Thrown when no peg-out requests to settle in the batch
    error NoPegOutToSettle(uint32 custodianId, uint32 batchId);

    /// @notice Thrown when request has not reached finality
    error RequestNotFinalized(uint256 requestId, uint64 finalityHeight);

    /// @notice Thrown when request status does not match expected status
    error InvalidRequestStatus(uint256 requestId, PegStatus expectedStatus, PegStatus actualStatus);

    /// @notice Thrown when request custodian does not match expected custodian
    error InvalidRequestCustodian(uint256 requestId, uint32 expectedCustodian, uint32 actualCustodian);

    /// @notice Thrown when settlement amount does not match expected amount
    error InvalidSettlementAmount(uint32 custodianId, uint32 batchId, uint64 expectedAmount, uint64 actualAmount);

    // Role for authorized relayers who can submit transaction proofs
    bytes32 public constant ROLE_RELAYER = keccak256("ROLE_RELAYER");

    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using PegRequestHelper for PegRequest;

    /// @notice Restricts function access to authorized relayers only
    /// @dev Uses role-based access control to ensure only trusted relayers can submit proofs
    modifier onlyRelayer() {
        _checkRole(ROLE_RELAYER, _msgSender());
        _;
    }

    /// @notice Restricts function access to lstBTC token contract only
    /// @dev Ensures only the lstBTC token contract can call certain functions
    modifier onlyLstBTC() {
        if (lstBTC != _msgSender()) { revert Unauthorized(_msgSender()); }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the bridge contract with admin and governor roles
    /// @dev Sets up access control and initializes all upgradeable contracts
    /// @param _admin Default admin address with full control
    /// @param _governor Governor address for operational decisions
    function initialize(
        address _admin,
        address _governor
    ) public initializer {
        AccessControlBase.__AccessControlBase_init(_admin, _governor);
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();
        UUPSUpgradeable.__UUPSUpgradeable_init();

        _setRoleAdmin(ROLE_RELAYER, ROLE_GOVERNOR);
    }

    /// @notice Authorizes contract upgrades
    /// @dev Only governor can upgrade the contract implementation
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}

    /// @notice Pauses all bridge operations
    /// @dev Only governor can pause the bridge in emergency situations
    function pauseBridge() external onlyGovernor {
        _pause();
    }

    /// @notice Unpauses bridge operations
    /// @dev Only governor can unpause the bridge after emergency is resolved
    function unpauseBridge() external onlyGovernor {
        _unpause();
    }

    /// @notice Updates the configuration registry address
    /// @dev Only governor can update the config registry
    /// @param _configRegistry New configuration registry address
    function setConfigRegistry(address _configRegistry) external onlyGovernor {
        if (_configRegistry == configRegistry) { return; }

        emit ConfigRegistryUpdated(configRegistry, _configRegistry);
        configRegistry = _configRegistry;
    }

    /// @notice Updates the whitelist registry address
    /// @dev Only governor can update the whitelist registry
    /// @param _whitelistRegistry New whitelist registry address
    function setWhitelistRegistry(address _whitelistRegistry) external onlyGovernor {
        if (_whitelistRegistry == whitelistRegistry) { return; }

        emit WhitelistRegistryUpdated(whitelistRegistry, _whitelistRegistry);
        whitelistRegistry = _whitelistRegistry;
    }

    /// @notice Updates the NAV provider address
    /// @dev Only governor can update the NAV provider
    /// @param _navProvider New NAV provider address
    function setNavProvider(address _navProvider) external onlyGovernor {
        if (_navProvider == navProvider) { return; }

        emit NavProviderUpdated(navProvider, _navProvider);
        navProvider = _navProvider;
    }

    /// @notice Updates the Bitcoin relay address
    /// @dev Only governor can update the Bitcoin relay
    /// @param _bitcoinRelay New Bitcoin relay address
    function setBitcoinRelay(address _bitcoinRelay) external onlyGovernor {
        if (_bitcoinRelay == bitcoinRelay) { return; }

        emit BitcoinRelayUpdated(bitcoinRelay, _bitcoinRelay);
        bitcoinRelay = _bitcoinRelay;
    }

    /// @notice Updates the lstBTC token address
    /// @dev Only governor can update the lstBTC token contract
    /// @param _lstBTC New lstBTC token address
    function setLstBTC(address _lstBTC) external onlyGovernor {
        if (_lstBTC == lstBTC) { return; }

        emit LstBTCUpdated(lstBTC, _lstBTC);
        lstBTC = _lstBTC;
    }

    /// @notice Submits a Bitcoin transaction proof for processing
    /// @dev This is the main entry point for processing Bitcoin transactions.
    /// Only authorized relayers can submit proofs.
    /// Validates transaction, analyzes transfer type, and routes to appropriate handler.
    /// Both _fromPkScripts and _toPkScripts contain deduplicated pkScripts from transaction parsing.
    /// When _fromPkScripts has size 1 and represents a whitelisted pkScript, if outputs contain change,
    /// the change pkScript must be placed as the last element in _toPkScripts array
    /// @param _rawTx Raw Bitcoin transaction data
    /// @param _blockHeight Bitcoin block height containing the transaction
    /// @param _merkleProof Merkle proof for transaction inclusion
    /// @param _index Transaction index in the block
    /// @param _fromPkScripts Deduplicated input pkScripts from transaction inputs
    /// @param _toPkScripts Deduplicated output pkScripts from transaction outputs (change pkScript as last element if exists)
    function submitTransactionProof(
        bytes calldata _rawTx,
        uint32 _blockHeight,
        bytes32[] calldata _merkleProof,
        uint32 _index,
        bytes[] calldata _fromPkScripts,
        bytes[] calldata _toPkScripts
    ) external nonReentrant onlyRelayer {
        // Phase 1: Input Validation
        // Step 1: Ensure pkScript arrays are not empty
        if (_fromPkScripts.length == 0 || _toPkScripts.length == 0) {
            revert EmptyPkScriptArray();
        }

        // Step 2: Verify at least one output pkScript is whitelisted
        // This ensures the transaction involves authorized addresses
        if (!IWhitelistRegistry(whitelistRegistry).containsWhitelistedEntry(_toPkScripts)) {
            revert WhitelistedPkScriptNotFound();
        }

        // Phase 2: Transaction Verification and Storage
        // Step 3: Verify transaction inclusion in blockchain and store transaction data
        // This validates the merkle proof and stores transaction for future reference
        bytes32 txId = IBitcoinRelay(bitcoinRelay).verifyAndStoreTransaction(
            _rawTx,
            _blockHeight,
            _merkleProof,
            _index
        );

        // Phase 3: Transaction Analysis and Validation
        // Step 4: Analyze transaction to determine transfer type and extract key information
        // This validates transaction structure and identifies the type of cross-chain operation
        (
            uint32 custodianId,
            TransferType transferType,
            uint64 outputAmount
        ) = PegRequestHelper.analyzeBTCTransfer(
            ILstBTCBridge(this),
            txId,
            _fromPkScripts,
            _toPkScripts
        );

        // Step 5: Skip processing if transfer type is unknown
        if (transferType == TransferType.Unknown) { return; }

        // Step 6: Verify transaction has no lock time (immediate execution required)
        // Lock time transactions are not supported for cross-chain operations
        uint64 lockTime = IBitcoinRelay(bitcoinRelay).getTransactionLockTime(txId);
        if (lockTime != 0) {
            revert NonZeroLockTime(txId);
        }

        // Step 7: Check if transaction has already been processed
        // Prevents double-processing of the same transaction
        if (provenTransactions[txId]) {
            revert DuplicateTransaction(txId);
        }
        provenTransactions[txId] = true;

        // Phase 4: Transaction Processing
        // Step 8: Route to appropriate handler based on transfer type
        if (transferType == TransferType.PegInDeposited) {
            // Handle Bitcoin deposit for peg-in operation
            _createPegInRequest(
                txId,
                _blockHeight,
                _fromPkScripts[0],
                _toPkScripts[0],
                outputAmount,
                custodianId
            );

        } else if (transferType == TransferType.PegInRefunded) {
            // Handle refund for rejected peg-in request
            _settleRejectedPegInBatch(
                txId,
                outputAmount,
                custodianId
            );

        } else if (transferType == TransferType.PegOutPaid) {
            // Handle Bitcoin payment for approved peg-out request
            _settleProcessedPegOutBatch(
                txId,
                outputAmount,
                custodianId
            );

        } else if (transferType == TransferType.YieldReceived) {
            // Handle yield distribution to custodian
            INavProvider(navProvider).accrueYield(
                txId,
                outputAmount,
                custodianId
            );

        } else if (transferType == TransferType.Borrowed) {
            // Handle borrowing operation
            _borrow(
                txId,
                outputAmount,
                custodianId
            );

        } else if (transferType == TransferType.Repaid) {
            // Handle repayment operation
            _repay(
                txId,
                outputAmount,
                custodianId
            );
        }
    }

    /// @notice Handles lstBTC token transfer events
    /// @dev Called by lstBTC token contract when transfers occur.
    /// Analyzes transfer type and routes to appropriate handler
    /// @param _from Address sending lstBTC tokens
    /// @param _to Address receiving lstBTC tokens
    /// @param _amount Amount of lstBTC tokens transferred
    function onLstBTCTransfer(
        address _from,
        address _to,
        uint64 _amount
    ) external onlyLstBTC {
        (
            uint32 custodianId,
            TransferType transferType
        ) = PegRequestHelper.analyzeWrappedBTCTransfer(
            ILstBTCBridge(this),
            _from,
            _to
        );

        if (transferType == TransferType.Unknown) { return; }

        if (transferType == TransferType.PegOutDeposited) {
            _createPegOutRequest(_from, _to, _amount, custodianId);

        } else if (transferType == TransferType.PegOutRefunded) {
            _settleRejectedPegOutBatch(_amount, custodianId);

        } else if (transferType == TransferType.PegInPaid) {
            _settleProcessedPegInBatch(_amount, custodianId);
        }
    }

    /// @notice Processes a batch of peg-in and peg-out requests
    /// @dev Only whitelisted operators can process batches.
    /// Mints lstBTC for approved peg-in requests and burns lstBTC for approved peg-out requests
    /// @param pegInIds Array of peg-in request IDs to process
    /// @param pegOutIds Array of peg-out request IDs to process
    function processPegRequestBatch(
        uint256[] calldata pegInIds,
        uint256[] calldata pegOutIds
    ) external nonReentrant whenNotPaused {
        _requireValidBatchParams(pegInIds, pegOutIds);

        uint32 custodianId = _requireWhitelistedOperatorNoPendingBatch();

        uint32 batchId = _allocBatchId();

        uint64 pendingPayBTCAmount = _processPegOutBatch(pegOutIds, custodianId, batchId);
        uint64 pendingPayWrappedAmount = _processPegInBatch(pegInIds, custodianId, batchId);

        if (pegInIds.length == 0) {
            batches[batchId].isPegInSettled = true;
        } else {
            batches[batchId].pegInIds = pegInIds;
        }

        if (pegOutIds.length == 0) {
            batches[batchId].isPegOutSettled = true;
        } else {
            batches[batchId].pegOutIds = pegOutIds;
        }

        custodianDatas[custodianId].batches.push(batchId);

        emit BatchProcessed(
            batchId,
            pegInIds,
            pegOutIds,
            pendingPayWrappedAmount,
            pendingPayBTCAmount
        );
    }

    /// @notice Rejects a batch of peg-in and peg-out requests
    /// @dev Only whitelisted operators can reject batches.
    /// Refunds Bitcoin for rejected peg-in requests and lstBTC for rejected peg-out requests
    /// @param pegInIds Array of peg-in request IDs to reject
    /// @param pegOutIds Array of peg-out request IDs to reject
    function rejectPegRequestBatch(
        uint256[] calldata pegInIds,
        uint256[] calldata pegOutIds
    ) external whenNotPaused {
        _requireValidBatchParams(pegInIds, pegOutIds);

        uint32 custodianId = _requireWhitelistedOperatorNoPendingBatch();
        uint32 batchId = _allocBatchId();

        uint64 pendingRefundBTC = _rejectPegInBatch(pegInIds, custodianId, batchId);
        uint64 pendingRefundWrappedBTC = _rejectPegOutBatch(pegOutIds, custodianId, batchId);

        if (pegInIds.length == 0) {
            batches[batchId].isPegInSettled = true;
        } else {
            batches[batchId].pegInIds = pegInIds;
        }

        if (pegOutIds.length == 0) {
            batches[batchId].isPegOutSettled = true;
        } else {
            batches[batchId].pegOutIds = pegOutIds;
        }

        custodianDatas[custodianId].batches.push(batchId);

        emit BatchRejected(
            batchId,
            pegInIds,
            pegOutIds,
            pendingRefundBTC,
            pendingRefundWrappedBTC
        );
    }

    /// @notice Allows users to claim accumulated fees
    /// @dev Transfers lstBTC fees to the caller and resets their claimable amount.
    /// Only callable by users who have accumulated fees
    function claimFees() external nonReentrant {
        uint64 amount = claimableFees[_msgSender()];
        if (amount == 0) { return; }

        claimableFees[_msgSender()] = 0;
        IERC20(lstBTC).safeTransfer(_msgSender(), amount);

        emit FeesClaimed(_msgSender(), amount);
    }

    /// @notice Retrieves batch information by batch ID
    /// @param _batchId The batch ID to query
    /// @return pegInIds Array of peg-in request IDs in the batch
    /// @return pegOutIds Array of peg-out request IDs in the batch
    /// @return isPegInSettled Whether peg-in requests in the batch have been settled
    /// @return isPegOutSettled Whether peg-out requests in the batch have been settled
    function getBatch(
        uint32 _batchId
    ) public view returns (
        uint256[] memory pegInIds,
        uint256[] memory pegOutIds,
        bool isPegInSettled,
        bool isPegOutSettled
    ) {
        Batch storage batch = batches[_batchId];

        pegInIds = batch.pegInIds;
        pegOutIds = batch.pegOutIds;
        isPegInSettled = batch.isPegInSettled;
        isPegOutSettled = batch.isPegOutSettled;
    }

    /// @notice Retrieves all batch IDs for a specific custodian
    /// @param _custodianId The custodian ID to query
    /// @return Array of batch IDs associated with the custodian
    function getCustodianBatchIds(
        uint32 _custodianId
    ) external view returns (uint32[] memory) {
        return custodianDatas[_custodianId].batches;
    }

    /// @notice Retrieves the latest batch ID for a specific custodian
    /// @param _custodianId The custodian ID to query
    /// @return latestBatchId The most recent batch ID for the custodian, or 0 if none exists
    function getCustodianLatestBatchId(
        uint32 _custodianId
    ) public view returns (uint32 latestBatchId) {
        uint32[] storage batchIds = custodianDatas[_custodianId].batches;
        if (batchIds.length == 0) { return 0; }

        latestBatchId = batchIds[batchIds.length-1];
    }

    /// @notice Retrieves the latest batch information for a specific custodian
    /// @dev This function provides a convenient way to access the most recent batch
    /// for a custodian without needing to first get the batch ID. It returns the
    /// complete batch information including all peg-in and peg-out request IDs
    /// and their settlement status. If no batch exists for the custodian,
    /// all return values will be empty/zero.
    ///
    /// The function first retrieves the latest batch ID using getCustodianLatestBatchId,
    /// then fetches the complete batch data using getBatch. This is useful for
    /// monitoring custodian activity and checking batch settlement status.
    ///
    /// @param _custodianId The unique identifier of the custodian to query
    /// @return latestBatchId The most recent batch ID for the custodian, or 0 if none exists
    /// @return pegInIds Array of peg-in request IDs in the latest batch
    /// @return pegOutIds Array of peg-out request IDs in the latest batch
    /// @return isPegInSettled Whether all peg-in requests in the batch have been settled
    /// @return isPegOutSettled Whether all peg-out requests in the batch have been settled
    function getCustodianLatestBatch(
        uint32 _custodianId
    ) external view returns (
        uint32 latestBatchId,
        uint256[] memory pegInIds,
        uint256[] memory pegOutIds,
        bool isPegInSettled,
        bool isPegOutSettled
    ) {
        latestBatchId = getCustodianLatestBatchId(_custodianId);

        if (latestBatchId != 0) {
            (
                pegInIds,
                pegOutIds,
                isPegInSettled,
                isPegOutSettled
            ) = getBatch(latestBatchId);
        }
    }

    /// @notice Retrieves the current debt amount for a specific custodian
    /// @param _custodianId The custodian ID to query
    /// @return debt The amount of debt associated with the custodian
    function getCustodianDebt(
        uint32 _custodianId
    ) external view returns (uint64 debt) {
        return custodianDatas[_custodianId].debt;
    }

    /// @notice Allocates a new unique request ID
    /// @dev Uses a counter and keccak256 hash to generate unique IDs
    /// @return New unique request ID
    function _allocRequestId() internal returns(uint256) {
        return ++requestIdCounter;
    }

    /// @notice Allocates a new unique batch ID
    /// @dev Uses a simple incrementing counter
    /// @return New unique batch ID
    function _allocBatchId() internal returns(uint32) {
        return ++batchIdCounter;
    }

    /// @notice Validates that the caller is a whitelisted operator with no pending batches
    /// @dev Checks whitelist entry and ensures no pending batches exist for the custodian
    /// @return custodianId ID of the custodian if validation passes
    function _requireWhitelistedOperatorNoPendingBatch() internal view returns (uint32) {
        (
            uint32 custodianId,
            uint8 usage
        ) = IWhitelistRegistry(whitelistRegistry).getWhitelistEntry(
            abi.encodePacked(_msgSender())
        );

        if (usage != AddressUsage.OPERATIONS) {
            revert Unauthorized(_msgSender());
        }

        uint32 latestBatchId = getCustodianLatestBatchId(custodianId);
        if (latestBatchId != 0) {
            Batch storage batch = batches[latestBatchId];

            if (!batch.isPegInSettled || !batch.isPegOutSettled) {
                revert PendingBatchFound(custodianId, latestBatchId);
            }
        }

        return custodianId;
    }

    /// @notice Validates batch parameters for processing
    /// @dev Ensures at least one request exists and arrays are within bounds
    /// @param pegInIds Array of peg-in request IDs
    /// @param pegOutIds Array of peg-out request IDs
    function _requireValidBatchParams(
        uint256[] calldata pegInIds,
        uint256[] calldata pegOutIds
    ) internal pure {
        if (pegInIds.length == 0 && pegOutIds.length == 0) {
            revert BatchRequestsEmpty();
        }

        if (pegInIds.length > type(uint16).max) {
            revert BatchRequestLengthOutOfBounds(pegInIds.length);
        }

        if (pegOutIds.length > type(uint16).max) {
            revert BatchRequestLengthOutOfBounds(pegOutIds.length);
        }
    }

    /// @notice Creates a new peg-in request from Bitcoin deposit
    /// @dev Allocates request ID, initializes request, and stages fee recipients
    /// @param _txId Bitcoin transaction ID
    /// @param _blockHeight Bitcoin block height
    /// @param _fromPkScript Input script public key
    /// @param _toPkScript Output script public key
    /// @param _amount Amount of Bitcoin deposited (in satoshis)
    /// @param _custodianId ID of the custodian handling the request
    /// @return requestId ID of the created peg-in request
    function _createPegInRequest(
        bytes32 _txId,
        uint32 _blockHeight,
        bytes memory _fromPkScript,
        bytes memory _toPkScript,
        uint64 _amount,
        uint32 _custodianId
    ) internal returns (uint256 requestId) {
        requestId = _allocRequestId();
        PegRequest storage request = pegInRequests[requestId];

        (
            uint64 exchangeRate,
            address[] memory recipients,
            uint64[] memory recipientAmounts
        ) = request.initializePegInRequest(
            ILstBTCBridge(this),
            _blockHeight,
            _amount,
            _custodianId
        );

        emit PegInCreated(
            requestId,
            _custodianId,
            _txId,
            _fromPkScript,
            _toPkScript,
            _amount,
            exchangeRate,
            recipients,
            recipientAmounts,
            request.netAmount
        );
    }

    /// @notice Settles a processed peg-in batch by paying out lstBTC
    /// @dev Calls internal settlement function and emits batch paid event
    /// @param _amount Total amount to pay out (in lstBTC)
    /// @param _custodianId ID of the custodian handling the batch
    function _settleProcessedPegInBatch(
        uint64 _amount,
        uint32 _custodianId
    ) internal {
        (
            uint32 latestBatchId,
            uint256[] memory settledRequestIds,
            bool isBatchCompleted
        ) = _settleLatestPegInBatch(
            _custodianId,
            _amount,
            PegStatus.PendingPayout
        );

        emit PegInBatchPaid(
            latestBatchId,
            settledRequestIds,
            _amount,
            isBatchCompleted
        );
    }

    /// @notice Settles a rejected peg-in batch by refunding Bitcoin
    /// @dev Calls internal settlement function and emits batch refunded event
    /// @param _txId Bitcoin transaction ID for the refund
    /// @param _amount Total amount to refund (in satoshis)
    /// @param _custodianId ID of the custodian handling the batch
    function _settleRejectedPegInBatch(
        bytes32 _txId,
        uint64 _amount,
        uint32 _custodianId
    ) internal {
        (
            uint32 latestBatchId,
            uint256[] memory settledRequestIds,
            bool isBatchCompleted
        ) = _settleLatestPegInBatch(
            _custodianId,
            _amount,
            PegStatus.PendingRefund
        );

        emit PegInBatchRefunded(
            latestBatchId,
            _txId,
            settledRequestIds,
            _amount,
            isBatchCompleted
        );
    }

    /// @notice Settles the latest peg-in batch for a custodian
    /// @dev Processes all peg-in requests in the batch and marks batch as settled
    /// @param _custodianId ID of the custodian
    /// @param _amount Expected total settlement amount
    /// @param _status Status to set for the requests (PendingPayout or PendingRefund)
    /// @return latestBatchId ID of the batch being settled
    /// @return settledIds Array of request IDs that were settled
    /// @return isCompleted Whether the batch is fully completed
    function _settleLatestPegInBatch(
        uint32 _custodianId,
        uint64 _amount,
        PegStatus _status
    ) internal returns(
        uint32 latestBatchId,
        uint256[] memory settledIds,
        bool isCompleted
    ) {
        latestBatchId = getCustodianLatestBatchId(_custodianId);
        if (latestBatchId == 0) {
            revert BatchNotFound(_custodianId);
        }

        Batch storage batch = batches[latestBatchId];
        if (batch.isPegInSettled) {
            revert NoPegInToSettle(_custodianId, latestBatchId);
        }

        uint64 settledAmount;

        uint16 pegInCount = batch.pegInIds.length.toUint16();
        for (uint16 i = 0; i < pegInCount; ++i) {
            settledAmount += pegInRequests[batch.pegInIds[i]].settlePegInRequest(_custodianId, _status);
        }

        if (settledAmount != _amount) {
            revert InvalidSettlementAmount(_custodianId, latestBatchId, settledAmount, _amount);
        }

        batch.isPegInSettled = true;
        settledIds = batch.pegInIds;
        isCompleted = batch.isPegOutSettled;
    }


    /// @notice Creates a new peg-out request for lstBTC redemption
    /// @dev Allocates request ID, initializes request, and stages fee recipients
    /// @param _from Address sending lstBTC tokens
    /// @param _to Address receiving lstBTC tokens
    /// @param _amount Amount of lstBTC to redeem (in satoshis)
    /// @param _custodianId ID of the custodian handling the request
    /// @return requestId ID of the created peg-out request
    function _createPegOutRequest(
        address _from,
        address _to,
        uint64 _amount,
        uint32 _custodianId
    ) internal returns (uint256 requestId) {
        requestId = _allocRequestId();
        PegRequest storage request = pegOutRequests[requestId];

        (
            uint64 exchangeRate,
            address[] memory recipients,
            uint64[] memory recipientAmounts
        ) = request.initializePegOutRequest(
            ILstBTCBridge(this),
            _amount,
            _custodianId
        );

        emit PegOutCreated(
            requestId,
            _custodianId,
            _from,
            _to,
            _amount,
            exchangeRate,
            recipients,
            recipientAmounts,
            request.netAmount
        );
    }

    /// @notice Settles a processed peg-out batch by paying out Bitcoin
    /// @dev Calls internal settlement function and emits batch paid event
    /// @param _txId Bitcoin transaction ID for the payout
    /// @param _amount Total amount to pay out (in satoshis)
    /// @param _custodianId ID of the custodian handling the batch
    function _settleProcessedPegOutBatch(
        bytes32 _txId,
        uint64 _amount,
        uint32 _custodianId
    ) internal {
        (
            uint32 latestBatchId,
            uint256[] memory settledRequestIds,
            bool isBatchCompleted
        ) = _settleLatestPegOutBatch(
            _custodianId,
            _amount,
            PegStatus.PendingPayout
        );

        emit PegOutBatchPaid(
            latestBatchId,
            _txId,
            settledRequestIds,
            _amount,
            isBatchCompleted
        );
    }

    /// @notice Settles a rejected peg-out batch by refunding lstBTC
    /// @dev Calls internal settlement function and emits batch refunded event
    /// @param _amount Total amount to refund (in lstBTC)
    /// @param _custodianId ID of the custodian handling the batch
    function _settleRejectedPegOutBatch(
        uint64 _amount,
        uint32 _custodianId
    ) internal {
        (
            uint32 latestBatchId,
            uint256[] memory settledRequestIds,
            bool isBatchCompleted
        ) = _settleLatestPegOutBatch(
            _custodianId,
            _amount,
            PegStatus.PendingRefund
        );

        emit PegOutBatchRefunded(
            latestBatchId,
            settledRequestIds,
            _amount,
            isBatchCompleted
        );
    }

    /// @notice Settles the latest peg-out batch for a custodian
    /// @dev Processes all peg-out requests in the batch and marks batch as settled
    /// @param _custodianId ID of the custodian
    /// @param _amount Expected total settlement amount
    /// @param _status Status to set for the requests (PendingPayout or PendingRefund)
    /// @return latestBatchId ID of the batch being settled
    /// @return settledIds Array of request IDs that were settled
    /// @return isCompleted Whether the batch is fully completed
    function _settleLatestPegOutBatch(
        uint32 _custodianId,
        uint64 _amount,
        PegStatus _status
    ) internal returns (
        uint32 latestBatchId,
        uint256[] memory settledIds,
        bool isCompleted
    ) {
        latestBatchId = getCustodianLatestBatchId(_custodianId);
        if (latestBatchId == 0) {
            revert BatchNotFound(_custodianId);
        }

        Batch storage batch = batches[latestBatchId];
        if (batch.isPegOutSettled) {
            revert NoPegOutToSettle(_custodianId, latestBatchId);
        }

        uint64 settledAmount;

        uint16 pegOutCount = batch.pegOutIds.length.toUint16();
        for (uint16 i = 0; i < pegOutCount; ++i) {
            settledAmount += pegOutRequests[batch.pegOutIds[i]].settlePegOutRequest(_custodianId, _status);
        }

        if (settledAmount != _amount) {
            revert InvalidSettlementAmount(_custodianId, latestBatchId, settledAmount, _amount);
        }

        batch.isPegOutSettled = true;
        settledIds = batch.pegOutIds;
        isCompleted = batch.isPegInSettled;
    }

    /// @notice Records a Bitcoin borrow operation for a custodian
    /// @dev Increases custodian and total debt amounts
    /// @param _txId Bitcoin transaction ID for the borrow
    /// @param _amount Amount borrowed (in satoshis)
    /// @param _custodianId ID of the custodian borrowing
    function _borrow(
        bytes32 _txId,
        uint64 _amount,
        uint32 _custodianId
    ) internal {
        custodianDatas[_custodianId].debt += _amount;
        totalDebt += _amount;

        emit Borrowed(
            _custodianId,
            _txId,
            _amount,
            custodianDatas[_custodianId].debt,
            totalDebt
        );
    }

    /// @notice Records a Bitcoin repayment operation for a custodian
    /// @dev Decreases custodian and total debt amounts
    /// @param _txId Bitcoin transaction ID for the repayment
    /// @param _amount Amount repaid (in satoshis)
    /// @param _custodianId ID of the custodian repaying
    function _repay(
        bytes32 _txId,
        uint64 _amount,
        uint32 _custodianId
    ) internal {
        uint64 currentDebt = custodianDatas[_custodianId].debt;
        uint64 repaidAmount = currentDebt >= _amount ? _amount : currentDebt;
        uint64 newDebt = currentDebt - repaidAmount;

        custodianDatas[_custodianId].debt = newDebt;
        totalDebt -= repaidAmount;

        emit Repaid(
            _custodianId,
            _txId,
            _amount,
            newDebt,
            totalDebt
        );
    }

    /// @notice Processes a batch of peg-in requests
    /// @dev Iterates through all requests and processes them individually
    /// @param _requestIds Array of peg-in request IDs to process
    /// @param _custodianId ID of the custodian processing the batch
    /// @param _batchId ID of the batch being processed
    /// @return totalNetAmount Total net amount processed across all requests
    function _processPegInBatch(
        uint256[] calldata _requestIds,
        uint32 _custodianId,
        uint32 _batchId
    ) internal returns (uint64 totalNetAmount) {
        uint32 bitcoinBlockHeight = IBitcoinRelay(bitcoinRelay).lastSubmittedHeight();

        uint256 reqCount = _requestIds.length;
        for (uint256 i = 0; i < reqCount; ++i) {
            totalNetAmount += _processPegInRequest(_requestIds[i], _custodianId, _batchId, bitcoinBlockHeight);
        }
    }

    /// @notice Processes a single peg-in request
    /// @dev Mints lstBTC tokens and updates pegged BTC amount
    /// @param _requestId ID of the peg-in request to process
    /// @param _custodianId ID of the custodian processing the request
    /// @param _batchId ID of the batch containing this request
    /// @return netAmount Net amount of lstBTC minted for the request
    function _processPegInRequest(
        uint256 _requestId,
        uint32 _custodianId,
        uint32 _batchId,
        uint32 _bitcoinBlockHeight
    ) internal returns (uint64 netAmount) {
        PegRequest storage request = pegInRequests[_requestId];

        if (request.status != PegStatus.Pending) {
            revert InvalidRequestStatus(_requestId, PegStatus.Pending, request.status);
        }

        if (request.finalityHeight > _bitcoinBlockHeight) {
            revert RequestNotFinalized(_requestId, request.finalityHeight);
        }

        if (request.custodianId != _custodianId) {
            revert InvalidRequestCustodian(_requestId, _custodianId, request.custodianId);
        }

        if (request.treasuryFee > 0) {
            ILstBTC(lstBTC).mint(address(this), request.treasuryFee);
        }

        if (request.netAmount > 0) {
            ILstBTC(lstBTC).mint(_msgSender(), request.netAmount);
        }

        INavProvider(navProvider).increasePeggedBTC(request.amount);

        (
            address[] memory recipients,
            uint64[] memory recipientAmounts
        ) = request.calculatePegInTreasuryFeeSplits(IConfigRegistry(configRegistry));

        _settleTreasuryFees(_batchId, _requestId, recipients, recipientAmounts);

        request.batchId = _batchId;
        request.status = PegStatus.PendingPayout;

        netAmount = request.netAmount;
    }


    /// @notice Processes a batch of peg-out requests
    /// @dev Iterates through all requests and processes them individually
    /// @param _requestIds Array of peg-out request IDs to process
    /// @param _custodianId ID of the custodian processing the batch
    /// @param _batchId ID of the batch being processed
    /// @return totalNetAmount Total net amount processed across all requests
    function _processPegOutBatch(
        uint256[] calldata _requestIds,
        uint32 _custodianId,
        uint32 _batchId
    ) internal returns (uint64 totalNetAmount) {
        uint256 reqCount = _requestIds.length;

        for (uint256 i = 0; i < reqCount; ++i) {
            totalNetAmount += _processPegOutRequest(_requestIds[i], _custodianId, _batchId);
        }
    }

    /// @notice Processes a single peg-out request
    /// @dev Burns lstBTC tokens and updates pegged BTC amount
    /// @param _requestId ID of the peg-out request to process
    /// @param _custodianId ID of the custodian processing the request
    /// @param _batchId ID of the batch containing this request
    /// @return netAmount Net amount of Bitcoin to be redeemed
    function _processPegOutRequest(
        uint256 _requestId,
        uint32 _custodianId,
        uint32 _batchId
    ) internal returns (uint64 netAmount) {
        PegRequest storage request = pegOutRequests[_requestId];

        if (request.finalityHeight > block.number) {
            revert RequestNotFinalized(_requestId, request.finalityHeight);
        }

        if (request.status != PegStatus.Pending) {
            revert InvalidRequestStatus(_requestId, PegStatus.Pending, request.status);
        }

        if (request.custodianId != _custodianId) {
            revert InvalidRequestCustodian(_requestId, _custodianId, request.custodianId);
        }

        IERC20(lstBTC).safeTransferFrom(_msgSender(), address(this), request.amount);

        ILstBTC(lstBTC).burn(request.amount - request.treasuryFee);

        uint64 unpeggedBTC = request.netAmount + request.transactionFee;
        INavProvider(navProvider).decreasePeggedBTC(unpeggedBTC);

        (
            address[] memory recipients,
            uint64[] memory recipientAmounts
        ) = request.calculatePegOutTreasuryFeeSplits(IConfigRegistry(configRegistry));

        _settleTreasuryFees(_batchId, _requestId, recipients, recipientAmounts);

        request.batchId = _batchId;
        request.status = PegStatus.PendingPayout;

        netAmount = request.netAmount;
    }

    /// @notice Rejects a batch of peg-in requests
    /// @dev Iterates through all requests and rejects them individually
    /// @param _requestIds Array of peg-in request IDs to reject
    /// @param _custodianId ID of the custodian rejecting the batch
    /// @param _batchId ID of the batch being rejected
    /// @return pendingRefundAount Total amount pending refund across all requests
    function _rejectPegInBatch(
        uint256[] calldata _requestIds,
        uint32 _custodianId,
        uint32 _batchId
    ) internal returns (uint64 pendingRefundAount) {
        uint256 reqCount = _requestIds.length;

        for (uint256 i = 0; i < reqCount; ++i) {
            uint256 requestId = _requestIds[i];
            pendingRefundAount += pegInRequests[requestId].rejectPegInRequest(
                _custodianId,
                _batchId
            );
        }
    }

    /// @notice Rejects a batch of peg-out requests
    /// @dev Iterates through all requests and rejects them individually
    /// @param _requestIds Array of peg-out request IDs to reject
    /// @param _custodianId ID of the custodian rejecting the batch
    /// @param _batchId ID of the batch being rejected
    /// @return pendingRefundAmount Total amount pending refund across all requests
    function _rejectPegOutBatch(
        uint256[] calldata _requestIds,
        uint32 _custodianId,
        uint32 _batchId
    ) internal returns (uint64 pendingRefundAmount) {
        uint256 reqCount = _requestIds.length;

        for (uint256 i = 0; i < reqCount; ++i) {
            uint256 requestId = _requestIds[i];
            pendingRefundAmount += pegOutRequests[requestId].rejectPegOutRequest(
                _custodianId,
                _batchId
            );
        }
    }

    /// @notice Settles treasury fees for a processed request
    /// @dev Distributes fees to recipients and clears staged data
    /// @param _batchId ID of the batch containing the request
    /// @param _requestId ID of the request to settle fees for
    function _settleTreasuryFees(
        uint32 _batchId,
        uint256 _requestId,
        address[] memory _recipients,
        uint64[] memory _recipientAmounts
    ) internal {
        uint256 recipientCount = _recipients.length;
        for (uint256 i = 0; i < recipientCount; ++i) {
            if (_recipientAmounts[i] != 0) {
                claimableFees[_recipients[i]] += _recipientAmounts[i];
            }
        }

        emit TreasuryFeeAccumulated(
            _batchId,
            _requestId,
            _recipients,
            _recipientAmounts
        );
    }
}
