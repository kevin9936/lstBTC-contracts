// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deployer} from "./utils/Deployer.sol";
import {WhitelistRegistryLogic} from "contracts/whitelist/WhitelistRegistryLogic.sol";
import {WhitelistRegistryProxy} from "contracts/whitelist/WhitelistRegistryProxy.sol";
import {AccessControlBase} from "contracts/access/AccessControlBase.sol";
import {AddressUsage} from "contracts/types/DataTypes.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract WhitelistRegistryLogicTest is Deployer {
    address public user1;
    address public user2;
    address public user3;
    address public notGovernor;
    address public notGroupMemberOperator;
    address public groupMemberOperator;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ROLE_GROUP_MEMBER_OPERATOR = keccak256("ROLE_GROUP_MEMBER_OPERATOR");

    // BTC address formats
    uint8 public constant ADDRESS_FORMAT_NATIVE = 1;
    uint8 public constant ADDRESS_FORMAT_BTC = 2;
    // Invalid address
    bytes public constant INVALID_NATIVE_ADDRESS = hex"DcE49E20aEA8be32C182E4f3429258001A10176711";
    bytes public constant INVALID_BTC_ADDRESS = hex"41048826ddeeda9e736e038613f290ef6fbab287a184c211380f4ef4d35a51cf24c0d6bb33cdec8f60a3ba4d2863e0644e0fc4a7179fce4b01e69ce0189c991dddf2ac";


    function setUp() public {
        user1 = address(2000);
        user2 = address(2001);
        user3 = address(2002);
        notGovernor = address(3000);
        notGroupMemberOperator = address(3001);
        groupMemberOperator = address(4000);
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(notGovernor, "NotGovernor");
        vm.label(notGroupMemberOperator, "NotGroupMemberOperator");
        vm.label(groupMemberOperator, "GroupMemberOperator");
        vm.prank(govAddress);
        whitelistRegistry.grantRole(ROLE_GROUP_MEMBER_OPERATOR, groupMemberOperator);
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public {
        assertTrue(whitelistRegistry.hasRole(DEFAULT_ADMIN_ROLE, adminAddress));
        assertTrue(whitelistRegistry.hasRole(ROLE_GOVERNOR, govAddress));
        assertTrue(whitelistRegistry.hasRole(ROLE_GROUP_MEMBER_OPERATOR, groupMemberOperator));
        assertEq(whitelistRegistry.getRoleAdmin(ROLE_GROUP_MEMBER_OPERATOR), ROLE_GOVERNOR);

        assertTrue(whitelistRegistry.isWhitelistedReservedGroup(whitelistRegistry.RESERVED_GROUP_ID()));

        assertEq(whitelistRegistry.nextGroupId(), whitelistRegistry.RESERVED_GROUP_ID() + 1);

    }

    function test_RevertWhen_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        whitelistRegistry.initialize(adminAddress, govAddress);
    }

    // ============ Access Control Tests ============


    function test_RevertWhen_CreateGroup_NotGovernor() public {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(notGovernor),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
            )
        );
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }

    function test_RevertWhen_RemoveGroup_NotGovernor() public {
        uint32 groupId = _createTestGroup();

        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(notGovernor),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
            )
        );
        whitelistRegistry.removeGroup(groupId);
    }


    function test_RevertWhen_AddEntriesToGroup_NotGroupMemberOperator() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(govAddress);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(govAddress),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(ROLE_GROUP_MEMBER_OPERATOR), 32)
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);
    }


    function test_RevertWhen_RemoveEntriesFromGroup_NotGroupMemberOperator() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(notGroupMemberOperator);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(notGroupMemberOperator),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(ROLE_GROUP_MEMBER_OPERATOR), 32)
            )
        );
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);
    }


    function test_RevertWhen_UpdateEntriesInGroup_NotGovernor() public {
        uint32 groupId = _createTestGroup();

        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        bytes[] memory oldRawAddresses = new bytes[](1);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;
        oldRawAddresses[0] = LST_ADDRESS1;
        newRawAddresses[0] = LST_ADDRESS2;

        vm.prank(notGovernor);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(notGovernor),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
            )
        );
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);
    }

    // ============ createGroup() Tests ============


    function test_CreateGroup_Success() public {
        bytes[] memory rawAddresses = new bytes[](6);
        uint8[] memory formats = new uint8[](6);
        uint8[] memory usages = new uint8[](6);

        rawAddresses[0] = P2PKH_ADDRESS;
        rawAddresses[1] = P2WPKH_ADDRESS;
        rawAddresses[2] = P2PK_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        formats[1] = ADDRESS_FORMAT_BTC;
        formats[2] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.OPERATIONS;
        usages[2] = AddressUsage.INBOUND;
        rawAddresses[3] = LST_ADDRESS1;
        rawAddresses[4] = LST_ADDRESS2;
        rawAddresses[5] = LST_ADDRESS3;
        formats[3] = ADDRESS_FORMAT_NATIVE;
        formats[4] = ADDRESS_FORMAT_NATIVE;
        formats[5] = ADDRESS_FORMAT_NATIVE;
        usages[3] = AddressUsage.OUTBOUND;
        usages[4] = AddressUsage.OPERATIONS;
        usages[5] = AddressUsage.INBOUND;


        uint32 expectedGroupId = whitelistRegistry.nextGroupId();

        vm.expectEmit(true, false, false, true);
        emit WhitelistGroupCreated(expectedGroupId, rawAddresses, formats, usages);

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(expectedGroupId));
        assertEq(whitelistRegistry.nextGroupId(), expectedGroupId + 1);
        assertEq(expectedGroupId, 10001);

        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));
        assertTrue(whitelistRegistry.isWhitelisted(P2WPKH_ADDRESS));
        assertTrue(whitelistRegistry.isWhitelisted(P2PK_ADDRESS));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS3));

        (bool exists, bytes32[] memory entryKeys) = whitelistRegistry.getWhitelistGroup(expectedGroupId);
        assertTrue(exists);
        assertEq(entryKeys.length, 6);
        assertEq(entryKeys[0], keccak256(abi.encodePacked(P2PKH_ADDRESS)));
        assertEq(entryKeys[1], keccak256(abi.encodePacked(P2WPKH_ADDRESS)));
        assertEq(entryKeys[2], keccak256(abi.encodePacked(P2PK_ADDRESS)));
        assertEq(entryKeys[3], keccak256(abi.encodePacked(LST_ADDRESS1)));
        assertEq(entryKeys[4], keccak256(abi.encodePacked(LST_ADDRESS2)));
        assertEq(entryKeys[5], keccak256(abi.encodePacked(LST_ADDRESS3)));
        (uint32 groupId1, uint8 usage1) = whitelistRegistry.getWhitelistEntry(P2PKH_ADDRESS);
        assertEq(groupId1, expectedGroupId);
        assertEq(usage1, AddressUsage.OUTBOUND);
        (uint32 groupId2, uint8 usage2) = whitelistRegistry.getWhitelistEntry(P2WPKH_ADDRESS);
        assertEq(groupId2, expectedGroupId);
        assertEq(usage2, AddressUsage.OPERATIONS);
        (uint32 groupId3, uint8 usage3) = whitelistRegistry.getWhitelistEntry(P2PK_ADDRESS);
        assertEq(groupId3, expectedGroupId);
        assertEq(usage3, AddressUsage.INBOUND);
        (uint32 groupId4, uint8 usage4) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS1);
        assertEq(groupId4, expectedGroupId);
        assertEq(usage4, AddressUsage.OUTBOUND);
        (uint32 groupId5, uint8 usage5) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);
        assertEq(groupId5, expectedGroupId);
        assertEq(usage5, AddressUsage.OPERATIONS);
        (uint32 groupId6, uint8 usage6) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS3);
        assertEq(groupId6, 10001);
        assertEq(usage6, AddressUsage.INBOUND);
    }


    function test_CreateGroup_PartialAddresses() public {
        uint32 expectedGroupId = whitelistRegistry.nextGroupId();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS1;
        rawAddresses[1] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.INBOUND;

        vm.expectEmit(true, false, false, true);
        emit WhitelistGroupCreated(expectedGroupId, rawAddresses, formats, usages);

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(expectedGroupId));
        assertEq(whitelistRegistry.nextGroupId(), expectedGroupId + 1);

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));

        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS3));
        assertFalse(whitelistRegistry.isWhitelisted(P2WPKH_ADDRESS));

        (bool exists, bytes32[] memory entryKeys) = whitelistRegistry.getWhitelistGroup(expectedGroupId);
        assertTrue(exists);
        assertEq(entryKeys.length, 2);
        assertEq(entryKeys[0], keccak256(abi.encodePacked(LST_ADDRESS1)));
        assertEq(entryKeys[1], keccak256(abi.encodePacked(P2PKH_ADDRESS)));

        (uint32 groupId1, uint8 usage1) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS1);
        assertEq(groupId1, expectedGroupId);
        assertEq(usage1, AddressUsage.OUTBOUND);

        (uint32 groupId2, uint8 usage2) = whitelistRegistry.getWhitelistEntry(P2PKH_ADDRESS);
        assertEq(groupId2, expectedGroupId);
        assertEq(usage2, AddressUsage.INBOUND);
    }

    function test_CreateMultipleGroups_Success() public {
        uint32 groupId1 = whitelistRegistry.nextGroupId();
        bytes[] memory rawAddresses1 = new bytes[](2);
        uint8[] memory formats1 = new uint8[](2);
        uint8[] memory usages1 = new uint8[](2);

        rawAddresses1[0] = LST_ADDRESS1;
        rawAddresses1[1] = P2SH_ADDRESS;
        formats1[0] = ADDRESS_FORMAT_NATIVE;
        formats1[1] = ADDRESS_FORMAT_BTC;
        usages1[0] = AddressUsage.OUTBOUND;
        usages1[1] = AddressUsage.INBOUND;

        vm.expectEmit(true, false, false, true);
        emit WhitelistGroupCreated(groupId1, rawAddresses1, formats1, usages1);

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses1, formats1, usages1);

        uint32 groupId2 = whitelistRegistry.nextGroupId();
        bytes[] memory rawAddresses2 = new bytes[](1);
        uint8[] memory formats2 = new uint8[](1);
        uint8[] memory usages2 = new uint8[](1);
        assertEq(groupId2, 10002);
        rawAddresses2[0] = P2WPKH_ADDRESS;
        formats2[0] = ADDRESS_FORMAT_BTC;
        usages2[0] = AddressUsage.OPERATIONS;

        vm.expectEmit(true, false, false, true);
        emit WhitelistGroupCreated(groupId2, rawAddresses2, formats2, usages2);

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses2, formats2, usages2);

        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(groupId1));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(P2SH_ADDRESS));
        assertFalse(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));

        (uint32 g1_1, uint8 u1_1) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS1);
        (uint32 g1_2, uint8 u1_2) = whitelistRegistry.getWhitelistEntry(P2SH_ADDRESS);
        assertEq(g1_1, groupId1);
        assertEq(u1_1, AddressUsage.OUTBOUND);
        assertEq(g1_2, groupId1);
        assertEq(u1_2, AddressUsage.INBOUND);

        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(groupId2));
        assertTrue(whitelistRegistry.isWhitelisted(P2WPKH_ADDRESS));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));

        (uint32 g2_1, uint8 u2_1) = whitelistRegistry.getWhitelistEntry(P2WPKH_ADDRESS);
        assertEq(g2_1, groupId2);
        assertEq(u2_1, AddressUsage.OPERATIONS);

        assertEq(whitelistRegistry.nextGroupId(), groupId2 + 1);
    }

    function test_CreateGroup_DifferentAddress_SameUsage() public {
        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        rawAddresses[1] = LST_ADDRESS2;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        usages[1] = AddressUsage.OUTBOUND;

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        (uint32 g1, uint8 u1) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS1);
        (uint32 g2, uint8 u2) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);

        assertEq(g1, 10001);
        assertEq(u1, AddressUsage.OUTBOUND);
        assertEq(g2, 10001);
        assertEq(u2, AddressUsage.OUTBOUND);
    }


    function test_RevertWhen_CreateGroup_ArrayLengthMismatch() public {
        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS1;
        rawAddresses[1] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.INBOUND;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.EntryArrayLengthMismatch.selector
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }


    function test_RevertWhen_CreateGroup_EmptyArrays() public {
        bytes[] memory rawAddresses = new bytes[](0);
        uint8[] memory formats = new uint8[](0);
        uint8[] memory usages = new uint8[](0);

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.EntryArrayLengthMismatch.selector
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }

    function test_RevertWhen_CreateGroup_InvalidCustomUsage() public {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.YIELD;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.InvalidCustomGroupAddressUsage.selector,
            AddressUsage.YIELD
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
        usages[0] = AddressUsage.BORROW;
        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.InvalidCustomGroupAddressUsage.selector,
            AddressUsage.BORROW
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
        usages[0] = AddressUsage.REPAYMENT;
        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.InvalidCustomGroupAddressUsage.selector,
            AddressUsage.REPAYMENT
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

    }


    function test_RevertWhen_CreateGroup_InvalidNativeAddressFormat() public {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = INVALID_NATIVE_ADDRESS;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.InvalidNativeAddress.selector,
            INVALID_NATIVE_ADDRESS
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        rawAddresses[0] = INVALID_BTC_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.InvalidBTCPkScript.selector,
            INVALID_BTC_ADDRESS
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }


    function test_RevertWhen_CreateGroup_AddressConflict() public {
        uint32 firstGroupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.AddressAlreadyUsed.selector,
            LST_ADDRESS1,
            firstGroupId,
            AddressUsage.OUTBOUND
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }


    function test_RevertWhen_CreateGroup_AddressUsedInRemovedGroup() public {
        uint32 groupId = _createTestGroup();

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId);

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.AddressAlreadyUsed.selector,
            LST_ADDRESS1,
            groupId,
            AddressUsage.OUTBOUND
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }

    function test_RevertWhen_CreateGroup_AddressUsedInRemovedEntry() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory removeAddresses = new bytes[](1);
        uint8[] memory removeFormats = new uint8[](1);
        uint8[] memory removeUsages = new uint8[](1);

        removeAddresses[0] = LST_ADDRESS1;
        removeFormats[0] = ADDRESS_FORMAT_NATIVE;
        removeUsages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId, removeAddresses, removeFormats, removeUsages);

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OPERATIONS;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.AddressAlreadyUsed.selector,
            LST_ADDRESS1,
            groupId,
            AddressUsage.OUTBOUND
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }


    function test_RevertWhen_CreateGroup_UnsupportedAddressFormat() public {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = 99;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.InvalidAddressFormat.selector,
            uint8(99)
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }


    function test_RevertWhen_CreateGroup_UnsupportedUsage() public {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = 99;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.InvalidCustomGroupAddressUsage.selector,
            uint8(99)
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }

    function test_CreateGroup_DuplicateAddress_DifferentUsage() public {
        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OPERATIONS;

        rawAddresses[1] = LST_ADDRESS1;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        usages[1] = AddressUsage.INBOUND;
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.AddressAlreadyUsed.selector,
            LST_ADDRESS1,
            10001,
            AddressUsage.OPERATIONS
        ));

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }

    function test_CreateGroup_DuplicateAddress_SameUsage() public {
        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = P2SH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;

        rawAddresses[1] = P2SH_ADDRESS;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[1] = AddressUsage.OUTBOUND;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.AddressAlreadyUsed.selector,
            P2SH_ADDRESS,
            10001,
            AddressUsage.OUTBOUND
        ));
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
    }

    // ============ removeGroup() Tests ============


    function test_RemoveGroup_Success() public {
        uint32 groupId = _createTestGroup();

        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(groupId));
        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));

        vm.expectEmit(true, false, false, false);
        emit WhitelistGroupRemoved(groupId);

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId);

        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(groupId));

        assertFalse(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));
        (uint32 entryGroupId, uint8 entryUsage) = whitelistRegistry.getWhitelistEntry(P2PKH_ADDRESS);
        assertEq(entryGroupId, 0);
        assertEq(entryUsage, 0);
    }


    function test_RemoveGroup_MultipleGroups() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS3;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OPERATIONS;

        uint32 groupId3 = whitelistRegistry.nextGroupId();
        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(groupId1));
        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(groupId2));
        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(groupId3));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS3));

        vm.startPrank(govAddress);
        whitelistRegistry.removeGroup(groupId1);
        whitelistRegistry.removeGroup(groupId2);
        whitelistRegistry.removeGroup(groupId3);
        vm.stopPrank();

        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(groupId1));
        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(groupId2));
        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(groupId3));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS3));

        (bool exists1,) = whitelistRegistry.getWhitelistGroup(groupId1);
        (bool exists2,) = whitelistRegistry.getWhitelistGroup(groupId2);
        (bool exists3,) = whitelistRegistry.getWhitelistGroup(groupId3);
        assertFalse(exists1);
        assertFalse(exists2);
        assertFalse(exists3);
    }


    function test_RevertWhen_RemoveGroup_ReservedGroup() public {
        uint32 groupId = whitelistRegistry.RESERVED_GROUP_ID();
        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.NotCustomGroup.selector,
            groupId
        ));
        whitelistRegistry.removeGroup(groupId);
    }


    function test_RevertWhen_RemoveGroup_NonExistentGroup() public {
        uint32 nonExistentGroupId = 99999;

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.NotCustomGroup.selector,
            nonExistentGroupId
        ));
        whitelistRegistry.removeGroup(nonExistentGroupId);
    }


    function test_RevertWhen_RemoveGroup_AlreadyRemoved() public {
        uint32 groupId = _createTestGroup();

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId);

        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(groupId));

        vm.prank(govAddress);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.NotCustomGroup.selector,
            groupId
        ));
        whitelistRegistry.removeGroup(groupId);
    }


    function test_RemoveGroup_DifferentAddressesSameUsage() public {
        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS1;
        rawAddresses[1] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;
        usages[1] = AddressUsage.INBOUND;
        uint32 groupId = whitelistRegistry.nextGroupId();
        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId);

        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(groupId));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
    }


    function test_RevertWhen_RemoveGroup_ContainsRemovedEntry() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);

        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS1));

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId);
        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(groupId));
    }


    function test_RemoveGroup_WithRecentlyAddedAddress() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS2;
        rawAddresses[1] = LST_ADDRESS3;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;
        usages[1] = AddressUsage.OPERATIONS;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS3));

        (bool exists, bytes32[] memory entryKeys) = whitelistRegistry.getWhitelistGroup(groupId);
        assertTrue(exists);
        assertEq(entryKeys.length, 5);

        vm.expectEmit(true, false, false, false);
        emit WhitelistGroupRemoved(groupId);

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId);

        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(groupId));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS3));

        (uint32 groupId1, uint8 usage1) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS1);
        (uint32 groupId2, uint8 usage2) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);
        (uint32 groupId3, uint8 usage3) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS3);

        assertEq(groupId1, 0);
        assertEq(groupId2, 0);
        assertEq(groupId3, 0);
        assertEq(usage1, 0);
        assertEq(usage2, 0);
        assertEq(usage3, 0);
    }

    // ============ addEntriesToGroup() Tests ============


    function test_AddEntriesToGroup_Success() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS2;
        rawAddresses[1] = P2WPKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.INBOUND;
        usages[1] = AddressUsage.OPERATIONS;

        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryAdded(groupId, rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertTrue(whitelistRegistry.isWhitelisted(P2WPKH_ADDRESS));

        (uint32 groupId1, uint8 usage1) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);
        (uint32 groupId2, uint8 usage2) = whitelistRegistry.getWhitelistEntry(P2WPKH_ADDRESS);

        assertEq(groupId1, groupId);
        assertEq(usage1, AddressUsage.INBOUND);
        assertEq(groupId2, groupId);
        assertEq(usage2, AddressUsage.OPERATIONS);
    }


    function test_AddEntriesToGroup_MultipleTimesSuccess() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses1 = new bytes[](1);
        uint8[] memory formats1 = new uint8[](1);
        uint8[] memory usages1 = new uint8[](1);

        rawAddresses1[0] = LST_ADDRESS2;
        formats1[0] = ADDRESS_FORMAT_NATIVE;
        usages1[0] = AddressUsage.INBOUND;
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertFalse(whitelistRegistry.isWhitelisted(P2WPKH_ADDRESS));
        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses1, formats1, usages1);

        bytes[] memory rawAddresses2 = new bytes[](1);
        uint8[] memory formats2 = new uint8[](1);
        uint8[] memory usages2 = new uint8[](1);

        rawAddresses2[0] = P2WPKH_ADDRESS;
        formats2[0] = ADDRESS_FORMAT_BTC;
        usages2[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses2, formats2, usages2);

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertTrue(whitelistRegistry.isWhitelisted(P2WPKH_ADDRESS));
        (uint32 groupId1, uint8 usage1) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);
        (uint32 groupId2, uint8 usage2) = whitelistRegistry.getWhitelistEntry(P2WPKH_ADDRESS);
        assertEq(groupId1, groupId);
        assertEq(usage1, AddressUsage.INBOUND);
        assertEq(groupId2, groupId);
        assertEq(usage2, AddressUsage.OUTBOUND);
        (bytes[] memory rawAddresses, uint8[] memory formats, uint8[] memory usages) = whitelistRegistry.getGroupEntries(groupId);
        assertEq(rawAddresses.length, 5);
        assertEq(formats.length, 5);
        assertEq(usages.length, 5);
        assertEq(rawAddresses[3], LST_ADDRESS2);
        assertEq(formats[3], ADDRESS_FORMAT_NATIVE);
        assertEq(usages[3], AddressUsage.INBOUND);
        assertEq(rawAddresses[4], P2WPKH_ADDRESS);
        assertEq(formats[4], ADDRESS_FORMAT_BTC);
        assertEq(usages[4], AddressUsage.OUTBOUND);
    }

    function test_RevertWhen_AddEntriesToGroup_AddRemovedAddressFromSameGroup() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory removeAddresses = new bytes[](1);
        uint8[] memory removeFormats = new uint8[](1);
        uint8[] memory removeUsages = new uint8[](1);

        removeAddresses[0] = LST_ADDRESS1;
        removeFormats[0] = ADDRESS_FORMAT_NATIVE;
        removeUsages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId, removeAddresses, removeFormats, removeUsages);

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                LST_ADDRESS1,
                groupId,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId, removeAddresses, removeFormats, removeUsages);
    }

    function test_RevertWhen_AddEntriesToGroup_ExistingAddressDifferentUsage() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                LST_ADDRESS1,
                groupId,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_AddressExistsInOtherGroup() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                LST_ADDRESS2,
                groupId2,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId1, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_AddRemovedAddressFromOtherGroup() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        bytes[] memory removeAddresses = new bytes[](1);
        uint8[] memory removeFormats = new uint8[](1);
        uint8[] memory removeUsages = new uint8[](1);

        removeAddresses[0] = LST_ADDRESS2;
        removeFormats[0] = ADDRESS_FORMAT_NATIVE;
        removeUsages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId2, removeAddresses, removeFormats, removeUsages);
        removeUsages[0] = AddressUsage.INBOUND;
        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                LST_ADDRESS2,
                groupId2,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId2, removeAddresses, removeFormats, removeUsages);
    }

    function test_RevertWhen_AddEntriesToGroup_ReservedGroupAddressToCustomGroup() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory reservedAddresses = new bytes[](1);
        uint8[] memory reservedFormats = new uint8[](1);
        uint8[] memory reservedUsages = new uint8[](1);

        reservedAddresses[0] = P2TR_ADDRESS;
        reservedFormats[0] = ADDRESS_FORMAT_BTC;
        reservedUsages[0] = AddressUsage.YIELD;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, reservedAddresses, reservedFormats, reservedUsages);
        uint32 customGroupId = _createTestGroup();

        bytes[] memory customAddresses = new bytes[](1);
        uint8[] memory customFormats = new uint8[](1);
        uint8[] memory customUsages = new uint8[](1);

        customAddresses[0] = P2TR_ADDRESS;
        customFormats[0] = ADDRESS_FORMAT_BTC;
        customUsages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                P2TR_ADDRESS,
                reservedGroupId,
                AddressUsage.YIELD
            )
        );
        whitelistRegistry.addEntriesToGroup(customGroupId, customAddresses, customFormats, customUsages);
    }

    function test_RevertWhen_AddEntriesToGroup_AddressFromRemovedGroup() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId2);

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                LST_ADDRESS2,
                groupId2,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId1, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_InvalidReservedGroupUsage() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS3;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.InvalidReservedGroupAddressUsage.selector,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_InvalidCustomGroupUsage() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS3;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.YIELD;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.InvalidCustomGroupAddressUsage.selector,
                AddressUsage.YIELD
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_GroupNotExists() public {
        uint32 nonExistentGroupId = 99999;

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS3;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.GroupNotFound.selector,
                nonExistentGroupId
            )
        );
        whitelistRegistry.addEntriesToGroup(nonExistentGroupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_InvalidReservedGroupAddressFormat() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS3;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.YIELD;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.InvalidReservedGroupAddressFormat.selector,
                ADDRESS_FORMAT_NATIVE
            )
        );
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_InvalidNativeAddress() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = INVALID_NATIVE_ADDRESS;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.InvalidNativeAddress.selector,
                INVALID_NATIVE_ADDRESS
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_InvalidBTCAddress() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = INVALID_BTC_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.InvalidBTCPkScript.selector,
                INVALID_BTC_ADDRESS
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_InvalidAddressFormat() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS3;
        formats[0] = 99;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.InvalidAddressFormat.selector,
                99
            )
        );
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_ArrayLengthMismatch() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS2;
        rawAddresses[1] = LST_ADDRESS3;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.INBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(WhitelistRegistryLogic.EntryArrayLengthMismatch.selector);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_EmptyArrays() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](0);
        uint8[] memory formats = new uint8[](0);
        uint8[] memory usages = new uint8[](0);

        vm.prank(groupMemberOperator);
        vm.expectRevert(WhitelistRegistryLogic.EntryArrayLengthMismatch.selector);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);
    }

    function test_AddEntriesToGroup_ReservedGroupSuccess() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = P2TR_ADDRESS;
        rawAddresses[1] = P2WSH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.YIELD;
        usages[1] = AddressUsage.BORROW;
        assertFalse(whitelistRegistry.isWhitelisted(P2TR_ADDRESS));
        assertFalse(whitelistRegistry.isWhitelisted(P2WSH_ADDRESS));
        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(P2TR_ADDRESS));
        assertTrue(whitelistRegistry.isWhitelisted(P2WSH_ADDRESS));

        (uint32 groupId1, uint8 usage1) = whitelistRegistry.getWhitelistEntry(P2TR_ADDRESS);
        (uint32 groupId2, uint8 usage2) = whitelistRegistry.getWhitelistEntry(P2WSH_ADDRESS);

        assertEq(groupId1, reservedGroupId);
        assertEq(usage1, AddressUsage.YIELD);
        assertEq(groupId2, reservedGroupId);
        assertEq(usage2, AddressUsage.BORROW);
    }

    function test_AddEntriesToGroup_ReservedGroupSameAddressDifferentUsage() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses1 = new bytes[](1);
        uint8[] memory formats1 = new uint8[](1);
        uint8[] memory usages1 = new uint8[](1);

        rawAddresses1[0] = P2TR_ADDRESS;
        formats1[0] = ADDRESS_FORMAT_BTC;
        usages1[0] = AddressUsage.BORROW;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses1, formats1, usages1);

        bytes[] memory rawAddresses2 = new bytes[](1);
        uint8[] memory formats2 = new uint8[](1);
        uint8[] memory usages2 = new uint8[](1);

        rawAddresses2[0] = P2TR_ADDRESS;
        formats2[0] = ADDRESS_FORMAT_BTC;
        usages2[0] = AddressUsage.REPAYMENT;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses2, formats2, usages2);

        (uint32 groupId, uint8 usage) = whitelistRegistry.getWhitelistEntry(P2TR_ADDRESS);
        assertEq(groupId, reservedGroupId);
        assertEq(usage, AddressUsage.BORROW | AddressUsage.REPAYMENT);
    }

    function test_RevertWhen_AddEntriesToGroup_ReservedGroupRemovedAddress() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = P2PK_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.YIELD;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(reservedGroupId, rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                P2PK_ADDRESS,
                reservedGroupId,
                AddressUsage.YIELD
            )
        );
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                P2PK_ADDRESS,
                reservedGroupId,
                AddressUsage.YIELD
            )
        );
        usages[0] = AddressUsage.BORROW;
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);


    }

    function test_RevertWhen_AddEntriesToGroup_CustomGroupAddressToReservedGroup() public {
        uint32 customGroupId = _createTestGroup();
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.YIELD;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                P2PKH_ADDRESS,
                customGroupId,
                AddressUsage.INBOUND
            )
        );
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);
    }


    function test_RevertWhen_AddEntriesToGroup_RemovedCustomGroupAddressToReservedGroup() public {
        uint32 customGroupId = _createTestGroup();
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory removeAddresses = new bytes[](1);
        uint8[] memory removeFormats = new uint8[](1);
        uint8[] memory removeUsages = new uint8[](1);

        removeAddresses[0] = P2SH_ADDRESS;
        removeFormats[0] = ADDRESS_FORMAT_BTC;
        removeUsages[0] = AddressUsage.OPERATIONS;

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(customGroupId, removeAddresses, removeFormats, removeUsages);

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = P2SH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.YIELD;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                P2SH_ADDRESS,
                customGroupId,
                AddressUsage.OPERATIONS
            )
        );
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_AddEntriesToGroup_RemovedGroupAddressToReservedGroup() public {
        uint32 customGroupId = _createTestGroup();
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(customGroupId);

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = P2SH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.YIELD;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                P2SH_ADDRESS,
                customGroupId,
                AddressUsage.OPERATIONS
            )
        );
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);
    }

    function test_AddEntriesToEmptyGroup_AllAddresses() public {
        uint32 groupId = _createTestGroupWithDifferentAddress();

        bytes[] memory rawAddresses = new bytes[](5);
        uint8[] memory formats = new uint8[](5);
        uint8[] memory usages = new uint8[](5);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        rawAddresses[1] = LST_ADDRESS3;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        usages[1] = AddressUsage.OPERATIONS;

        rawAddresses[2] = P2SH_ADDRESS;
        formats[2] = ADDRESS_FORMAT_BTC;
        usages[2] = AddressUsage.OPERATIONS;

        rawAddresses[3] = P2TR_ADDRESS;
        formats[3] = ADDRESS_FORMAT_BTC;
        usages[3] = AddressUsage.INBOUND;

        rawAddresses[4] = P2WSH_ADDRESS;
        formats[4] = ADDRESS_FORMAT_BTC;
        usages[4] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryAdded(groupId, rawAddresses, formats, usages);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS3));
        assertTrue(whitelistRegistry.isWhitelisted(P2SH_ADDRESS));
        assertTrue(whitelistRegistry.isWhitelisted(P2TR_ADDRESS));
        assertTrue(whitelistRegistry.isWhitelisted(P2WSH_ADDRESS));
        (bytes[] memory rawAddresses1, uint8[] memory formats1, uint8[] memory usages1) = whitelistRegistry.getGroupEntries(groupId);
        assertEq(rawAddresses1.length, 6);
        assertEq(formats1.length, 6);
        assertEq(usages1.length, 6);
    }

    function test_AddEntriesToReservedGroup_SameAddressDifferentType() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.BORROW;

        rawAddresses[1] = P2PKH_ADDRESS;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[1] = AddressUsage.REPAYMENT;

        vm.prank(groupMemberOperator);
        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryAdded(reservedGroupId, rawAddresses, formats, usages);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        (uint32 entryGroupId, uint8 entryUsage) = whitelistRegistry.getWhitelistEntry(P2PKH_ADDRESS);
        assertEq(entryGroupId, reservedGroupId);
        assertEq(entryUsage, AddressUsage.BORROW | AddressUsage.REPAYMENT);
    }

    function test_AddEntriesToCustomGroup_DifferentAddressSameUsage() public {
        uint32 groupId = _createTestGroupWithDifferentAddress();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        rawAddresses[1] = LST_ADDRESS3;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        usages[1] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryAdded(groupId, rawAddresses, formats, usages);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);

        (uint32 entryGroupId1, uint8 entryUsage1) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS1);
        (uint32 entryGroupId2, uint8 entryUsage2) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS3);
        assertEq(entryGroupId1, groupId);
        assertEq(entryUsage1, AddressUsage.OUTBOUND);
        assertEq(entryGroupId2, groupId);
        assertEq(entryUsage2, AddressUsage.OUTBOUND);
    }

    function test_AddEntriesToReservedGroup_DifferentAddressSameUsage() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.BORROW;

        rawAddresses[1] = P2SH_ADDRESS;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[1] = AddressUsage.BORROW;

        vm.prank(groupMemberOperator);
        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryAdded(reservedGroupId, rawAddresses, formats, usages);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        (uint32 entryGroupId1, uint8 entryUsage1) = whitelistRegistry.getWhitelistEntry(P2PKH_ADDRESS);
        (uint32 entryGroupId2, uint8 entryUsage2) = whitelistRegistry.getWhitelistEntry(P2SH_ADDRESS);
        assertEq(entryGroupId1, reservedGroupId);
        assertEq(entryUsage1, AddressUsage.BORROW);
        assertEq(entryGroupId2, reservedGroupId);
        assertEq(entryUsage2, AddressUsage.BORROW);
    }

    function test_RevertWhen_AddEntriesToReservedGroup_YieldAddressMultipleUsages() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.YIELD | AddressUsage.BORROW;

        vm.prank(groupMemberOperator);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.InvalidReservedGroupAddressUsage.selector,
            usages[0]
        ));
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        usages[0] = AddressUsage.YIELD;
        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        usages[0] = AddressUsage.BORROW;
        vm.prank(groupMemberOperator);
        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.AddressAlreadyUsed.selector,
            P2PKH_ADDRESS,
            reservedGroupId,
            AddressUsage.YIELD
        ));
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);
    }

    // ============ removeEntriesFromGroup() Tests ============


    function test_RemoveEntriesFromGroup_Success() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));

        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryRemoved(groupId, rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);
        bytes32 entryKey = keccak256(LST_ADDRESS1);
        bytes32 entryKey2 = keccak256(P2PKH_ADDRESS);
        bytes32 entryKey3 = keccak256(P2SH_ADDRESS);
        bytes32[] memory entryKeys1 = new bytes32[](2);
        entryKeys1[0] = entryKey3;
        entryKeys1[1] = entryKey2;
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        (/*bool exists*/, bytes32[] memory entryKeys) = whitelistRegistry.getWhitelistGroup(groupId);
        assertEq(entryKeys.length, 2);
        assertEq(entryKeys[0], entryKey3);
        assertEq(entryKeys[1], entryKey2);
        assertEq(entryKeys, entryKeys1);
    }


    function test_RemoveEntriesFromGroup_MultipleEntriesSuccess() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);

        rawAddresses[0] = LST_ADDRESS1;
        rawAddresses[1] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.INBOUND;

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));

        (bytes[] memory beforeRawAddresses,,) = whitelistRegistry.getGroupEntries(groupId);
        uint256 beforeCount = beforeRawAddresses.length;

        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryRemoved(groupId, rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);

        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertFalse(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));

        (bytes[] memory afterRawAddresses,,) = whitelistRegistry.getGroupEntries(groupId);
        assertEq(afterRawAddresses.length, beforeCount - 2);
    }

    function test_RevertWhen_RemoveEntriesFromGroup_EmptyArrays() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](0);
        uint8[] memory formats = new uint8[](0);
        uint8[] memory usages = new uint8[](0);

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryArrayLengthMismatch.selector
            )
        );
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);
    }

    function test_RevertWhen_RemoveEntriesFromGroup_ArrayLengthMismatch() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](2);
        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        rawAddresses[1] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryArrayLengthMismatch.selector
            )
        );
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);
    }


    function test_RevertWhen_RemoveEntriesFromGroup_AlreadyRemovedEntry() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryStatusMismatch.selector,
                WhitelistRegistryLogic.EntryStatus.Active,
                WhitelistRegistryLogic.EntryStatus.Removed
            )
        );
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);
    }


    function test_RevertWhen_RemoveEntriesFromGroup_AddressFromDifferentGroup() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryGroupIdMismatch.selector,
                groupId1,
                groupId2
            )
        );
        whitelistRegistry.removeEntriesFromGroup(groupId1, rawAddresses, formats, usages);
    }


    function test_RevertWhen_RemoveEntriesFromGroup_UsageMismatch() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryUsageMismatch.selector,
                AddressUsage.INBOUND,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);
    }


    function test_RevertWhen_RemoveEntriesFromGroup_AddressNotFoundInGroup() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS3;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        vm.prank(groupMemberOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryStatusMismatch.selector,
                WhitelistRegistryLogic.EntryStatus.Active,
                WhitelistRegistryLogic.EntryStatus.Unknown
            )
        );
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);
    }

    function test_RemoveEntriesFromGroup_AddRemoveSequence() public {
        uint32 groupId = _createTestGroup();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        (bytes[] memory initialRawAddresses,,) = whitelistRegistry.getGroupEntries(groupId);
        uint256 initialCount = initialRawAddresses.length;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        (bytes[] memory afterAddRawAddresses,,) = whitelistRegistry.getGroupEntries(groupId);
        assertEq(afterAddRawAddresses.length, initialCount + 1);

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);

        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        (bytes[] memory afterRemoveRawAddresses,,) = whitelistRegistry.getGroupEntries(groupId);
        assertEq(afterRemoveRawAddresses.length, initialCount);
        assertEq(afterRemoveRawAddresses, initialRawAddresses);

    }

    function test_RemoveEntriesFromGroup_ReservedGroupSuccess() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.BORROW;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));

        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryRemoved(reservedGroupId, rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(reservedGroupId, rawAddresses, formats, usages);

        assertFalse(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));
    }

    function test_RemoveEntriesFromGroup_ReservedGroupPartialUsageRemoval() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = P2PKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.REPAYMENT;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);
        usages[0] = AddressUsage.BORROW;
        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));
        (uint32 groupId, uint8 currentUsage) = whitelistRegistry.getWhitelistEntry(P2PKH_ADDRESS);
        assertEq(groupId, reservedGroupId);
        assertEq(currentUsage, AddressUsage.REPAYMENT | AddressUsage.BORROW);

        usages[0] = AddressUsage.REPAYMENT;

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(reservedGroupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));
        (uint32 newGroupId, uint8 newUsage) = whitelistRegistry.getWhitelistEntry(P2PKH_ADDRESS);
        assertEq(newGroupId, reservedGroupId);
        assertEq(newUsage, AddressUsage.BORROW);

        usages[0] = AddressUsage.BORROW;
        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(reservedGroupId, rawAddresses, formats, usages);
        assertFalse(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));

    }

    // ============ updateEntriesInGroup() Tests ============


    function test_UpdateEntriesInGroup_ReservedGroupSuccess() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory addAddresses = new bytes[](1);
        uint8[] memory addFormats = new uint8[](1);
        uint8[] memory addUsages = new uint8[](1);

        addAddresses[0] = P2PKH_ADDRESS;
        addFormats[0] = ADDRESS_FORMAT_BTC;
        addUsages[0] = AddressUsage.BORROW;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, addAddresses, addFormats, addUsages);

        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));

        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        bytes[] memory oldRawAddresses = new bytes[](1);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.BORROW;
        oldRawAddresses[0] = P2PKH_ADDRESS;
        newRawAddresses[0] = P2SH_ADDRESS;

        assertTrue(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));
        assertFalse(whitelistRegistry.isWhitelisted(P2SH_ADDRESS));

        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryUpdated(reservedGroupId, formats, usages, oldRawAddresses, newRawAddresses);

        vm.prank(govAddress);
        whitelistRegistry.updateEntriesInGroup(reservedGroupId, formats, usages, oldRawAddresses, newRawAddresses);

        assertFalse(whitelistRegistry.isWhitelisted(P2PKH_ADDRESS));
        assertTrue(whitelistRegistry.isWhitelisted(P2SH_ADDRESS));

        (uint32 entryGroupId, uint8 entryUsage) = whitelistRegistry.getWhitelistEntry(P2SH_ADDRESS);
        assertEq(entryGroupId, reservedGroupId);
        assertEq(entryUsage, AddressUsage.BORROW);
    }


    function test_UpdateEntriesInGroup_CustomGroupSuccess() public {
        uint32 groupId = _createTestGroup();

        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        bytes[] memory oldRawAddresses = new bytes[](1);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;
        oldRawAddresses[0] = LST_ADDRESS1;
        newRawAddresses[0] = LST_ADDRESS2;

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));

        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryUpdated(groupId, formats, usages, oldRawAddresses, newRawAddresses);

        vm.prank(govAddress);
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);

        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));

        (uint32 entryGroupId, uint8 entryUsage) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);
        assertEq(entryGroupId, groupId);
        assertEq(entryUsage, AddressUsage.OUTBOUND);
        (/*bool exists*/, bytes32[] memory entryKeys) = whitelistRegistry.getWhitelistGroup(groupId);
        assertEq(entryKeys.length, 3);
        assertEq(entryKeys[0], keccak256(P2SH_ADDRESS));
        assertEq(entryKeys[1], keccak256(P2PKH_ADDRESS));
        assertEq(entryKeys[2], keccak256(LST_ADDRESS2));
    }

    function test_UpdateEntriesInGroup_CustomGroupMultipleSuccess() public {
        uint32 groupId = _createTestGroup();

        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);
        bytes[] memory oldRawAddresses = new bytes[](2);
        bytes[] memory newRawAddresses = new bytes[](2);

        oldRawAddresses[0] = LST_ADDRESS1;
        oldRawAddresses[1] = P2SH_ADDRESS;
        newRawAddresses[0] = LST_ADDRESS2;
        newRawAddresses[1] = P2TR_ADDRESS;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.OPERATIONS;

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(P2SH_ADDRESS));
        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertFalse(whitelistRegistry.isWhitelisted(P2TR_ADDRESS));

        vm.expectEmit(true, false, false, true);
        emit WhitelistEntryUpdated(groupId, formats, usages, oldRawAddresses, newRawAddresses);

        vm.prank(govAddress);
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);

        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertFalse(whitelistRegistry.isWhitelisted(P2SH_ADDRESS));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
        assertTrue(whitelistRegistry.isWhitelisted(P2TR_ADDRESS));

        (uint32 entryGroupId2, uint8 entryUsage2) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);
        (uint32 entryGroupId4, uint8 entryUsage4) = whitelistRegistry.getWhitelistEntry(P2TR_ADDRESS);
        assertEq(entryGroupId2, groupId);
        assertEq(entryUsage2, AddressUsage.OUTBOUND);
        assertEq(entryGroupId4, groupId);
        assertEq(entryUsage4, AddressUsage.OPERATIONS);

        (bytes[] memory rawAddresses1,uint8[] memory formats1,uint8[] memory usages1) = whitelistRegistry.getGroupEntries(groupId);
        assertEq(rawAddresses1.length, 3);
        assertEq(rawAddresses1[0], LST_ADDRESS2);
        assertEq(rawAddresses1[1], P2PKH_ADDRESS);
        assertEq(rawAddresses1[2], P2TR_ADDRESS);
        assertEq(formats1[0], ADDRESS_FORMAT_NATIVE);
        assertEq(formats1[1], ADDRESS_FORMAT_BTC);
        assertEq(formats1[2], ADDRESS_FORMAT_BTC);
        assertEq(usages1[0], AddressUsage.OUTBOUND);
        assertEq(usages1[1], AddressUsage.INBOUND);
        assertEq(usages1[2], AddressUsage.OPERATIONS);
    }


    function test_RevertWhen_UpdateEntriesInGroup_EmptyArrays() public {
        uint32 groupId = _createTestGroup();

        uint8[] memory formats = new uint8[](0);
        uint8[] memory usages = new uint8[](0);
        bytes[] memory oldRawAddresses = new bytes[](0);
        bytes[] memory newRawAddresses = new bytes[](0);

        vm.prank(govAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryArrayLengthMismatch.selector
            )
        );
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);
    }


    function test_RevertWhen_UpdateEntriesInGroup_ArrayLengthMismatch() public {
        uint32 groupId = _createTestGroup();

        uint8[] memory formats = new uint8[](2);
        uint8[] memory usages = new uint8[](2);
        bytes[] memory oldRawAddresses = new bytes[](2);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.INBOUND;
        oldRawAddresses[0] = LST_ADDRESS1;
        oldRawAddresses[1] = P2PKH_ADDRESS;
        newRawAddresses[0] = LST_ADDRESS2;

        vm.prank(govAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryArrayLengthMismatch.selector
            )
        );
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);
    }


    function test_RevertWhen_UpdateEntriesInGroup_OldAddressNotFound() public {
        uint32 groupId = _createTestGroup();

        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        bytes[] memory oldRawAddresses = new bytes[](1);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;
        oldRawAddresses[0] = LST_ADDRESS3;
        newRawAddresses[0] = LST_ADDRESS2;

        vm.prank(govAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryStatusMismatch.selector,
                WhitelistRegistryLogic.EntryStatus.Active,
                WhitelistRegistryLogic.EntryStatus.Unknown
            )
        );
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);
    }


    function test_RevertWhen_UpdateEntriesInGroup_InvalidNewAddressFormat() public {
        uint32 groupId = _createTestGroup();

        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        bytes[] memory oldRawAddresses = new bytes[](1);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;
        oldRawAddresses[0] = LST_ADDRESS1;
        newRawAddresses[0] = INVALID_NATIVE_ADDRESS;

        vm.prank(govAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.InvalidNativeAddress.selector,
                INVALID_NATIVE_ADDRESS
            )
        );
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);
    }


    function test_RevertWhen_UpdateEntriesInGroup_NewAddressAlreadyExists() public {
        uint32 groupId = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        bytes[] memory oldRawAddresses = new bytes[](1);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;
        oldRawAddresses[0] = LST_ADDRESS1;
        newRawAddresses[0] = LST_ADDRESS2;

        vm.prank(govAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.AddressAlreadyUsed.selector,
                LST_ADDRESS2,
                groupId2,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);
    }


    function test_RevertWhen_UpdateEntriesInGroup_InvalidReservedGroupAddressFormat() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        bytes[] memory addAddresses = new bytes[](1);
        uint8[] memory addFormats = new uint8[](1);
        uint8[] memory addUsages = new uint8[](1);

        addAddresses[0] = P2PKH_ADDRESS;
        addFormats[0] = ADDRESS_FORMAT_BTC;
        addUsages[0] = AddressUsage.BORROW;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(reservedGroupId, addAddresses, addFormats, addUsages);

        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        bytes[] memory oldRawAddresses = new bytes[](1);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.BORROW;
        oldRawAddresses[0] = P2PKH_ADDRESS;
        newRawAddresses[0] = INVALID_BTC_ADDRESS;

        vm.prank(govAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.InvalidBTCPkScript.selector,
                INVALID_BTC_ADDRESS
            )
        );
        whitelistRegistry.updateEntriesInGroup(reservedGroupId, formats, usages, oldRawAddresses, newRawAddresses);
    }

    function test_RevertWhen_UpdateEntriesInGroup_UsageMismatch() public {
        uint32 groupId = _createTestGroup();

        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        bytes[] memory oldRawAddresses = new bytes[](1);
        bytes[] memory newRawAddresses = new bytes[](1);

        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;
        oldRawAddresses[0] = LST_ADDRESS1;
        newRawAddresses[0] = LST_ADDRESS2;

        vm.prank(govAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WhitelistRegistryLogic.EntryUsageMismatch.selector,
                AddressUsage.INBOUND,
                AddressUsage.OUTBOUND
            )
        );
        whitelistRegistry.updateEntriesInGroup(groupId, formats, usages, oldRawAddresses, newRawAddresses);
    }

    // ============ View Functions Tests ============

    // ============ isWhitelisted() Tests ============
    function test_IsWhitelisted() public {
        uint32 groupId = _createTestGroup();

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));

        assertFalse(whitelistRegistry.isWhitelisted(LST_ADDRESS2));

        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.INBOUND;

        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(groupId, rawAddresses, formats, usages);

        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS1));
        assertTrue(whitelistRegistry.isWhitelisted(LST_ADDRESS2));
    }

    // ============ isWhitelistedReservedGroup() Tests ============
    function test_IsWhitelistedReservedGroup() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        assertTrue(whitelistRegistry.isWhitelistedReservedGroup(reservedGroupId));

        uint32 customGroupId = _createTestGroup();

        assertFalse(whitelistRegistry.isWhitelistedReservedGroup(customGroupId));

        assertFalse(whitelistRegistry.isWhitelistedReservedGroup(99999));
    }

    // ============ isWhitelistedCustomGroup() Tests ============
    function test_IsWhitelistedCustomGroup() public {
        uint32 reservedGroupId = whitelistRegistry.RESERVED_GROUP_ID();

        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(reservedGroupId));

        uint32 customGroupId = _createTestGroup();

        assertTrue(whitelistRegistry.isWhitelistedCustomGroup(customGroupId));

        assertFalse(whitelistRegistry.isWhitelistedCustomGroup(99999));
    }

    // ============ getWhitelistEntry() Tests ============
    function test_GetWhitelistEntry() public {
        uint32 groupId = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        (uint32 entryGroupId, uint8 entryUsage) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);
        assertEq(entryGroupId, groupId2);
        assertEq(entryUsage, AddressUsage.OUTBOUND);

        (uint32 notFoundGroupId, uint8 notFoundUsage) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS3);
        assertEq(notFoundGroupId, 0);
        assertEq(notFoundUsage, 0);
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);
        rawAddresses[0] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;
        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId2, rawAddresses, formats, usages);
        (uint32 entryGroupId3, uint8 entryUsage3) = whitelistRegistry.getWhitelistEntry(LST_ADDRESS2);
        assertEq(entryGroupId3, 0);
        assertEq(entryUsage3, 0);

    }

    // ============ getWhitelistGroup() Tests ============
    function test_GetWhitelistGroup() public {
        uint32 groupId = _createTestGroup();

        (bool exists, bytes32[] memory entryKeys) = whitelistRegistry.getWhitelistGroup(groupId);
        assertTrue(exists);
        assertEq(entryKeys.length, 3);
        assertEq(entryKeys[0], keccak256(LST_ADDRESS1));
        assertEq(entryKeys[1], keccak256(P2PKH_ADDRESS));
        assertEq(entryKeys[2], keccak256(P2SH_ADDRESS));

        (bool notExists, bytes32[] memory emptyKeys) = whitelistRegistry.getWhitelistGroup(99999);
        assertFalse(notExists);
        assertEq(emptyKeys.length, 0);
    }

    // ============ getGroupIds() Tests ============

    function test_GetGroupIds_BasicFunctionality() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        uint32[] memory allGroupIds = whitelistRegistry.getGroupIds(true, true);
        assertTrue(allGroupIds.length == 3);

        bool foundReservedGroup = false;
        bool foundGroup1 = false;
        bool foundGroup2 = false;

        for (uint i = 0; i < allGroupIds.length; i++) {
            if (allGroupIds[i] == whitelistRegistry.RESERVED_GROUP_ID()) {
                foundReservedGroup = true;
            }
            if (allGroupIds[i] == groupId1) {
                foundGroup1 = true;
            }
            if (allGroupIds[i] == groupId2) {
                foundGroup2 = true;
            }
        }

        assertTrue(foundReservedGroup);
        assertTrue(foundGroup1);
        assertTrue(foundGroup2);
    }

    function test_GetGroupIds_ExcludeReservedGroup() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        uint32[] memory customGroupIds = whitelistRegistry.getGroupIds(false, true);

        for (uint i = 0; i < customGroupIds.length; i++) {
            assertGt(customGroupIds[i], whitelistRegistry.RESERVED_GROUP_ID());
        }

        bool foundGroup1 = false;
        bool foundGroup2 = false;
        for (uint i = 0; i < customGroupIds.length; i++) {
            if (customGroupIds[i] == groupId1) {
                foundGroup1 = true;
            }
            if (customGroupIds[i] == groupId2) {
                foundGroup2 = true;
            }
        }
        assertTrue(foundGroup1);
        assertTrue(foundGroup2);
    }

    function test_GetGroupIds_IncludeEmptyGroups() public {
        uint32 normalGroupId = _createTestGroup();
        uint32 emptyGroupId = _createEmptyGroup();
        uint32 normalGroupId2 = _createTestGroupWithDifferentAddress();

        uint32[] memory allGroupIds = whitelistRegistry.getGroupIds(false, true);
        uint32[] memory allGroupIdsBytes = new uint32[](3);
        allGroupIdsBytes[0] = normalGroupId;
        allGroupIdsBytes[1] = emptyGroupId;
        allGroupIdsBytes[2] = normalGroupId2;
        assertTrue(keccak256(abi.encodePacked(allGroupIds)) == keccak256(abi.encodePacked(allGroupIdsBytes)));

        uint32[] memory nonEmptyGroupIds = whitelistRegistry.getGroupIds(false, false);
        uint32[] memory nonEmptyGroupIdsBytes = new uint32[](2);
        nonEmptyGroupIdsBytes[0] = normalGroupId;
        nonEmptyGroupIdsBytes[1] = normalGroupId2;
        assertTrue(keccak256(abi.encodePacked(nonEmptyGroupIds)) == keccak256(abi.encodePacked(nonEmptyGroupIdsBytes)));
    }

    function test_GetGroupIds_EmptyArrayWhenNoCustomGroups() public {
        uint32[] memory groupIds = whitelistRegistry.getGroupIds(false, true);
        assertTrue(groupIds.length == 0);
    }

    function test_GetGroupIds_ArrayCompaction() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();
        uint32 groupId3 = _createEmptyGroup();

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId2);

        uint32[] memory groupIds = whitelistRegistry.getGroupIds(false, true);

        bool foundGroup1 = false;
        bool foundGroup2 = false;
        bool foundGroup3 = false;

        for (uint i = 0; i < groupIds.length; i++) {
            if (groupIds[i] == groupId1) foundGroup1 = true;
            if (groupIds[i] == groupId2) foundGroup2 = true;
            if (groupIds[i] == groupId3) foundGroup3 = true;
        }

        assertTrue(foundGroup1);
        assertFalse(foundGroup2);
        assertTrue(foundGroup3);
    }

    function test_GetGroupIds_OnlyReservedGroupExists() public {
        uint32 groupId1 = _createTestGroup();
        uint32 groupId2 = _createTestGroupWithDifferentAddress();

        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId1);
        vm.prank(govAddress);
        whitelistRegistry.removeGroup(groupId2);

        uint32[] memory groupIds = whitelistRegistry.getGroupIds(true, true);

        bool foundReservedGroup = false;
        assertEq(groupIds.length, 1);
        assertEq(groupIds[0], whitelistRegistry.RESERVED_GROUP_ID());
    }

    // ============ getGroupEntries() Tests ============
    function test_GetGroupEntries() public {
        uint32 groupId = _createTestGroup();

        (bytes[] memory rawAddresses, uint8[] memory formats, uint8[] memory usages) =
                            whitelistRegistry.getGroupEntries(groupId);

        assertEq(rawAddresses.length, 3);
        assertEq(formats.length, 3);
        assertEq(usages.length, 3);

        assertEq(rawAddresses[0], LST_ADDRESS1);
        assertEq(formats[0], ADDRESS_FORMAT_NATIVE);
        assertEq(usages[0], AddressUsage.OUTBOUND);

        assertEq(rawAddresses[1], P2PKH_ADDRESS);
        assertEq(formats[1], ADDRESS_FORMAT_BTC);
        assertEq(usages[1], AddressUsage.INBOUND);

        assertEq(rawAddresses[2], P2SH_ADDRESS);
        assertEq(formats[2], ADDRESS_FORMAT_BTC);
        assertEq(usages[2], AddressUsage.OPERATIONS);
    }

    function test_RevertWhen_GetGroupEntries_GroupNotFound() public {
        uint32 nonExistentGroupId = 99999;

        vm.expectRevert(abi.encodeWithSelector(
            WhitelistRegistryLogic.GroupNotFound.selector,
            nonExistentGroupId
        ));
        whitelistRegistry.getGroupEntries(nonExistentGroupId);
    }

    // ============ Constants Tests ============

    function test_Constants_Values() public {
        assertEq(whitelistRegistry.RESERVED_GROUP_ID(), 10000);
        assertEq(whitelistRegistry.ROLE_GROUP_MEMBER_OPERATOR(), keccak256("ROLE_GROUP_MEMBER_OPERATOR"));
    }

    // ============ Helper Functions ============

    function _createTestGroup() internal returns (uint32 groupId) {
        bytes[] memory rawAddresses = new bytes[](3);
        uint8[] memory formats = new uint8[](3);
        uint8[] memory usages = new uint8[](3);

        rawAddresses[0] = LST_ADDRESS1;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        rawAddresses[1] = P2PKH_ADDRESS;
        formats[1] = ADDRESS_FORMAT_BTC;
        usages[1] = AddressUsage.INBOUND;

        rawAddresses[2] = P2SH_ADDRESS;
        formats[2] = ADDRESS_FORMAT_BTC;
        usages[2] = AddressUsage.OPERATIONS;

        groupId = whitelistRegistry.nextGroupId();

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        return groupId;
    }

    function _createTestGroupWithDifferentAddress() internal returns (uint32 groupId) {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = LST_ADDRESS2;
        formats[0] = ADDRESS_FORMAT_NATIVE;
        usages[0] = AddressUsage.OUTBOUND;

        groupId = whitelistRegistry.nextGroupId();

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        return groupId;
    }

    function _createEmptyGroup() internal returns (uint32 groupId) {
        bytes[] memory rawAddresses = new bytes[](1);
        uint8[] memory formats = new uint8[](1);
        uint8[] memory usages = new uint8[](1);

        rawAddresses[0] = P2WPKH_ADDRESS;
        formats[0] = ADDRESS_FORMAT_BTC;
        usages[0] = AddressUsage.OPERATIONS;

        groupId = whitelistRegistry.nextGroupId();

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        vm.prank(groupMemberOperator);
        whitelistRegistry.removeEntriesFromGroup(groupId, rawAddresses, formats, usages);

        return groupId;
    }

    // ============ Events Declaration for Tests ============

    event WhitelistGroupCreated(
        uint32 indexed groupId,
        bytes[] rawAddresses,
        uint8[] formats,
        uint8[] usages
    );

    event WhitelistGroupRemoved(
        uint32 indexed groupId
    );

    event WhitelistEntryAdded(
        uint32 indexed groupId,
        bytes[] rawAddresses,
        uint8[] formats,
        uint8[] usages
    );

    event WhitelistEntryRemoved(
        uint32 indexed groupId,
        bytes[] rawAddresses,
        uint8[] formats,
        uint8[] usages
    );

    event WhitelistEntryUpdated(
        uint32 indexed groupId,
        uint8[] formats,
        uint8[] usages,
        bytes[] oldRawAddresses,
        bytes[] newRawAddresses
    );
} 