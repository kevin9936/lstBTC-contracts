// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../types/DataTypes.sol";
import "./interfaces/IWhitelistRegistry.sol";
import "../access/AccessControlBase.sol";
import "../libraries/BtcUtils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title WhitelistRegistryLogic
 * @dev Central whitelist registry for managing authorized addresses and script public keys
 *
 * This contract manages whitelisted addresses for the lstBTC protocol including:
 * - Bitcoin script public keys (P2PKH, P2SH, P2WPKH, P2WSH, P2TR)
 * - Native chain addresses (Ethereum, Core, etc.)
 * - Address usage permissions (outbound, inbound, operations, yield, borrow, repayment)
 * - Group-based address management
 *
 * The contract supports both reserved groups (system-managed) and custom groups
 * (user-managed) for flexible address organization.
 */
contract WhitelistRegistryLogic is IWhitelistRegistry, AccessControlBase, UUPSUpgradeable {
    /// @notice Thrown when the specified group does not exist
    error GroupNotFound(uint32 groupId);

    /// @notice Thrown when trying to remove a reserved group
    error NotCustomGroup(uint32 groupId);

    /// @notice Thrown when input arrays have different lengths
    error EntryArrayLengthMismatch();

    /// @notice Thrown when reserved group address has invalid usage
    error InvalidReservedGroupAddressUsage(uint8 usage);

    /// @notice Thrown when custom group address has invalid usage
    error InvalidCustomGroupAddressUsage(uint8 usage);

    /// @notice Thrown when reserved group address has invalid format
    error InvalidReservedGroupAddressFormat(uint8 usage);

    /// @notice Thrown when native address format is invalid
    error InvalidNativeAddress(bytes rawAddress);

    /// @notice Thrown when Bitcoin script public key format is invalid
    error InvalidBTCPkScript(bytes rawAddress);

    /// @notice Thrown when address format is not supported
    error InvalidAddressFormat(uint8 format);

    /// @notice Thrown when address is already used in the same group with same usage
    error AddressAlreadyUsed(bytes rawAddress, uint32 groupId, uint8 usage);

    /// @notice Thrown when trying to add an entry that was previously removed
    error CannotAddRemovedEntry(bytes rawAddress, uint32 groupId, uint8 usage);

    /// @notice Thrown when entry status does not match expected status
    error EntryStatusMismatch(EntryStatus expectedStatus, EntryStatus actualStatus);

    /// @notice Thrown when entry group ID does not match expected group ID
    error EntryGroupIdMismatch(uint32 expectedGroupId, uint32 actualGroupId);

    /// @notice Thrown when entry usage does not match expected usage
    error EntryUsageMismatch(uint8 expectedUsage, uint8 actualUsage);

    /// @notice Status of a whitelist entry
    enum EntryStatus {
        Unknown,    // Entry not found or invalid
        Active,     // Entry is active and can be used
        Removed     // Entry has been removed and cannot be used
    }

    /// @notice Structure representing a whitelist entry
    struct WhitelistEntry {
        uint8 usage;        // Bitmap of allowed usages (outbound, inbound, operations, etc.)
        uint8 format;       // Address format (native, BTC)
        bytes rawAddress;   // Raw address bytes (20 bytes for native, variable for BTC)
        EntryStatus status; // Current status of the entry
        uint32 groupId;     // Group ID this entry belongs to
    }

    /// @notice Structure representing a whitelist group
    struct WhitelistGroup {
        bool exists;        // Whether the group exists
        bytes32[] entryKeys; // Array of entry keys in this group
    }

    /// @notice Native chain address format (Ethereum, Core, etc.)
    uint8 constant ADDRESS_FORMAT_NATIVE = 1;

    /// @notice Bitcoin script public key format
    uint8 constant ADDRESS_FORMAT_BTC = 2;

    /// @notice Reserved group ID for system-managed addresses
    uint32 public constant RESERVED_GROUP_ID = 10000;

    /// @notice Role for managing group members
    bytes32 public constant ROLE_GROUP_MEMBER_OPERATOR = keccak256("ROLE_GROUP_MEMBER_OPERATOR");

    /// @notice Next available group ID for custom groups
    uint32 public nextGroupId;

    /// @notice Mapping of group ID to group information
    mapping (uint256 => WhitelistGroup) public whitelistGroups;

    /// @notice Mapping of entry key to entry information
    mapping (bytes32 => WhitelistEntry) public whitelistEntries;

    using BtcUtils for bytes;

    /// @notice Ensures the specified group exists
    modifier onlyGroupExists(uint32 _groupId) {
        if (!_isGroupExists(_groupId)) {
            revert GroupNotFound(_groupId);
        }
        _;
    }

    /// @notice Ensures caller has group member operator permissions
    modifier onlyGroupMemberOperator() {
        _checkRole(ROLE_GROUP_MEMBER_OPERATOR, _msgSender());
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the whitelist registry
    /// @dev Sets up access control and creates the reserved group
    /// @param _admin Default admin address with full control
    /// @param _governor Governor address for operational decisions
    function initialize(
        address _admin,
        address _governor
    ) public initializer {
        AccessControlBase.__AccessControlBase_init(_admin, _governor);
        UUPSUpgradeable.__UUPSUpgradeable_init();

        _setRoleAdmin(ROLE_GROUP_MEMBER_OPERATOR, ROLE_GOVERNOR);

        whitelistGroups[RESERVED_GROUP_ID].exists = true;
        nextGroupId = RESERVED_GROUP_ID + 1;
    }

    /// @notice Authorizes contract upgrades
    /// @dev Only governor can upgrade the contract implementation
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}

    /// @notice Creates a new whitelist group with initial entries
    /// @dev Only governor can create groups.
    /// Validates all entries before creating the group
    /// @param _rawAddresses Array of raw address bytes
    /// @param _formats Array of address formats (ADDRESS_FORMAT_NATIVE, ADDRESS_FORMAT_BTC)
    /// @param _usages Array of usage bitmaps
    function createGroup(
        bytes[] calldata _rawAddresses,
        uint8[] calldata _formats,
        uint8[] calldata _usages
    ) external onlyGovernor {
        _validateEntryArrayLengths(
            _rawAddresses,
            _formats,
            _usages
        );

        uint32 groupId = nextGroupId++;

        uint256 entryCount = _usages.length;
        for (uint256 i = 0; i < entryCount; ++i) {
            _addEntryToGroup(
                groupId,
                _rawAddresses[i],
                _formats[i],
                _usages[i]
            );
        }

        whitelistGroups[groupId].exists = true;

        emit WhitelistGroupCreated(
            groupId,
            _rawAddresses,
            _formats,
            _usages
        );
    }

    /// @notice Removes a custom whitelist group and marks all entries as removed
    /// @dev Only governor can remove groups.
    /// Cannot remove reserved groups
    /// @param _groupId The group ID to remove
    function removeGroup(uint32 _groupId) external onlyGovernor {
        if (!isWhitelistedCustomGroup(_groupId)) {
            revert NotCustomGroup(_groupId);
        }

        bytes32[] storage entryKeys = whitelistGroups[_groupId].entryKeys;
        uint256 entryCount = entryKeys.length;

        for (uint256 i = 0; i < entryCount; ++i) {
            WhitelistEntry storage storedEntry = whitelistEntries[entryKeys[i]];
            if (storedEntry.status != EntryStatus.Active) {
                revert EntryStatusMismatch(EntryStatus.Active, storedEntry.status);
            }

            storedEntry.status = EntryStatus.Removed;
        }

        delete whitelistGroups[_groupId];

        emit WhitelistGroupRemoved(_groupId);
    }

    /// @notice Adds new entries to an existing group
    /// @dev Only group member operators can add entries.
    /// Validates all entries before adding them
    /// @param _groupId The group ID to add entries to
    /// @param _rawAddresses Array of raw address bytes
    /// @param _formats Array of address formats
    /// @param _usages Array of usage bitmaps
    function addEntriesToGroup(
        uint32 _groupId,
        bytes[] calldata _rawAddresses,
        uint8[] calldata _formats,
        uint8[] calldata _usages
    ) external onlyGroupMemberOperator onlyGroupExists(_groupId) {
        _validateEntryArrayLengths(
            _rawAddresses,
            _formats,
            _usages
        );

        uint256 entryCount = _usages.length;
        for (uint256 i = 0; i < entryCount; ++i) {
            _addEntryToGroup(
                _groupId,
                _rawAddresses[i],
                _formats[i],
                _usages[i]
            );
        }

        emit WhitelistEntryAdded(
            _groupId,
            _rawAddresses,
            _formats,
            _usages
        );
    }

    /// @notice Removes entries from a group by marking them as removed
    /// @dev Only group member operators can remove entries.
    /// Validates all entries before removing them
    /// @param _groupId The group ID to remove entries from
    /// @param _rawAddresses Array of raw address bytes
    /// @param _formats Array of address formats
    /// @param _usages Array of usage bitmaps
    function removeEntriesFromGroup(
        uint32 _groupId,
        bytes[] calldata _rawAddresses,
        uint8[] calldata _formats,
        uint8[] calldata _usages
    ) external onlyGroupMemberOperator onlyGroupExists(_groupId) {
        _validateEntryArrayLengths(
            _rawAddresses,
            _formats,
            _usages
        );

        uint256 entryCount = _usages.length;
        for (uint256 i = 0; i < entryCount; ++i) {
            _removeEntryFromGroup(
                _groupId,
                _rawAddresses[i],
                _usages[i]
            );
        }

        emit WhitelistEntryRemoved(
            _groupId,
            _rawAddresses,
            _formats,
            _usages
        );
    }

    /// @notice Updates entries in a group by replacing old addresses with new ones
    /// @dev Only governor can update entries.
    /// Validates all entries before updating them
    /// @param _groupId The group ID to update entries in
    /// @param _formats Array of new address formats
    /// @param _usages Array of usage bitmaps
    /// @param _oldRawAddresses Array of old raw address bytes
    /// @param _newRawAddresses Array of new raw address bytes
    function updateEntriesInGroup(
        uint32 _groupId,
        uint8[] calldata _formats,
        uint8[] calldata _usages,
        bytes[] calldata _oldRawAddresses,
        bytes[] calldata _newRawAddresses
    ) external onlyGovernor onlyGroupExists(_groupId) {
        _validateEntryArrayLengths(
            _formats,
            _usages,
            _oldRawAddresses,
            _newRawAddresses
        );

        uint256 updateCount = _usages.length;
        for (uint256 i = 0; i < updateCount; ++i) {
            _updateEntryInGroup(
                _groupId,
                _formats[i],
                _usages[i],
                _oldRawAddresses[i],
                _newRawAddresses[i]
            );
        }

        emit WhitelistEntryUpdated(
            _groupId,
            _formats,
            _usages,
            _oldRawAddresses,
            _newRawAddresses
        );
    }

    /// @notice Checks if an address is whitelisted
    /// @param _rawAddress Raw address bytes to check
    /// @return True if the address is whitelisted, false otherwise
    function isWhitelisted(bytes calldata _rawAddress) public override view returns (bool) {
        return whitelistEntries[keccak256(_rawAddress)].status == EntryStatus.Active;
    }

    /// @notice Checks if a group is a whitelisted reserved group
    /// @param _groupId Group ID to check
    /// @return True if the group is a whitelisted reserved group, false otherwise
    function isWhitelistedReservedGroup(uint32 _groupId) public override view returns (bool) {
        if (!whitelistGroups[_groupId].exists) { return false; }

        return _isReservedGroupId(_groupId);
    }

    /// @notice Checks if a group is a whitelisted custom group
    /// @param _groupId Group ID to check
    /// @return True if the group is a whitelisted custom group, false otherwise
    function isWhitelistedCustomGroup(uint32 _groupId) public override view returns (bool) {
        if (!whitelistGroups[_groupId].exists) { return false; }

        return _isCustomGroupId(_groupId);
    }

    /// @notice Gets whitelist entry information for an address
    /// @param _rawAddress Raw address bytes to get entry for
    /// @return groupId Group ID of the entry (0 if not found)
    /// @return usage Usage bitmap of the entry (0 if not found)
    function getWhitelistEntry(
        bytes calldata _rawAddress
    ) external override view returns (
        uint32 groupId,
        uint8 usage
    ) {
        WhitelistEntry storage entry = whitelistEntries[keccak256(_rawAddress)];

        if (entry.status == EntryStatus.Active) {
            groupId = entry.groupId;
            usage = entry.usage;
        }
    }

    /// @notice Gets whitelist group information for a specific group ID
    /// @dev Returns the existence status and all entry keys for the specified group.
    /// Entry keys are keccak256 hashes of raw addresses used as mapping keys.
    /// This function allows querying group structure without accessing individual entries
    /// @param _groupId ID of the group to query
    /// @return exists Whether the group exists
    /// @return entryKeys Array of entry keys (keccak256 hashes) in this group
    function getWhitelistGroup(
        uint32 _groupId
    ) external view returns (
        bool exists,
        bytes32[] memory entryKeys
    ) {
        WhitelistGroup storage group = whitelistGroups[_groupId];
        return (group.exists, group.entryKeys);
    }

    /// @notice Gets all group IDs based on filter criteria
    /// @dev Returns a compacted array of group IDs meeting the criteria
    /// @param _includeReservedGroup Whether to include the reserved group
    /// @param _includeEmptyGroup Whether to include empty groups
    /// @return groupIds Array of group IDs meeting the criteria
    function getGroupIds(
        bool _includeReservedGroup,
        bool _includeEmptyGroup
    ) external view returns (uint32[] memory groupIds) {
        (uint32 startId, uint32 endId) = _getGroupIdRange(_includeReservedGroup);
        if (startId >= endId) {
            return groupIds;
        }

        uint32 count;
        groupIds = new uint32[](endId-startId);

        for (uint32 i = startId; i < endId; ++i) {
            if (!_isGroupExists(i)) {
                continue;
            }

            if (_isGroupEmpty(i) && !_includeEmptyGroup) {
                continue;
            }
            groupIds[count++] = i;
        }

        if (count == groupIds.length) {
            return groupIds;
        }

        uint32[] memory compactIds = new uint32[](count);
        for (uint32 i = 0; i < count; ++i) {
            compactIds[i] = groupIds[i];
        }

        return compactIds;
    }

    /// @notice Gets all entries for a specific group
    /// @dev Returns arrays of addresses, formats, and usages for the group
    /// @param _groupId ID of the group to get entries for
    /// @return rawAddresses Array of raw address bytes
    /// @return formats Array of address formats
    /// @return usages Array of usage bitmaps
    function getGroupEntries(uint32 _groupId) external view onlyGroupExists(_groupId) returns (
        bytes[] memory rawAddresses,
        uint8[] memory formats,
        uint8[] memory usages
    ) {
        bytes32[] storage entryKeys = whitelistGroups[_groupId].entryKeys;
        uint256 entryCount = entryKeys.length;

        usages = new uint8[](entryCount);
        formats = new uint8[](entryCount);
        rawAddresses = new bytes[](entryCount);

        for (uint256 i = 0; i < entryCount; ++i) {
            rawAddresses[i] = whitelistEntries[entryKeys[i]].rawAddress;
            formats[i] = whitelistEntries[entryKeys[i]].format;
            usages[i] = whitelistEntries[entryKeys[i]].usage;
        }
    }

    /// @notice Checks if a whitelist group exists
    /// @param _groupId ID of the group to check
    /// @return True if the group exists, false otherwise
    function _isGroupExists(uint32 _groupId) internal view returns (bool) {
        return whitelistGroups[_groupId].exists;
    }
    /// @notice Checks if a whitelist group has no entries
    /// @param _groupId ID of the group to check
    /// @return True if the group is empty, false otherwise
    function _isGroupEmpty(uint32 _groupId) internal view returns (bool) {
        return whitelistGroups[_groupId].entryKeys.length == 0;
    }

    /// @notice Checks if a group ID is the reserved group ID
    /// @param _groupId ID to check
    /// @return True if it's the reserved group ID, false otherwise
    function _isReservedGroupId(uint32 _groupId) internal pure returns (bool) {
        return _groupId == RESERVED_GROUP_ID;
    }

    /// @notice Checks if a group ID is a custom group ID
    /// @param _groupId ID to check
    /// @return True if it's a custom group ID, false otherwise
    function _isCustomGroupId(uint32 _groupId) internal pure returns (bool) {
        return _groupId > RESERVED_GROUP_ID;
    }

    /// @notice Gets the range of group IDs based on inclusion criteria
    /// @dev Returns start and end IDs for group iteration
    /// @param _includeReservedGroup Whether to include reserved group in range
    /// @return startId Starting group ID
    /// @return endId Ending group ID (exclusive)
    function _getGroupIdRange(
        bool _includeReservedGroup
    ) internal view returns (uint32, uint32) {
        uint32 startId = RESERVED_GROUP_ID + 1;
        uint32 endId = nextGroupId;

        if (_includeReservedGroup) {
            startId = RESERVED_GROUP_ID;
        }

        return (startId, endId);
    }

    /// @notice Validates that entry arrays have matching lengths
    /// @dev Ensures all arrays have the same length and are not empty
    /// @param _rawAddresses Array of raw address bytes
    /// @param _formats Array of address formats
    /// @param _usages Array of usage bitmaps
    function _validateEntryArrayLengths(
        bytes[] calldata _rawAddresses,
        uint8[] calldata _formats,
        uint8[] calldata _usages
    ) internal pure {
        uint256 entryCount = _rawAddresses.length;

        bool isEmpty = entryCount == 0;
        bool isLengthMisMatch =
            entryCount != _formats.length ||
            entryCount != _usages.length;

        if (isEmpty || isLengthMisMatch) {
            revert EntryArrayLengthMismatch();
        }
    }

    /// @notice Validates that update entry arrays have matching lengths
    /// @dev Ensures all arrays have the same length and are not empty
    /// @param _formats Array of address formats
    /// @param _usages Array of usage bitmaps
    /// @param _oldRawAddresses Array of old raw address bytes
    /// @param _newRawAddresses Array of new raw address bytes
    function _validateEntryArrayLengths(
        uint8[] calldata _formats,
        uint8[] calldata _usages,
        bytes[] calldata _oldRawAddresses,
        bytes[] calldata _newRawAddresses
    ) internal pure {
        uint256 entryCount = _oldRawAddresses.length;

        bool isEmpty = entryCount == 0;
        bool isLengthMisMatch =
            entryCount != _formats.length ||
            entryCount != _usages.length ||
            entryCount != _newRawAddresses.length;

        if (isEmpty || isLengthMisMatch) {
            revert EntryArrayLengthMismatch();
        }
    }

    /// @notice Validates that an address usage is valid for the given group
    /// @dev Different groups have different allowed usage types
    /// @param _groupId ID of the group
    /// @param _usage Usage type to validate
    function _requireEntryValidUsage(uint32 _groupId, uint8 _usage) internal pure {
        if (_isReservedGroupId(_groupId)) {

            bool isValidReservedUsage =
                _usage == AddressUsage.YIELD ||
                _usage == AddressUsage.BORROW ||
                _usage == AddressUsage.REPAYMENT;

            if (!isValidReservedUsage) {
                revert InvalidReservedGroupAddressUsage(_usage);
            }

            return;
        }

        if (_isCustomGroupId(_groupId)) {
            bool isValidCustomUsage =
                _usage == AddressUsage.OUTBOUND ||
                _usage == AddressUsage.INBOUND ||
                _usage == AddressUsage.OPERATIONS;

            if (!isValidCustomUsage) {
                revert InvalidCustomGroupAddressUsage(_usage);
            }
            return;
        }

        revert GroupNotFound(_groupId);
    }

    /// @notice Validates that an address format is valid for the given group
    /// @dev Different groups have different allowed address formats
    /// @param _groupId ID of the group
    /// @param _format Address format to validate
    /// @param _rawAddress Raw address bytes to validate
    function _requireEntryValidFormat(
        uint32 _groupId,
        uint8 _format,
        bytes calldata _rawAddress
    ) internal pure {
        if (_isReservedGroupId(_groupId)) {
            if (_format != ADDRESS_FORMAT_BTC) {
                revert InvalidReservedGroupAddressFormat(_format);
            }
        }

        if (_format == ADDRESS_FORMAT_NATIVE) {
            if (_rawAddress.length != 20) {
                revert InvalidNativeAddress(_rawAddress);
            }
            return;
        }

        if (_format == ADDRESS_FORMAT_BTC) {
            if (!_rawAddress.isValidPkScript()) {
                revert InvalidBTCPkScript(_rawAddress);
            }
            return;
        }

        revert InvalidAddressFormat(_format);
    }

    /// @notice Validates that an address entry has no conflicts
    /// @dev Checks for address reuse and shared usage conflicts
    /// @param _groupId ID of the group
    /// @param _usage Usage type to check
    /// @param _rawAddress Raw address bytes to check
    function _requireEntryNoConflict(
        uint32 _groupId,
        uint8 _usage,
        bytes calldata _rawAddress
    ) internal view {
        bytes32 entryKey = keccak256(_rawAddress);
        WhitelistEntry storage storedEntry = whitelistEntries[entryKey];

        if (storedEntry.status == EntryStatus.Unknown) { return; }

        if (storedEntry.groupId != _groupId) {
            revert AddressAlreadyUsed(_rawAddress, storedEntry.groupId, storedEntry.usage);
        }

        bool isSharedUsage =
            (_usage == AddressUsage.BORROW && storedEntry.usage == AddressUsage.REPAYMENT) ||
            (_usage == AddressUsage.REPAYMENT && storedEntry.usage == AddressUsage.BORROW);

        if (!isSharedUsage) {
            revert AddressAlreadyUsed(_rawAddress, storedEntry.groupId, storedEntry.usage);
        }
    }

    /// @notice Adds an entry to a whitelist group
    /// @dev Validates entry and updates storage accordingly
    /// @param _groupId ID of the group to add entry to
    /// @param _rawAddress Raw address bytes
    /// @param _format Address format
    /// @param _usage Usage type for the address
    function _addEntryToGroup(
        uint32 _groupId,
        bytes calldata _rawAddress,
        uint8 _format,
        uint8 _usage
    ) internal {
        _requireEntryValidUsage(_groupId, _usage);
        _requireEntryValidFormat(_groupId, _format, _rawAddress);
        _requireEntryNoConflict(_groupId, _usage, _rawAddress);

        bytes32 entryKey = keccak256(_rawAddress);
        WhitelistEntry storage storedEntry = whitelistEntries[entryKey];

        if (storedEntry.status == EntryStatus.Unknown) {
            storedEntry.usage = _usage;
            storedEntry.status = EntryStatus.Active;
            storedEntry.format = _format;
            storedEntry.rawAddress = _rawAddress;
            storedEntry.groupId = _groupId;
            whitelistGroups[_groupId].entryKeys.push(entryKey);
            return;
        }

        if (storedEntry.status == EntryStatus.Active) {
            storedEntry.usage |= _usage;
            return;
        }

        revert CannotAddRemovedEntry(_rawAddress, _groupId, storedEntry.usage);
    }

    /// @notice Removes an entry from a whitelist group
    /// @dev Updates usage or removes entry entirely based on remaining usages
    /// @param _groupId ID of the group to remove entry from
    /// @param _rawAddress Raw address bytes
    /// @param _usage Usage type to remove
    function _removeEntryFromGroup(
        uint32 _groupId,
        bytes calldata _rawAddress,
        uint8 _usage
    ) internal {
        bytes32 entryKey = keccak256(_rawAddress);
        WhitelistEntry storage storedEntry = whitelistEntries[entryKey];

        if (storedEntry.status != EntryStatus.Active) {
            revert EntryStatusMismatch(EntryStatus.Active, storedEntry.status);
        }

        if (storedEntry.groupId != _groupId) {
            revert EntryGroupIdMismatch(_groupId, storedEntry.groupId);
        }

        if ((storedEntry.usage & _usage) != _usage) {
            revert EntryUsageMismatch(_usage, storedEntry.usage);
        }

        if (storedEntry.usage != _usage) {
            storedEntry.usage &= ~_usage;
        } else {
            storedEntry.status = EntryStatus.Removed;
            _removeEntryKeyFromGroup(_groupId, entryKey);
        }
    }

    /// @notice Removes an entry key from a group's entry keys array
    /// @dev Removes an entryKey from the specified group's entryKeys array.
    /// This is an infrequent operation, and each group is expected to contain a limited
    /// number of entries (typically less than a few dozen), so a linear search is acceptable
    /// and helps keep the storage structure simple and gas-efficient
    /// @param _groupId ID of the group to remove entry key from
    /// @param _entryKey Entry key to remove from the group
    function _removeEntryKeyFromGroup(
        uint32 _groupId,
        bytes32 _entryKey
    ) internal {
        bytes32[] storage entryKeys = whitelistGroups[_groupId].entryKeys;
        uint256 entryCount = entryKeys.length;

        uint256 i = 0;
        for (; i < entryCount; ++i) {
            if (_entryKey == entryKeys[i]) {
                break;
            }
        }

        if (i == entryCount) { return; }

        if (i < entryCount - 1) {
            entryKeys[i] = entryKeys[entryCount-1];
        }

        entryKeys.pop();
    }

    /// @notice Updates an entry in a whitelist group
    /// @dev Removes old entry and adds new entry
    /// @param _groupId ID of the group to update entry in
    /// @param _format New address format
    /// @param _usage Usage type for the address
    /// @param _oldRawAddress Old raw address bytes
    /// @param _newRawAddress New raw address bytes
    function _updateEntryInGroup(
        uint32 _groupId,
        uint8 _format,
        uint8 _usage,
        bytes calldata _oldRawAddress,
        bytes calldata _newRawAddress
    ) internal {
        _removeEntryFromGroup(_groupId, _oldRawAddress, _usage);
        _addEntryToGroup(_groupId, _newRawAddress, _format, _usage);
    }
}
