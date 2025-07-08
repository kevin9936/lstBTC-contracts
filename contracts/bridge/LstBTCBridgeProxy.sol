// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title LstBTCBridgeProxy
 * @dev Proxy contract for the lstBTC bridge implementation
 *
 * This contract acts as a proxy for the LstBTCBridgeLogic implementation,
 * allowing for upgradeable bridge functionality. It uses OpenZeppelin's
 * ERC1967Proxy pattern for secure and efficient proxy operations.
 *
 * The proxy delegates all calls to the implementation contract while
 * maintaining the same storage layout for upgradeability.
 */
contract LstBTCBridgeProxy is ERC1967Proxy {

    /// @notice Initializes the proxy contract
    /// @dev Sets up the proxy with the implementation contract and initialization data
    /// @param _logic Address of the implementation contract
    /// @param _data Initialization data for the implementation contract
    constructor(
        address _logic,
        bytes memory _data
    ) payable ERC1967Proxy(_logic, _data) {}

}