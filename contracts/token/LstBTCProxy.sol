// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title LstBTCProxy
 * @dev Proxy contract for the lstBTC token implementation
 *
 * This contract acts as a proxy for the LstBTCLogic implementation,
 * allowing for upgradeable token functionality. It uses OpenZeppelin's
 * ERC1967Proxy pattern for secure and efficient proxy operations.
 *
 * The proxy delegates all calls to the implementation contract while
 * maintaining the same storage layout for upgradeability.
 */
contract LstBTCProxy is ERC1967Proxy {

    /// @notice Initializes the proxy contract
    /// @dev Sets up the proxy with the implementation contract and initialization data
    /// @param _logic Address of the implementation contract
    /// @param _data Initialization data for the implementation contract
    constructor(
        address _logic,
        bytes memory _data
    ) payable ERC1967Proxy(_logic, _data) {}

}