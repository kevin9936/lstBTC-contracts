// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ILstBTCBridgeStorage.sol";

/**
 * @title ILstBTCBridge
 * @dev Interface for the main bridge contract in the lstBTC protocol
 *
 * This interface defines the events and functions for the bridge contract,
 * which is the central coordinator for all peg-in and peg-out operations.
 * It manages the lifecycle of requests, batch processing, fee distribution,
 * and integration with other protocol components.
 */
interface ILstBTCBridge is ILstBTCBridgeStorage  {
    /// @notice Emitted when the config registry address is updated
    /// @param oldAddress Previous config registry address
    /// @param newAddress New config registry address
    event ConfigRegistryUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when the whitelist registry address is updated
    /// @param oldAddress Previous whitelist registry address
    /// @param newAddress New whitelist registry address
    event WhitelistRegistryUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when the NAV provider address is updated
    /// @param oldAddress Previous NAV provider address
    /// @param newAddress New NAV provider address
    event NavProviderUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when the Bitcoin transaction store address is updated
    /// @param oldAddress Previous Bitcoin transaction store address
    /// @param newAddress New Bitcoin transaction store address
    event BitcoinTxStoreUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when the lstBTC token address is updated
    /// @param oldAddress Previous lstBTC token address
    /// @param newAddress New lstBTC token address
    event LstBTCUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when a batch of requests is processed successfully
    /// @param batchId ID of the processed batch
    /// @param pegInIds Array of peg-in request IDs in the batch
    /// @param pegOutIds Array of peg-out request IDs in the batch
    /// @param pendingPayWrappedAmount Total lstBTC amount pending payout
    /// @param pendingPayBTCAmount Total Bitcoin amount pending payout
    event BatchProcessed(
        uint32 indexed batchId,
        uint256[] pegInIds,
        uint256[] pegOutIds,
        uint64 pendingPayWrappedAmount,
        uint64 pendingPayBTCAmount
    );

    /// @notice Emitted when a batch of requests is rejected
    /// @param batchId ID of the rejected batch
    /// @param pegInIds Array of peg-in request IDs in the batch
    /// @param pegOutIds Array of peg-out request IDs in the batch
    /// @param pendingRefundBTCAmount Total Bitcoin amount pending refund
    /// @param pendingRefundWrappedBTCAmount Total lstBTC amount pending refund
    event BatchRejected(
        uint32 indexed batchId,
        uint256[] pegInIds,
        uint256[] pegOutIds,
        uint64 pendingRefundBTCAmount,
        uint64 pendingRefundWrappedBTCAmount
    );

    /// @notice Emitted when treasury fees are accumulated in a batch
    /// @param batchId ID of the batch containing the fees
    /// @param requestId ID of the request generating the fees
    /// @param recipients Array of fee recipient addresses
    /// @param amounts Array of fee amounts for each recipient
    event TreasuryFeeAccumulated(
        uint32 indexed batchId,
        uint256 indexed requestId,
        address[] recipients,
        uint64[] amounts
    );

    /// @notice Emitted when a new peg-in request is created
    /// @param requestId ID of the created request
    /// @param custodianId ID of the custodian handling the request
    /// @param bitcoinTxId Bitcoin transaction ID of the deposit
    /// @param sender Bitcoin script public key of the sender
    /// @param receiver Bitcoin script public key of the receiver
    /// @param amount Amount of Bitcoin deposited (in satoshis)
    /// @param exchangeRate Exchange rate at the time of deposit
    /// @param recipients Array of treasury fee recipients
    /// @param recipientAmounts Array of fee amounts for each recipient
    /// @param netAmount Net amount after fees (in satoshis)
    event PegInCreated(
        uint256 indexed requestId,
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        bytes sender,
        bytes receiver,
        uint64 amount,
        uint64 exchangeRate,
        address[] recipients,
        uint64[] recipientAmounts,
        uint64 netAmount
    );

    /// @notice Emitted when a batch of peg-in requests is refunded
    /// @param batchId ID of the batch being refunded
    /// @param bitcoinTxId Bitcoin transaction ID of the refund
    /// @param requestIds Array of request IDs in the batch
    /// @param totalAmount Total amount refunded (in satoshis)
    /// @param isCompleted Whether this completes the batch refund
    event PegInBatchRefunded(
        uint64 indexed batchId,
        bytes32 indexed bitcoinTxId,
        uint256[] requestIds,
        uint64 totalAmount,
        bool isCompleted
    );

    /// @notice Emitted when a batch of peg-in requests is paid out
    /// @param batchId ID of the batch being paid
    /// @param requestIds Array of request IDs in the batch
    /// @param totalAmount Total amount paid out (in lstBTC)
    /// @param isCompleted Whether this completes the batch payout
    event PegInBatchPaid(
        uint32 indexed batchId,
        uint256[] requestIds,
        uint64 totalAmount,
        bool isCompleted
    );

    /// @notice Emitted when a new peg-out request is created
    /// @param requestId ID of the created request
    /// @param custodianId ID of the custodian handling the request
    /// @param sender Address of the lstBTC sender
    /// @param receiver Address of the lstBTC receiver
    /// @param amount Amount of lstBTC to redeem (in satoshis)
    /// @param exchangeRate Exchange rate at the time of request
    /// @param recipients Array of treasury fee recipients
    /// @param recipientAmounts Array of fee amounts for each recipient
    /// @param netAmount Net amount after fees (in satoshis)
    event PegOutCreated(
        uint256 indexed requestId,
        uint32 indexed custodianId,
        address sender,
        address receiver,
        uint64 amount,
        uint64 exchangeRate,
        address[] recipients,
        uint64[] recipientAmounts,
        uint64 netAmount
    );

    /// @notice Emitted when a batch of peg-out requests is refunded
    /// @param batchId ID of the batch being refunded
    /// @param requestIds Array of request IDs in the batch
    /// @param totalAmount Total amount refunded (in lstBTC)
    /// @param isCompleted Whether this completes the batch refund
    event PegOutBatchRefunded(
        uint32 indexed batchId,
        uint256[] requestIds,
        uint64 totalAmount,
        bool isCompleted
    );

    /// @notice Emitted when a batch of peg-out requests is paid out
    /// @param batchId ID of the batch being paid
    /// @param bitcoinTxId Bitcoin transaction ID of the payout
    /// @param requestIds Array of request IDs in the batch
    /// @param totalAmount Total amount paid out (in satoshis)
    /// @param isCompleted Whether this completes the batch payout
    event PegOutBatchPaid(
        uint32 indexed batchId,
        bytes32 indexed bitcoinTxId,
        uint256[] requestIds,
        uint64 totalAmount,
        bool isCompleted
    );

    /// @notice Emitted when Bitcoin is borrowed from a custodian
    /// @param custodianId ID of the custodian providing the loan
    /// @param bitcoinTxId Bitcoin transaction ID of the borrow
    /// @param borrowedAmount Amount borrowed (in satoshis)
    /// @param custodianDebt New debt level of the custodian
    /// @param totalDebt Total debt across all custodians
    event Borrowed(
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        uint64 borrowedAmount,
        uint64 custodianDebt,
        uint64 totalDebt
    );

    /// @notice Emitted when Bitcoin is repaid to a custodian
    /// @param custodianId ID of the custodian receiving the repayment
    /// @param bitcoinTxId Bitcoin transaction ID of the repayment
    /// @param repaidAmount Amount repaid (in satoshis)
    /// @param custodianDebt New debt level of the custodian
    /// @param totalDebt Total debt across all custodians
    event Repaid(
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        uint64 repaidAmount,
        uint64 custodianDebt,
        uint64 totalDebt
    );

    /// @notice Emitted when accumulated fees are claimed
    /// @param claimer Address claiming the fees
    /// @param amount Amount of fees claimed
    event FeesClaimed(address indexed claimer, uint64 amount);
}
