// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @title IWhitelistRegistry
 * @dev Interface for the whitelist registry contract
 *
 * This interface defines the functions and events for the whitelist registry,
 * which manages authorized addresses and script public keys for the lstBTC protocol.
 * The registry supports:
 * - Group-based address management (reserved and custom groups)
 * - Multiple address formats (native chain addresses and Bitcoin script public keys)
 * - Usage-based permissions (outbound, inbound, operations, yield, borrow, repayment)
 * - Dynamic address addition and removal
 *
 * The registry ensures only authorized addresses can participate in protocol operations
 * and provides flexible group management for different custodians and use cases.
 */
interface IWhitelistRegistry {
    /// @notice Emitted when a new whitelist group is created
    /// @param groupId ID of the created group
    /// @param rawAddresses Array of raw address bytes in the group
    /// @param formats Array of address formats (ADDRESS_FORMAT_NATIVE, ADDRESS_FORMAT_BTC)
    /// @param usages Array of usage bitmaps for each address
    event WhitelistGroupCreated(
        uint32 indexed groupId,
        bytes[] rawAddresses,
        uint8[] formats,
        uint8[] usages
    );

    /// @notice Emitted when a whitelist group is removed
    /// @param groupId ID of the removed group
    event WhitelistGroupRemoved(
        uint32 indexed groupId
    );

    /// @notice Emitted when new entries are added to a whitelist group
    /// @param groupId ID of the group receiving the entries
    /// @param rawAddresses Array of raw address bytes being added
    /// @param formats Array of address formats for the new entries
    /// @param usages Array of usage bitmaps for the new entries
    event WhitelistEntryAdded(
        uint32 indexed groupId,
        bytes[] rawAddresses,
        uint8[] formats,
        uint8[] usages
    );

    /// @notice Emitted when entries are removed from a whitelist group
    /// @param groupId ID of the group losing the entries
    /// @param rawAddresses Array of raw address bytes being removed
    /// @param formats Array of address formats for the removed entries
    /// @param usages Array of usage bitmaps for the removed entries
    event WhitelistEntryRemoved(
        uint32 indexed groupId,
        bytes[] rawAddresses,
        uint8[] formats,
        uint8[] usages
    );

    /// @notice Emitted when whitelist entries are updated
    /// @param groupId ID of the group containing the updated entries
    /// @param formats Array of address formats for the updated entries
    /// @param usages Array of usage bitmaps for the updated entries
    /// @param oldRawAddresses Array of old raw address bytes
    /// @param newRawAddresses Array of new raw address bytes
    event WhitelistEntryUpdated(
        uint32 indexed groupId,
        uint8[] formats,
        uint8[] usages,
        bytes[] oldRawAddresses,
        bytes[] newRawAddresses
    );

    /// @notice Checks if an address is whitelisted
    /// @param _rawAddress Raw address bytes to check
    /// @return Whether the address is whitelisted
    function isWhitelisted(bytes calldata _rawAddress) external view returns (bool);

    /// @notice Checks if a group ID belongs to a reserved group
    /// @param _groupId Group ID to check
    /// @return Whether the group is a reserved group
    function isWhitelistedReservedGroup(uint32 _groupId) external view returns (bool);

    /// @notice Checks if a group ID belongs to a custom group
    /// @param _groupId Group ID to check
    /// @return Whether the group is a custom group
    function isWhitelistedCustomGroup(uint32 _groupId) external view returns (bool);

    /// @notice Finds the first whitelisted address in an array of addresses
    /// @dev Iterates through the provided address array and returns the index of the first whitelisted address.
    /// This function is commonly used in bridge operations to identify which output address in a Bitcoin
    /// transaction is authorized for cross-chain operations. Returns early on first match for gas efficiency.
    /// @param _rawAddresses Array of raw address bytes to search through
    /// @return found Whether a whitelisted address was found in the array
    /// @return index Index of the first whitelisted address (meaningful only if found is true)
    function findFirstWhitelistedIndex(bytes[] calldata _rawAddresses) external view returns (bool, uint256);

    /// @notice Gets the whitelist entry information for an address
    /// @param _rawAddress Raw address bytes to query
    /// @return groupId ID of the group containing the address (0 if not found)
    /// @return usage Usage bitmap for the address (0 if not found)
    function getWhitelistEntry(bytes calldata _rawAddress) external view returns (uint32, uint8);
}
