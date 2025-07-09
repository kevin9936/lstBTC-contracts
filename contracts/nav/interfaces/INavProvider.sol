// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @title INavProvider
 * @dev Interface for the Net Asset Value (NAV) provider contract
 *
 * This interface defines the functions and events for the NAV provider,
 * which manages the exchange rate between lstBTC tokens and underlying Bitcoin.
 * The provider tracks:
 * - Total pegged Bitcoin amount in the system
 * - Yield generated from custodian operations
 * - Historical exchange rates over time
 * - Bridge integration for NAV calculations
 *
 * The NAV provider ensures the exchange rate can only increase over time
 * to protect token holders from value dilution.
 */
interface INavProvider {
    /// @notice	Emitted when yield is received from custodian operations
    /// @param	custodianId	ID of the custodian that generated the yield
    /// @param	bitcoinTxId	Bitcoin transaction ID that generated the yield
    /// @param	yieldAmount	Amount of yield received (in satoshis)
    /// @param	totalYield	Total accumulated yield (in satoshis)
    event YieldReceived(
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        uint64 yieldAmount,
        uint64 totalYield
    );

    /// @notice	Emitted when the total pegged Bitcoin amount increases
    /// @param	addedAmount	Amount of Bitcoin added (in satoshis)
    /// @param	totalAmount	New total pegged Bitcoin amount (in satoshis)
    event PeggedBTCIncreased(
        uint64 addedAmount,
        uint64 totalAmount
    );

    /// @notice	Emitted when the total pegged Bitcoin amount decreases
    /// @param	subtractedAmount	Amount of Bitcoin subtracted (in satoshis)
    /// @param	remainingAmount	Remaining total pegged Bitcoin amount (in satoshis)
    event PeggedBTCDecreased(
        uint64 subtractedAmount,
        uint64 remainingAmount
    );

    /// @notice	Emitted when the bridge address is updated
    /// @param	oldBridge	Previous bridge address
    /// @param	newBridge	New bridge address
    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);

    /// @notice	Emitted when the exchange rate is updated
    /// @param	oldExchangeRate	Previous exchange rate
    /// @param	newExchangeRate	New exchange rate
    event ExchangeRateUpdated(uint64 oldExchangeRate, uint64 newExchangeRate);

    /// @notice	Returns the address of the bridge contract
    /// @return	Bridge	contract address
    function bridge() external view returns (address);

    /// @notice	Returns the total amount of Bitcoin pegged in the system
    /// @return	Total	pegged Bitcoin amount (in satoshis)
    function peggedBTC() external view returns (uint64);

    /// @notice	Returns the total yield generated from custodian operations
    /// @return	Total	yield amount (in satoshis)
    function yieldBTC() external view returns (uint64);

    /// @notice	Returns the exchange rate for a specific timestamp
    /// @param	_timestamp	Timestamp to query the exchange rate for
    /// @return	exchangeRate	Exchange rate at the specified timestamp
    /// @return	decimals	Number of decimal places for the exchange rate
    function getExchangeRate(uint64 _timestamp) external view returns (uint64, uint8);

    /// @notice	Returns the latest exchange rate
    /// @return	exchangeRate	Latest exchange rate
    /// @return	decimals	Number of decimal places for the exchange rate
    function getLatestExchangeRate() external view returns (uint64, uint8);

    /// @notice	Increases the total pegged Bitcoin amount
    /// @dev	Only callable by the bridge contract
    /// @param	_increasedAmount	Amount of Bitcoin to add (in satoshis)
    function increasePeggedBTC(uint64 _increasedAmount) external;

    /// @notice	Decreases the total pegged Bitcoin amount
    /// @dev	Only callable by the bridge contract
    /// @param	_decreasedAmount	Amount of Bitcoin to subtract (in satoshis)
    function decreasePeggedBTC(uint64 _decreasedAmount) external;

    /// @notice	Records yield received from custodian operations
    /// @dev	   Only callable by the bridge contract.
    ///         Increases both yieldBTC and peggedBTC
    /// @param		_txId         Bitcoin transaction ID that generated the yield
    /// @param		_amount       Yield amount (in satoshis)
    /// @param		_custodianId  ID of the custodian that generated the yield
    function accrueYield(bytes32 _txId, uint64 _amount, uint32 _custodianId) external;
}