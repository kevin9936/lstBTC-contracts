// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {Deployer} from "./utils/Deployer.sol";
import {LstBTCBridgeLogic} from "contracts/bridge/LstBTCBridgeLogic.sol";
import {AccessControlBase} from "contracts/access/AccessControlBase.sol";
import {LstBTCBridgeStorage} from "contracts/bridge/LstBTCBridgeStorage.sol";
import {LstBTCBridgeProxy} from "contracts/bridge/LstBTCBridgeProxy.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {AddressUsage, PegRequest, PegStatus} from "contracts/types/DataTypes.sol";
import {Vm} from "forge-std/Vm.sol";
import "contracts/libraries/BitcoinHelper.sol";

contract TestFlow is Deployer {
    address public user1;
    address public user2;
    address public relayer1;
    address public relayer2;
    address public upgrader1;
    address public groupMemberOperator;
    bytes public userBtcAddress0;
    bytes public userBtcAddress1;

    bytes32 public constant ROLE_GROUP_MEMBER_OPERATOR = keccak256("ROLE_GROUP_MEMBER_OPERATOR");
    uint8 public constant ADDRESS_FORMAT_NATIVE = 1;
    uint8 public constant ADDRESS_FORMAT_BTC = 2;
    uint32 public constant BTC_TX_TIMESTAMP = 1717334400;

    address public operationsNativeAddress = 0x0e3d18A5703c2f7b024d79b878b586Cbd844C159;
    address public inboundNativeAddress = 0xDcE49E20aEA8be32C182E4f3429258001A101767;
    address public outboundNativeAddress = 0xC33B9734003154A6e1C305F313201AC247C42392;

    bytes public constant OUTBOUND_NATIVE_ADDRESS = hex"C33B9734003154A6e1C305F313201AC247C42392";
    bytes public constant INBOUND_NATIVE_ADDRESS = hex"DcE49E20aEA8be32C182E4f3429258001A101767";
    bytes public constant OPERATIONS_NATIVE_ADDRESS = hex"0e3d18A5703c2f7b024d79b878b586Cbd844C159";

    bytes public constant OUTBOUND_BTC_ADDRESS = P2PKH_ADDRESS;
    bytes public constant INBOUND_BTC_ADDRESS = P2WPKH_ADDRESS;
    bytes public constant OPERATIONS_BTC_ADDRESS = P2SH_ADDRESS;

    bytes public constant BORROW_BTC_ADDRESS = P2TR_ADDRESS;
    bytes public constant REPAYMENT_BTC_ADDRESS = P2WSH_ADDRESS;
    bytes public constant YIELD_BTC_ADDRESS = P2PK_ADDRESS;


    function setUp() public {
        user1 = address(2000);
        user2 = address(2001);
        groupMemberOperator = address(2005);
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(groupMemberOperator, "GroupMemberOperator");
        userBtcAddress0 = hex"001432220ff4c610d4ac87116d9af48c6a7e08250dd8";
        userBtcAddress1 = hex"5120df4f9110554d7fa9df30d6aaa6a7ee4358a7ae26ee2421aa495d09e3126956c4";
        vm.startPrank(govAddress);
        whitelistRegistry.grantRole(ROLE_GROUP_MEMBER_OPERATOR, groupMemberOperator);
        vm.stopPrank();
        mockGetChainTipHeight(20000);
        _initConfig();
        _addWhitelist();
    }

    function test_flow_mint_and_burn() public {
        bytes32 outboundBtcUtxo0 = submitBtcTx(bytes32('outboundBtcUtxo0'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, 10e8, hex"", 0);
        bytes32 outboundBtcUtxo1 = submitBtcTx(bytes32('outboundBtcUtxo1'), 0, userBtcAddress1, OUTBOUND_BTC_ADDRESS, 10e8, hex"", 0);
        bytes32 op0 = submitBtcTx(outboundBtcUtxo0, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 9e8);
        bytes32 op1 = submitBtcTx(outboundBtcUtxo1, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        bytes32 op2 = submitBtcTx(op0, 1, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 5e8, OUTBOUND_BTC_ADDRESS, 4e8);
        uint256[] memory pegInIds = new uint256[](3);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        pegInIds[2] = 3;
        (uint64 pendingPayWrappedAmount, uint64 pendingPayBTCAmount) = processPegBatch(pegInIds, new uint256[](0), operationsNativeAddress);
        vm.startPrank(operationsNativeAddress);
        lstBTC.transfer(inboundNativeAddress, pendingPayWrappedAmount);
        vm.startPrank(inboundNativeAddress);
        lstBTC.transfer(user1, 1e8 - 5e5);
        lstBTC.transfer(user2, 10e8 - 5e6);
        lstBTC.transfer(user2, 497500000);
        vm.stopPrank();
        bytes32 yieldBtcUtxo = submitBtcTx(bytes32('yieldBtcUtxo'), 0, userBtcAddress1, YIELD_BTC_ADDRESS, 10e8, hex"", 0);
        submitBtcTx(yieldBtcUtxo, 0, YIELD_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, YIELD_BTC_ADDRESS, 9e8);
        lstBTCTransfer(user1, outboundNativeAddress, 1e7);
        lstBTCTransfer(user2, outboundNativeAddress, 497500000);
        lstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 497500000);
        lstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e7);
        bytes32 operationsBtcUtxo0 = submitBtcTx(outboundBtcUtxo0, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e6, hex"", 0);
        bytes32 operationsBtcUtxo1 = submitBtcTx(outboundBtcUtxo0, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 3e8, hex"", 0);
        uint256[] memory pegInIds0 = new uint256[](1);
        uint256[] memory pegOutIds0 = new uint256[](1);
        pegInIds0[0] = 6;
        pegOutIds0[0] = 4;
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 20e8);
        (uint64 pendingPayWrappedAmount0, uint64 pendingPayBTCAmount0) = processPegBatch(pegInIds0, pegOutIds0, operationsNativeAddress);
        lstBTCBridge.getCustodianLatestBatch(10001);
        (uint32 latestBatchId, , , bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertEq(latestBatchId, 2);
        assertFalse(isPegInSettled);
        assertFalse(isPegOutSettled);
        bytes32 inboundBtcUtxo0 = submitBtcTx(operationsBtcUtxo0, 0, OPERATIONS_BTC_ADDRESS, INBOUND_BTC_ADDRESS, pendingPayBTCAmount0, hex"", 0);
        lstBTCTransfer(operationsNativeAddress, inboundNativeAddress, pendingPayWrappedAmount0);
        assertEq(lstBTC.balanceOf(user1), 1e8 - 5e5 - 1e7);
        assertEq(lstBTC.balanceOf(user2), 10e8 - 5e6);
        submitBtcTx(inboundBtcUtxo0, 0, INBOUND_BTC_ADDRESS, hex"001432220ff4c610d4ac87116d9af48c6a7e08250dd8", pendingPayBTCAmount0, hex"", 0);

        (,uint64 exchangeRate,) = navProvider.getLatestExchangeRate();
        uint64 expectedPendingPayBTCAmount0 = (497500000 - 497500000 * 100 / 10000) * exchangeRate / 1e8 - 1e3;
        uint64 expectedPendingPayWrappedAmount0 = (1e6 * 1e8 / exchangeRate) - (1e6 * 1e8 / exchangeRate * 50 / 10000);
        assertEq(pendingPayBTCAmount0, expectedPendingPayBTCAmount0);
        assertEq(pendingPayWrappedAmount0, expectedPendingPayWrappedAmount0);

        lstBTCTransfer(inboundNativeAddress, user1, pendingPayWrappedAmount0);
        assertEq(lstBTC.balanceOf(user1), 1e8 - 5e5 - 1e7 + pendingPayWrappedAmount0);
        pegInIds0[0] = 7;
        pegOutIds0[0] = 5;
        rejectPegBatch(pegInIds0, pegOutIds0);
        submitBtcTx(operationsBtcUtxo1, 0, OPERATIONS_BTC_ADDRESS, OUTBOUND_BTC_ADDRESS, 3e8, hex"", 0);
        lstBTCTransfer(operationsNativeAddress, outboundNativeAddress, 1e7);

        (uint32 latestBatchId1, , , bool isPegInSettled1, bool isPegOutSettled1) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertEq(latestBatchId1, 3);
        assertTrue(isPegInSettled1);
        assertTrue(isPegOutSettled1);

    }


    function test_multi_group_independent_mint_and_burn() public {
        address group2OperationsNative = makeAddr('group2OperationsNative');
        address group2InboundNative = makeAddr('group2InboundNative');
        address group2OutboundNative = makeAddr('group2OutboundNative');

        bytes memory group2OutboundBtc = hex"76a91411b366edfc0a8b66feebae5c2e25a7b6a5d1cf3188ac"; // P2PKH
        bytes memory group2InboundBtc = hex"0014751e76af77f1b9c6b7b4f2d1d5a3c7b8e9a2f3d4"; // P2WPKH  
        bytes memory group2OperationsBtc = hex"a91414ab65016d04bb9d2df3b6b15c6b4a7f9e8c3d2b87"; // P2SH

        _addGroup2Whitelist(
            group2OutboundBtc, group2InboundBtc, group2OperationsBtc,
            abi.encodePacked(group2OutboundNative), abi.encodePacked(group2InboundNative), abi.encodePacked(group2OperationsNative)
        );

        bytes32 group1OutboundUtxo0 = submitBtcTx(bytes32('group1OutboundUtxo0'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, 5e8, hex"", 0);
        bytes32 group1OutboundUtxo1 = submitBtcTx(bytes32('group1OutboundUtxo1'), 0, userBtcAddress1, OUTBOUND_BTC_ADDRESS, 8e8, hex"", 0);

        bytes32 group1Op0 = submitBtcTx(group1OutboundUtxo0, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 5e8, hex"", 0);
        bytes32 group1Op1 = submitBtcTx(group1OutboundUtxo1, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 8e8, hex"", 0);

        bytes32 group2OutboundUtxo0 = submitBtcTx(bytes32('group2OutboundUtxo0'), 0, userBtcAddress0, group2OutboundBtc, 6e8, hex"", 0);
        bytes32 group2OutboundUtxo1 = submitBtcTx(bytes32('group2OutboundUtxo1'), 0, userBtcAddress1, group2OutboundBtc, 9e8, hex"", 0);

        bytes32 group2Op0 = submitBtcTx(group2OutboundUtxo0, 0, group2OutboundBtc, hex"a91414ab65016d04bb9d2df3b6b15c6b4a7f9e8c3d2b87", 6e8, hex"", 0);
        bytes32 group2Op1 = submitBtcTx(group2OutboundUtxo1, 0, group2OutboundBtc, hex"a91414ab65016d04bb9d2df3b6b15c6b4a7f9e8c3d2b87", 9e8, hex"", 0);

        uint256[] memory group1PegInIds = new uint256[](2);
        group1PegInIds[0] = 1;
        group1PegInIds[1] = 2;
        (uint64 group1PendingPayWrapped, uint64 group1PendingPayBTC) = processPegBatch(group1PegInIds, new uint256[](0), operationsNativeAddress);

        uint256[] memory group2PegInIds = new uint256[](2);
        group2PegInIds[0] = 3;
        group2PegInIds[1] = 4;
        (uint64 group2PendingPayWrapped, uint64 group2PendingPayBTC) = processPegBatch(group2PegInIds, new uint256[](0), makeAddr('group2OperationsNative'));

        lstBTCTransfer(operationsNativeAddress, inboundNativeAddress, group1PendingPayWrapped);
        lstBTCTransfer(makeAddr('group2OperationsNative'), makeAddr('group2InboundNative'), group2PendingPayWrapped);

        lstBTCTransfer(inboundNativeAddress, user1, group1PendingPayWrapped / 2);
        lstBTCTransfer(inboundNativeAddress, user2, group1PendingPayWrapped / 2);
        lstBTCTransfer(makeAddr('group2InboundNative'), user1, group2PendingPayWrapped / 3);
        lstBTCTransfer(makeAddr('group2InboundNative'), user2, group2PendingPayWrapped * 2 / 3);

        bytes32 group1YieldUtxo = submitBtcTx(bytes32('group1YieldUtxo'), 0, userBtcAddress0, YIELD_BTC_ADDRESS, 2e8, hex"", 0);
        submitBtcTx(group1YieldUtxo, 0, YIELD_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);
        vm.warp(block.timestamp + 1);
        bytes32 group2YieldUtxo = submitBtcTx(bytes32('group2YieldUtxo'), 0, userBtcAddress1, YIELD_BTC_ADDRESS, 3e8, hex"", 0);
        submitBtcTx(group2YieldUtxo, 0, YIELD_BTC_ADDRESS, hex"a91414ab65016d04bb9d2df3b6b15c6b4a7f9e8c3d2b87", 3e8, hex"", 0);
        vm.warp(block.timestamp + 20);
        uint64 group1BurnAmount = 1e8;
        lstBTCTransfer(user1, outboundNativeAddress, group1BurnAmount);
        lstBTCTransfer(outboundNativeAddress, operationsNativeAddress, group1BurnAmount);

        uint64 group2BurnAmount = 2e8;
        lstBTCTransfer(user2, makeAddr('group2OutboundNative'), group2BurnAmount);
        lstBTCTransfer(makeAddr('group2OutboundNative'), makeAddr('group2OperationsNative'), group2BurnAmount);

        uint256[] memory group1PegOutIds = new uint256[](1);
        group1PegOutIds[0] = 5;
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 10e8);
        (, uint64 group2PendingPayBTC1) = processPegBatch(new uint256[](0), group1PegOutIds, operationsNativeAddress);
        (, uint64 exchangeRate,) = navProvider.getLatestExchangeRate();
        uint64 expectedPendingPayBTC1 = (1e8 - (1e8 * 100 / 10000)) * exchangeRate / 1e8 - 1e3;
        assertEq(group2PendingPayBTC1, expectedPendingPayBTC1);

        uint256[] memory group2PegOutIds = new uint256[](1);
        group2PegOutIds[0] = 6;
        vm.prank(makeAddr('group2OperationsNative'));
        lstBTC.approve(address(lstBTCBridge), 10e8);
        processPegBatch(new uint256[](0), group2PegOutIds, makeAddr('group2OperationsNative'));

        (, , uint256[] memory pegOutIds0,, bool group1IsPegOutSettled) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertEq(pegOutIds0[0], 5);
        assertEq(group1IsPegOutSettled, false);

        (, , uint256[] memory pegOutIds1,, bool group2IsPegOutSettled) = lstBTCBridge.getCustodianLatestBatch(10002);
        assertEq(pegOutIds1[0], 6);
        assertEq(group2IsPegOutSettled, false);

        assertTrue(lstBTC.balanceOf(user1) > 0);
        assertTrue(lstBTC.balanceOf(user2) > 0);
    }


    function test_flow_borrow_repay() public {
        address group2OperationsNative = makeAddr('group2OperationsNative');
        address group2InboundNative = makeAddr('group2InboundNative');
        address group2OutboundNative = makeAddr('group2OutboundNative');

        bytes memory group2OutboundBtc = hex"76a91411b366edfc0a8b66feebae5c2e25a7b6a5d1cf3188ac";
        bytes memory group2InboundBtc = hex"0014751e76af77f1b9c6b7b4f2d1d5a3c7b8e9a2f3d4";
        bytes memory group2OperationsBtc = hex"a91414ab65016d04bb9d2df3b6b15c6b4a7f9e8c3d2b87";

        _addGroup2Whitelist(
            group2OutboundBtc, group2InboundBtc, group2OperationsBtc,
            abi.encodePacked(group2OutboundNative), abi.encodePacked(group2InboundNative), abi.encodePacked(group2OperationsNative)
        );
        bytes32 userMint1 = submitBtcTx(bytes32('userMint1'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, 5e8, hex"", 0);
        bytes32 userMint2 = submitBtcTx(bytes32('userMint2'), 0, userBtcAddress1, group2OutboundBtc, 8e8, hex"", 0);
        submitBtcTx(userMint1, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 5e8, hex"", 0);
        submitBtcTx(userMint2, 0, group2OutboundBtc, group2OperationsBtc, 8e8, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](0);
        processPegBatch(pegInIds, pegOutIds, operationsNativeAddress);
        pegInIds[0] = 2;
        processPegBatch(pegInIds, pegOutIds, makeAddr('group2OperationsNative'));


        uint64 initialTotalDebt = lstBTCBridge.getCustodianDebt(10001);
        uint64 initialTotalDebt2 = lstBTCBridge.getCustodianDebt(10002);
        bytes32 group1BorrowUtxo = submitBtcTx(bytes32('group1BorrowUtxo'), 0, userBtcAddress0, BORROW_BTC_ADDRESS, 5e8, hex"", 0);
        bytes32 group2BorrowUtxo = submitBtcTx(bytes32('group2BorrowUtxo'), 0, userBtcAddress1, BORROW_BTC_ADDRESS, 8e8, hex"", 0);

        bytes32 group1OperationsUtxo = submitBtcTx(group1BorrowUtxo, 0, BORROW_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 5e8, hex"", 0);
        bytes32 group2OperationsUtxo = submitBtcTx(group2BorrowUtxo, 0, BORROW_BTC_ADDRESS, hex"a91414ab65016d04bb9d2df3b6b15c6b4a7f9e8c3d2b87", 8e8, hex"", 0);
        uint64 debtAfterBorrow = lstBTCBridge.getCustodianDebt(10001);
        uint64 debtAfterBorrow2 = lstBTCBridge.getCustodianDebt(10002);
        assertEq(debtAfterBorrow, initialTotalDebt + 5e8);
        assertEq(debtAfterBorrow2, initialTotalDebt2 + 8e8);

        bytes32 group1RepayUtxo = submitBtcTx(group1OperationsUtxo, 0, OPERATIONS_BTC_ADDRESS, REPAYMENT_BTC_ADDRESS, 5e8, hex"", 0);
        bytes32 group2RepayUtxo = submitBtcTx(group2OperationsUtxo, 0, hex"a91414ab65016d04bb9d2df3b6b15c6b4a7f9e8c3d2b87", REPAYMENT_BTC_ADDRESS, 8e8, hex"", 0);
        uint64 debtAfterRepay = lstBTCBridge.getCustodianDebt(10001);
        uint64 debtAfterRepay2 = lstBTCBridge.getCustodianDebt(10002);
        assertEq(debtAfterRepay, initialTotalDebt + 5e8 - 5e8);
        assertEq(debtAfterRepay2, initialTotalDebt2 + 8e8 - 8e8);


    }


    function test_flow_modified_fee_rates() public {
        uint16 newPegInFeeRate = 200;
        uint16 newPegOutFeeRate = 300;
        uint64 newPegOutTransactionFee = 2000;

        address treasury1 = makeAddr("treasury1");
        address treasury2 = makeAddr("treasury2");
        address[] memory newRecipients = new address[](2);
        uint16[] memory newShares = new uint16[](2);
        newRecipients[0] = treasury1;
        newRecipients[1] = treasury2;
        newShares[0] = 6000;
        newShares[1] = 4000;

        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        configRegistry.setPegInTreasuryFeeRate(newPegInFeeRate);

        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(newRecipients, newShares);

        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(newPegOutFeeRate);
        vm.prank(govAddress);
        configRegistry.setPegOutTransactionFee(newPegOutTransactionFee);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeShares(newRecipients, newShares);

        uint64 mintAmount = 10e8;
        bytes32 userMintTx = submitBtcTx(bytes32('userMintTx0'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, mintAmount, hex"", 0);
        bytes32 operationsTx = submitBtcTx(userMintTx, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, mintAmount, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        (uint64 pendingPayWrapped, uint64 pendingPayBTC) = processPegBatch(pegInIds, new uint256[](0), operationsNativeAddress);

        uint64 expectedFee = (mintAmount * 200) / 10000;
        uint64 expectedNetAmount = mintAmount - expectedFee;

        assertEq(pendingPayWrapped, expectedNetAmount);

        lstBTCTransfer(operationsNativeAddress, inboundNativeAddress, pendingPayWrapped);
        lstBTCTransfer(inboundNativeAddress, user1, pendingPayWrapped);

        assertEq(lstBTC.balanceOf(user1), pendingPayWrapped);

        address treasury3 = makeAddr("treasury3");
        address treasury4 = makeAddr("treasury4");
        address[] memory newRecipients1 = new address[](2);
        uint16[] memory newShares1 = new uint16[](2);
        newRecipients1[0] = treasury3;
        newRecipients1[1] = treasury4;
        newShares1[0] = 7000;
        newShares1[1] = 3000;

        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP + 1000);
        configRegistry.setPegInTreasuryFeeRate(5000);
        vm.prank(govAddress);
        configRegistry.setPegInTreasuryFeeShares(newRecipients1, newShares1);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(1000);
        vm.prank(govAddress);
        configRegistry.setPegOutTransactionFee(3000);
        vm.prank(govAddress);
        configRegistry.setPegOutTreasuryFeeShares(newRecipients1, newShares1);

        uint64 redeemAmount = 5e8;
        lstBTCTransfer(user1, outboundNativeAddress, redeemAmount);
        vm.warp(BTC_TX_TIMESTAMP + 2000);
        lstBTCTransfer(outboundNativeAddress, operationsNativeAddress, redeemAmount);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 2;
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 10e8);
        (uint64 pendingPayWrapped2, uint64 pendingPayBTC2) = processPegBatch(new uint256[](0), pegOutIds, operationsNativeAddress);

        uint64 expectedPegOutFee = redeemAmount * 1000 / 10000;
        uint64 expectedNetPayout = redeemAmount - expectedPegOutFee - 3000;
        assertEq(pendingPayBTC2, expectedNetPayout);
        assertEq(lstBTCBridge.claimableFees(makeAddr("treasury3")), expectedPegOutFee * 7000 / 10000);
        assertEq(lstBTCBridge.claimableFees(makeAddr("treasury4")), expectedPegOutFee * 3000 / 10000);

        bytes32 operationsTx1 = submitBtcTx('userTx1', 0, userBtcAddress0, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        submitBtcTx(operationsTx1, 0, OPERATIONS_BTC_ADDRESS, INBOUND_BTC_ADDRESS, pendingPayBTC2, hex"", 0);

        vm.warp(BTC_TX_TIMESTAMP + 3000);
        bytes32 userMintTx1 = submitBtcTx(bytes32('userMintTx1'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, 1e8, hex"", 0);
        submitBtcTx(userMintTx1, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        vm.warp(BTC_TX_TIMESTAMP + 4000);
        vm.prank(govAddress);
        address treasury5 = makeAddr("treasury5");
        address treasury6 = makeAddr("treasury6");
        address[] memory newRecipients2 = new address[](2);
        uint16[] memory newShares2 = new uint16[](2);
        newRecipients2[0] = treasury5;
        newRecipients2[1] = treasury6;
        newShares2[0] = 9000;
        newShares2[1] = 1000;
        configRegistry.setPegInTreasuryFeeShares(newRecipients2, newShares2);
        vm.warp(BTC_TX_TIMESTAMP + 5000);
        uint256[] memory pegInIds1 = new uint256[](1);
        pegInIds1[0] = 3;
        processPegBatch(pegInIds1, new uint256[](0), operationsNativeAddress);
        assertEq(lstBTCBridge.claimableFees(makeAddr("treasury3")), 1e8 / 2 * 7000 / 10000 * 2);
        assertEq(lstBTCBridge.claimableFees(makeAddr("treasury4")), 1e8 / 2 * 3000 / 10000 * 2);

    }

    function test_flow_modified_fee_rates_0() public {
        vm.startPrank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        configRegistry.setPegInTreasuryFeeRate(0);
        configRegistry.setPegOutTreasuryFeeRate(0);
        configRegistry.setPegOutTransactionFee(0);
        vm.stopPrank();

        uint64 mintAmount = 10e8;
        bytes32 userMintTx = submitBtcTx(bytes32('userMintTx0'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, mintAmount, hex"", 0);
        bytes32 operationsTx = submitBtcTx(userMintTx, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, mintAmount, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        (uint64 pendingPayWrapped, uint64 pendingPayBTC) = processPegBatch(pegInIds, new uint256[](0), operationsNativeAddress);
        assertEq(pendingPayWrapped, mintAmount);
        assertEq(pendingPayBTC, 0);
        lstBTCTransfer(operationsNativeAddress, inboundNativeAddress, pendingPayWrapped);

        lstBTCTransfer(inboundNativeAddress, user1, mintAmount);
        lstBTCTransfer(user1, outboundNativeAddress, mintAmount);
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 20e8);
        lstBTCTransfer(outboundNativeAddress, operationsNativeAddress, mintAmount);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 2;
        (uint64 pendingPayWrapped2, uint64 pendingPayBTC2) = processPegBatch(new uint256[](0), pegOutIds, operationsNativeAddress);
        assertEq(pendingPayBTC2, mintAmount);
        assertEq(pendingPayWrapped2, 0);
        submitBtcTx(operationsTx, 0, OPERATIONS_BTC_ADDRESS, INBOUND_BTC_ADDRESS, pendingPayBTC2, hex"", 0);
    }

    function test_transfer_operation_errors() public {
        uint64 correctAmount = 5e8;
        uint64 wrongAmount = 3e8;
        bytes32 userMintTx = submitBtcTx(bytes32('userMintTx'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, correctAmount, OUTBOUND_BTC_ADDRESS, correctAmount);
        bytes32 operationsTx = submitBtcTx(userMintTx, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, correctAmount, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 20e8);
        (uint64 pendingPayWrapped, uint64 pendingPayBTC) = processPegBatch(pegInIds, new uint256[](0), operationsNativeAddress);
        lstBTCTransfer(operationsNativeAddress, inboundNativeAddress, pendingPayWrapped);
        lstBTCTransfer(inboundNativeAddress, user1, pendingPayWrapped);
        lstBTCTransfer(user1, outboundNativeAddress, pendingPayWrapped);
        lstBTCTransfer(outboundNativeAddress, operationsNativeAddress, pendingPayWrapped / 2);
        // 1. The amount of money paid is incorrect
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 2;
        (uint64 pendingPayWrapped2, uint64 pendingPayBTC2) = processPegBatch(new uint256[](0), pegOutIds, operationsNativeAddress);
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(operationsTx, 0, INBOUND_BTC_ADDRESS, pendingPayBTC2 - 1, hex"", 0);
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectRevert();
        lstBTCBridge.submitTransactionProof(rawTx, blockHeight, new bytes32[](1), 0, OPERATIONS_BTC_ADDRESS, toPkScripts);
        bytes32 operationsTx1 = submitBtcTx(txId, 0, INBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, pendingPayBTC2 - 1, hex"", 0);
        (, , ,bool isPegInSettled1, bool isPegOutSettled1) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertFalse(isPegOutSettled1);
        submitBtcTx(operationsTx1, 0, OPERATIONS_BTC_ADDRESS, INBOUND_BTC_ADDRESS, pendingPayBTC2, hex"", 0);
        (, , ,bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertTrue(isPegInSettled);
        assertTrue(isPegOutSettled);
        // 2.I need a refund, I went to pay
        bytes32 userMintTx2 = submitBtcTx(bytes32('userMintTx1'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, 10e8, OUTBOUND_BTC_ADDRESS, 10e8);
        bytes32 operationsTx2 = submitBtcTx(userMintTx2, 1, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 5e8, hex"", 0);
        uint256[] memory inPendingPegInIds = new uint256[](1);
        inPendingPegInIds[0] = 3;
        rejectPegBatch(inPendingPegInIds, new uint256[](0));
        (bytes memory rawTx1, bytes32 txId1, bytes[] memory toPkScripts1) = buildBtcRawTx(operationsTx2, 0, INBOUND_BTC_ADDRESS, 5e8, hex"", 0);
        uint32 blockHeight1 = 90001;
        mockCheckTxProof(txId1, blockHeight1, true);
        vm.prank(relayerAddress);
        vm.expectRevert();
        lstBTCBridge.submitTransactionProof(rawTx1, blockHeight1, new bytes32[](1), 0, OPERATIONS_BTC_ADDRESS, toPkScripts1);
        bytes32 operationsTx3 = submitBtcTx(txId1, 0, INBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 5e8, hex"", 0);
        (, , ,bool isPegInSettled2, bool isPegOutSettled2) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertFalse(isPegInSettled2);
        submitBtcTx(operationsTx3, 0, OPERATIONS_BTC_ADDRESS, OUTBOUND_BTC_ADDRESS, 5e8, hex"", 0);
        (, , ,bool isPegInSettled3, bool isPegOutSettled3) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertTrue(isPegInSettled3);
        assertTrue(isPegOutSettled3);
        // 3.The change address is another withdrawal address when minting
        bytes memory secondOutboundBtcAddress = hex"76a91412c54f253623b6f6bb328fae0e8c9a73ee8a544688ac";
        bytes[] memory newAddresses = new bytes[](1);
        uint8[] memory newFormats = new uint8[](1);
        uint8[] memory newUsages = new uint8[](1);
        newAddresses[0] = secondOutboundBtcAddress;
        newFormats[0] = ADDRESS_FORMAT_BTC;
        newUsages[0] = AddressUsage.INBOUND;
        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(10001, newAddresses, newFormats, newUsages);
        assertEq(lstBTCBridge.requestIdCounter(), 3);
        bytes32 userMintTx3 = submitBtcTx(bytes32('userMintTx3'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, 10e8, secondOutboundBtcAddress, 10e8);
        assertEq(lstBTCBridge.requestIdCounter(), 3);
    }

    function test_flow_multiple_operations_addresses_in_group() public {
        address secondOperationsNativeAddress = makeAddr("secondOperationsNative");
        bytes memory secondOperationsBtcAddress = hex"a914f2cce6a0fa833e85a9127843a68a640c0d12107787";

        bytes[] memory newAddresses = new bytes[](2);
        uint8[] memory newFormats = new uint8[](2);
        uint8[] memory newUsages = new uint8[](2);

        newAddresses[0] = abi.encodePacked(secondOperationsNativeAddress);
        newAddresses[1] = secondOperationsBtcAddress;
        newFormats[0] = ADDRESS_FORMAT_NATIVE;
        newFormats[1] = ADDRESS_FORMAT_BTC;
        newUsages[0] = AddressUsage.OPERATIONS;
        newUsages[1] = AddressUsage.OPERATIONS;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(10001, newAddresses, newFormats, newUsages);

        bytes32 userMintTx1 = submitBtcTx(bytes32('userMintTx1'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, 5e8, hex"", 0);
        bytes32 userMintTx2 = submitBtcTx(bytes32('userMintTx2'), 0, userBtcAddress1, OUTBOUND_BTC_ADDRESS, 3e8, hex"", 0);

        bytes32 operationsTx1 = submitBtcTx(userMintTx1, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 5e8, hex"", 0);

        bytes32 operationsTx2 = submitBtcTx(userMintTx2, 0, OUTBOUND_BTC_ADDRESS, hex"a914f2cce6a0fa833e85a9127843a68a640c0d12107787", 3e8, hex"", 0);

        uint256[] memory pegInIds1 = new uint256[](1);
        pegInIds1[0] = 1;
        (uint64 pendingPayWrapped1,) = processPegBatch(pegInIds1, new uint256[](0), operationsNativeAddress);
        lstBTCTransfer(operationsNativeAddress, inboundNativeAddress, pendingPayWrapped1);


        uint256[] memory pegInIds2 = new uint256[](1);
        pegInIds2[0] = 2;
        (uint64 pendingPayWrapped2,) = processPegBatch(pegInIds2, new uint256[](0), makeAddr("secondOperationsNative"));
        lstBTCTransfer(makeAddr("secondOperationsNative"), inboundNativeAddress, pendingPayWrapped2);
        lstBTCTransfer(inboundNativeAddress, user1, pendingPayWrapped1);
        lstBTCTransfer(inboundNativeAddress, user2, pendingPayWrapped2);

        assertEq(lstBTC.balanceOf(user1), pendingPayWrapped1);
        assertEq(lstBTC.balanceOf(user2), pendingPayWrapped2);

        lstBTCTransfer(user1, outboundNativeAddress, pendingPayWrapped1 / 2);
        lstBTCTransfer(outboundNativeAddress, makeAddr("secondOperationsNative"), pendingPayWrapped1 / 2);

        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 3;
        vm.prank(makeAddr("secondOperationsNative"));
        lstBTC.approve(address(lstBTCBridge), 10e8);
        (, uint64 pendingPayBTC) = processPegBatch(new uint256[](0), pegOutIds, makeAddr("secondOperationsNative"));

        bytes32 finalTx = submitBtcTx(operationsTx2, 0, hex"a914f2cce6a0fa833e85a9127843a68a640c0d12107787", INBOUND_BTC_ADDRESS, pendingPayBTC, hex"", 0);


        (uint32 latestBatchId, , , bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertEq(latestBatchId, 3);
        assertEq(isPegInSettled, true);
        assertEq(isPegOutSettled, true);
    }


    function test_flow_multiple_inbound_outbound_addresses_in_group() public {
        address secondOutboundNativeAddress = makeAddr("secondOutboundNative");
        address secondInboundNativeAddress = makeAddr("secondInboundNative");
        bytes memory secondOutboundBtcAddress = hex"76a91412c54f253623b6f6bb328fae0e8c9a73ee8a544688ac";
        bytes memory secondInboundBtcAddress = hex"a9149640ddcafd397f9b6e45f9ef5284c10ce3486cd987";

        bytes[] memory newAddresses = new bytes[](4);
        uint8[] memory newFormats = new uint8[](4);
        uint8[] memory newUsages = new uint8[](4);

        newAddresses[0] = abi.encodePacked(secondOutboundNativeAddress);
        newAddresses[1] = secondOutboundBtcAddress;
        newAddresses[2] = abi.encodePacked(secondInboundNativeAddress);
        newAddresses[3] = secondInboundBtcAddress;

        newFormats[0] = ADDRESS_FORMAT_NATIVE;
        newFormats[1] = ADDRESS_FORMAT_BTC;
        newFormats[2] = ADDRESS_FORMAT_NATIVE;
        newFormats[3] = ADDRESS_FORMAT_BTC;

        newUsages[0] = AddressUsage.OUTBOUND;
        newUsages[1] = AddressUsage.OUTBOUND;
        newUsages[2] = AddressUsage.INBOUND;
        newUsages[3] = AddressUsage.INBOUND;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(10001, newAddresses, newFormats, newUsages);

        bytes32 userMintTx1 = submitBtcTx(bytes32('userMintTx1'), 0, userBtcAddress0, OUTBOUND_BTC_ADDRESS, 4e8, hex"", 0);
        bytes32 userMintTx2 = submitBtcTx(bytes32('userMintTx2'), 0, userBtcAddress1, secondOutboundBtcAddress, 6e8, hex"", 0);

        bytes32 operationsTx1 = submitBtcTx(userMintTx1, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 4e8, hex"", 0);
        bytes32 operationsTx2 = submitBtcTx(userMintTx2, 0, secondOutboundBtcAddress, OPERATIONS_BTC_ADDRESS, 6e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](2);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        (uint64 pendingPayWrapped,) = processPegBatch(pegInIds, new uint256[](0), operationsNativeAddress);

        lstBTCTransfer(operationsNativeAddress, secondInboundNativeAddress, pendingPayWrapped);
        lstBTCTransfer(secondInboundNativeAddress, user1, pendingPayWrapped / 2);
        lstBTCTransfer(secondInboundNativeAddress, user2, pendingPayWrapped / 2);

        assertEq(lstBTC.balanceOf(user1), pendingPayWrapped / 2);
        assertEq(lstBTC.balanceOf(user2), pendingPayWrapped / 2);

        uint64 redeemAmount1 = 2e8;
        uint64 redeemAmount2 = 3e8;

        lstBTCTransfer(user1, outboundNativeAddress, redeemAmount1);
        lstBTCTransfer(user2, makeAddr("secondOutboundNative"), redeemAmount2);
        lstBTCTransfer(outboundNativeAddress, operationsNativeAddress, redeemAmount1);
        lstBTCTransfer(makeAddr("secondOutboundNative"), operationsNativeAddress, redeemAmount2);

        uint256[] memory pegOutIds = new uint256[](2);
        pegOutIds[0] = 3;
        pegOutIds[1] = 4;
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 20e8);
        (, uint64 pendingPayBTC) = processPegBatch(new uint256[](0), pegOutIds, operationsNativeAddress);

        bytes32 inboundTx1 = submitBtcTx(operationsTx1, 0, OPERATIONS_BTC_ADDRESS, INBOUND_BTC_ADDRESS, pendingPayBTC, hex"", 0);

        submitBtcTx(inboundTx1, 0, INBOUND_BTC_ADDRESS, userBtcAddress0, pendingPayBTC / 2, hex"", 0);
        submitBtcTx(inboundTx1, 0, hex"a9149640ddcafd397f9b6e45f9ef5284c10ce3486cd987", userBtcAddress1, pendingPayBTC / 2, hex"", 0);

        (uint32 latestBatchId, , , bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.getCustodianLatestBatch(10001);
        assertEq(latestBatchId, 2);
        assertEq(isPegInSettled, true);
        assertEq(isPegOutSettled, true);
    }


    function _addGroup2Whitelist(
        bytes memory group2OutboundBtc,
        bytes memory group2InboundBtc,
        bytes memory group2OperationsBtc,
        bytes memory group2OutboundNative,
        bytes memory group2InboundNative,
        bytes memory group2OperationsNative
    ) internal {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        rawAddresses[0] = hex"a914000000000000000000000000000000000000000187";
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;
        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(10002, rawAddresses, formats, usages);

        bytes[] memory group2Addresses = new bytes[](6);
        uint8[] memory group2Formats = new uint8[](6);
        uint8[] memory group2Usages = new uint8[](6);

        group2Addresses[0] = group2OutboundBtc;
        group2Addresses[1] = group2InboundBtc;
        group2Addresses[2] = group2OperationsBtc;
        group2Addresses[3] = group2OutboundNative;
        group2Addresses[4] = group2InboundNative;
        group2Addresses[5] = group2OperationsNative;

        group2Formats[0] = ADDRESS_FORMAT_BTC;
        group2Formats[1] = ADDRESS_FORMAT_BTC;
        group2Formats[2] = ADDRESS_FORMAT_BTC;
        group2Formats[3] = ADDRESS_FORMAT_NATIVE;
        group2Formats[4] = ADDRESS_FORMAT_NATIVE;
        group2Formats[5] = ADDRESS_FORMAT_NATIVE;

        group2Usages[0] = AddressUsage.OUTBOUND;
        group2Usages[1] = AddressUsage.INBOUND;
        group2Usages[2] = AddressUsage.OPERATIONS;
        group2Usages[3] = AddressUsage.OUTBOUND;
        group2Usages[4] = AddressUsage.INBOUND;
        group2Usages[5] = AddressUsage.OPERATIONS;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(10002, group2Addresses, group2Formats, group2Usages);
    }

    function processPegBatch(uint256[] memory pegInIds, uint256[] memory pegOutIds, address operationsNative) public returns (uint64, uint64) {
        vm.prank(operationsNative);
        vm.roll(block.number + 12);
        mockGetChainTipHeight(90030);
        vm.recordLogs();
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 batchProcessedSig = keccak256("BatchProcessed(uint32,uint256[],uint256[],uint64,uint64)");
        uint64 pendingPayWrappedAmount;
        uint64 pendingPayBTCAmount;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == batchProcessedSig) {
                bytes memory data = entries[i].data;
                assembly {
                    pendingPayWrappedAmount := mload(add(data, 0x60))
                    pendingPayBTCAmount := mload(add(data, 0x80))
                }
                break;
            }
        }
        return (pendingPayWrappedAmount, pendingPayBTCAmount);
    }

    function rejectPegBatch(uint256[] memory pegInIds, uint256[] memory pegOutIds) public {
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function _initConfig() public {
        lstBTC.setMaxMintLimit(30e8);
        _init_createGroup();
    }

    function _init_createGroup() internal {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        rawAddresses[0] = hex"a914000000000000000000000000000000000000000087";
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;
        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(10001, rawAddresses, formats, usages);
    }

    function _addWhitelist() internal {
        bytes[] memory rawAddresses = new bytes[](6);
        uint8[] memory formats = new uint8[](6);
        uint8[] memory usages = new uint8[](6);
        bytes[] memory rawAddresses1 = new bytes[](3);
        uint8[] memory formats1 = new uint8[](3);
        uint8[] memory usages1 = new uint8[](3);

        rawAddresses[0] = OUTBOUND_BTC_ADDRESS;
        rawAddresses[1] = INBOUND_BTC_ADDRESS;
        rawAddresses[2] = OPERATIONS_BTC_ADDRESS;
        rawAddresses[3] = OUTBOUND_NATIVE_ADDRESS;
        rawAddresses[4] = INBOUND_NATIVE_ADDRESS;
        rawAddresses[5] = OPERATIONS_NATIVE_ADDRESS;

        formats[0] = ADDRESS_FORMAT_BTC;
        formats[1] = ADDRESS_FORMAT_BTC;
        formats[2] = ADDRESS_FORMAT_BTC;
        formats[3] = ADDRESS_FORMAT_NATIVE;
        formats[4] = ADDRESS_FORMAT_NATIVE;
        formats[5] = ADDRESS_FORMAT_NATIVE;

        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.INBOUND;
        usages[2] = AddressUsage.OPERATIONS;
        usages[3] = AddressUsage.OUTBOUND;
        usages[4] = AddressUsage.INBOUND;
        usages[5] = AddressUsage.OPERATIONS;

        rawAddresses1[0] = BORROW_BTC_ADDRESS;
        rawAddresses1[1] = REPAYMENT_BTC_ADDRESS;
        rawAddresses1[2] = YIELD_BTC_ADDRESS;

        formats1[0] = ADDRESS_FORMAT_BTC;
        formats1[1] = ADDRESS_FORMAT_BTC;
        formats1[2] = ADDRESS_FORMAT_BTC;

        usages1[0] = AddressUsage.BORROW;
        usages1[1] = AddressUsage.REPAYMENT;
        usages1[2] = AddressUsage.YIELD;
        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(10000, rawAddresses1, formats1, usages1);
        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(10001, rawAddresses, formats, usages);
    }

    function lstBTCTransfer(address from, address to, uint64 amount) public {
        vm.prank(from);
        lstBTC.transfer(to, amount);
    }

    function submitBtcTx(bytes32 utxo, uint32 index, bytes memory fromPkScript, bytes memory toPkScript, uint64 amount, bytes memory changePkScript, uint64 changeAmount) public returns (bytes32) {
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(utxo, index, toPkScript, amount, changePkScript, changeAmount);
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            fromPkScript,
            toPkScripts
        );
        return txId;
    }
}
