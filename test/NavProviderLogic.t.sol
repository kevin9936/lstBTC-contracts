// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deployer} from "./utils/Deployer.sol";
import {NavProviderLogic} from "contracts/nav/NavProviderLogic.sol";
import {NavProviderProxy} from "contracts/nav/NavProviderProxy.sol";
import {AccessControlBase} from "contracts/access/AccessControlBase.sol";
import {ILstBTCBridge} from "contracts/bridge/interfaces/ILstBTCBridge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NavProviderLogicTest is Deployer {
    address public user1;
    address public user2;
    address public user3;
    address public notGovernor;
    address public notBridge;
    address public custodian1;
    address public custodian2;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    // Test data
    uint64 public constant TEST_PEGGED_BTC_AMOUNT = 1000000; // 0.01 BTC in satoshis
    uint64 public constant TEST_YIELD_AMOUNT = 50000; // 0.0005 BTC in satoshis
    uint32 public constant TEST_CUSTODIAN_ID = 10001;
    uint64 public constant DEFAULT_DECIMALS = 1e8;
    bytes32 public constant TEST_TX_ID = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    uint64 public constant TEST_TIMESTAMP = 1640995200; // 2022-01-01 00:00:00

    function setUp() public {
        user1 = address(2000);
        user2 = address(2001);
        user3 = address(2002);
        notGovernor = address(3000);
        notBridge = address(3001);
        custodian1 = address(4000);
        custodian2 = address(4001);

        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(notGovernor, "NotGovernor");
        vm.label(notBridge, "NotBridge");
        vm.label(custodian1, "Custodian1");
        vm.label(custodian2, "Custodian2");

        // Set max mint limit to 1000 * DEFAULT_DECIMALS
        lstBTC.setMaxMintLimit(1000 * DEFAULT_DECIMALS);
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public {
        assertTrue(navProvider.hasRole(DEFAULT_ADMIN_ROLE, adminAddress));
        assertTrue(navProvider.hasRole(ROLE_GOVERNOR, govAddress));

        (uint64 updateTime, uint64 exchangeRate, uint8 decimals) = navProvider.getLatestExchangeRate();
        assertEq(updateTime, 0);
        assertEq(exchangeRate, navProvider.INITIAL_EXCHANGE_RATE());
        assertEq(decimals, navProvider.EXCHANGE_RATE_DECIMALS());

        assertEq(navProvider.peggedBTC(), 0);
        assertEq(navProvider.yieldBTC(), 0);
        assertEq(navProvider.bridge(), address(lstBTCBridge));
        assertEq(lstBTCBridge.lstBTC(), address(lstBTC));
    }

    function test_RevertWhen_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        navProvider.initialize(adminAddress, govAddress);
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
        navProvider.setBridge(address(0x123));
    }

    function test_RevertWhen_PauseProvider_NotGovernor() public {
        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        navProvider.pauseProvider();
    }

    function test_RevertWhen_UnpauseProvider_NotGovernor() public {
        vm.prank(govAddress);
        navProvider.pauseProvider();

        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(notGovernor),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        navProvider.unpauseProvider();
    }

    function test_RevertWhen_IncreasePeggedBTC_NotBridge() public {
        vm.prank(notBridge);
        vm.expectRevert(abi.encodeWithSelector(
            AccessControlBase.Unauthorized.selector,
            notBridge
        ));
        navProvider.increasePeggedBTC(TEST_PEGGED_BTC_AMOUNT);
    }

    function test_RevertWhen_DecreasePeggedBTC_NotBridge() public {
        vm.prank(notBridge);
        vm.expectRevert(abi.encodeWithSelector(
            AccessControlBase.Unauthorized.selector,
            notBridge
        ));
        navProvider.decreasePeggedBTC(TEST_PEGGED_BTC_AMOUNT);
    }

    function test_RevertWhen_AccrueYield_NotBridge() public {
        vm.prank(notBridge);
        vm.expectRevert(abi.encodeWithSelector(
            AccessControlBase.Unauthorized.selector,
            notBridge
        ));
        navProvider.accrueYield(TEST_TX_ID, TEST_YIELD_AMOUNT, TEST_CUSTODIAN_ID);
    }

    // ============ Pause/Unpause Tests ============
    //  no test for pause/unpause

    // ============ setBridge() Tests ============

    function test_SetBridge_Success() public {
        address newBridge = address(0x123);
        address oldBridge = navProvider.bridge();

        vm.expectEmit(true, true, false, true);
        emit BridgeUpdated(oldBridge, newBridge);

        vm.prank(govAddress);
        navProvider.setBridge(newBridge);
        assertEq(navProvider.bridge(), newBridge);
    }

    function test_SetBridge_SameAddress() public {
        address currentBridge = navProvider.bridge();

        vm.recordLogs();
        vm.prank(govAddress);
        navProvider.setBridge(currentBridge);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    // ============ increasePeggedBTC() Tests ============

    function test_IncreasePeggedBTC_Success() public {
        uint64 initialPeggedBTC = 0;
        uint64 increasedAmount = TEST_PEGGED_BTC_AMOUNT;

        vm.expectEmit(true, true, false, true);
        emit PeggedBTCIncreased(increasedAmount, initialPeggedBTC + increasedAmount);

        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(increasedAmount);

        assertEq(navProvider.peggedBTC(), initialPeggedBTC + increasedAmount);
    }

    function test_IncreasePeggedBTC_MultipleTimes() public {
        uint64 amount1 = 100000;
        uint64 amount2 = 200000;
        uint64 amount3 = 300000;

        vm.startPrank(address(lstBTCBridge));

        navProvider.increasePeggedBTC(amount1);
        assertEq(navProvider.peggedBTC(), amount1);

        navProvider.increasePeggedBTC(amount2);
        assertEq(navProvider.peggedBTC(), amount1 + amount2);

        navProvider.increasePeggedBTC(amount3);
        assertEq(navProvider.peggedBTC(), amount1 + amount2 + amount3);
        vm.stopPrank();
    }

    function test_IncreasePeggedBTC_ZeroAmount() public {
        uint64 initialPeggedBTC = 0;
        uint64 increasedAmount = 0;

        vm.expectEmit(true, true, false, true);
        emit PeggedBTCIncreased(increasedAmount, initialPeggedBTC + increasedAmount);

        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(increasedAmount);

        assertEq(navProvider.peggedBTC(), 0);
    }

    // ============ decreasePeggedBTC() Tests ============

    function test_DecreasePeggedBTC_Success() public {
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(TEST_PEGGED_BTC_AMOUNT);

        uint64 initialPeggedBTC = navProvider.peggedBTC();
        uint64 decreasedAmount = 200000;

        vm.expectEmit(true, true, false, true);
        emit PeggedBTCDecreased(decreasedAmount, initialPeggedBTC - decreasedAmount);

        vm.prank(address(lstBTCBridge));
        navProvider.decreasePeggedBTC(decreasedAmount);

        assertEq(navProvider.peggedBTC(), initialPeggedBTC - decreasedAmount);
    }

    function test_RevertWhen_DecreasePeggedBTC_Overflow() public {
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(TEST_PEGGED_BTC_AMOUNT);
        uint64 decreasedAmount = TEST_PEGGED_BTC_AMOUNT + 1000;
        vm.prank(address(lstBTCBridge));
        vm.expectRevert(abi.encodeWithSelector(
            NavProviderLogic.PeggedBTCDecreasedAmountExceeds.selector,
            decreasedAmount,
            TEST_PEGGED_BTC_AMOUNT
        ));
        navProvider.decreasePeggedBTC(decreasedAmount);
    }

    function test_RevertWhen_DecreasePeggedBTC_EqualToCurrent() public {
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(TEST_PEGGED_BTC_AMOUNT);

        uint64 currentPeggedBTC = navProvider.peggedBTC();

        vm.prank(address(lstBTCBridge));
        navProvider.decreasePeggedBTC(currentPeggedBTC);
        assertEq(navProvider.peggedBTC(), 0);
    }

    function test_DecreasePeggedBTC_ZeroAmount() public {
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(TEST_PEGGED_BTC_AMOUNT);

        uint64 initialPeggedBTC = navProvider.peggedBTC();
        uint64 decreasedAmount = 0;

        vm.expectEmit(true, true, false, true);
        emit PeggedBTCDecreased(decreasedAmount, initialPeggedBTC);

        vm.prank(address(lstBTCBridge));
        navProvider.decreasePeggedBTC(decreasedAmount);

        assertEq(navProvider.peggedBTC(), initialPeggedBTC);
    }

    // ============ accrueYield() Tests ============

    function test_AccrueYield_Success() public {
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(TEST_PEGGED_BTC_AMOUNT);

        uint256 mintAmount = 1000000;
        vm.prank(address(lstBTCBridge));
        lstBTC.mint(address(lstBTCBridge), mintAmount);

        uint64 initialYieldBTC = navProvider.yieldBTC();
        uint64 initialPeggedBTC = navProvider.peggedBTC();
        uint64 yieldAmount = TEST_YIELD_AMOUNT;

        (,uint64 initialExchangeRate,) = navProvider.getLatestExchangeRate();

        vm.warp(TEST_TIMESTAMP);

        vm.expectEmit(true, true, false, true);
        emit YieldReceived(TEST_CUSTODIAN_ID, TEST_TX_ID, yieldAmount, initialYieldBTC + yieldAmount);

        uint64 expectedExchangeRate = uint64((initialPeggedBTC + yieldAmount) * DEFAULT_DECIMALS / mintAmount);
        vm.expectEmit(false, false, false, true);
        emit ExchangeRateUpdated(initialExchangeRate, expectedExchangeRate);

        vm.prank(address(lstBTCBridge));
        navProvider.accrueYield(TEST_TX_ID, yieldAmount, TEST_CUSTODIAN_ID);

        uint256 actualExchangeRate = (initialPeggedBTC + yieldAmount) * DEFAULT_DECIMALS / mintAmount;
        assertEq(actualExchangeRate, 105000000);
        (uint64 exchangeRate, uint8 decimals) = navProvider.getExchangeRate(TEST_TIMESTAMP + 1);
        assertEq(exchangeRate, actualExchangeRate);
        assertEq(decimals, navProvider.EXCHANGE_RATE_DECIMALS());
        assertEq(navProvider.yieldBTC(), initialYieldBTC + yieldAmount);
        assertEq(navProvider.peggedBTC(), initialPeggedBTC + yieldAmount);

    }

    function test_AccrueYield_MultipleTimes() public {
        lstBTC.setMaxMintLimit(250000000);
        uint256 sumMintAmount = 150000000;
        uint64 totalPeggedBTC = 150000000;
        vm.startPrank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(totalPeggedBTC);
        lstBTC.mint(address(lstBTCBridge), 10000000);
        lstBTC.mint(address(lstBTCBridge), 20000000);
        lstBTC.mint(address(lstBTCBridge), 30000000);
        lstBTC.mint(address(lstBTCBridge), 40000000);
        lstBTC.mint(address(lstBTCBridge), 50000000);

        uint64 yield1 = 10000;
        uint64 yield2 = 20000;
        uint64 yield3 = 30000;

        (,uint64 initialExchangeRate,) = navProvider.getLatestExchangeRate();

        vm.startPrank(address(lstBTCBridge));
        vm.warp(TEST_TIMESTAMP);

        uint64 expectedRate1 = uint64((totalPeggedBTC + yield1) * 1e8 / sumMintAmount);
        vm.expectEmit(false, false, false, true);
        emit ExchangeRateUpdated(initialExchangeRate, expectedRate1);
        navProvider.accrueYield(TEST_TX_ID, yield1, TEST_CUSTODIAN_ID);
        assertEq(navProvider.yieldBTC(), yield1);
        vm.warp(TEST_TIMESTAMP + 100);

        uint64 expectedRate2 = uint64((totalPeggedBTC + yield1 + yield2) * 1e8 / sumMintAmount);
        vm.expectEmit(false, false, false, true);
        emit ExchangeRateUpdated(expectedRate1, expectedRate2);
        navProvider.accrueYield(TEST_TX_ID, yield2, TEST_CUSTODIAN_ID);
        assertEq(navProvider.yieldBTC(), yield1 + yield2);

        vm.warp(TEST_TIMESTAMP + 200);

        uint64 expectedRate3 = uint64((totalPeggedBTC + navProvider.yieldBTC() + yield3) * 1e8 / sumMintAmount);
        vm.expectEmit(false, false, false, true);
        emit ExchangeRateUpdated(expectedRate2, expectedRate3);
        navProvider.accrueYield(TEST_TX_ID, yield3, TEST_CUSTODIAN_ID);
        assertEq(navProvider.yieldBTC(), yield1 + yield2 + yield3);
        (uint64 exchangeRate,) = navProvider.getExchangeRate(TEST_TIMESTAMP + 99);
        assertEq(exchangeRate, expectedRate1);

        (uint64 exchangeRate2,) = navProvider.getExchangeRate(TEST_TIMESTAMP + 150);
        assertEq(exchangeRate2, expectedRate2);

        (uint64 exchangeRate3,) = navProvider.getExchangeRate(TEST_TIMESTAMP + 299);
        assertEq(exchangeRate3, expectedRate3);

        (uint64 latestUpdateTime, uint64 latestExchangeRate, uint8 latestDecimals) = navProvider.getLatestExchangeRate();
        assertEq(latestUpdateTime, TEST_TIMESTAMP + 200);
        assertEq(latestExchangeRate, expectedRate3);
        assertEq(latestDecimals, navProvider.EXCHANGE_RATE_DECIMALS());
        vm.stopPrank();
    }

    function test_RevertWhen_RefreshExchangeRate_LstBTCZero() public {
        uint64 peggedBTC = 1000000;
        vm.startPrank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(peggedBTC);
        uint64 yieldAmount = 1000;
        vm.expectRevert(
            abi.encodeWithSelector(
                NavProviderLogic.PeggedBTCInvariantViolated.selector,
                0, // wrappedBTC
                peggedBTC + yieldAmount
            )
        );
        navProvider.accrueYield(TEST_TX_ID, yieldAmount, TEST_CUSTODIAN_ID);
        vm.stopPrank();
    }

    function test_RevertWhen_RefreshExchangeRate_PeggedBTCLessThanLstBTC() public {
        uint64 sumMintAmount = 1000 * DEFAULT_DECIMALS;
        uint64 totalPeggedBTC = sumMintAmount - 2;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(address(user1), sumMintAmount);
        navProvider.increasePeggedBTC(totalPeggedBTC);

        uint64 yieldAmount = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                NavProviderLogic.PeggedBTCInvariantViolated.selector,
                uint64(sumMintAmount), // wrappedBTC
                totalPeggedBTC + yieldAmount
            )
        );
        navProvider.accrueYield(TEST_TX_ID, yieldAmount, TEST_CUSTODIAN_ID);
        vm.stopPrank();
    }

    function test_AcquireYield_TooSmall_NoExchangeRateChange() public {
        lstBTC.setMaxMintLimit(1000000000 * DEFAULT_DECIMALS);
        uint64 sumMintAmount = 100000000 * DEFAULT_DECIMALS;
        uint64 totalPeggedBTC = sumMintAmount;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(address(lstBTCBridge), sumMintAmount);
        navProvider.increasePeggedBTC(totalPeggedBTC);
        (,uint64 oldExchangeRate,) = navProvider.getLatestExchangeRate();
        uint64 yieldAmount = 1;
        vm.recordLogs();
        navProvider.accrueYield(TEST_TX_ID, yieldAmount, TEST_CUSTODIAN_ID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 exchangeRateUpdatedTopic = keccak256("ExchangeRateUpdated(uint64,uint64)");
        bool foundExchangeRateUpdated = false;

        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == exchangeRateUpdatedTopic) {
                foundExchangeRateUpdated = true;
                break;
            }
        }
        assertFalse(foundExchangeRateUpdated, "ExchangeRateUpdated event should not be emitted");
        (,uint64 newExchangeRate,) = navProvider.getLatestExchangeRate();
        assertEq(newExchangeRate, oldExchangeRate);
        vm.stopPrank();
    }

    function test_AccrueYield_ZeroAmount_NoExchangeRateChange() public {
        uint256 mintAmount = 1000000;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(address(lstBTCBridge), mintAmount);
        uint64 peggedBTC = uint64(mintAmount);
        vm.startPrank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(peggedBTC);
        uint64 yieldAmount = 0;
        (,uint64 oldExchangeRate,) = navProvider.getLatestExchangeRate();
        navProvider.accrueYield(TEST_TX_ID, yieldAmount, TEST_CUSTODIAN_ID);
        (,uint64 newExchangeRate,) = navProvider.getLatestExchangeRate();

        assertEq(newExchangeRate, oldExchangeRate);
        vm.stopPrank();
    }

    function test_AccrueYield_SmallAmount_ExchangeRateIncrease() public {
        uint256 mintAmount = 100000000;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(address(lstBTCBridge), mintAmount);
        uint64 peggedBTC = uint64(mintAmount);
        vm.startPrank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(peggedBTC);

        uint64 yieldAmount = 1;
        (,uint64 oldExchangeRate, uint8 decimals) = navProvider.getLatestExchangeRate();
        navProvider.accrueYield(TEST_TX_ID, yieldAmount, TEST_CUSTODIAN_ID);
        (,uint64 newExchangeRate,) = navProvider.getLatestExchangeRate();

        uint256 expectedRate = ((peggedBTC + yieldAmount) * (10 ** decimals)) / mintAmount;
        uint64 expectedExchangeRate = uint64(expectedRate);

        assertEq(newExchangeRate, expectedExchangeRate);
        assertGt(newExchangeRate, oldExchangeRate);
    }

    function test_AccrueYield_Revert_SameTimestamp() public {
        uint256 mintAmount = 1000000;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(address(lstBTCBridge), mintAmount);
        uint64 peggedBTC = uint64(mintAmount);
        navProvider.increasePeggedBTC(peggedBTC);
        uint64 fixedTimestamp = 123456789;
        vm.warp(fixedTimestamp);
        uint64 yieldAmount = 1;
        navProvider.accrueYield(TEST_TX_ID, yieldAmount, TEST_CUSTODIAN_ID);
        vm.warp(fixedTimestamp);
        vm.expectRevert("TimeSeriesDataLib: timestamp must be strictly increasing");
        navProvider.accrueYield(TEST_TX_ID, yieldAmount, TEST_CUSTODIAN_ID);
        vm.stopPrank();
    }

    function test_RevertWhen_ExchangeRateDecreases() public {
        uint256 mintAmount = 1000000;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(address(lstBTCBridge), mintAmount);
        uint64 peggedBTC = uint64(mintAmount);
        navProvider.increasePeggedBTC(peggedBTC * 3);
        navProvider.accrueYield(TEST_TX_ID, 10000, TEST_CUSTODIAN_ID);
        uint256 extraMint = 1000000;
        lstBTC.mint(address(lstBTCBridge), extraMint);
        uint64 smallYield = 10000;
        uint64 newExchangeRate = uint64((peggedBTC * 3 + smallYield * 2) * DEFAULT_DECIMALS / (mintAmount + extraMint));
        (,uint64 oldExchangeRate,) = navProvider.getLatestExchangeRate();
        vm.expectRevert(
            abi.encodeWithSelector(
                NavProviderLogic.ExchangeRateMustIncrease.selector,
                oldExchangeRate,
                newExchangeRate
            )
        );
        navProvider.accrueYield(TEST_TX_ID, smallYield, TEST_CUSTODIAN_ID);
        vm.stopPrank();
    }
    // ============ View Functions Tests ============

    // ============ getExchangeRate() Tests ============
    function test_GetExchangeRate_Success() public {
        (uint64 exchangeRate1, uint8 decimals1) = navProvider.getExchangeRate(0);
        assertEq(exchangeRate1, 100000000);
        vm.startPrank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(1000000);
        uint256 mintAmount = 1000000;
        lstBTC.mint(address(lstBTCBridge), mintAmount);
        vm.warp(TEST_TIMESTAMP);
        navProvider.accrueYield(TEST_TX_ID, 10000, TEST_CUSTODIAN_ID);
        (uint64 exchangeRate, uint8 decimals) = navProvider.getExchangeRate(TEST_TIMESTAMP);
        assertEq(exchangeRate, 101000000);
        assertEq(decimals, navProvider.EXCHANGE_RATE_DECIMALS());
        (uint64 exchangeRate2, uint8 decimals2) = navProvider.getExchangeRate(TEST_TIMESTAMP - 1);
        assertEq(exchangeRate2, 100000000);
    }

    function test_GetExchangeRate_MultipleTimestamps() public {
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(1000000);

        uint256 mintAmount = 1000000;
        vm.prank(address(lstBTCBridge));
        lstBTC.mint(address(lstBTCBridge), mintAmount);

        vm.startPrank(address(lstBTCBridge));

        vm.warp(1000);
        navProvider.accrueYield(TEST_TX_ID, 10000, TEST_CUSTODIAN_ID);

        vm.warp(2000);
        navProvider.accrueYield(TEST_TX_ID, 20000, TEST_CUSTODIAN_ID);

        vm.warp(3000);
        navProvider.accrueYield(TEST_TX_ID, 30000, TEST_CUSTODIAN_ID);

        vm.stopPrank();

        (uint64 rate1, uint8 decimals1) = navProvider.getExchangeRate(999);
        assertEq(rate1, navProvider.INITIAL_EXCHANGE_RATE());
        assertEq(decimals1, navProvider.EXCHANGE_RATE_DECIMALS());

        (uint64 rate2, uint8 decimals2) = navProvider.getExchangeRate(1001);
        assertGt(rate2, rate1);
        assertEq(decimals2, navProvider.EXCHANGE_RATE_DECIMALS());

        (uint64 rate3, uint8 decimals3) = navProvider.getExchangeRate(2500);
        assertGt(rate3, rate2);
        assertEq(decimals3, navProvider.EXCHANGE_RATE_DECIMALS());

        (uint64 rate4, uint8 decimals4) = navProvider.getExchangeRate(3500);
        assertGt(rate4, rate3);
        assertEq(decimals4, navProvider.EXCHANGE_RATE_DECIMALS());
    }

    // ============ getLatestExchangeRate() Tests ============

    function test_GetLatestExchangeRate_Success() public {
        (uint64 updateTime, uint64 exchangeRate, uint8 decimals) = navProvider.getLatestExchangeRate();
        assertEq(updateTime, 0);
        assertEq(exchangeRate, navProvider.INITIAL_EXCHANGE_RATE());
        uint256 mintAmount = 1000000;
        vm.startPrank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(1000000);
        lstBTC.mint(address(lstBTCBridge), mintAmount);
        vm.warp(TEST_TIMESTAMP);
        navProvider.accrueYield(TEST_TX_ID, 10000, TEST_CUSTODIAN_ID);
        (uint64 updateTime2, uint64 exchangeRate2, uint8 decimals2) = navProvider.getLatestExchangeRate();
        assertEq(updateTime2, TEST_TIMESTAMP);
        assertEq(exchangeRate2, 101000000);
        vm.warp(TEST_TIMESTAMP + 1);
        navProvider.accrueYield(TEST_TX_ID, 10000, TEST_CUSTODIAN_ID);
        (uint64 updateTime3, uint64 exchangeRate3, uint8 decimals3) = navProvider.getLatestExchangeRate();
        assertEq(updateTime3, TEST_TIMESTAMP + 1);
        assertEq(exchangeRate3, 102000000);
        vm.stopPrank();

    }

    // ============ Constants Tests ============

    function test_Constants_Values() public {
        assertEq(navProvider.EXCHANGE_RATE_DECIMALS(), 8);
        assertEq(navProvider.INITIAL_EXCHANGE_RATE(), 1e8);
    }

    // ============ Events Declaration for Tests ============

    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);
    event PeggedBTCIncreased(uint64 addedAmount, uint64 totalAmount);
    event PeggedBTCDecreased(uint64 subtractedAmount, uint64 remainingAmount);
    event YieldReceived(
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        uint64 yieldAmount,
        uint64 totalYield
    );
    event ExchangeRateUpdated(uint64 oldExchangeRate, uint64 newExchangeRate);
} 