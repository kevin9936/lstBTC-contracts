// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title AccessControlBase
 * @dev Base contract for access control in the lstBTC protocol
 *
 * This contract provides a standardized access control system with:
 * - Admin role with full control over the protocol
 * - Governor role for operational decisions
 * - Role-based access control using OpenZeppelin's AccessControl
 * - Upgradeable design for future modifications
 *
 * The contract defines common modifiers and error handling for
 * consistent access control across all protocol contracts.
 */
abstract contract AccessControlBase is Initializable, AccessControlUpgradeable {
    /// @notice Thrown when a zero address is provided where not allowed
    /// @dev Used to validate that addresses are not zero before performing operations
    error ZeroAddress();

    /// @notice Thrown when an unauthorized address attempts an operation
    /// @dev Used when an address without proper permissions tries to call restricted functions
    /// @param caller Address that attempted the unauthorized operation
    error Unauthorized(address caller);

    // Role for operational governance decisions (governors can perform operational functions but not admin functions)
    bytes32 public constant ROLE_GOVERNOR = keccak256("ROLE_GOVERNOR");

    /// @notice Initializes the access control system
    /// @dev Sets up admin and governor roles with proper permissions.
    /// Can only be called once during contract initialization
    /// @param _admin Address to be granted admin role with full control
    /// @param _governor Address to be granted governor role for operations
    function __AccessControlBase_init(
        address _admin,
        address _governor
    ) internal onlyInitializing nonZeroAddress(_admin) nonZeroAddress(_governor) {
        AccessControlUpgradeable.__AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ROLE_GOVERNOR, _governor);

        // Any role's admin defaults to DEFAULT_ADMIN_ROLE (0x00)
        // The following settings do not change state, only improve readability
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ROLE_GOVERNOR, DEFAULT_ADMIN_ROLE);
    }

    /// @notice Ensures only admin can call the function
    /// @dev Checks if caller has DEFAULT_ADMIN_ROLE
    modifier onlyAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _;
    }

    /// @notice Ensures only governor or admin can call the function
    /// @dev Checks if caller has either DEFAULT_ADMIN_ROLE or ROLE_GOVERNOR
    modifier onlyGovernor() {
        _checkRole(ROLE_GOVERNOR, _msgSender());
        _;
    }

    /// @notice Ensures the provided address is not zero
    /// @dev Reverts with ZeroAddress error if address is zero
    /// @param _account Address to validate
    modifier nonZeroAddress(address _account) {
        if (_account == address(0)) { revert ZeroAddress(); }
        _;
    }
}
