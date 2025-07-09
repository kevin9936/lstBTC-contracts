// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../access/AccessControlBase.sol";
import "../libraries/FeeConfigHelper.sol";
import "./interfaces/IConfigRegistry.sol";
import "../libraries/TimeSeriesDataLib.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../bridge/interfaces/ILstBTCBridge.sol";
import "../whitelist/interfaces/IWhitelistRegistry.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title ConfigRegistryLogic
 * @dev Central configuration registry for the lstBTC protocol
 *
 * This contract manages all protocol configuration parameters including:
 * - Bitcoin and native chain confirmation requirements
 * - Fee structures for peg-in and peg-out operations
 * - Treasury fee distribution settings
 * - Dust amount thresholds
 *
 * The contract uses time-series data structures to support historical
 * configuration tracking and allows for dynamic parameter updates.
 */
contract ConfigRegistryLogic is IConfigRegistry, AccessControlBase, UUPSUpgradeable {
    /// @notice	Thrown when custodian ID is not authorized
    error UnauthorizedCustodian(uint32 custodianId);

    /// @notice	Thrown when Bitcoin confirmations are below minimum requirement
    error BitcoinConfirmationsBelowMinimum(uint32 confirmations);

    /// @notice	Thrown when native confirmations are below minimum requirement
    error NativeConfirmationsBelowMinimum(uint32 confirmations);

    /// @notice	Thrown when redeem dust amount is below minimum
    error RedeemDustAmountBelowMinimum(uint64 amount);

    /// @notice	Thrown when treasury fee rate exceeds maximum allowed
    error TreasuryFeeRateExceedsMax(uint16 rate);

    /// @notice	Thrown when recipients array is empty
    error RecipientsEmpty();

    /// @notice	Thrown when recipients and shares arrays have different lengths
    error RecipientsSharesLengthMismatch(uint256 recipientCount, uint256 shareCount);

    /// @notice	Thrown when total shares do not equal the expected base amount
    error TotalSharesMismatch(uint256 expectedShares, uint256 actualShares);


    struct CustodianConfig {
        uint32 bitcoinConfirmations;
        uint32 nativeConfirmations;
    }

    /// @notice	Configuration structure for fee management
    /// @dev	Contains time-series data for different fee parameters
    struct FeeConfig {
        TimeSeriesDataLib.TimeSeriesData amountThresholds;    // Minimum amounts for operations
        TimeSeriesDataLib.TimeSeriesData transactionFees;     // Fixed transaction fees
        TimeSeriesDataLib.TimeSeriesData treasuryFeeRates;    // Percentage-based treasury fees
        TimeSeriesDataLib.TimeSeriesData treasuryFeeShares;   // Fee distribution shares
    }

    /// @notice	Default Bitcoin confirmation requirement (6 blocks)
    uint32 public constant DEFAULT_BITCOIN_CONFIRMATIONS = 1;

    /// @notice	Default native chain confirmation requirement (12 blocks)
    uint32 public constant DEFAULT_NATIVE_CONFIRMATIONS = 12;

    /// @notice	Default minimum redeem dust amount in satoshis
    uint64 public constant DEFAULT_REDEEM_DUST_AMOUNT = 3000;

    /// @notice	Base for percentage calculations (10000 = 100%)
    uint16 public constant PERCENTAGE_BASE = 10000;

    /// @notice	Address of the main bridge contract
    address public override bridge;

    /// @notice	Mapping of custodian ID to custodian configuration
    mapping (uint256 => CustodianConfig) public custodianConfigs;

    /// @notice	Fee configuration for peg-in operations
    FeeConfig internal pegInFeeConfig;

    /// @notice	Fee configuration for peg-out operations
    FeeConfig internal pegOutFeeConfig;

    using FeeConfigHelper for TimeSeriesDataLib.TimeSeriesData;

    constructor() {
        _disableInitializers();
    }

    /// @notice	Initializes the configuration registry
    /// @dev	Sets up access control and initializes upgradeable contracts
    /// @param	_admin	   Default admin address with full control
    /// @param	_governor	   Governor address for operational decisions
    function initialize(
        address _admin,
        address _governor
    ) public initializer {
        AccessControlBase.__AccessControlBase_init(_admin, _governor);
        UUPSUpgradeable.__UUPSUpgradeable_init();
    }

    /// @notice	Authorizes contract upgrades
    /// @dev	Only governor can upgrade the contract implementation
    /// @param	newImplementation	   Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}

    /// @notice	Updates the bridge contract address
    /// @dev	Only governor can update the bridge address
    /// @param	_bridge	   New bridge contract address
    function setBridge(address _bridge) external onlyGovernor nonZeroAddress(_bridge) {
        if (_bridge == bridge) { return; }

        emit BridgeUpdated(bridge, _bridge);
        bridge = _bridge;
    }

    /// @notice	Sets Bitcoin confirmation requirements for a custodian
    /// @dev	Only governor can update confirmation requirements.
    ///         Must be at least DEFAULT_BITCOIN_CONFIRMATIONS
    /// @param	_custodianId	   The custodian ID to configure
    /// @param	_confirmations	   Required number of Bitcoin confirmations
    function setBitcoinConfirmations(
        uint32 _custodianId,
        uint32 _confirmations
    ) external onlyGovernor {
        _requireValidCustodianId(_custodianId);

        if (_confirmations < DEFAULT_BITCOIN_CONFIRMATIONS) {
            revert BitcoinConfirmationsBelowMinimum(_confirmations);
        }

        emit BitcoinConfirmationsUpdated(
            _custodianId,
            custodianConfigs[_custodianId].bitcoinConfirmations,
            _confirmations
        );

        custodianConfigs[_custodianId].bitcoinConfirmations = _confirmations;
    }

    /// @notice	Sets native chain confirmation requirements for a custodian
    /// @dev	Only governor can update confirmation requirements.
    ///         Must be at least DEFAULT_NATIVE_CONFIRMATIONS
    /// @param	_custodianId	   The custodian ID to configure
    /// @param	_confirmations	   Required number of native chain confirmations
    function setNativeConfirmations(
        uint32 _custodianId,
        uint32 _confirmations
    ) external onlyGovernor {
        _requireValidCustodianId(_custodianId);

        if (_confirmations < DEFAULT_NATIVE_CONFIRMATIONS) {
            revert NativeConfirmationsBelowMinimum(_confirmations);
        }

        emit NativeConfirmationsUpdated(
            _custodianId,
            custodianConfigs[_custodianId].nativeConfirmations,
            _confirmations
        );

        custodianConfigs[_custodianId].nativeConfirmations = _confirmations;
    }

    /// @notice	Sets the minimum dust amount for peg-in deposits
    /// @dev	Only governor can update dust amounts
    /// @param	_amount	   Minimum amount in satoshis for peg-in deposits
    function setPegInDepositDustAmount(uint64 _amount) external onlyGovernor {
        (, uint64 oldAmount) = pegInFeeConfig.amountThresholds.getLatestAmountThreshold();
        pegInFeeConfig.amountThresholds.setAmountThreshold(_amount);

        emit PegInDepositDustAmountUpdated(oldAmount, _amount);
    }

    /// @notice	Sets the treasury fee rate for peg-in operations
    /// @dev	Only governor can update fee rates.
    ///         Rate must be less than PERCENTAGE_BASE (100%)
    /// @param	_rate	   Treasury fee rate in basis points (e.g., 100 = 1%)
    function setPegInTreasuryFeeRate(uint16 _rate) external onlyGovernor {
        if (_rate >= PERCENTAGE_BASE) {
            revert TreasuryFeeRateExceedsMax(_rate);
        }

        (, uint16 oldRate) = pegInFeeConfig.treasuryFeeRates.getLatestTreasuryFeeRate();
        pegInFeeConfig.treasuryFeeRates.setTreasuryFeeRate(_rate);

        emit PegInTreasuryFeeRateUpdated(oldRate, _rate);
    }

    /// @notice	Sets treasury fee distribution shares for peg-in operations
    /// @dev	Only governor can update fee distribution.
    ///         Recipients and shares arrays must have same length.
    ///         Total shares must equal PERCENTAGE_BASE
    /// @param	_recipients	   Array of fee recipient addresses
    /// @param	_shares	   Array of fee shares in basis points
    function setPegInTreasuryFeeShares(
        address[] calldata _recipients,
        uint16[] calldata _shares
    ) external onlyGovernor {
        _requireValidRecipientsAndSharesLength(_recipients, _shares);
        _requireTotalSharesEqualsBase(_shares);

        (
            ,
            address[] memory oldRecipients,
            uint16[] memory oldShares
        ) = pegInFeeConfig.treasuryFeeShares.getLatestTreasuryFeeShares();

        pegInFeeConfig.treasuryFeeShares.setTreasuryFeeShares(
            _recipients,
            _shares
        );

        emit PegInTreasuryFeeSharesUpdated(
            oldRecipients,
            oldShares,
            _recipients,
            _shares
        );
    }

    /// @notice	Sets the minimum dust amount for peg-out redemptions
    /// @dev	Only governor can update dust amounts.
    ///         Must be at least DEFAULT_REDEEM_DUST_AMOUNT
    /// @param	_amount	   Minimum amount in satoshis for peg-out redemptions
    function setPegOutRedeemDustAmount(uint64 _amount) external onlyGovernor {
        if (_amount < DEFAULT_REDEEM_DUST_AMOUNT) {
            revert RedeemDustAmountBelowMinimum(_amount);
        }

        (, uint64 oldAmount) = pegOutFeeConfig.amountThresholds.getLatestAmountThreshold();
        pegOutFeeConfig.amountThresholds.setAmountThreshold(_amount);

        emit PegOutRedeemDustAmountUpdated(oldAmount, _amount);
    }

    /// @notice	Sets the fixed transaction fee for peg-out operations
    /// @dev	Only governor can update transaction fees
    /// @param	_transactionFee	   Fixed transaction fee in satoshis
    function setPegOutTransactionFee(uint64 _transactionFee) external onlyGovernor {
        (, uint64 oldTransactionFee) = pegOutFeeConfig.transactionFees.getLatestTransactionFee();
        pegOutFeeConfig.transactionFees.setTransactionFee(_transactionFee);

        emit PegOutTransactionFeeUpdated(oldTransactionFee, _transactionFee);
    }

    /// @notice	Sets the treasury fee rate for peg-out operations
    /// @dev	Only governor can update fee rates.
    ///         Rate must be less than PERCENTAGE_BASE (100%)
    /// @param	_rate	   Treasury fee rate in basis points (e.g., 100 = 1%)
    function setPegOutTreasuryFeeRate(uint16 _rate) external onlyGovernor {
        if (_rate >= PERCENTAGE_BASE) {
            revert TreasuryFeeRateExceedsMax(_rate);
        }

        (, uint16 oldRate) = pegOutFeeConfig.treasuryFeeRates.getLatestTreasuryFeeRate();
        pegOutFeeConfig.treasuryFeeRates.setTreasuryFeeRate(_rate);

        emit PegOutTreasuryFeeRateUpdated(oldRate, _rate);
    }

    /// @notice	Sets treasury fee distribution shares for peg-out operations
    /// @dev	Only governor can update fee distribution.
    ///         Recipients and shares arrays must have same length.
    ///         Total shares must equal PERCENTAGE_BASE
    /// @param	_recipients	   Array of fee recipient addresses
    /// @param	_shares	   Array of fee shares in basis points
    function setPegOutTreasuryFeeShares(
        address[] calldata _recipients,
        uint16[] calldata _shares
    ) external onlyGovernor {
        _requireValidRecipientsAndSharesLength(_recipients, _shares);
        _requireTotalSharesEqualsBase(_shares);

        (
            ,
            address[] memory oldRecipients,
            uint16[] memory oldShares
        ) = pegOutFeeConfig.treasuryFeeShares.getLatestTreasuryFeeShares();

        pegOutFeeConfig.treasuryFeeShares.setTreasuryFeeShares(
            _recipients,
            _shares
        );

        emit PegOutTreasuryFeeSharesUpdated(
            oldRecipients,
            oldShares,
            _recipients,
            _shares
        );
    }

    /// @notice	Gets the required Bitcoin confirmations for a custodian
    /// @dev	Returns default confirmations if custodian has no specific setting
    /// @param	_custodianId	   ID of the custodian
    /// @return	Number	of required Bitcoin confirmations
    function getBitcoinConfirmations(uint32 _custodianId) external override view returns (uint32) {
        uint32 confirmations = custodianConfigs[_custodianId].bitcoinConfirmations;

        return confirmations == 0 ? DEFAULT_BITCOIN_CONFIRMATIONS : confirmations;
    }

    /// @notice	Gets the required native confirmations for a custodian
    /// @dev	Returns default confirmations if custodian has no specific setting
    /// @param	_custodianId	   ID of the custodian
    /// @return	Number	of required native confirmations
    function getNativeConfirmations(uint32 _custodianId) external override view returns (uint32) {
        uint32 confirmations = custodianConfigs[_custodianId].nativeConfirmations;

        return confirmations == 0 ? DEFAULT_NATIVE_CONFIRMATIONS : confirmations;
    }

    /// @notice	Gets the minimum deposit dust amount for peg-in operations
    /// @dev	Retrieves amount threshold from time-series data
    /// @param	_timestamp	   Timestamp to query the dust amount for
    /// @return	amount	   Minimum deposit amount in satoshis
    function getPegInDepositDustAmount(
        uint64 _timestamp
    ) external override view returns (uint64 amount) {
        amount = pegInFeeConfig.amountThresholds.getAmountThreshold(_timestamp);
    }

    /// @notice	Gets the treasury fee rate for peg-in operations
    /// @dev	Retrieves fee rate from time-series data
    /// @param	_timestamp	   Timestamp to query the fee rate for
    /// @return	rate	   Treasury fee rate in basis points
    function getPegInTreasuryFeeRate(
        uint64 _timestamp
    ) external override view returns (uint16 rate) {
        rate = pegInFeeConfig.treasuryFeeRates.getTreasuryFeeRate(_timestamp);
    }

    /// @notice	Gets the treasury fee distribution shares for peg-in operations
    /// @dev	Retrieves recipients and shares from time-series data
    /// @param	_timestamp	   Timestamp to query the fee shares for
    /// @return	receipients	   Array of fee recipient addresses
    /// @return	shares	   Array of fee shares in basis points
    function getPegInTreasuryFeeShares(
        uint64 _timestamp
    ) external override view returns (
        address[] memory receipients,
        uint16[] memory shares
    ) {
        (receipients, shares) = pegInFeeConfig.treasuryFeeShares.getTreasuryFeeShares(_timestamp);
    }

    /// @notice	Gets the minimum redeem dust amount for peg-out operations
    /// @dev	Retrieves amount threshold from time-series data
    /// @param	_timestamp	   Timestamp to query the dust amount for
    /// @return	amount	   Minimum redeem amount in satoshis
    function getPegOutRedeemDustAmount(
        uint64 _timestamp
    ) external override view returns (uint64 amount) {
        amount = pegOutFeeConfig.amountThresholds.getAmountThreshold(_timestamp);
    }

    /// @notice	Gets the fixed transaction fee for peg-out operations
    /// @dev	Retrieves transaction fee from time-series data
    /// @param	_timestamp	   Timestamp to query the transaction fee for
    /// @return	fee	   Fixed transaction fee in satoshis
    function getPegOutTransactionFee(
        uint64 _timestamp
    ) external override view returns (uint64 fee) {
        fee = pegOutFeeConfig.transactionFees.getTransactionFee(_timestamp);
    }

    /// @notice	Gets the treasury fee rate for peg-out operations
    /// @dev	Retrieves fee rate from time-series data
    /// @param	_timestamp	   Timestamp to query the fee rate for
    /// @return	rate	   Treasury fee rate in basis points
    function getPegOutTreasuryFeeRate(
        uint64 _timestamp
    ) external override view returns (uint16 rate) {
        rate = pegOutFeeConfig.treasuryFeeRates.getTreasuryFeeRate(_timestamp);
    }

    /// @notice	Gets the treasury fee distribution shares for peg-out operations
    /// @dev	Retrieves recipients and shares from time-series data
    /// @param	_timestamp	   Timestamp to query the fee shares for
    /// @return	receipients	   Array of fee recipient addresses
    /// @return	shares	   Array of fee shares in basis points
    function getPegOutTreasuryFeeShares(
        uint64 _timestamp
    ) external override view returns (
        address[] memory receipients,
        uint16[] memory shares
    ) {
        (receipients, shares) = pegOutFeeConfig.treasuryFeeShares.getTreasuryFeeShares(_timestamp);
    }

    /// @notice	Validates that a custodian ID is whitelisted
    /// @dev	Checks if the custodian exists in the whitelist registry
    /// @param	_custodianId	   ID of the custodian to validate
    function _requireValidCustodianId(uint32 _custodianId) internal view {
        IWhitelistRegistry whitelistRegistry = IWhitelistRegistry(
            ILstBTCBridge(bridge).whitelistRegistry()
        );

        if (!whitelistRegistry.isWhitelistedCustomGroup(_custodianId)) {
            revert UnauthorizedCustodian(_custodianId);
        }
    }

    /// @notice	Validates that recipients and shares arrays have valid lengths
    /// @dev	Ensures arrays are not empty and have matching lengths
    /// @param	_recipients	   Array of fee recipient addresses
    /// @param	_shares	   Array of fee shares in basis points
    function _requireValidRecipientsAndSharesLength(
        address[] calldata _recipients,
        uint16[] calldata _shares
    ) internal pure {
        if (_recipients.length == 0) {
            revert RecipientsEmpty();
        }

        if (_recipients.length != _shares.length) {
            revert RecipientsSharesLengthMismatch(_recipients.length, _shares.length);
        }
    }

    /// @notice	Validates that total shares equal the base percentage
    /// @dev	Ensures fee distribution shares sum to 100%
    /// @param	_shares	   Array of fee shares to validate
    function _requireTotalSharesEqualsBase(uint16[] calldata _shares) internal pure {
        uint256 totalShares;

        for (uint256 i = 0; i < _shares.length; ++i) {
            totalShares += _shares[i];
        }

        if (totalShares != PERCENTAGE_BASE) {
            revert TotalSharesMismatch(PERCENTAGE_BASE, totalShares);
        }
    }
}
