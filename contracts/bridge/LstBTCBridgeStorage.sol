// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../types/DataTypes.sol";
import "./interfaces/ILstBTCBridgeStorage.sol";

contract LstBTCBridgeStorage is ILstBTCBridgeStorage {
    /// @notice	Structure representing a batch of peg-in and peg-out requests
    /// @dev	Batches are used to group related requests for efficient processing and settlement.
    ///            Each batch contains requests from the same custodian and can be settled together.
    ///            This structure tracks the settlement status and request IDs for both peg-in and peg-out operations.
    /// @param	isPegInSettled	   Flag indicating whether all peg-in requests in this batch have been settled
    /// @param	isPegOutSettled	   Flag indicating whether all peg-out requests in this batch have been settled
    /// @param	pegInIds	   Array of request IDs for peg-in operations in this batch
    /// @param	pegOutIds	   Array of request IDs for peg-out operations in this batch
    struct Batch {
        bool isPegInSettled;
        bool isPegOutSettled;
        uint256[] pegInIds;
        uint256[] pegOutIds;
    }

    /// @notice	Structure representing custodian data including debt and batch information
    /// @dev	This structure tracks the debt owed to a custodian and the batches they are responsible for.
    ///            Debt represents the amount of lstBTC tokens owed to the custodian for their services.
    /// @param	debt	Amount of lstBTC tokens owed to the custodian
    /// @param	batches	Array of batch IDs that this custodian is responsible for
    struct CustodianData {
        uint64 debt;
        uint32[] batches;
    }

    /// @notice	Counter for generating unique request IDs
    uint256 public override requestIdCounter;

    /// @notice	Counter for generating unique batch IDs
    uint32 public override batchIdCounter;

    /// @notice	Total debt across all custodians
    uint64 public override totalDebt;

    /// @notice	Address of the configuration registry contract
    address public override configRegistry;

    /// @notice	Address of the NAV provider contract
    address public override navProvider;

    /// @notice	Address of the whitelist registry contract
    address public override whitelistRegistry;

    /// @notice	Address of the Bitcoin relay contract
    address public override bitcoinRelay;

    /// @notice	Address of the lstBTC token contract
    address public override lstBTC;

    /// @notice	Mapping of transaction ID to whether it has been proven
    mapping (bytes32 => bool) public provenTransactions;

    /// @notice	Mapping of request ID to peg-in request details
    mapping (uint256 => PegRequest) public pegInRequests;

    /// @notice	Mapping of request ID to peg-out request details
    mapping (uint256 => PegRequest) public pegOutRequests;

    /// @notice	Mapping of batch ID to batch information
    mapping (uint256 => Batch) public batches;

    /// @notice	Mapping of custodian ID to custodian data
    mapping (uint256 => CustodianData) public custodianDatas;

    /// @notice	Mapping of address to claimable fee amount
    mapping (address => uint64) public claimableFees;

    uint256[50] private __gap;
}
