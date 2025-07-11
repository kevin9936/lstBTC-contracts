// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../types/DataTypes.sol";
import "../nav/interfaces/INavProvider.sol";
import "../bitcoin-tx-store/interfaces/IBitcoinTxStore.sol";
import "../bridge/interfaces/ILstBTCBridge.sol";
import "../whitelist/interfaces/IWhitelistRegistry.sol";
import "../configuration/interfaces/IConfigRegistry.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title PegRequestHelper
 * @dev Helper library for managing peg-in and peg-out requests in the lstBTC protocol
 *
 * This library provides functions for:
 * - Analyzing Bitcoin and wrapped BTC transfers to determine transfer types
 * - Initializing and managing peg-in/peg-out requests
 * - Calculating fees and amounts for different operations
 * - Processing batch operations and refunds
 *
 * The library handles the complex logic of determining whether a transfer
 * represents a peg-in, peg-out, yield, borrow, or repayment operation.
 */
library PegRequestHelper {
    // Base for percentage calculations (10000 = 100%)
    uint16 public constant PERCENTAGE_BASE = 10000;

    using SafeCast for uint256;

    /// @notice Analyzes a Bitcoin transfer to determine its type and custodian
    /// @dev Validates the transfer structure and checks whitelist entries for both sender and receiver addresses.
    /// Determines transfer type based on usage patterns and custodian groups
    /// @param fromGroupId Group ID of the fromAddress's entry
    /// @param fromUsage Usage bitmap of the fromAddress's entry
    /// @param toGroupId Group ID of the toAddress's entry
    /// @param toUsage Usage bitmap of the toAddress's entry
    /// @return custodianId ID of the custodian involved in the transfer
    /// @return transferType Type of transfer (PegInDeposited, PegOutPaid, YieldReceived, etc.)
    function analyzeBTCTransfer(
        uint32 fromGroupId,
        uint8 fromUsage,
        uint32 toGroupId,
        uint8 toUsage
    ) external view returns (uint32, TransferType) {
        if (fromGroupId != toGroupId) {
            if (fromUsage == AddressUsage.YIELD && toUsage == AddressUsage.OPERATIONS) {
                return (toGroupId, TransferType.YieldReceived);
            }

            if ((fromUsage & AddressUsage.BORROW) == AddressUsage.BORROW &&
                toUsage == AddressUsage.OPERATIONS) {
                return (toGroupId, TransferType.Borrowed);
            }

            if (fromUsage == AddressUsage.OPERATIONS &&
                (toUsage & AddressUsage.REPAYMENT) == AddressUsage.REPAYMENT) {
                return (fromGroupId, TransferType.Repaid);
            }

        } else {
             if (fromUsage == AddressUsage.OUTBOUND && toUsage == AddressUsage.OPERATIONS) {
                return (fromGroupId, TransferType.PegInDeposited);
            }

            if (fromUsage == AddressUsage.OPERATIONS && toUsage == AddressUsage.INBOUND) {
                return (fromGroupId, TransferType.PegOutPaid);
            }

            if (fromUsage == AddressUsage.OPERATIONS && toUsage == AddressUsage.OUTBOUND) {
                return (fromGroupId, TransferType.PegInRefunded);
            }
        }

        return (0, TransferType.Unknown);
    }

    /// @notice Analyzes a wrapped BTC transfer to determine its type and custodian
    /// @dev Checks whitelist entries for both sender and receiver addresses.
    /// Only processes transfers within the same custodian group
    /// @param _bridge Bridge contract for accessing whitelist registry
    /// @param _fromAddress Address sending lstBTC tokens
    /// @param _toAddress Address receiving lstBTC tokens
    /// @return custodianId ID of the custodian involved in the transfer
    /// @return transferType Type of transfer (PegOutDeposited, PegInPaid, PegOutRefunded)
    function analyzeWrappedBTCTransfer(
        ILstBTCBridge _bridge,
        address _fromAddress,
        address _toAddress
    ) external view returns (uint32, TransferType) {
        IWhitelistRegistry whitelistRegistry = IWhitelistRegistry(_bridge.whitelistRegistry());

        (uint32 fromGroupId, uint8 fromUsage) = whitelistRegistry.getWhitelistEntry(
            abi.encodePacked(_fromAddress)
        );
        if (fromGroupId == 0 || fromUsage == 0) {
            return (0, TransferType.Unknown);
        }

        (uint32 toGroupId, uint8 toUsage) = whitelistRegistry.getWhitelistEntry(
            abi.encodePacked(_toAddress)
        );
        if (toGroupId == 0 || toUsage == 0) {
            return (0, TransferType.Unknown);
        }

        if (fromGroupId != toGroupId) {
            return (0, TransferType.Unknown);
        }

        if (fromUsage == AddressUsage.OUTBOUND && toUsage == AddressUsage.OPERATIONS) {
            return (fromGroupId, TransferType.PegOutDeposited);
        }

        if (fromUsage == AddressUsage.OPERATIONS && toUsage == AddressUsage.INBOUND) {
            return (fromGroupId, TransferType.PegInPaid);
        }

        if (fromUsage == AddressUsage.OPERATIONS && toUsage == AddressUsage.OUTBOUND) {
            return (fromGroupId, TransferType.PegOutRefunded);
        }

        return (0, TransferType.Unknown);
    }

    /// @notice Initializes a peg-in request with calculated fees and amounts
    /// @dev Sets up the request structure with all necessary parameters.
    /// Calculates treasury fees and determines fee recipients
    /// @param _request Storage reference to the peg request
    /// @param _bridge Bridge contract for accessing configuration
    /// @param _blockHeight Bitcoin block height of the deposit
    /// @param _amount Amount of Bitcoin deposited (in satoshis)
    /// @param _custodianId ID of the custodian handling the request
    /// @return exchangeRate Exchange rate at the time of deposit
    /// @return recipients Array of treasury fee recipients
    /// @return recipientAmounts Array of amounts for each recipient
    function initializePegInRequest(
        PegRequest storage _request,
        ILstBTCBridge _bridge,
        uint32 _blockHeight,
        uint64 _amount,
        uint32 _custodianId
    ) external returns (
        uint64 exchangeRate,
        address[] memory recipients,
        uint64[] memory recipientAmounts
    ) {

        _request.depositedAt = IBitcoinTxStore(_bridge.bitcoinTxStore()).getBlockTimestamp(_blockHeight);

        (
            exchangeRate,
            _request.treasuryFee,
            _request.netAmount
        ) = calculatePegInMintAmounts(
            _bridge,
            _amount,
            _request.depositedAt
        );

        IConfigRegistry configRegistry = IConfigRegistry(_bridge.configRegistry());
        (recipients, recipientAmounts) = calculatePegInTreasuryFeeSplits(_request, configRegistry);

        _request.amount = _amount;
        _request.finalityHeight = _blockHeight + configRegistry.getBitcoinConfirmations(_custodianId);
        _request.custodianId = _custodianId;
        _request.status = PegStatus.Pending;
    }

    /// @notice Initializes a peg-out request with calculated fees and amounts
    /// @dev Sets up the request structure with all necessary parameters.
    /// Calculates transaction and treasury fees
    /// @param _request Storage reference to the peg request
    /// @param _bridge Bridge contract for accessing configuration
    /// @param _amount Amount of lstBTC to redeem (in satoshis)
    /// @param _custodianId ID of the custodian handling the request
    /// @return exchangeRate Exchange rate at the time of request
    /// @return recipients Array of treasury fee recipients
    /// @return recipientAmounts Array of amounts for each recipient
    function initializePegOutRequest(
        PegRequest storage _request,
        ILstBTCBridge _bridge,
        uint64 _amount,
        uint32 _custodianId
    ) external returns (
        uint64 exchangeRate,
        address[] memory recipients,
        uint64[] memory recipientAmounts
    ) {
        _request.depositedAt = block.timestamp.toUint64();

        (
           exchangeRate,
           _request.transactionFee,
           _request.treasuryFee,
           _request.netAmount
        ) = calculatePegOutBurnAmounts(
            _bridge,
            _amount,
            _request.depositedAt
        );

        IConfigRegistry configRegistry = IConfigRegistry(_bridge.configRegistry());
        (recipients, recipientAmounts) = calculatePegOutTreasuryFeeSplits(_request, configRegistry);

        _request.amount = _amount;
        _request.finalityHeight = block.number.toUint32() + configRegistry.getNativeConfirmations(_custodianId);
        _request.custodianId = _custodianId;
        _request.status = PegStatus.Pending;
    }

    /// @notice Rejects a peg-in request and marks it for refund
    /// @dev Validates request status and custodian ID.
    /// Changes status to PendingRefund
    /// @param _request Storage reference to the peg request
    /// @param _custodianId ID of the custodian rejecting the request
    /// @param _batchId ID of the batch containing this request
    /// @return refundAmount Amount to be refunded (original deposit amount)
    function rejectPegInRequest(
        PegRequest storage _request,
        uint32 _custodianId,
        uint32 _batchId
    ) internal returns (uint64) {
        require(_request.status == PegStatus.Pending, "PegRequestHelper: mismatch request status");
        require(_request.custodianId == _custodianId, "PegRequestHelper: mismatch request custodianId");

        _request.batchId = _batchId;
        _request.status = PegStatus.PendingRefund;

        return _request.amount;
    }

    /// @notice Rejects a peg-out request and marks it for refund
    /// @dev Validates request status and custodian ID.
    /// Changes status to PendingRefund
    /// @param _request Storage reference to the peg request
    /// @param _custodianId ID of the custodian rejecting the request
    /// @param _batchId ID of the batch containing this request
    /// @return refundAmount Amount to be refunded (original lstBTC amount)
    function rejectPegOutRequest(
        PegRequest storage _request,
        uint32 _custodianId,
        uint32 _batchId
    ) internal returns (uint64) {
        require(_request.status == PegStatus.Pending, "PegRequestHelper: mismatch request status");
        require(_request.custodianId == _custodianId, "PegRequestHelper: mismatch request custodianId");

        _request.batchId = _batchId;
        _request.status = PegStatus.PendingRefund;

        return _request.amount;
    }

    /// @notice Settles a peg-out request by processing payout or refund
    /// @dev Validates request status and custodian ID.
    /// Updates request status based on settlement type
    /// @param _request Storage reference to the peg request
    /// @param _custodianId ID of the custodian settling the request
    /// @param _status Expected status for settlement (PendingPayout or PendingRefund)
    /// @return settledAmount Amount settled (net amount for payout, original amount for refund)
    function settlePegOutRequest(
        PegRequest storage _request,
        uint32 _custodianId,
        PegStatus _status
    ) internal returns (uint64 settledAmount) {
        require(_request.custodianId == _custodianId, "PegRequestHelper: mismatch request custodianId");
        require(_request.status == _status, "PegRequestHelper: mismatch request status");

        if (_status == PegStatus.PendingPayout) {
            settledAmount = _request.netAmount;
            _request.status = PegStatus.Paid;
        } else if (_status == PegStatus.PendingRefund) {
            settledAmount = _request.amount;
            _request.status = PegStatus.Refunded;
        }

        require(settledAmount != 0, "PegRequestHelper: invalid settled amount");
    }

    /// @notice Settles a peg-in request by processing payout or refund
    /// @dev Validates request status and custodian ID.
    /// Updates request status based on settlement type
    /// @param _request Storage reference to the peg request
    /// @param _custodianId ID of the custodian settling the request
    /// @param _status Expected status for settlement (PendingPayout or PendingRefund)
    /// @return settledAmount Amount settled (net amount for payout, original amount for refund)
    function settlePegInRequest(
        PegRequest storage _request,
        uint32 _custodianId,
        PegStatus _status
    ) internal returns (uint64 settledAmount) {
        require(_request.custodianId == _custodianId, "PegRequestHelper: mismatch request custodianId");
        require(_request.status == _status, "PegRequestHelper: mismatch request status");

        if (_status == PegStatus.PendingPayout) {
            settledAmount = _request.netAmount;
            _request.status = PegStatus.Paid;
        } else if (_status == PegStatus.PendingRefund) {
            settledAmount = _request.amount;
            _request.status = PegStatus.Refunded;
        }

        require(settledAmount != 0, "PegRequestHelper: invalid settled amount");
    }

    /// @notice Calculates treasury fee distribution for peg-in operations
    /// @dev Retrieves fee recipient addresses and their share percentages from configuration,
    /// then calculates the proportional amount each recipient should receive from the total treasury fee.
    /// Uses the deposit timestamp to get the fee configuration that was active at the time of deposit.
    /// @param _request Peg-in request containing treasury fee and deposit timestamp
    /// @param _configRegistry Configuration registry for fee recipient and share information
    /// @return recipients Array of fee recipient addresses
    /// @return recipientAmounts Array of fee amounts for each recipient (corresponds to recipients array)
    function calculatePegInTreasuryFeeSplits(
        PegRequest storage _request,
        IConfigRegistry _configRegistry
    ) internal view returns (
        address[] memory recipients,
        uint64[] memory recipientAmounts
    ) {
        uint16[] memory shares;
        (
            recipients,
            shares
        ) = _configRegistry.getPegInTreasuryFeeShares(
            _request.depositedAt
        );

        recipientAmounts = splitAmounts(shares, _request.treasuryFee);
    }

    /// @notice Calculates treasury fee distribution for peg-out operations
    /// @dev Retrieves fee recipient addresses and their share percentages from configuration,
    /// then calculates the proportional amount each recipient should receive from the total treasury fee.
    /// Uses the request timestamp to get the fee configuration that was active at the time of request creation.
    /// @param _request Peg-out request containing treasury fee and request timestamp
    /// @param _configRegistry Configuration registry for fee recipient and share information
    /// @return recipients Array of fee recipient addresses
    /// @return recipientAmounts Array of fee amounts for each recipient (corresponds to recipients array)
    function calculatePegOutTreasuryFeeSplits(
        PegRequest storage _request,
        IConfigRegistry _configRegistry
    ) internal view returns (
        address[] memory recipients,
        uint64[] memory recipientAmounts
    ) {
        uint16[] memory shares;
        (
            recipients,
            shares
        ) = _configRegistry.getPegOutTreasuryFeeShares(
            _request.depositedAt
        );

        recipientAmounts = splitAmounts(shares, _request.treasuryFee);
    }

    /// @notice Validates a standard Bitcoin transfer structure for peg-in/peg-out operations
    /// @dev Validates transaction structure
    /// @param _fromPkScripts Deduplicated input pkScripts from transaction inputs
    /// @param _toPkScripts Deduplicated output pkScripts from transaction outputs
    /// @return isValid True if transfer structure is valid and secure
    function isStandardTransfer(
        bytes[] calldata _fromPkScripts,
        bytes[] calldata _toPkScripts
    ) internal view returns (bool) {
        // Phase 1: Basic Structure Validation
        // Step 1: Ensure single source address type (all inputs from same pkScript)
        // _fromPkScripts contains deduplicated pkScripts from actual transaction inputs
        if (_fromPkScripts.length != 1) {
            return false;
        }

        // Step 2: Validate output structure (1 or 2 unique destination addresses)
        // _toPkScripts contains deduplicated pkScripts from actual transaction outputs
        // 1 output = direct transfer, 2 outputs = transfer + change back to source
        if (_toPkScripts.length != 1 && _toPkScripts.length != 2) {
            return false;
        }

        if (_toPkScripts.length == 2) {
            // Step 3: For dual outputs, verify destination and change addresses are different
            // Prevents suspicious transactions sending to same address twice
            if (bytesEqual(_toPkScripts[0], _toPkScripts[1])) {
                return false;
            }

            // Step 4: Verify second output is change back to source address
            // Ensures proper change handling in dual-output transactions
            if (!bytesEqual(_toPkScripts[1], _fromPkScripts[0])) {
                return false;
            }
        }
        return true;
    }

    /// @notice Validates a standard Bitcoin transfer structure for peg-in/peg-out operations
    /// @dev Validates transaction structure, script authenticity, and amount verification.
    /// Ensures external parameters match on-chain transaction data and security requirements
    /// @param _bitcoinTxStore Bitcoin tx store contract
    /// @param _txId Bitcoin transaction ID to validate
    /// @param _fromPkScript Unique input pkScript from transaction inputs
    /// @param _toPkScripts Deduplicated output pkScripts from transaction outputs
    /// @return isValid True if transfer structure is valid and secure
    /// @return amount Validated transfer amount in satoshi
    function validatePkScripts(
        IBitcoinTxStore _bitcoinTxStore,
        bytes32 _txId,
        bytes calldata _fromPkScript,
        bytes[] calldata _toPkScripts
    ) internal view returns (
        bool isValid,
        uint64 amount
    ) {
        // On-chain Data Consistency Verification
        uint256 outputCount = _bitcoinTxStore.getOutputCount(_txId);
        if (outputCount != _toPkScripts.length) {
            return (false, 0);
        }

        // Verify transaction actually spends from claimed source address
        // Prevents spoofing by ensuring all inputs come from the specified pkScript
        if (!_bitcoinTxStore.areAllInputsFromPkScript(_txId, _fromPkScript)) {
            return (false, 0);
        }

        // Handle double output scenario (direct transfer to destination)
        if (outputCount == 2) {
            (isValid, , ) = _bitcoinTxStore.findTxOutputByPkScript(_txId, _toPkScripts[1]);
            require(isValid, "PegRequestHelper: invalid output pkScript");
        }
        // Extract and validate main transfer amount from first output
        // This is the actual amount being transferred to the destination address
        (isValid, amount, ) = _bitcoinTxStore.findTxOutputByPkScript(_txId, _toPkScripts[0]);
        require(isValid && amount != 0, "PegRequestHelper: invalid output pkScript");
    }

    /// @notice Calculates mint amounts for peg-in operations
    /// @dev Determines exchange rate, treasury fees, and net mintable amount.
    /// Validates minimum deposit requirements and applies fee calculations
    /// @param _bridge Bridge contract for accessing configuration
    /// @param _amount Amount of Bitcoin deposited (in satoshis)
    /// @param _depositedAt Timestamp when deposit was made
    /// @return exchangeRate Exchange rate at deposit time
    /// @return treasuryFee Treasury fee amount in lstBTC
    /// @return netAmount Net amount to mint after fees
    function calculatePegInMintAmounts(
        ILstBTCBridge _bridge,
        uint64 _amount,
        uint64 _depositedAt
    ) private view returns (
        uint64 exchangeRate,
        uint64 treasuryFee,
        uint64 netAmount
    ) {
        IConfigRegistry configRegistry = IConfigRegistry(_bridge.configRegistry());
        uint64 depositDustAmount = configRegistry.getPegInDepositDustAmount(_depositedAt);
        require(_amount >= depositDustAmount, "PegRequestHelper: low deposit amount");

        uint8 decimals;
        (exchangeRate, decimals) = INavProvider(_bridge.navProvider()).getExchangeRate(_depositedAt);
        require(exchangeRate != 0, "PegRequestHelper: exchange rate is zero");

        uint64 mintableAmount = (_amount * (10 ** decimals) / exchangeRate).toUint64();
        uint16 treasuryFeeRate = configRegistry.getPegInTreasuryFeeRate(_depositedAt);
        if (treasuryFeeRate != 0) {
            treasuryFee = mintableAmount * treasuryFeeRate / PERCENTAGE_BASE;
        }

        netAmount = mintableAmount - treasuryFee;
    }

    /// @notice Calculates burn amounts for peg-out operations
    /// @dev Determines exchange rate, fees, and net redeemable amount.
    /// Validates minimum redeem requirements and applies fee calculations
    /// @param _bridge Bridge contract for accessing configuration
    /// @param _amount Amount of lstBTC to burn (in satoshis)
    /// @param _depositedAt Timestamp when request was made
    /// @return exchangeRate Exchange rate at request time
    /// @return transactionFee Fixed transaction fee in satoshis
    /// @return treasuryFee Treasury fee amount in lstBTC
    /// @return netAmount Net amount to redeem after fees
    function calculatePegOutBurnAmounts(
        ILstBTCBridge _bridge,
        uint64 _amount,
        uint64 _depositedAt
    ) private view returns (
        uint64 exchangeRate,
        uint64 transactionFee,
        uint64 treasuryFee,
        uint64 netAmount
    ) {
        uint8 decimals;
        INavProvider navProvider = INavProvider(_bridge.navProvider());

        (exchangeRate, decimals) = navProvider.getExchangeRate(_depositedAt);
        require(exchangeRate != 0, "PegRequestHelper: exchange rate is zero");

        IConfigRegistry configRegistry = IConfigRegistry(_bridge.configRegistry());

        transactionFee = configRegistry.getPegOutTransactionFee(_depositedAt);
        uint64 redeemDustAmount = configRegistry.getPegOutRedeemDustAmount(_depositedAt);

        uint16 treasuryFeeRate = configRegistry.getPegOutTreasuryFeeRate(_depositedAt);
        if (treasuryFeeRate != 0) {
            treasuryFee = _amount * treasuryFeeRate / PERCENTAGE_BASE;
        }

        uint64 burnAmount = _amount - treasuryFee;
        uint64 redeemableAmount = (burnAmount * exchangeRate / (10 ** decimals)).toUint64();

        require(
            redeemableAmount >= transactionFee + redeemDustAmount,
            "PegRequestHelper: low redeem amount"
        );

        netAmount = redeemableAmount - transactionFee;
    }

    /// @notice Splits a total amount among recipients based on their shares
    /// @dev Calculates proportional amounts for each recipient.
    /// Uses PERCENTAGE_BASE for precise percentage calculations
    /// @param _shares Array of share percentages for each recipient
    /// @param _totalAmount Total amount to be distributed
    /// @return amounts Array of amounts for each recipient
    function splitAmounts(
        uint16[] memory _shares,
        uint64 _totalAmount
    ) private pure returns(uint64[] memory amounts) {
        uint256 recipientCount = _shares.length;
        amounts = new uint64[](recipientCount);

        if (recipientCount == 0 || _totalAmount == 0) {
            return amounts;
        }

        for (uint256 i = 0; i < recipientCount; ++i) {
            amounts[i] = _totalAmount * _shares[i] / PERCENTAGE_BASE;
        }
    }

    /// @notice Compares two byte arrays for equality
    /// @dev Uses keccak256 hash for efficient comparison
    /// @param a First byte array to compare
    /// @param b Second byte array to compare
    /// @return True if arrays are equal, false otherwise
    function bytesEqual(bytes calldata a, bytes memory b) internal pure returns (bool) {
        if (a.length != b.length) {
            return false;
        }

        return keccak256(a) == keccak256(b);
    }

}
