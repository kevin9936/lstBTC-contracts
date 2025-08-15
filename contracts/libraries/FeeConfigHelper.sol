// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./TimeSeriesDataLib.sol";

/**
 * @title FeeConfigHelper
 * @dev Helper library for managing fee configurations in the lstBTC protocol
 *
 * This library provides functions for:
 * - Retrieving fee configurations from time-series data
 * - Setting new fee configurations
 * - Managing amount thresholds, transaction fees, treasury fee rates, and fee shares
 *
 * The library works with TimeSeriesDataLib to maintain historical fee data
 * and provides both timestamp-specific and latest value retrieval methods.
 */
library FeeConfigHelper {

    using TimeSeriesDataLib for TimeSeriesDataLib.TimeSeriesData;

    /// @notice Gets the amount threshold for a specific timestamp
    /// @dev Reverts if threshold is not available for the timestamp
    /// @param _amountThresholds Time-series data storage for amount thresholds
    /// @param _timestamp Timestamp to query threshold for
    /// @return amount Threshold amount at the specified timestamp
    function getAmountThreshold(
        TimeSeriesDataLib.TimeSeriesData storage _amountThresholds,
        uint64 _timestamp
    ) internal view returns (uint64 amount) {
        (bool exists, bytes memory encodedValue) = _amountThresholds.get(_timestamp);
        require(exists, "FeeConfigHelper: fetch amount threshold failed");

        amount = abi.decode(encodedValue, (uint64));
    }

    /// @notice Gets the latest amount threshold
    /// @dev Returns false if no threshold is available
    /// @param _amountThresholds Time-series data storage for amount thresholds
    /// @return exists Whether a threshold exists
    /// @return amount Latest threshold amount
    function getLatestAmountThreshold(
        TimeSeriesDataLib.TimeSeriesData storage _amountThresholds
    ) internal view returns (bool exists, uint64 amount) {
        bytes memory encodedValue;
        (exists, , encodedValue) = _amountThresholds.getLatest();

        if (exists) {
            amount = abi.decode(encodedValue, (uint64));
        }
    }

    /// @notice Gets the transaction fee for a specific timestamp
    /// @dev Reverts if fee is not available for the timestamp
    /// @param _transactionFees Time-series data storage for transaction fees
    /// @param _timestamp Timestamp to query fee for
    /// @return transactionFee Transaction fee at the specified timestamp
    function getTransactionFee(
        TimeSeriesDataLib.TimeSeriesData storage _transactionFees,
        uint64 _timestamp
    ) internal view returns (uint64 transactionFee) {
        (bool exists, bytes memory encodedValue) = _transactionFees.get(_timestamp);
        require(exists, "FeeConfigHelper: fetch transaction fee failed");

        transactionFee = abi.decode(encodedValue, (uint64));
    }

    /// @notice Gets the latest transaction fee
    /// @dev Returns false if no fee is available
    /// @param _transactionFees Time-series data storage for transaction fees
    /// @return exists Whether a fee exists
    /// @return transactionFee Latest transaction fee
    function getLatestTransactionFee(
        TimeSeriesDataLib.TimeSeriesData storage _transactionFees
    ) internal view returns (bool exists, uint64 transactionFee) {
        bytes memory encodedValue;
        (exists, , encodedValue) = _transactionFees.getLatest();

        if (exists) {
            transactionFee = abi.decode(encodedValue, (uint64));
        }
    }

    /// @notice Gets the treasury fee rate for a specific timestamp
    /// @dev Reverts if rate is not available for the timestamp
    /// @param _treasuryFeeRates Time-series data storage for treasury fee rates
    /// @param _timestamp Timestamp to query rate for
    /// @return rate Treasury fee rate at the specified timestamp
    function getTreasuryFeeRate(
        TimeSeriesDataLib.TimeSeriesData storage _treasuryFeeRates,
        uint64 _timestamp
    ) internal view returns (uint16 rate) {
        (bool exists, bytes memory encodedValue) = _treasuryFeeRates.get(_timestamp);
        require(exists, "FeeConfigHelper: fetch treasury fee rate failed");

        rate = abi.decode(encodedValue, (uint16));
    }

    /// @notice Gets the latest treasury fee rate
    /// @dev Returns false if no rate is available
    /// @param _treasuryFeeRates Time-series data storage for treasury fee rates
    /// @return exists Whether a rate exists
    /// @return rate Latest treasury fee rate
    function getLatestTreasuryFeeRate(
        TimeSeriesDataLib.TimeSeriesData storage _treasuryFeeRates
    ) internal view returns (bool exists, uint16 rate) {
        bytes memory encodedValue;
        (exists, , encodedValue) = _treasuryFeeRates.getLatest();

        if (exists) {
            rate = abi.decode(encodedValue, (uint16));
        }
    }

    /// @notice Gets the treasury fee shares for a specific timestamp
    /// @dev Reverts if shares are not available for the timestamp
    /// @param _treasuryFeeShares Time-series data storage for treasury fee shares
    /// @param _timestamp Timestamp to query shares for
    /// @return recipients Array of fee recipient addresses
    /// @return recipientAmounts Array of fee share amounts for each recipient
    function getTreasuryFeeShares(
        TimeSeriesDataLib.TimeSeriesData storage _treasuryFeeShares,
        uint64 _timestamp
    ) internal view returns (
        address[] memory recipients,
        uint16[] memory recipientAmounts
    ) {
        (bool exists, bytes memory encodedValue) =  _treasuryFeeShares.get(_timestamp);
        require(exists, "FeeConfigHelper: fetch treasury fee shares failed");

        (recipients, recipientAmounts) = abi.decode(encodedValue, (address[], uint16[]));
    }

    /// @notice Gets the latest treasury fee shares
    /// @dev Returns false if no shares are available
    /// @param _treasuryFeeShares Time-series data storage for treasury fee shares
    /// @return exists Whether shares exist
    /// @return recipients Array of fee recipient addresses
    /// @return recipientAmounts Array of fee share amounts for each recipient
    function getLatestTreasuryFeeShares(
        TimeSeriesDataLib.TimeSeriesData storage _treasuryFeeShares
    ) internal view returns (
        bool exists,
        address[] memory recipients,
        uint16[] memory recipientAmounts
    ) {
        bytes memory encodedValue;
        (exists, , encodedValue) =  _treasuryFeeShares.getLatest();

        if (exists) {
            (recipients, recipientAmounts) = abi.decode(encodedValue, (address[], uint16[]));
        }
    }

    /// @notice Sets a new amount threshold
    /// @dev Appends the threshold to the time-series data
    /// @param _amountThresholds Time-series data storage for amount thresholds
    /// @param _amount New threshold amount to set
    function setAmountThreshold(
        TimeSeriesDataLib.TimeSeriesData storage _amountThresholds,
        uint64 _amount
    ) internal {
        _amountThresholds.append(abi.encode(_amount));
    }

    /// @notice Sets a new transaction fee
    /// @dev Appends the fee to the time-series data
    /// @param _transactionFees Time-series data storage for transaction fees
    /// @param _amount New transaction fee to set
    function setTransactionFee(
        TimeSeriesDataLib.TimeSeriesData storage _transactionFees,
        uint64 _amount
    ) internal {
        _transactionFees.append(abi.encode(_amount));
    }

    /// @notice Sets a new treasury fee rate
    /// @dev Appends the rate to the time-series data
    /// @param _treasuryFeeRates Time-series data storage for treasury fee rates
    /// @param _rate New treasury fee rate to set
    function setTreasuryFeeRate(
        TimeSeriesDataLib.TimeSeriesData storage _treasuryFeeRates,
        uint16 _rate
    ) internal {
        _treasuryFeeRates.append(abi.encode(_rate));
    }

    /// @notice Sets new treasury fee shares
    /// @dev Appends the shares to the time-series data
    /// @param _treasuryFeeShares Time-series data storage for treasury fee shares
    /// @param _recipients Array of fee recipient addresses
    /// @param _shares Array of fee share amounts for each recipient
    function setTreasuryFeeShares(
        TimeSeriesDataLib.TimeSeriesData storage _treasuryFeeShares,
        address[] calldata _recipients,
        uint16[] calldata _shares
    ) internal {
        _treasuryFeeShares.append(abi.encode(_recipients, _shares));
    }
}
