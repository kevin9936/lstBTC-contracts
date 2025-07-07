// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title ILstBTC
 * @dev Interface for the lstBTC token contract
 *
 * This interface defines the functions and events for the lstBTC token,
 * which represents Bitcoin pegged into the protocol. The token supports:
 * - Minting and burning by authorized addresses (bridge, custodians)
 * - Role-based access control for minters, burners, and blacklisters
 * - Blacklisting functionality for security
 * - Configurable mint limits and bridge address
 *
 * The token follows the ERC20 standard with additional protocol-specific features.
 */
interface ILstBTC is IERC20Upgradeable {
    /// @notice Emitted when new lstBTC tokens are minted
    /// @param doer Address that performed the mint operation
    /// @param receiver Address that received the minted tokens
    /// @param value Amount of tokens minted
    event Mint(address indexed doer, address indexed receiver, uint value);

    /// @notice Emitted when lstBTC tokens are burned
    /// @param doer Address that performed the burn operation
    /// @param burner Address whose tokens were burned
    /// @param value Amount of tokens burned
    event Burn(address indexed doer, address indexed burner, uint value);

    /// @notice Emitted when a new minter is added
    /// @param newMinter Address of the newly added minter
    event MinterAdded(address indexed newMinter);

    /// @notice Emitted when a minter is removed
    /// @param minter Address of the removed minter
    event MinterRemoved(address indexed minter);

    /// @notice Emitted when a new burner is added
    /// @param newBurner Address of the newly added burner
    event BurnerAdded(address indexed newBurner);

    /// @notice Emitted when a burner is removed
    /// @param burner Address of the removed burner
    event BurnerRemoved(address indexed burner);

    /// @notice Emitted when the bridge address is updated
    /// @param oldBridge Previous bridge address
    /// @param newBridge New bridge address
    event NewBridge(address indexed oldBridge, address indexed newBridge);

    /// @notice Emitted when the maximum mint limit is updated
    /// @param oldMintLimit Previous mint limit
    /// @param newMintLimit New mint limit
    event NewMintLimit(uint oldMintLimit, uint newMintLimit);

    /// @notice Emitted when an account is blacklisted
    /// @param account Address that was blacklisted
    event Blacklisted(address indexed account);

    /// @notice Emitted when an account is removed from blacklist
    /// @param account Address that was unblacklisted
    event UnBlacklisted(address indexed account);

    /// @notice Emitted when a new blacklister is added
    /// @param newBlackLister Address of the newly added blacklister
    event BlackListerAdded(address indexed newBlackLister);

    /// @notice Emitted when a blacklister is removed
    /// @param blackLister Address of the removed blacklister
    event BlackListerRemoved(address indexed blackLister);

    /// @notice Returns the number of decimals used by the token
    /// @return Number of decimal places
    function decimals() external view returns (uint8);

    /// @notice Returns the address of the bridge contract
    /// @return Address of the bridge contract
    function bridge()  external view returns (address);

    /// @notice Returns the maximum amount that can be minted in a single operation
    /// @return Maximum mint limit
    function maxMintLimit() external view returns (uint);

    /// @notice Adds a new minter role
    /// @dev Only callable by admin
    /// @param account Address to grant minter role
    function addMinter(address account) external;

    /// @notice Removes minter role from an address
    /// @dev Only callable by admin
    /// @param account Address to revoke minter role from
    function removeMinter(address account) external;

    /// @notice Adds a new burner role
    /// @dev Only callable by admin
    /// @param account Address to grant burner role
    function addBurner(address account) external;

    /// @notice Removes burner role from an address
    /// @dev Only callable by admin
    /// @param account Address to revoke burner role from
    function removeBurner(address account) external;

    /// @notice Mints new lstBTC tokens to a receiver
    /// @dev Only callable by authorized minters
    /// @param receiver Address to receive the minted tokens
    /// @param amount Amount of tokens to mint
    /// @return success Whether the mint operation was successful
    function mint(address receiver, uint amount) external returns(bool);

    /// @notice Burns lstBTC tokens from the caller
    /// @dev Only callable by authorized burners
    /// @param amount Amount of tokens to burn
    /// @return success Whether the burn operation was successful
    function burn(uint amount) external returns(bool);

    /// @notice Burns lstBTC tokens from a specific user
    /// @dev Only callable by authorized burners
    /// @param _user Address whose tokens to burn
    /// @param _amount Amount of tokens to burn
    /// @return success Whether the burn operation was successful
    function ownerBurn(address _user, uint _amount) external returns (bool);

    /// @notice Sets the bridge contract address
    /// @dev Only callable by admin
    /// @param _bridge New bridge contract address
    function setBridge(address _bridge) external;

    /// @notice Sets the maximum mint limit
    /// @dev Only callable by admin
    /// @param _mintLimit New maximum mint limit
    function setMaxMintLimit(uint _mintLimit) external;

    /// @notice Adds a new blacklister role
    /// @dev Only callable by admin
    /// @param account Address to grant blacklister role
    function addBlackLister(address account) external;

    /// @notice Removes blacklister role from an address
    /// @dev Only callable by admin
    /// @param account Address to revoke blacklister role from
    function removeBlackLister(address account) external;

    /// @notice Blacklists an account, preventing it from transferring tokens
    /// @dev Only callable by authorized blacklisters
    /// @param _account Address to blacklist
    function blacklist(address _account) external;

    /// @notice Removes an account from the blacklist
    /// @dev Only callable by authorized blacklisters
    /// @param _account Address to remove from blacklist
    function unBlacklist(address _account) external;
}