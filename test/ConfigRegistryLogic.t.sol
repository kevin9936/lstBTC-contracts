// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deployer} from "./utils/Deployer.sol";
import {ConfigRegistryLogic} from "contracts/configuration/ConfigRegistryLogic.sol";
import {ConfigRegistryProxy} from "contracts/configuration/ConfigRegistryProxy.sol";
import {AccessControlBase} from "contracts/access/AccessControlBase.sol";
import {ILstBTCBridge} from "contracts/bridge/interfaces/ILstBTCBridge.sol";
import {IWhitelistRegistry} from "contracts/whitelist/interfaces/IWhitelistRegistry.sol";

contract ConfigRegistryLogicTest is Deployer {
    address public user1;
    address public user2;
    address public user3;
    address public notGovernor;
    address public custodian1;
    address public custodian2;
    address public recipient1;
    address public recipient2;
    address public recipient3;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    // Test data
    uint32 public constant TEST_CUSTODIAN_ID = 10001;
    uint32 public constant TEST_BITCOIN_CONFIRMATIONS = 6;
    uint32 public constant TEST_NATIVE_CONFIRMATIONS = 12;
    uint64 public constant TEST_DUST_AMOUNT = 5000;
    uint64 public constant TEST_TRANSACTION_FEE = 1000;
    uint16 public constant TEST_TREASURY_FEE_RATE = 100; // 1%
    uint64 public constant TEST_TIMESTAMP = 1640995200; // 2022-01-01 00:00:00
    function setUp() public {
        user1 = address(2000);
        user2 = address(2001);
        user3 = address(2002);
        notGovernor = address(3000);
        custodian1 = address(4000);
        custodian2 = address(4001);
        recipient1 = address(5000);
        recipient2 = address(5001);
        recipient3 = address(5002);

        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(notGovernor, "NotGovernor");
        vm.label(custodian1, "Custodian1");
        vm.label(custodian2, "Custodian2");
        vm.label(recipient1, "Recipient1");
        vm.label(recipient2, "Recipient2");
        vm.label(recipient3, "Recipient3");

        // Create whitelist group for testing
        _createWhitelistGroup();
    }

    // ============ Initialization Tests ============


    function test_Initialize_Success() public {
        assertEq(configRegistry.bridge(), address(lstBTCBridge));
        assertTrue(configRegistry.hasRole(DEFAULT_ADMIN_ROLE, adminAddress));
        assertTrue(configRegistry.hasRole(ROLE_GOVERNOR, govAddress));
    }


    function test_RevertWhen_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        configRegistry.initialize(adminAddress, govAddress);
    }

    // ============ Access Control Tests ============


    function test_RevertWhen_SetBridge_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setBridge(address(0x123));
    }


    function test_RevertWhen_SetBitcoinConfirmations_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setBitcoinConfirmations(TEST_CUSTODIAN_ID, TEST_BITCOIN_CONFIRMATIONS);
    }


    function test_RevertWhen_SetNativeConfirmations_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setNativeConfirmations(TEST_CUSTODIAN_ID, TEST_NATIVE_CONFIRMATIONS);
    }


    function test_RevertWhen_SetPegInDepositDustAmount_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setPegInDepositDustAmount(TEST_DUST_AMOUNT);
    }


    function test_RevertWhen_SetPegInTreasuryFeeRate_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setPegInTreasuryFeeRate(TEST_TREASURY_FEE_RATE);
    }


    function test_RevertWhen_SetPegInTreasuryFeeShares_NotGovernor() public {
        address[] memory recipients = new address[](1);
        uint16[] memory shares = new uint16[](1);
        recipients[0] = recipient1;
        shares[0] = 10000; // 100%

        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setPegInTreasuryFeeShares(recipients, shares);
    }


    function test_RevertWhen_SetPegOutRedeemDustAmount_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setPegOutRedeemDustAmount(TEST_DUST_AMOUNT);
    }


    function test_RevertWhen_SetPegOutTransactionFee_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setPegOutTransactionFee(TEST_TRANSACTION_FEE);
    }


    function test_RevertWhen_SetPegOutTreasuryFeeRate_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setPegOutTreasuryFeeRate(TEST_TREASURY_FEE_RATE);
    }


    function test_RevertWhen_SetPegOutTreasuryFeeShares_NotGovernor() public {
        address[] memory recipients = new address[](1);
        uint16[] memory shares = new uint16[](1);
        recipients[0] = recipient1;
        shares[0] = 10000; // 100%

        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        configRegistry.setPegOutTreasuryFeeShares(recipients, shares);
    }

    // ============ setBridge() Tests ============


    function test_SetBridge_Success() public {
        address newBridge = address(0x123);
        address oldBridge = configRegistry.bridge();

        vm.expectEmit(true, true, false, true);
        emit BridgeUpdated(oldBridge, newBridge);

        vm.prank(govAddress);
        configRegistry.setBridge(newBridge);
        assertEq(configRegistry.bridge(), newBridge);
    }


    function test_SetBridge_SameAddress() public {
        address currentBridge = configRegistry.bridge();

        vm.recordLogs();
        vm.prank(govAddress);
        configRegistry.setBridge(currentBridge);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    // ============ setBitcoinConfirmations() Tests ============


    function test_SetBitcoinConfirmations_Success() public {
        uint32 oldConfirmations = 0;
        uint32 newConfirmations = 10;
        vm.expectEmit(true, true, false, true);
        emit BitcoinConfirmationsUpdated(TEST_CUSTODIAN_ID, oldConfirmations, newConfirmations);
        vm.prank(govAddress);
        configRegistry.setBitcoinConfirmations(TEST_CUSTODIAN_ID, newConfirmations);
        assertEq(configRegistry.getBitcoinConfirmations(TEST_CUSTODIAN_ID), newConfirmations);
    }


    function test_RevertWhen_SetBitcoinConfirmations_BelowMinimum() public {
        uint32 invalidConfirmations = 0; // Below DEFAULT_BITCOIN_CONFIRMATIONS (1)
        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.BitcoinConfirmationsBelowMinimum.selector,
            invalidConfirmations
        ));
        configRegistry.setBitcoinConfirmations(TEST_CUSTODIAN_ID, invalidConfirmations);
    }


    function test_RevertWhen_SetBitcoinConfirmations_UnauthorizedCustodian() public {
        uint32 unauthorizedCustodianId = 999;
        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.UnauthorizedCustodian.selector,
            unauthorizedCustodianId
        ));
        configRegistry.setBitcoinConfirmations(unauthorizedCustodianId, TEST_BITCOIN_CONFIRMATIONS);
    }

    function test_SetBitcoinConfirmations_SameValue_NoEffect() public {
        uint32 newConfirmations = 10;
        vm.prank(govAddress);
        configRegistry.setBitcoinConfirmations(TEST_CUSTODIAN_ID, newConfirmations);
        vm.prank(govAddress);
        configRegistry.setBitcoinConfirmations(TEST_CUSTODIAN_ID, newConfirmations);
        assertEq(configRegistry.getBitcoinConfirmations(TEST_CUSTODIAN_ID), newConfirmations);
    }

    // ============ setNativeConfirmations() Tests ============


    function test_SetNativeConfirmations_Success() public {
        uint32 oldConfirmations = 0;
        uint32 newConfirmations = 20;
        vm.expectEmit(true, true, false, true);
        emit NativeConfirmationsUpdated(TEST_CUSTODIAN_ID, oldConfirmations, newConfirmations);

        vm.prank(govAddress);
        configRegistry.setNativeConfirmations(TEST_CUSTODIAN_ID, newConfirmations);

        assertEq(configRegistry.getNativeConfirmations(TEST_CUSTODIAN_ID), newConfirmations);
    }


    function test_RevertWhen_SetNativeConfirmations_BelowMinimum() public {
        uint32 invalidConfirmations = 10; // Below DEFAULT_NATIVE_CONFIRMATIONS (12)
        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.NativeConfirmationsBelowMinimum.selector,
            invalidConfirmations
        ));
        configRegistry.setNativeConfirmations(TEST_CUSTODIAN_ID, invalidConfirmations);
    }


    function test_RevertWhen_SetNativeConfirmations_UnauthorizedCustodian() public {
        uint32 unauthorizedCustodianId = 999;
        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.UnauthorizedCustodian.selector,
            unauthorizedCustodianId
        ));
        configRegistry.setNativeConfirmations(unauthorizedCustodianId, TEST_NATIVE_CONFIRMATIONS);
    }

    // ============ setPegInDepositDustAmount() Tests ============


    function test_SetPegInDepositDustAmount_Success() public {
        uint64 oldAmount = DEFAULT_PEG_IN_DEPOSIT_DUST_AMOUNT;
        uint64 newAmount = 8000;
        vm.expectEmit(true, true, false, true);
        emit PegInDepositDustAmountUpdated(oldAmount, newAmount);
        vm.warp(TEST_TIMESTAMP);
        vm.startPrank(govAddress);
        configRegistry.setPegInDepositDustAmount(newAmount);
        assertEq(configRegistry.getPegInDepositDustAmount(TEST_TIMESTAMP), newAmount);
        uint64 currentTimestamp = 1740995200;
        vm.expectEmit(true, true, false, true);
        emit PegInDepositDustAmountUpdated(newAmount, newAmount * 2);
        vm.warp(currentTimestamp);
        configRegistry.setPegInDepositDustAmount(newAmount * 2);
        assertEq(configRegistry.getPegInDepositDustAmount(currentTimestamp), newAmount * 2);
        assertEq(configRegistry.getPegInDepositDustAmount(TEST_TIMESTAMP), newAmount);
        vm.stopPrank();
    }

    // ============ setPegInTreasuryFeeRate() Tests ============


    function test_SetPegInTreasuryFeeRate_Success() public {
        uint16 oldRate = DEFAULT_PEG_IN_TREASURY_FEE_RATE;
        uint16 newRate = 200; // 2%
        vm.expectEmit(true, true, false, true);
        emit PegInTreasuryFeeRateUpdated(oldRate, newRate);
        vm.warp(TEST_TIMESTAMP);
        vm.startPrank(govAddress);
        configRegistry.setPegInTreasuryFeeRate(newRate);
        assertEq(configRegistry.getPegInTreasuryFeeRate(TEST_TIMESTAMP), newRate);
        uint64 currentTimestamp = 1740995200;
        vm.warp(currentTimestamp);
        vm.expectEmit(true, true, false, true);
        emit PegInTreasuryFeeRateUpdated(newRate, newRate * 2);
        configRegistry.setPegInTreasuryFeeRate(newRate * 2);
        assertEq(configRegistry.getPegInTreasuryFeeRate(currentTimestamp), newRate * 2);
        assertEq(configRegistry.getPegInTreasuryFeeRate(TEST_TIMESTAMP + 1), newRate);
        vm.stopPrank();
    }


    function test_RevertWhen_SetPegInTreasuryFeeRate_ExceedsMax() public {
        uint16 invalidRate = 10000; // Equal to PERCENTAGE_BASE (100%)

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.TreasuryFeeRateExceeds.selector,
            invalidRate
        ));
        configRegistry.setPegInTreasuryFeeRate(invalidRate);
    }

    // ============ setPegInTreasuryFeeShares() Tests ============


    function test_SetPegInTreasuryFeeShares_Success() public {
        address[] memory recipients = new address[](2);
        uint16[] memory shares = new uint16[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        shares[0] = 6000; // 60%
        shares[1] = 4000; // 40%
        vm.warp(TEST_TIMESTAMP);
        vm.expectEmit(true, true, false, true);
        emit PegInTreasuryFeeSharesUpdated(
            DEFAULT_PEG_IN_RECIPIENTS, // oldRecipients
            DEFAULT_PEG_IN_SHARES,  // oldShares
            recipients,
            shares
        );

        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(recipients, shares);

        (address[] memory storedRecipients, uint16[] memory storedShares) =
                            configRegistry.getPegInTreasuryFeeShares(TEST_TIMESTAMP);

        assertEq(storedRecipients.length, recipients.length);
        assertEq(storedShares.length, shares.length);
        assertEq(storedRecipients[0], recipients[0]);
        assertEq(storedRecipients[1], recipients[1]);
        assertEq(storedShares[0], shares[0]);
        assertEq(storedShares[1], shares[1]);
    }

    function test_SetPegInTreasuryFeeShares_MultipleTimes_Success() public {
        address[] memory recipients1 = new address[](2);
        uint16[] memory shares1 = new uint16[](2);
        recipients1[0] = recipient1;
        recipients1[1] = recipient2;
        shares1[0] = 7000; // 70%
        shares1[1] = 3000; // 30%

        vm.warp(TEST_TIMESTAMP);
        vm.expectEmit(true, true, false, true);
        emit PegInTreasuryFeeSharesUpdated(
            DEFAULT_PEG_IN_RECIPIENTS, // oldRecipients
            DEFAULT_PEG_IN_SHARES,  // oldShares
            recipients1,
            shares1
        );
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(recipients1, shares1);

        (address[] memory storedRecipients1, uint16[] memory storedShares1) =
                            configRegistry.getPegInTreasuryFeeShares(TEST_TIMESTAMP);
        assertEq(storedRecipients1.length, recipients1.length);
        assertEq(storedShares1.length, shares1.length);
        assertEq(storedRecipients1[0], recipients1[0]);
        assertEq(storedRecipients1[1], recipients1[1]);
        assertEq(storedShares1[0], shares1[0]);
        assertEq(storedShares1[1], shares1[1]);

        address[] memory recipients2 = new address[](3);
        uint16[] memory shares2 = new uint16[](3);
        recipients2[0] = recipient1;
        recipients2[1] = recipient2;
        recipients2[2] = recipient3;
        shares2[0] = 5000; // 50%
        shares2[1] = 3000; // 30%
        shares2[2] = 2000; // 20%

        vm.warp(TEST_TIMESTAMP + 100);
        vm.expectEmit(true, true, false, true);
        emit PegInTreasuryFeeSharesUpdated(
            recipients1,
            shares1,
            recipients2,
            shares2
        );
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(recipients2, shares2);

        (address[] memory storedRecipients2, uint16[] memory storedShares2) =
                            configRegistry.getPegInTreasuryFeeShares(TEST_TIMESTAMP + 100);
        assertEq(storedRecipients2.length, recipients2.length);
        assertEq(storedShares2.length, shares2.length);
        assertEq(storedRecipients2[0], recipients2[0]);
        assertEq(storedRecipients2[1], recipients2[1]);
        assertEq(storedRecipients2[2], recipients2[2]);
        assertEq(storedShares2[0], shares2[0]);
        assertEq(storedShares2[1], shares2[1]);
        assertEq(storedShares2[2], shares2[2]);

        address[] memory recipients3 = new address[](1);
        uint16[] memory shares3 = new uint16[](1);
        recipients3[0] = recipient3;
        shares3[0] = 10000; // 100%

        vm.warp(TEST_TIMESTAMP + 200);
        vm.expectEmit(true, true, false, true);
        emit PegInTreasuryFeeSharesUpdated(
            recipients2,
            shares2,
            recipients3,
            shares3
        );
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(recipients3, shares3);

        (address[] memory storedRecipients3, uint16[] memory storedShares3) =
                            configRegistry.getPegInTreasuryFeeShares(TEST_TIMESTAMP + 200);
        assertEq(storedRecipients3.length, recipients3.length);
        assertEq(storedShares3.length, shares3.length);
        assertEq(storedRecipients3[0], recipients3[0]);
        assertEq(storedShares3[0], shares3[0]);

        (address[] memory storedRecipients4, uint16[] memory storedShares4) =
                            configRegistry.getPegInTreasuryFeeShares(TEST_TIMESTAMP + 199);
        assertEq(storedRecipients4.length, recipients2.length);
        assertEq(storedShares4.length, shares2.length);
        assertEq(storedRecipients2[0], recipients2[0]);
        assertEq(storedRecipients2[1], recipients2[1]);
        assertEq(storedRecipients2[2], recipients2[2]);
        assertEq(storedShares2[0], shares2[0]);
        assertEq(storedShares2[1], shares2[1]);
        assertEq(storedShares2[2], shares2[2]);
    }


    function test_RevertWhen_SetPegInTreasuryFeeShares_EmptyRecipients() public {
        address[] memory recipients = new address[](0);
        uint16[] memory shares = new uint16[](0);

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(ConfigRegistryLogic.RecipientsEmpty.selector));
        configRegistry.setPegInTreasuryFeeShares(recipients, shares);
    }


    function test_RevertWhen_SetPegInTreasuryFeeShares_LengthMismatch() public {
        address[] memory recipients = new address[](2);
        uint16[] memory shares = new uint16[](1);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        shares[0] = 10000;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.RecipientsSharesLengthMismatch.selector,
            2,
            1
        ));
        configRegistry.setPegInTreasuryFeeShares(recipients, shares);
    }


    function test_RevertWhen_SetPegInTreasuryFeeShares_TotalSharesMismatch() public {
        address[] memory recipients = new address[](2);
        uint16[] memory shares = new uint16[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        shares[0] = 6000; // 60%
        shares[1] = 3000; // 30% (total 90%, should be 100%)

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.TotalSharesMismatch.selector,
            10000,
            9000
        ));
        configRegistry.setPegInTreasuryFeeShares(recipients, shares);
        address[] memory recipients2 = new address[](2);
        uint16[] memory shares2 = new uint16[](2);
        recipients2[0] = recipient1;
        recipients2[1] = recipient2;
        shares2[0] = 7000; // 60%
        shares2[1] = 3001; // 30% (total 90%, should be 100%)

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.TotalSharesMismatch.selector,
            10000,
            10001
        ));
        configRegistry.setPegInTreasuryFeeShares(recipients2, shares2);

    }

    // ============ setPegOutRedeemDustAmount() Tests ============


    function test_SetPegOutRedeemDustAmount_Success() public {
        uint64 oldAmount = DEFAULT_PEG_OUT_REDEEM_DUST_AMOUNT;
        uint64 newAmount = 8000;
        vm.expectEmit(true, true, false, true);
        emit PegOutRedeemDustAmountUpdated(oldAmount, newAmount);
        vm.warp(TEST_TIMESTAMP);
        vm.startPrank(govAddress);
        configRegistry.setPegOutRedeemDustAmount(newAmount);
        assertEq(configRegistry.getPegOutRedeemDustAmount(TEST_TIMESTAMP), newAmount);
        uint64 currentTimestamp = 1740995200;
        vm.warp(currentTimestamp);
        vm.expectEmit(true, true, false, true);
        emit PegOutRedeemDustAmountUpdated(newAmount, newAmount * 2);
        configRegistry.setPegOutRedeemDustAmount(newAmount * 2);
        assertEq(configRegistry.getPegOutRedeemDustAmount(currentTimestamp), newAmount * 2);
        assertEq(configRegistry.getPegOutRedeemDustAmount(TEST_TIMESTAMP), newAmount);
        vm.stopPrank();
    }


    function test_RevertWhen_SetPegOutRedeemDustAmount_BelowMinimum() public {
        uint64 invalidAmount = 2999; // Below DEFAULT_REDEEM_DUST_AMOUNT (3000)

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.RedeemDustAmountBelowMinimum.selector,
            invalidAmount
        ));
        configRegistry.setPegOutRedeemDustAmount(invalidAmount);
    }

    // ============ setPegOutTransactionFee() Tests ============


    function test_SetPegOutTransactionFee_Success() public {
        uint64 oldFee = DEFAULT_PEG_OUT_TRANSACTION_FEE;
        uint64 newFee = 2000;
        vm.expectEmit(true, true, false, true);
        emit PegOutTransactionFeeUpdated(oldFee, newFee);
        vm.warp(TEST_TIMESTAMP);
        vm.startPrank(govAddress);
        configRegistry.setPegOutTransactionFee(newFee);
        assertEq(configRegistry.getPegOutTransactionFee(TEST_TIMESTAMP), newFee);
        uint64 currentTimestamp = 1740995200;
        vm.warp(currentTimestamp);
        vm.expectEmit(true, true, false, true);
        emit PegOutTransactionFeeUpdated(newFee, newFee * 2);
        configRegistry.setPegOutTransactionFee(newFee * 2);
        assertEq(configRegistry.getPegOutTransactionFee(currentTimestamp), newFee * 2);
        assertEq(configRegistry.getPegOutTransactionFee(TEST_TIMESTAMP), newFee);
    }

    // ============ setPegOutTreasuryFeeRate() Tests ============


    function test_SetPegOutTreasuryFeeRate_Success() public {
        uint16 oldRate = DEFAULT_PEG_OUT_TREASURY_FEE_RATE;
        uint16 newRate = 300; // 3%
        vm.warp(TEST_TIMESTAMP);
        vm.expectEmit(true, true, false, true);
        emit PegOutTreasuryFeeRateUpdated(oldRate, newRate);
        vm.startPrank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(newRate);
        uint64 currentTimestamp = TEST_TIMESTAMP + 1;
        vm.warp(currentTimestamp);
        vm.expectEmit(true, true, false, true);
        emit PegOutTreasuryFeeRateUpdated(newRate, newRate * 2);
        configRegistry.setPegOutTreasuryFeeRate(newRate * 2);
        assertEq(configRegistry.getPegOutTreasuryFeeRate(currentTimestamp), newRate * 2);
        assertEq(configRegistry.getPegOutTreasuryFeeRate(TEST_TIMESTAMP), newRate);
        vm.stopPrank();
    }


    function test_RevertWhen_SetPegOutTreasuryFeeRate_ExceedsMax() public {
        uint16 invalidRate = 10000; // Equal to PERCENTAGE_BASE (100%)

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.TreasuryFeeRateExceeds.selector,
            invalidRate
        ));
        configRegistry.setPegOutTreasuryFeeRate(invalidRate);
    }

    // ============ setPegOutTreasuryFeeShares() Tests ============


    function test_SetPegOutTreasuryFeeShares_Success() public {
        vm.warp(TEST_TIMESTAMP);
        address[] memory recipients = new address[](3);
        uint16[] memory shares = new uint16[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;
        shares[0] = 5000; // 50%
        shares[1] = 3000; // 30%
        shares[2] = 2000; // 20%

        vm.expectEmit(true, true, false, true);
        emit PegOutTreasuryFeeSharesUpdated(
            DEFAULT_PEG_OUT_RECIPIENTS, // oldRecipients
            DEFAULT_PEG_OUT_SHARES,  // oldShares
            recipients,
            shares
        );

        vm.startPrank(govAddress);
        configRegistry.setPegOutTreasuryFeeShares(recipients, shares);

        (address[] memory storedRecipients, uint16[] memory storedShares) =
                            configRegistry.getPegOutTreasuryFeeShares(TEST_TIMESTAMP);

        assertEq(storedRecipients.length, recipients.length);
        assertEq(storedShares.length, shares.length);
        assertEq(storedRecipients[0], recipients[0]);
        assertEq(storedRecipients[1], recipients[1]);
        assertEq(storedRecipients[2], recipients[2]);
        assertEq(storedShares[0], shares[0]);
        assertEq(storedShares[1], shares[1]);
        assertEq(storedShares[2], shares[2]);
        vm.stopPrank();
    }

    function test_SetPegOutTreasuryFeeShares_MultipleTimes() public {
        vm.warp(TEST_TIMESTAMP);
        vm.startPrank(govAddress);
        address[] memory recipients1 = new address[](2);
        uint16[] memory shares1 = new uint16[](2);
        recipients1[0] = recipient1;
        recipients1[1] = recipient2;
        shares1[0] = 7000; // 70%
        shares1[1] = 3000; // 30%

        vm.expectEmit(true, true, false, true);
        emit PegOutTreasuryFeeSharesUpdated(
            DEFAULT_PEG_OUT_RECIPIENTS, // oldRecipients
            DEFAULT_PEG_OUT_SHARES,  // oldShares
            recipients1,
            shares1
        );

        configRegistry.setPegOutTreasuryFeeShares(recipients1, shares1);

        vm.warp(TEST_TIMESTAMP + 1);
        address[] memory recipients2 = new address[](3);
        uint16[] memory shares2 = new uint16[](3);
        recipients2[0] = recipient1;
        recipients2[1] = recipient2;
        recipients2[2] = recipient3;
        shares2[0] = 4000; // 40%
        shares2[1] = 4000; // 40%
        shares2[2] = 2000; // 20%

        vm.expectEmit(true, true, false, true);
        emit PegOutTreasuryFeeSharesUpdated(
            recipients1,
            shares1,
            recipients2,
            shares2
        );

        configRegistry.setPegOutTreasuryFeeShares(recipients2, shares2);
        (address[] memory storedRecipients2, uint16[] memory storedShares2) =
                            configRegistry.getPegOutTreasuryFeeShares(TEST_TIMESTAMP + 1);
        assertEq(storedRecipients2.length, 3);
        assertEq(storedRecipients2[0], recipient1);
        assertEq(storedRecipients2[1], recipient2);
        assertEq(storedRecipients2[2], recipient3);
        assertEq(storedShares2[0], 4000);
        assertEq(storedShares2[1], 4000);
        assertEq(storedShares2[2], 2000);

        vm.warp(TEST_TIMESTAMP + 2);
        address[] memory recipients3 = new address[](1);
        uint16[] memory shares3 = new uint16[](1);
        recipients3[0] = recipient3;
        shares3[0] = 10000; // 100%

        vm.expectEmit(true, true, false, true);
        emit PegOutTreasuryFeeSharesUpdated(
            recipients2,
            shares2,
            recipients3,
            shares3
        );

        (address[] memory storedRecipients1, uint16[] memory storedShares1) =
                            configRegistry.getPegOutTreasuryFeeShares(TEST_TIMESTAMP);
        assertEq(storedRecipients1.length, 2);
        assertEq(storedRecipients1[0], recipient1);
        assertEq(storedRecipients1[1], recipient2);
        assertEq(storedShares1[0], 7000);
        assertEq(storedShares1[1], 3000);

        configRegistry.setPegOutTreasuryFeeShares(recipients3, shares3);
        (address[] memory storedRecipients3, uint16[] memory storedShares3) =
                            configRegistry.getPegOutTreasuryFeeShares(TEST_TIMESTAMP + 2);
        assertEq(storedRecipients3.length, 1);
        assertEq(storedRecipients3[0], recipient3);
        assertEq(storedShares3[0], 10000);
        vm.stopPrank();
    }

    function test_RevertWhen_SetPegOutTreasuryFeeShares_EmptyRecipients() public {
        address[] memory recipients = new address[](0);
        uint16[] memory shares = new uint16[](0);

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(ConfigRegistryLogic.RecipientsEmpty.selector));
        configRegistry.setPegOutTreasuryFeeShares(recipients, shares);
    }

    function test_RevertWhen_SetPegOutTreasuryFeeShares_LengthMismatch() public {
        address[] memory recipients = new address[](2);
        uint16[] memory shares = new uint16[](1);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        shares[0] = 10000;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.RecipientsSharesLengthMismatch.selector,
            2,
            1
        ));
        configRegistry.setPegOutTreasuryFeeShares(recipients, shares);
    }

    function test_RevertWhen_SetPegOutTreasuryFeeShares_TotalSharesMismatch() public {
        address[] memory recipients = new address[](2);
        uint16[] memory shares = new uint16[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        shares[0] = 6000; // 60%
        shares[1] = 3000; // 30% (total 90%, should be 100%)

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            ConfigRegistryLogic.TotalSharesMismatch.selector,
            10000,
            9000
        ));
        configRegistry.setPegOutTreasuryFeeShares(recipients, shares);
    }

    // ============ View Functions Tests ============

    // ============ getBitcoinConfirmations() Tests ============

    function test_GetBitcoinConfirmations_DefaultValue() public {
        uint32 confirmations = configRegistry.getBitcoinConfirmations(TEST_CUSTODIAN_ID);
        assertEq(confirmations, configRegistry.DEFAULT_BITCOIN_CONFIRMATIONS());
    }

    function test_GetBitcoinConfirmations_CustomValue() public {
        uint32 customConfirmations = 8;

        vm.prank(govAddress);
        configRegistry.setBitcoinConfirmations(TEST_CUSTODIAN_ID, customConfirmations);

        uint32 confirmations = configRegistry.getBitcoinConfirmations(TEST_CUSTODIAN_ID);
        assertEq(confirmations, customConfirmations);
    }
    // ============ getNativeConfirmations() Tests ============

    function test_GetNativeConfirmations_DefaultValue() public {
        uint32 confirmations = configRegistry.getNativeConfirmations(TEST_CUSTODIAN_ID);
        assertEq(confirmations, configRegistry.DEFAULT_NATIVE_CONFIRMATIONS());
    }

    function test_GetNativeConfirmations_CustomValue() public {
        uint32 customConfirmations = 15;

        vm.prank(govAddress);
        configRegistry.setNativeConfirmations(TEST_CUSTODIAN_ID, customConfirmations);

        uint32 confirmations = configRegistry.getNativeConfirmations(TEST_CUSTODIAN_ID);
        assertEq(confirmations, customConfirmations);
    }

    // ============ getPegInDepositDustAmount() Tests ============

    function test_RevertWhen_GetPegInDepositDustAmount_DefaultValue() public {
        vm.expectRevert("FeeConfigHelper: fetch amount threshold failed");
        configRegistry.getPegInDepositDustAmount(INIT_ADD_CONFIG_TIMESTAMP - 1);
    }

    function test_GetPegInDepositDustAmount_CustomValue() public {
        uint64 customAmount = 7000;
        vm.warp(TEST_TIMESTAMP);
        vm.prank(govAddress);
        configRegistry.setPegInDepositDustAmount(customAmount);

        uint64 amount = configRegistry.getPegInDepositDustAmount(TEST_TIMESTAMP);
        assertEq(amount, customAmount);
        uint64 currentTimestamp = INIT_ADD_CONFIG_TIMESTAMP - 1;
        vm.expectRevert("FeeConfigHelper: fetch amount threshold failed");
        uint64 amount2 = configRegistry.getPegInDepositDustAmount(currentTimestamp);
        assertEq(amount2, 0);
    }

    function test_RevertWhen_GetPegInDepositDustAmount_BeforeSet() public {
        uint64 tsSet = INIT_ADD_CONFIG_TIMESTAMP - 1;
        vm.expectRevert("FeeConfigHelper: fetch amount threshold failed");
        configRegistry.getPegInDepositDustAmount(tsSet);
    }

    function test_GetPegInDepositDustAmount_MultiTimestamps() public {
        uint64 ts1 = TEST_TIMESTAMP;
        uint64 ts2 = TEST_TIMESTAMP + 1000;
        uint64 ts3 = TEST_TIMESTAMP + 2000;

        uint64 amount1 = 1111;
        uint64 amount2 = 2222;
        uint64 amount3 = 3333;

        vm.warp(ts1);
        vm.prank(govAddress);
        configRegistry.setPegInDepositDustAmount(amount1);

        vm.warp(ts2);
        vm.prank(govAddress);
        configRegistry.setPegInDepositDustAmount(amount2);

        vm.warp(ts3);
        vm.prank(govAddress);
        configRegistry.setPegInDepositDustAmount(amount3);

        uint64 queried1 = configRegistry.getPegInDepositDustAmount(ts1);
        assertEq(queried1, amount1);

        uint64 queried2 = configRegistry.getPegInDepositDustAmount(ts2);
        assertEq(queried2, amount2);

        uint64 queried3 = configRegistry.getPegInDepositDustAmount(ts3);
        assertEq(queried3, amount3);

        uint64 tsMid = ts2 + 500;
        uint64 queriedMid = configRegistry.getPegInDepositDustAmount(tsMid);
        assertEq(queriedMid, amount2);

        uint64 tsMid2 = ts1 + 999;
        uint64 queriedMid2 = configRegistry.getPegInDepositDustAmount(tsMid2);
        assertEq(queriedMid2, amount1);

        vm.expectRevert("FeeConfigHelper: fetch amount threshold failed");
        configRegistry.getPegInDepositDustAmount(INIT_ADD_CONFIG_TIMESTAMP - 1000);
    }

    // ============ getPegInTreasuryFeeRate() Tests ============

    function test_RevertWhen_GetPegInTreasuryFeeRate_NotSet() public {
        vm.expectRevert("FeeConfigHelper: fetch treasury fee rate failed");
        configRegistry.getPegInTreasuryFeeRate(INIT_ADD_CONFIG_TIMESTAMP - 1);
    }

    function test_GetPegInTreasuryFeeRate_CustomValue() public {
        uint16 customRate = 250; // 2.5%
        vm.warp(TEST_TIMESTAMP - 1);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeRate(customRate);

        uint16 rate = configRegistry.getPegInTreasuryFeeRate(TEST_TIMESTAMP);
        assertEq(rate, customRate);
    }

    function test_GetPegInTreasuryFeeRate_MultiTimestamps() public {
        uint64 ts1 = TEST_TIMESTAMP;
        uint64 ts2 = TEST_TIMESTAMP + 1000;
        uint64 ts3 = TEST_TIMESTAMP + 2000;

        uint16 rate1 = 100;
        uint16 rate2 = 250;
        uint16 rate3 = 500;

        vm.warp(ts1);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeRate(rate1);

        vm.warp(ts2);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeRate(rate2);

        vm.warp(ts3);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeRate(rate3);

        uint16 queried1 = configRegistry.getPegInTreasuryFeeRate(ts1);
        assertEq(queried1, rate1);

        uint16 queried2 = configRegistry.getPegInTreasuryFeeRate(ts2);
        assertEq(queried2, rate2);

        uint16 queried3 = configRegistry.getPegInTreasuryFeeRate(ts3);
        assertEq(queried3, rate3);

        uint64 tsMid = ts2 + 500;
        uint16 queriedMid = configRegistry.getPegInTreasuryFeeRate(tsMid);
        assertEq(queriedMid, rate2);

        uint64 tsMid2 = ts1 + 999;
        uint16 queriedMid2 = configRegistry.getPegInTreasuryFeeRate(tsMid2);
        assertEq(queriedMid2, rate1);

        vm.expectRevert("FeeConfigHelper: fetch treasury fee rate failed");
        configRegistry.getPegInTreasuryFeeRate(INIT_ADD_CONFIG_TIMESTAMP - 1000);
    }
    // ============ getPegInTreasuryFeeShares() Tests ============

    function test_RevertWhen_GetPegInTreasuryFeeShares_NoData() public {
        vm.expectRevert("FeeConfigHelper: fetch treasury fee shares failed");
        configRegistry.getPegInTreasuryFeeShares(INIT_ADD_CONFIG_TIMESTAMP - 1);
    }

    function test_GetPegInTreasuryFeeShares_CustomValue() public {
        address[] memory customRecipients = new address[](2);
        uint16[] memory customShares = new uint16[](2);
        customRecipients[0] = recipient1;
        customRecipients[1] = recipient2;
        customShares[0] = 7000; // 70%
        customShares[1] = 3000; // 30%
        vm.warp(TEST_TIMESTAMP);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(customRecipients, customShares);

        (address[] memory recipients, uint16[] memory shares) =
                            configRegistry.getPegInTreasuryFeeShares(TEST_TIMESTAMP);

        assertEq(recipients.length, customRecipients.length);
        assertEq(shares.length, customShares.length);
        assertEq(recipients[0], customRecipients[0]);
        assertEq(recipients[1], customRecipients[1]);
        assertEq(shares[0], customShares[0]);
        assertEq(shares[1], customShares[1]);
    }

    function test_GetPegInTreasuryFeeShares_MultiTimestamps() public {
        uint64 ts1 = TEST_TIMESTAMP;
        uint64 ts2 = TEST_TIMESTAMP + 1000;
        uint64 ts3 = TEST_TIMESTAMP + 2000;

        address[] memory recipients1 = new address[](1);
        address[] memory recipients2 = new address[](2);
        address[] memory recipients3 = new address[](3);
        uint16[] memory shares1 = new uint16[](1);
        uint16[] memory shares2 = new uint16[](2);
        uint16[] memory shares3 = new uint16[](3);

        recipients1[0] = recipient1;
        recipients2[0] = recipient1;
        recipients2[1] = recipient2;
        recipients3[0] = recipient1;
        recipients3[1] = recipient2;
        recipients3[2] = recipient3;
        shares1[0] = 10000; // 100%
        shares2[0] = 6000; // 60%
        shares2[1] = 4000; // 40%
        shares3[0] = 5000; // 50%
        shares3[1] = 3000; // 30%
        shares3[2] = 2000; // 20%

        vm.warp(ts1);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(recipients1, shares1);

        vm.warp(ts2);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(recipients2, shares2);

        vm.warp(ts3);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(recipients3, shares3);

        (address[] memory queried1, uint16[] memory sharesQueried1) = configRegistry.getPegInTreasuryFeeShares(ts1);
        assertEq(queried1.length, recipients1.length);
        assertEq(sharesQueried1.length, shares1.length);
        assertEq(queried1[0], recipients1[0]);
        assertEq(sharesQueried1[0], shares1[0]);

        (address[] memory queried2, uint16[] memory sharesQueried2) = configRegistry.getPegInTreasuryFeeShares(ts2);
        assertEq(queried2.length, recipients2.length);
        assertEq(sharesQueried2.length, shares2.length);
        assertEq(queried2[0], recipients2[0]);
        assertEq(queried2[1], recipients2[1]);
        assertEq(sharesQueried2[0], shares2[0]);
        assertEq(sharesQueried2[1], shares2[1]);

        (address[] memory queried3, uint16[] memory sharesQueried3) = configRegistry.getPegInTreasuryFeeShares(ts3);
        assertEq(queried3.length, recipients3.length);
        assertEq(sharesQueried3.length, shares3.length);
        assertEq(queried3[0], recipients3[0]);
        assertEq(queried3[1], recipients3[1]);
        assertEq(queried3[2], recipients3[2]);
        assertEq(sharesQueried3[0], shares3[0]);
        assertEq(sharesQueried3[1], shares3[1]);
        assertEq(sharesQueried3[2], shares3[2]);

        uint64 tsMid = ts2 + 999;
        (address[] memory queriedMid, uint16[] memory sharesQueriedMid) = configRegistry.getPegInTreasuryFeeShares(tsMid);
        assertEq(queriedMid.length, recipients2.length);
        assertEq(sharesQueriedMid.length, shares2.length);
        assertEq(queriedMid[0], recipients2[0]);
        assertEq(queriedMid[1], recipients2[1]);
        assertEq(sharesQueriedMid[0], shares2[0]);
        assertEq(sharesQueriedMid[1], shares2[1]);

        vm.expectRevert("FeeConfigHelper: fetch treasury fee shares failed");
        configRegistry.getPegInTreasuryFeeShares(INIT_ADD_CONFIG_TIMESTAMP - 1000);
    }
    // ============ getPegOutRedeemDustAmount() Tests ============
    function test_RevertWhen_GetPegOutRedeemDustAmount_NoData() public {
        vm.warp(TEST_TIMESTAMP);
        vm.expectRevert("FeeConfigHelper: fetch amount threshold failed");
        configRegistry.getPegOutRedeemDustAmount(INIT_ADD_CONFIG_TIMESTAMP - 1);
    }

    function test_GetPegOutRedeemDustAmount_CustomValue() public {
        vm.warp(TEST_TIMESTAMP);
        uint64 customAmount = 8000;

        vm.prank(govAddress);
        configRegistry.setPegOutRedeemDustAmount(customAmount);

        uint64 amount = configRegistry.getPegOutRedeemDustAmount(TEST_TIMESTAMP + 2000);
        assertEq(amount, customAmount);
    }

    function test_GetPegOutRedeemDustAmount_MultiTimestamps() public {
        uint64 ts1 = TEST_TIMESTAMP;
        uint64 ts2 = TEST_TIMESTAMP + 1000;
        uint64 ts3 = TEST_TIMESTAMP + 2000;

        uint64 amount1 = 3000;
        uint64 amount2 = 5000;
        uint64 amount3 = 8000;

        vm.warp(ts1);
        vm.prank(govAddress);
        configRegistry.setPegOutRedeemDustAmount(amount1);

        vm.warp(ts2);
        vm.prank(govAddress);
        configRegistry.setPegOutRedeemDustAmount(amount2);

        vm.warp(ts3);
        vm.prank(govAddress);
        configRegistry.setPegOutRedeemDustAmount(amount3);

        uint64 queried1 = configRegistry.getPegOutRedeemDustAmount(ts1);
        assertEq(queried1, amount1);

        uint64 queried2 = configRegistry.getPegOutRedeemDustAmount(ts2);
        assertEq(queried2, amount2);

        uint64 queried3 = configRegistry.getPegOutRedeemDustAmount(ts3);
        assertEq(queried3, amount3);

        uint64 tsMid = ts2 + 500;
        uint64 queriedMid = configRegistry.getPegOutRedeemDustAmount(tsMid);
        assertEq(queriedMid, amount2);

        uint64 tsMid2 = ts1 + 999;
        uint64 queriedMid2 = configRegistry.getPegOutRedeemDustAmount(tsMid2);
        assertEq(queriedMid2, amount1);

        vm.expectRevert("FeeConfigHelper: fetch amount threshold failed");
        configRegistry.getPegOutRedeemDustAmount(INIT_ADD_CONFIG_TIMESTAMP - 1000);
    }
    // ============ getPegOutTransactionFee() Tests ============

    function test_RevertWhen_GetPegOutTransactionFee_NoData() public {
        vm.warp(TEST_TIMESTAMP);
        vm.expectRevert("FeeConfigHelper: fetch transaction fee failed");
        configRegistry.getPegOutTransactionFee(INIT_ADD_CONFIG_TIMESTAMP - 1);
    }

    function test_GetPegOutTransactionFee_CustomValue() public {
        vm.warp(TEST_TIMESTAMP);
        uint64 customFee = 1500;

        vm.prank(govAddress);
        configRegistry.setPegOutTransactionFee(customFee);

        uint64 fee = configRegistry.getPegOutTransactionFee(TEST_TIMESTAMP);
        assertEq(fee, customFee);
    }

    function test_GetPegOutTransactionFee_MultiTimestamps() public {
        uint64 ts1 = TEST_TIMESTAMP;
        uint64 ts2 = TEST_TIMESTAMP + 1000;
        uint64 ts3 = TEST_TIMESTAMP + 2000;

        uint64 fee1 = 1000;
        uint64 fee2 = 2000;
        uint64 fee3 = 3000;

        vm.warp(ts1);
        vm.prank(govAddress);
        configRegistry.setPegOutTransactionFee(fee1);

        vm.warp(ts2);
        vm.prank(govAddress);
        configRegistry.setPegOutTransactionFee(fee2);

        vm.warp(ts3);
        vm.prank(govAddress);
        configRegistry.setPegOutTransactionFee(fee3);

        uint64 queried1 = configRegistry.getPegOutTransactionFee(ts1);
        assertEq(queried1, fee1);

        uint64 queried2 = configRegistry.getPegOutTransactionFee(ts2);
        assertEq(queried2, fee2);

        uint64 queried3 = configRegistry.getPegOutTransactionFee(ts3);
        assertEq(queried3, fee3);

        uint64 tsMid = ts2 + 500;
        uint64 queriedMid = configRegistry.getPegOutTransactionFee(tsMid);
        assertEq(queriedMid, fee2);

        uint64 tsMid2 = ts1 + 999;
        uint64 queriedMid2 = configRegistry.getPegOutTransactionFee(tsMid2);
        assertEq(queriedMid2, fee1);

        vm.expectRevert("FeeConfigHelper: fetch transaction fee failed");
        configRegistry.getPegOutTransactionFee(INIT_ADD_CONFIG_TIMESTAMP - 1000);
    }
    // ============ getPegOutTreasuryFeeRate() Tests ============

    function test_RevertWhen_GetPegOutTreasuryFeeRate_NoData() public {
        vm.warp(TEST_TIMESTAMP);
        vm.expectRevert("FeeConfigHelper: fetch treasury fee rate failed");
        configRegistry.getPegOutTreasuryFeeRate(INIT_ADD_CONFIG_TIMESTAMP - 1);
    }

    function test_GetPegOutTreasuryFeeRate_CustomValue() public {
        vm.warp(TEST_TIMESTAMP);
        uint16 customRate = 350; // 3.5%
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(customRate);

        uint16 rate = configRegistry.getPegOutTreasuryFeeRate(TEST_TIMESTAMP);
        assertEq(rate, customRate);
    }

    function test_GetPegOutTreasuryFeeRate_MultiTimestamps() public {
        uint64 ts1 = TEST_TIMESTAMP;
        uint64 ts2 = TEST_TIMESTAMP + 1000;
        uint64 ts3 = TEST_TIMESTAMP + 2000;

        uint16 rate1 = 100; // 1%
        uint16 rate2 = 250; // 2.5%
        uint16 rate3 = 500; // 5%

        vm.warp(ts1);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(rate1);

        vm.warp(ts2);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(rate2);

        vm.warp(ts3);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(rate3);

        uint16 queried1 = configRegistry.getPegOutTreasuryFeeRate(ts1);
        assertEq(queried1, rate1);

        uint16 queried2 = configRegistry.getPegOutTreasuryFeeRate(ts2);
        assertEq(queried2, rate2);

        uint16 queried3 = configRegistry.getPegOutTreasuryFeeRate(ts3);
        assertEq(queried3, rate3);

        uint64 tsMid = ts2 + 500;
        uint16 queriedMid = configRegistry.getPegOutTreasuryFeeRate(tsMid);
        assertEq(queriedMid, rate2);

        uint64 tsMid2 = ts1 + 999;
        uint16 queriedMid2 = configRegistry.getPegOutTreasuryFeeRate(tsMid2);
        assertEq(queriedMid2, rate1);

        vm.expectRevert("FeeConfigHelper: fetch treasury fee rate failed");
        configRegistry.getPegOutTreasuryFeeRate(INIT_ADD_CONFIG_TIMESTAMP - 1000);
    }
    // ============ getPegOutTreasuryFeeShares() Tests ============

    function test_RevertWhen_GetPegOutTreasuryFeeShares_NoData() public {
        vm.warp(TEST_TIMESTAMP);
        vm.expectRevert("FeeConfigHelper: fetch treasury fee shares failed");
        configRegistry.getPegOutTreasuryFeeShares(INIT_ADD_CONFIG_TIMESTAMP - 1);
    }

    function test_GetPegOutTreasuryFeeShares_CustomValue() public {
        vm.warp(TEST_TIMESTAMP);
        address[] memory customRecipients = new address[](2);
        uint16[] memory customShares = new uint16[](2);
        customRecipients[0] = recipient1;
        customRecipients[1] = recipient2;
        customShares[0] = 8000; // 80%
        customShares[1] = 2000; // 20%

        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeShares(customRecipients, customShares);

        (address[] memory recipients, uint16[] memory shares) =
                            configRegistry.getPegOutTreasuryFeeShares(TEST_TIMESTAMP);

        assertEq(recipients.length, customRecipients.length);
        assertEq(shares.length, customShares.length);
        assertEq(recipients[0], customRecipients[0]);
        assertEq(recipients[1], customRecipients[1]);
        assertEq(shares[0], customShares[0]);
        assertEq(shares[1], customShares[1]);
    }

    function test_GetPegOutTreasuryFeeShares_MultiTimestamps() public {
        uint64 ts1 = TEST_TIMESTAMP;
        uint64 ts2 = TEST_TIMESTAMP + 1000;
        uint64 ts3 = TEST_TIMESTAMP + 2000;

        address[] memory recipients1 = new address[](1);
        address[] memory recipients2 = new address[](2);
        address[] memory recipients3 = new address[](3);
        uint16[] memory shares1 = new uint16[](1);
        uint16[] memory shares2 = new uint16[](2);
        uint16[] memory shares3 = new uint16[](3);

        recipients1[0] = recipient1;
        recipients2[0] = recipient1;
        recipients2[1] = recipient2;
        recipients3[0] = recipient1;
        recipients3[1] = recipient2;
        recipients3[2] = recipient3;
        shares1[0] = 10000; // 100%
        shares2[0] = 6000; // 60%
        shares2[1] = 4000; // 40%
        shares3[0] = 5000; // 50%
        shares3[1] = 3000; // 30%
        shares3[2] = 2000; // 20%

        vm.warp(ts1);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeShares(recipients1, shares1);

        vm.warp(ts2);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeShares(recipients2, shares2);

        vm.warp(ts3);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeShares(recipients3, shares3);

        (address[] memory queried1, uint16[] memory sharesQueried1) = configRegistry.getPegOutTreasuryFeeShares(ts1);
        assertEq(queried1.length, recipients1.length);
        assertEq(sharesQueried1.length, shares1.length);
        assertEq(queried1[0], recipients1[0]);
        assertEq(sharesQueried1[0], shares1[0]);

        (address[] memory queried2, uint16[] memory sharesQueried2) = configRegistry.getPegOutTreasuryFeeShares(ts2);
        assertEq(queried2.length, recipients2.length);
        assertEq(sharesQueried2.length, shares2.length);
        assertEq(queried2[0], recipients2[0]);
        assertEq(queried2[1], recipients2[1]);
        assertEq(sharesQueried2[0], shares2[0]);
        assertEq(sharesQueried2[1], shares2[1]);

        (address[] memory queried3, uint16[] memory sharesQueried3) = configRegistry.getPegOutTreasuryFeeShares(ts3);
        assertEq(queried3.length, recipients3.length);
        assertEq(sharesQueried3.length, shares3.length);
        assertEq(queried3[0], recipients3[0]);
        assertEq(queried3[1], recipients3[1]);
        assertEq(queried3[2], recipients3[2]);
        assertEq(sharesQueried3[0], shares3[0]);
        assertEq(sharesQueried3[1], shares3[1]);
        assertEq(sharesQueried3[2], shares3[2]);

        uint64 tsMid = ts2 + 500;
        (address[] memory queriedMid, uint16[] memory sharesQueriedMid) = configRegistry.getPegOutTreasuryFeeShares(tsMid);
        assertEq(queriedMid.length, recipients2.length);
        assertEq(sharesQueriedMid.length, shares2.length);

        vm.expectRevert("FeeConfigHelper: fetch treasury fee shares failed");
        configRegistry.getPegOutTreasuryFeeShares(INIT_ADD_CONFIG_TIMESTAMP - 1000);
    }

    // ============ Constants Tests ============

    function test_Constants_Values() public {
        assertEq(configRegistry.DEFAULT_BITCOIN_CONFIRMATIONS(), 6);
        assertEq(configRegistry.DEFAULT_NATIVE_CONFIRMATIONS(), 12);
        assertEq(configRegistry.DEFAULT_REDEEM_DUST_AMOUNT(), 3000);
        assertEq(configRegistry.PERCENTAGE_BASE(), 10000);
    }
    // ============ Internal Functions ============
    function _createWhitelistGroup() internal {
        vm.prank(govAddress);
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        rawAddresses[0] = hex"1111111111111111111111111111111111111111";
        formats[0] = 1; // ADDRESS_FORMAT_NATIVE
        usages[0] = 1;
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }

    // ============ Events Declaration for Tests ============

    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);
    event BitcoinConfirmationsUpdated(
        uint32 indexed custodianId,
        uint32 oldConfirmations,
        uint32 newConfirmations
    );
    event NativeConfirmationsUpdated(
        uint32 indexed custodianId,
        uint32 oldConfirmations,
        uint32 newConfirmations
    );
    event PegInDepositDustAmountUpdated(uint64 oldAmount, uint64 newAmount);
    event PegInTreasuryFeeRateUpdated(uint16 oldRate, uint16 newRate);
    event PegInTreasuryFeeSharesUpdated(
        address[] oldRecipients,
        uint16[] oldShares,
        address[] newRecipients,
        uint16[] newShares
    );
    event PegOutRedeemDustAmountUpdated(uint64 oldAmount, uint64 newAmount);
    event PegOutTransactionFeeUpdated(uint64 oldFee, uint64 newFee);
    event PegOutTreasuryFeeRateUpdated(uint16 oldRate, uint16 newRate);
    event PegOutTreasuryFeeSharesUpdated(
        address[] oldRecipients,
        uint16[] oldShares,
        address[] newRecipients,
        uint16[] newShares
    );
} 