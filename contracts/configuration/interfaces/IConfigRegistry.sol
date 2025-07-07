// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @title IConfigRegistry
 * @dev Interface for the configuration registry contract
 *
 * This interface defines the functions and events for the configuration registry,
 * which manages all protocol parameters and settings. The registry handles:
 * - Confirmation requirements for different custodians
 * - Fee rates and fee distribution for peg-in and peg-out operations
 * - Dust amounts for minimum transaction sizes
 * - Treasury fee recipient addresses and their shares
 *
 * The registry uses time-series data to support parameter updates over time
 * while maintaining historical values for audit purposes.
 */
interface IConfigRegistry {
    /// @notice Emitted when the bridge address is updated
    /// @param oldBridge Previous bridge address
    /// @param newBridge New bridge address
    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);

    /// @notice Emitted when Bitcoin confirmation requirements are updated for a custodian
    /// @param custodianId ID of the custodian
    /// @param oldConfirmations Previous confirmation requirement
    /// @param newConfirmations New confirmation requirement
    event BitcoinConfirmationsUpdated(
        uint32 indexed custodianId,
        uint32 oldConfirmations,
        uint32 newConfirmations
    );

    /// @notice Emitted when native chain confirmation requirements are updated for a custodian
    /// @param custodianId ID of the custodian
    /// @param oldConfirmations Previous confirmation requirement
    /// @param newConfirmations New confirmation requirement
    event NativeConfirmationsUpdated(
        uint32 indexed custodianId,
        uint32 oldConfirmations,
        uint32 newConfirmations
    );

    /// @notice Emitted when the peg-in deposit dust amount is updated
    /// @param oldAmount Previous dust amount
    /// @param newAmount New dust amount
    event PegInDepositDustAmountUpdated(uint64 oldAmount, uint64 newAmount);

    /// @notice Emitted when the peg-in treasury fee rate is updated
    /// @param oldRate Previous fee rate
    /// @param newRate New fee rate
    event PegInTreasuryFeeRateUpdated(uint16 oldRate, uint16 newRate);

    /// @notice Emitted when peg-in treasury fee shares are updated
    /// @param oldRecipients Previous fee recipient addresses
    /// @param oldShares Previous fee shares for each recipient
    /// @param newRecipients New fee recipient addresses
    /// @param newShares New fee shares for each recipient
    event PegInTreasuryFeeSharesUpdated(
        address[] oldRecipients,
        uint16[] oldShares,
        address[] newRecipients,
        uint16[] newShares
    );

    /// @notice Emitted when the peg-out redeem dust amount is updated
    /// @param oldAmount Previous dust amount
    /// @param newAmount New dust amount
    event PegOutRedeemDustAmountUpdated(uint64 oldAmount, uint64 newAmount);

    /// @notice Emitted when the peg-out treasury fee rate is updated
    /// @param oldRate Previous fee rate
    /// @param newRate New fee rate
    event PegOutTreasuryFeeRateUpdated(uint16 oldRate, uint16 newRate);

    /// @notice Emitted when peg-out treasury fee shares are updated
    /// @param oldRecipients Previous fee recipient addresses
    /// @param oldShares Previous fee shares for each recipient
    /// @param newRecipients New fee recipient addresses
    /// @param newShares New fee shares for each recipient
    event PegOutTreasuryFeeSharesUpdated(
        address[] oldRecipients,
        uint16[] oldShares,
        address[] newRecipients,
        uint16[] newShares
    );

    /// @notice Emitted when the peg-out transaction fee is updated
    /// @param oldAmount Previous transaction fee
    /// @param newAmount New transaction fee
    event PegOutTransactionFeeUpdated(uint64 oldAmount, uint64 newAmount);

    /// @notice Returns the address of the bridge contract
    /// @return Bridge contract address
    function bridge() external view returns (address);

    /// @notice Returns the number of Bitcoin confirmations required for a custodian
    /// @param _custodianId ID of the custodian
    /// @return Number of Bitcoin confirmations required
    function getBitcoinConfirmations(uint32 _custodianId) external view returns (uint32);

    /// @notice Returns the number of native chain confirmations required for a custodian
    /// @param _custodianId ID of the custodian
    /// @return Number of native chain confirmations required
    function getNativeConfirmations(uint32 _custodianId) external view returns (uint32);

    /// @notice Returns the minimum dust amount for peg-in deposits at a specific timestamp
    /// @param _timestamp Timestamp to query the dust amount for
    /// @return Minimum dust amount for peg-in deposits
    function getPegInDepositDustAmount(uint64 _timestamp) external view returns (uint64);

    /// @notice Returns the treasury fee rate for peg-in operations at a specific timestamp
    /// @param _timestamp Timestamp to query the fee rate for
    /// @return Treasury fee rate for peg-in operations
    function getPegInTreasuryFeeRate(uint64 _timestamp) external view returns (uint16);

    /// @notice Returns the treasury fee shares for peg-in operations at a specific timestamp
    /// @param _timestamp Timestamp to query the fee shares for
    /// @return receipients Array of fee recipient addresses
    /// @return shares Array of fee shares for each recipient
    function getPegInTreasuryFeeShares(
        uint64 _timestamp
    ) external view returns (
        address[] memory receipients,
        uint16[] memory shares
    );

    /// @notice Returns the minimum dust amount for peg-out redemptions at a specific timestamp
    /// @param _timestamp Timestamp to query the dust amount for
    /// @return Minimum dust amount for peg-out redemptions
    function getPegOutRedeemDustAmount(uint64 _timestamp) external view returns (uint64);

    /// @notice Returns the transaction fee for peg-out operations at a specific timestamp
    /// @param _timestamp Timestamp to query the transaction fee for
    /// @return Transaction fee for peg-out operations
    function getPegOutTransactionFee(uint64 _timestamp) external view returns (uint64);

    /// @notice Returns the treasury fee rate for peg-out operations at a specific timestamp
    /// @param _timestamp Timestamp to query the fee rate for
    /// @return Treasury fee rate for peg-out operations
    function getPegOutTreasuryFeeRate(uint64 _timestamp) external view returns (uint16);

    /// @notice Returns the treasury fee shares for peg-out operations at a specific timestamp
    /// @param _timestamp Timestamp to query the fee shares for
    /// @return receipients Array of fee recipient addresses
    /// @return shares Array of fee shares for each recipient
    function getPegOutTreasuryFeeShares(
        uint64 _timestamp
    ) external view returns (
        address[] memory receipients,
        uint16[] memory shares
    );
}