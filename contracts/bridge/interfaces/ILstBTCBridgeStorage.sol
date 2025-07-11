// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ILstBTCBridgeStorage {

    function requestIdCounter() external view returns (uint256);

    function batchIdCounter() external view returns (uint32);

    function totalDebt() external view returns (uint64);

    function configRegistry() external view returns (address);

    function navProvider() external view returns (address);

    function whitelistRegistry() external view returns (address);

    function bitcoinTxStore() external view returns (address);

    function lstBTC() external view returns (address);
}
