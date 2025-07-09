// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./interfaces/INavProvider.sol";
import "../access/AccessControlBase.sol";
import "../libraries/TimeSeriesDataLib.sol";
import "../bridge/interfaces/ILstBTCBridge.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title NavProviderLogic
 * @dev Net Asset Value (NAV) provider for the lstBTC protocol
 *
 * This contract manages the exchange rate between lstBTC tokens and underlying Bitcoin
 * by tracking the total pegged Bitcoin and calculating the NAV based on:
 * - Total supply of lstBTC tokens
 * - Total pegged Bitcoin amount
 * - Yield generated from custodian operations
 *
 * The contract maintains a time-series of exchange rates and ensures the rate
 * can only increase over time to protect token holders.
 */
contract NavProviderLogic is
    INavProvider,
    AccessControlBase,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /// @notice	Thrown when exchange rate is not available for the requested timestamp
    error ExchangeRateUnavailable();

    /// @notice	Thrown when new exchange rate is lower than the previous rate
    error ExchangeRateMustIncrease(uint64 oldExchangeRate, uint64 newExchangeRate);

    /// @notice	Thrown when trying to decrease pegged BTC below zero
    error PeggedBTCDecreaseOverflow(uint64 decreasedAmount, uint64 peggedBTC);

    /// @notice	Thrown when wrapped BTC amount exceeds pegged BTC amount
    error PeggedBTCInvariantViolated(uint64 wrappedBTC, uint64 peggedBTC);

    /// @notice	Number of decimal places for exchange rate calculations
    uint8 public constant EXCHANGE_RATE_DECIMALS = 8;

    /// @notice	Initial exchange rate (1:1 ratio)
    uint64 public constant INITIAL_EXCHANGE_RATE = 1e8;

    /// @notice	Address of the main bridge contract
    address public override bridge;

    /// @notice	Total amount of Bitcoin pegged in the system (in satoshis)
    uint64 public override peggedBTC;

    /// @notice	Total yield generated from custodian operations (in satoshis)
    uint64 public override yieldBTC;

    /// @notice	Time-series data for exchange rates
    TimeSeriesDataLib.TimeSeriesData internal exchangeRates;

    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using TimeSeriesDataLib for TimeSeriesDataLib.TimeSeriesData;

    /// @notice	Ensures only the bridge contract can call certain functions
    modifier onlyBridge() {
        if (bridge != _msgSender()) { revert Unauthorized(_msgSender()); }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice	Initializes the NAV provider
    /// @dev	Sets up access control and initializes the exchange rate
    /// @param	_admin	Default admin address with full control
    /// @param	_governor	Governor address for operational decisions
    function initialize(
        address _admin,
        address _governor
    ) public initializer {
        AccessControlBase.__AccessControlBase_init(_admin, _governor);
        PausableUpgradeable.__Pausable_init();
        UUPSUpgradeable.__UUPSUpgradeable_init();

        // Initialize exchange rate time-series with timestamp 0
        // Using timestamp 0 ensures that any timestamp query will at least return the initial rate
        // This provides a fallback exchange rate of 1:1 for any historical or future timestamp
        exchangeRates.initialize(0, abi.encode(INITIAL_EXCHANGE_RATE));
    }

    /// @notice	Authorizes contract upgrades
    /// @dev	Only governor can upgrade the contract implementation
    /// @param	newImplementation	Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}

    /// @notice	Pauses the NAV provider
    /// @dev	Only governor can pause in emergency situations
    function pauseProvider() external onlyGovernor {
        _pause();
    }

    /// @notice	Unpauses the NAV provider
    /// @dev	Only governor can unpause after emergency is resolved
    function unpauseProvider() external onlyGovernor {
        _unpause();
    }

    /// @notice	Updates the bridge contract address
    /// @dev	Only governor can update the bridge address
    /// @param	_bridge	New bridge contract address
    function setBridge(address _bridge) external onlyGovernor nonZeroAddress(_bridge) {
        if (_bridge == bridge) { return; }

        emit BridgeUpdated(bridge, _bridge);
        bridge = _bridge;
    }

    /// @notice	Increases the total pegged Bitcoin amount
    /// @dev	Only bridge can call this function.
    ///            Called when new Bitcoin is pegged into the system
    /// @param	_increasedAmount	   Amount of Bitcoin to add (in satoshis)
    function increasePeggedBTC(uint64 _increasedAmount) public override onlyBridge {
        peggedBTC += _increasedAmount;

        emit PeggedBTCIncreased(_increasedAmount, peggedBTC);
    }

    /// @notice	Decreases the total pegged Bitcoin amount
    /// @dev	Only bridge can call this function.
    ///            Called when Bitcoin is unpegged from the system.
    ///            Cannot decrease below zero
    /// @param	_decreasedAmount	   Amount of Bitcoin to remove (in satoshis)
    function decreasePeggedBTC(uint64 _decreasedAmount) external override onlyBridge {
        if (_decreasedAmount >= peggedBTC) {
            revert PeggedBTCDecreaseOverflow(_decreasedAmount, peggedBTC);
        }

        peggedBTC -= _decreasedAmount;
        emit PeggedBTCDecreased(_decreasedAmount, peggedBTC);
    }

    /// @notice	Records yield received from custodian operations
    /// @dev	Only bridge can call this function.
    ///            Increases both yieldBTC and peggedBTC.
    ///            Refreshes the exchange rate after yield accrual
    /// @param	_txId	   Bitcoin transaction ID that generated the yield
    /// @param	_amount	   Yield amount in satoshis
    /// @param	_custodianId	   ID of the custodian that generated the yield
    function accrueYield(
        bytes32 _txId,
        uint64 _amount,
        uint32 _custodianId
    ) external override onlyBridge {
        yieldBTC += _amount;

        emit YieldReceived(
            _custodianId,
            _txId,
            _amount,
            yieldBTC
        );

        increasePeggedBTC(_amount);
        _refreshExchangeRate();
    }

    /// @notice	Gets the exchange rate for a specific timestamp
    /// @dev	Reverts if exchange rate is not available for the timestamp
    /// @param	_timestamp	   Timestamp to query exchange rate for
    /// @return	exchangeRate	   Exchange rate at the specified timestamp
    /// @return	decimals	   Number of decimal places for the exchange rate
    function getExchangeRate(
        uint64 _timestamp
    ) external view override whenNotPaused returns (
        uint64 exchangeRate,
        uint8 decimals
    ) {
        return _fetchExchangeRate(_timestamp);
    }

    /// @notice	Gets the latest exchange rate
    /// @dev	Reverts if no exchange rate is available
    /// @return	exchangeRate	   Latest exchange rate
    /// @return	decimals	   Number of decimal places for the exchange rate
    function getLatestExchangeRate() external view override whenNotPaused returns (
        uint64 exchangeRate,
        uint8 decimals
    ) {
        return _fetchLatestExchangeRate();
    }

    /// @notice	Refreshes the exchange rate based on current pegged BTC and token supply
    /// @dev	Calculates new rate as peggedBTC / totalSupply.
    ///            Ensures rate can only increase to protect token holders.
    ///            Updates time-series data if rate has changed
    function _refreshExchangeRate() internal {
        uint256 totalSupply = IERC20(ILstBTCBridge(bridge).lstBTC()).totalSupply();
        uint64 wrappedBTC = totalSupply.toUint64();

        if (wrappedBTC == 0 || peggedBTC < wrappedBTC) {
            revert PeggedBTCInvariantViolated(wrappedBTC, peggedBTC);
        }

        (uint64 oldExchangeRate, uint8 decimals) = _fetchLatestExchangeRate();
        uint256 rate = (peggedBTC * (10 ** decimals)) / wrappedBTC;
        uint64 newExchangeRate = rate.toUint64();

        if (newExchangeRate < oldExchangeRate) {
            revert ExchangeRateMustIncrease(oldExchangeRate, newExchangeRate);
        }

        if (newExchangeRate != oldExchangeRate) {
            exchangeRates.append(abi.encode(newExchangeRate));
            emit ExchangeRateUpdated(oldExchangeRate, newExchangeRate);
        }
    }

    /// @dev	Retrieves the exchange rate for a specific timestamp, reverts if none exists.
    function _fetchExchangeRate(
        uint64 _timestamp
    ) internal view returns (
        uint64 exchangeRate,
        uint8 decimals
    ) {
        (bool exists, bytes memory encodedValue) = exchangeRates.get(_timestamp);
        if (!exists) { revert ExchangeRateUnavailable(); }

        return (abi.decode(encodedValue, (uint64)), EXCHANGE_RATE_DECIMALS);
    }

    /// @dev	Retrieves the latest exchange rate from storage, reverts if none exists.
    function _fetchLatestExchangeRate() internal view returns (
        uint64 exchangeRate,
        uint8 decimals
    ) {
        (bool exists, bytes memory encodedValue) = exchangeRates.getLatest();
        if (!exists) { revert ExchangeRateUnavailable(); }

        return (abi.decode(encodedValue, (uint64)), EXCHANGE_RATE_DECIMALS);
    }
}
