// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../types/DataTypes.sol";
import "./interfaces/ILstBTCBridgeStorage.sol";

contract LstBTCBridgeStorage is ILstBTCBridgeStorage {
    /// @notice	Structure representing a batch of peg-in and peg-out requests
    /// @dev	Batches are used to group related requests for efficient processing and settlement.
    ///		    Each batch contains requests from the same custodian and can be settled together.
    ///		    This structure tracks the settlement status and request IDs for both peg-in and peg-out operations.
    /// @param	isPegInSettled	Flag indicating whether all peg-in requests in this batch have been settled
    /// @param	isPegOutSettled	Flag indicating whether all peg-out requests in this batch have been settled
    /// @param	pegInIds	Array of request IDs for peg-in operations in this batch
    /// @param	pegOutIds	Array of request IDs for peg-out operations in this batch
    struct Batch {
        bool isPegInSettled;
        bool isPegOutSettled;
        uint256[] pegInIds;
        uint256[] pegOutIds;
    }

    struct CustodianData {
        uint64 debt;
        uint32[] batches;
    }

    // Counter for generating unique request IDs
    uint256 public override requestIdCounter;

    // Counter for generating unique batch IDs
    uint32 public override batchIdCounter;

    // Total debt across all custodians
    uint64 public override totalDebt;

    // Address of the configuration registry contract
    address public override configRegistry;

    // Address of the NAV provider contract
    address public override navProvider;

    // Address of the whitelist registry contract
    address public override whitelistRegistry;

    // Address of the Bitcoin relay contract
    address public override bitcoinRelay;

    // Address of the lstBTC token contract
    address public override lstBTC;

    // Mapping of transaction ID to whether it has been proven (txId => bool)
    mapping (bytes32 => bool) public provenTransactions;

    // Mapping of request ID to peg-in request details
    mapping (uint256 => PegRequest) public pegInRequests;

    // Mapping of request ID to peg-out request details
    mapping (uint256 => PegRequest) public pegOutRequests;

    // Mapping of batch ID to batch information (batchId => batch)
    mapping (uint256 => Batch) public batches;

    // Mapping of custodian ID to array of custodian data (custodianId => data)
    mapping (uint256 => CustodianData) public custodianDatas;

    // Mapping of request ID to array of fee recipient addresses
    mapping (uint256 => address[]) public stagedRecipients;

    // Mapping of request ID to array of treasury fee amounts
    mapping (uint256 => uint64[]) public stagedTreasuryFees;

    // Mapping of address to claimable fee amount
    mapping (address => uint64) public claimableFees;

    uint256[50] private __gap;
}
