// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @dev Common data types and constants used throughout the lstBTC protocol
 *
 * This file defines:
 * - Address usage constants for whitelist management
 * - Address format constants for different address types
 * - Transfer type enumerations for categorizing operations
 * - Peg status enumerations for request lifecycle management
 * - Data structures for peg requests and other protocol data
 */

/**
 * @title AddressUsage
 * @dev Address permission constants for whitelist management
 */
library AddressUsage {
    // Address can be used for outbound transfers (user to operations)
    uint8 constant OUTBOUND  = 1;

    // Address can be used for inbound transfers (operations to user)
    uint8 constant INBOUND   = 1 << 1;

    // Address can be used for operations (custodian operations)
    uint8 constant OPERATIONS= 1 << 2;

    // Address can be used for yield distribution
    uint8 constant YIELD     = 1 << 3;

    // Address can be used for borrowing operations
    uint8 constant BORROW    = 1 << 4;

    // Address can be used for repayment operations
    uint8 constant REPAYMENT = 1 << 5;
}

/// @notice Types of transfers that can occur in the protocol
/// @dev Used to categorize different types of Bitcoin and token transfers
enum TransferType {
    Unknown,        // Transfer type cannot be determined
    PegInDeposited, // Bitcoin deposited for peg-in (user -> operations)
    PegInRefunded,  // Bitcoin refunded from peg-in (operations -> user)
    PegInPaid,      // lstBTC minted for peg-in (operations -> user)
    PegOutDeposited,// lstBTC deposited for peg-out (user -> operations)
    PegOutRefunded, // lstBTC refunded from peg-out (operations -> user)
    PegOutPaid,     // Bitcoin paid for peg-out (operations -> user)
    YieldReceived,  // Yield received from custodian operations
    Borrowed,       // Bitcoin borrowed from custodian
    Repaid          // Bitcoin repaid to custodian
}

/// @notice Status of a peg-in or peg-out request
/// @dev Tracks the lifecycle of requests through the protocol
enum PegStatus {
    Unknown,        // Request status is unknown or invalid
    Pending,        // Request is pending finality confirmation
    Rejected,       // Request has been rejected by custodian
    PendingPayout,  // Request is confirmed and pending payout
    PendingRefund,  // Request is rejected and pending refund
    Paid,           // Request has been paid out successfully
    Refunded        // Request has been refunded successfully
}

/// @notice Structure representing a peg-in or peg-out request
/// @dev Contains all necessary information for processing and tracking requests
struct PegRequest {
    uint64 amount;          // Original request amount (in satoshis)
    uint64 treasuryFee;     // Treasury fee amount (in satoshis)
    uint64 transactionFee;  // Transaction fee amount (in satoshis)
    uint64 netAmount;       // Net amount after fees (in satoshis)
    uint64 depositedAt;     // Timestamp when request was deposited
    PegStatus status;       // Current status of the request
    uint32 finalityHeight;  // Block height when request achieves finality
    uint32 custodianId;     // ID of the custodian handling the request
    uint32 batchId;         // ID of the batch containing this request
}
