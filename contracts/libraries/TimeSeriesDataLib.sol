// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @title TimeSeriesDataLib
 * @dev Library for managing time-series data with efficient storage and retrieval
 *
 * This library provides a data structure for storing values associated with timestamps,
 * optimized for scenarios where values change infrequently over time. It uses:
 * - An array of timestamps for efficient binary search
 * - A mapping from timestamp to encoded values for storage
 * - Automatic deduplication when values don't change
 *
 * The library is designed for storing configuration data, fee rates, and other
 * time-dependent values in the lstBTC protocol.
 */
library TimeSeriesDataLib {
    /// @notice	Structure for storing time-series data
    /// @dev	Uses separate arrays and mappings for efficient storage and retrieval
    struct TimeSeriesData {
        uint64[] timestamps;                // Array of timestamps for binary search
        mapping(uint64 => bytes) values;    // Mapping from timestamp to encoded value
    }

    /// @notice	Initializes a time-series data structure with the first entry
    /// @dev	Can only be called once per TimeSeriesData instance.
    ///            Reverts if already initialized
    /// @param	_timeSeriesData	   Storage reference to the time-series data
    /// @param	_timestamp	   Initial timestamp for the first entry
    /// @param	_encodedValue	   Encoded value to store at the timestamp
    function initialize(
        TimeSeriesData storage _timeSeriesData,
        uint64 _timestamp,
        bytes memory _encodedValue
    ) internal {
        uint256 len = _timeSeriesData.timestamps.length;
        require(len == 0, "TimeSeriesDataLib: already initialized");

        _timeSeriesData.timestamps.push(_timestamp);
        _timeSeriesData.values[_timestamp] = _encodedValue;
    }

    /// @notice	Appends a new value to the time-series data
    /// @dev	Only adds a new entry if the value has changed from the last entry.
    ///            Uses current block timestamp if no timestamp is provided.
    ///            Ensures timestamps are strictly increasing
    /// @param	_timeSeriesData	   Storage reference to the time-series data
    /// @param	_encodedValue	   Encoded value to append
    function append(
        TimeSeriesData storage _timeSeriesData,
        bytes memory _encodedValue
    ) internal {
        uint64 timestamp = uint64(block.timestamp);

        if (_timeSeriesData.timestamps.length == 0) {
            _timeSeriesData.timestamps.push(timestamp);
            _timeSeriesData.values[timestamp] = _encodedValue;
            return;
        }

        uint64 lastTimestamp = _timeSeriesData.timestamps[
            _timeSeriesData.timestamps.length - 1
        ];

        require(
            timestamp > lastTimestamp,
            "TimeSeriesDataLib: timestamp must be strictly increasing"
        );

        bytes storage lastValue = _timeSeriesData.values[lastTimestamp];
        bool isValueChanged =
            lastValue.length != _encodedValue.length ||
            keccak256(lastValue) != keccak256(_encodedValue);

        if (isValueChanged) {
            _timeSeriesData.timestamps.push(timestamp);
            _timeSeriesData.values[timestamp] = _encodedValue;
        }
    }

    /// @notice	Removes the most recent entry from the time-series data
    /// @dev	   This is the counterpart to `append`. It deletes the last timestamp and its associated value.
    ///         No action is taken if the time-series is empty.
    /// @param		_timeSeriesData Storage reference to the time-series data
    /// @return	removed	Whether an entry was successfully removed
    function pop(
        TimeSeriesData storage _timeSeriesData
    ) internal returns (bool removed) {
        uint256 len = _timeSeriesData.timestamps.length;
        if (len == 0) { return false; }

        uint64 timestamp = _timeSeriesData.timestamps[len - 1];
        delete _timeSeriesData.values[timestamp];
        _timeSeriesData.timestamps.pop();

        return true;
    }

    /// @notice	Gets the value for a specific timestamp using binary search
    /// @dev	Returns the value at the most recent timestamp <= the query timestamp.
    ///            Returns false if no data exists or timestamp is before all data
    /// @param	_timeSeriesData	   Storage reference to the time-series data
    /// @param	_timestamp	   Timestamp to query value for
    /// @return	exists	   Whether a value exists for the timestamp
    /// @return	encodedValue	   The encoded value at the most recent timestamp <= query timestamp
    function get(
        TimeSeriesData storage _timeSeriesData,
        uint64 _timestamp
    ) internal view returns (bool exists, bytes memory encodedValue) {
        uint256 len = _timeSeriesData.timestamps.length;
        if (len == 0) { return (exists, encodedValue); }

        uint256 left = 0;
        uint256 right = len - 1;

        while (left < right) {
            uint256 mid = (left + right + 1) / 2;
            if (_timeSeriesData.timestamps[mid] <= _timestamp) {
                left = mid;
            } else {
                right = mid - 1;
            }
        }

        if (_timeSeriesData.timestamps[left] <= _timestamp) {
            encodedValue = _timeSeriesData.values[
                _timeSeriesData.timestamps[left]
            ];
            exists = true;
        }
    }

    /// @notice	Gets the latest value in the time-series data
    /// @dev	Returns false if no data exists
    /// @param	_timeSeriesData	   Storage reference to the time-series data
    /// @return	exists	   Whether any data exists
    /// @return	encodedValue	   The encoded value at the most recent timestamp
    function getLatest(
        TimeSeriesData storage _timeSeriesData
    ) internal view returns (bool exists, bytes memory encodedValue) {
        uint256 len = _timeSeriesData.timestamps.length;
        if (len == 0) { return (exists, encodedValue); }

        encodedValue = _timeSeriesData.values[
            _timeSeriesData.timestamps[len - 1]
        ];
        exists = true;
    }
}
