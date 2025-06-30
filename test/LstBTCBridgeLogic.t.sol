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

contract MockContract {}

contract LstBTCBridgeLogicTest is Deployer {
    event ConfigRegistryUpdated(
        address indexed oldConfigRegistry,
        address indexed newConfigRegistry
    );
    event WhitelistRegistryUpdated(
        address indexed oldWhitelistRegistry,
        address indexed newWhitelistRegistry
    );
    event NavProviderUpdated(
        address indexed oldNavProvider,
        address indexed newNavProvider
    );
    event BitcoinTxStoreUpdated(
        address indexed oldBitcoinTxStore,
        address indexed newBitcoinTxStore
    );
    event LstBTCUpdated(address indexed oldLstBTC, address indexed newLstBTC);

    event PegOutCreated(
        uint256 indexed requestId,
        uint32 indexed custodianId,
        address sender,
        address receiver,
        uint64 amount,
        uint64 exchangeRate,
        address[] recipients,
        uint64[] recipientAmounts,
        uint64 netAmount
    );

    event PegOutBatchRefunded(
        uint32 indexed batchId,
        uint256[] requestIds,
        uint64 totalAmount,
        bool isCompleted
    );

    event PegInBatchPaid(
        uint32 indexed batchId,
        uint256[] requestIds,
        uint64 totalAmount,
        bool isCompleted
    );

    event BatchProcessed(
        uint32 indexed batchId,
        uint256[] pegInIds,
        uint256[] pegOutIds,
        uint64 pendingPayWrappedAmount,
        uint64 pendingPayBTCAmount
    );

    event BatchRejected(
        uint32 indexed batchId,
        uint256[] pegInIds,
        uint256[] pegOutIds,
        uint64 pendingRefundBTC,
        uint64 pendingRefundWrappedBTC
    );

    event FeesClaimed(address indexed claimer, uint64 amount);

    event PegInCreated(
        uint256 indexed requestId,
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        bytes sender,
        bytes receiver,
        uint64 amount,
        uint64 exchangeRate,
        address[] recipients,
        uint64[] recipientAmounts,
        uint64 netAmount
    );
    event PegInBatchRefunded(
        uint64 indexed batchId,
        bytes32 indexed bitcoinTxId,
        uint256[] settledRequestIds,
        uint64 amount,
        bool isBatchCompleted
    );
    event PegOutBatchPaid(
        uint32 indexed batchId,
        bytes32 indexed bitcoinTxId,
        uint256[] settledRrequestIdsequestIds,
        uint64 totalAmount,
        bool isCompleted
    );
    event YieldReceived(
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        uint64 yieldAmount,
        uint64 totalYield
    );
    event Borrowed(
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        uint64 borrowedAmount,
        uint64 custodianDebt,
        uint64 totalDebt
    );
    event Repaid(
        uint32 indexed custodianId,
        bytes32 indexed bitcoinTxId,
        uint64 repaidAmount,
        uint64 custodianDebt,
        uint64 totalDebt
    );
    event TransactionSubmitted(
        bytes32 indexed txId,
        uint32 indexed blockNumber,
        uint32 currentBlockNumber
    );

    address public user1;
    address public user2;
    address public relayer1;
    address public relayer2;
    address public upgrader1;
    address public groupMemberOperator;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ROLE_UPGRADER = keccak256("ROLE_UPGRADER");
    bytes32 public constant ROLE_GROUP_MEMBER_OPERATOR = keccak256("ROLE_GROUP_MEMBER_OPERATOR");

    uint8 public constant ADDRESS_FORMAT_NATIVE = 1;
    uint8 public constant ADDRESS_FORMAT_BTC = 2;
    uint32 public constant BTC_TX_TIMESTAMP = 1717334400;

    address public operationsNativeAddress = 0x0e3d18A5703c2f7b024d79b878b586Cbd844C159;
    address public inboundNativeAddress = 0xDcE49E20aEA8be32C182E4f3429258001A101767;
    address public outboundNativeAddress = 0xC33B9734003154A6e1C305F313201AC247C42392;

    bytes32[] public merkleProof = new bytes32[](1);
    uint16 public blockIndex = 0;
    // Address usage
    bytes public constant OUTBOUND_NATIVE_ADDRESS = LST_ADDRESS1;
    bytes public constant INBOUND_NATIVE_ADDRESS = LST_ADDRESS2;
    bytes public constant OPERATIONS_NATIVE_ADDRESS = LST_ADDRESS3;
    bytes public constant OUTBOUND_BTC_ADDRESS = P2PKH_ADDRESS;
    bytes public constant INBOUND_BTC_ADDRESS = P2WPKH_ADDRESS;
    bytes public constant OPERATIONS_BTC_ADDRESS = P2SH_ADDRESS;

    bytes public constant BORROW_BTC_ADDRESS = P2TR_ADDRESS;
    bytes public constant REPAYMENT_BTC_ADDRESS = P2WSH_ADDRESS;
    bytes public constant YIELD_BTC_ADDRESS = P2PK_ADDRESS;


    bytes public constant OUTBOUND_BTC_ADDRESS_GROUP2 = hex"76a914b7536c788d8ca0a956ca93e8e8c2f1e5c9d9c3e888ac";
    bytes public constant INBOUND_BTC_ADDRESS_GROUP2 = hex"0014b7536c788d8ca0a956ca93e8e8c2f1e5c9d9c3e8";
    bytes public constant OPERATIONS_BTC_ADDRESS_GROUP2 = hex"a914b7536c788d8ca0a956ca93e8e8c2f1e5c9d9c3e887";

    bytes32 public outboundBtcUtxo;
    // bytes32 public inboundBtcUtxo;
    // bytes32 public operationsBtcUtxo;
    uint32 public constant FIRST_INPUT_INDEX = 0;
    uint64 public constant FIRST_TO_BTC_AMOUNT = 180000000;
    uint64 public constant FIRST_CHANGE_AMOUNT = 80000000;
    bytes public constant FIRST_FROM_BTC_ADDRESS = hex"0014025778a19e9b919bfb84e7d10e05ff35510a1afa";
    bytes public constant FIRST_TO_BTC_ADDRESS = OUTBOUND_BTC_ADDRESS;
    bytes public constant FIRST_CHANGE_BTC_ADDRESS = hex"76a9141322506fcdb11f36c7a78d19ae9b9ee30851042a88ac";


    function setUp() public {
        user1 = address(2000);
        user2 = address(2001);
        relayer1 = address(2002);
        relayer2 = address(2003);
        upgrader1 = address(2004);
        groupMemberOperator = address(2005);
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(relayer1, "Relayer1");
        vm.label(relayer2, "Relayer2");
        vm.label(groupMemberOperator, "GroupMemberOperator");
        vm.startPrank(govAddress);
        whitelistRegistry.grantRole(ROLE_GROUP_MEMBER_OPERATOR, groupMemberOperator);
        vm.stopPrank();
        lstBTC.setMaxMintLimit(30e8);
        _initWhitelistRegistry();
        outboundBtcUtxo = _initToOutBoundBTC();
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public {
        assertFalse(lstBTCBridge.paused());
        assertTrue(lstBTCBridge.hasRole(DEFAULT_ADMIN_ROLE, adminAddress));
        assertTrue(lstBTCBridge.hasRole(ROLE_GOVERNOR, govAddress));
        vm.startPrank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, address(relayer1));
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, address(relayer1)));
        assertEq(lstBTCBridge.getRoleAdmin(ROLE_GOVERNOR), DEFAULT_ADMIN_ROLE);
        assertEq(lstBTCBridge.getRoleAdmin(ROLE_RELAYER), ROLE_GOVERNOR);
    }

    function test_RevertWhen_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        lstBTCBridge.initialize(adminAddress, govAddress);
    }

    function test_Initialize_WithZeroAddress() public {
        LstBTCBridgeLogic logic = new LstBTCBridgeLogic();
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(0),
            govAddress
        );

        LstBTCBridgeProxy proxy = new LstBTCBridgeProxy(
            address(logic),
            initData
        );

        LstBTCBridgeLogic inst = LstBTCBridgeLogic(address(proxy));
        assertTrue(inst.hasRole(DEFAULT_ADMIN_ROLE, address(0)));
    }

    // ============ Access Control Tests ============

    function test_RevertIf_NotGovernorPauseBridge() public {
        address[] memory authorizedUsers = new address[](2);
        authorizedUsers[0] = govAddress;
        authorizedUsers[1] = adminAddress;
        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);
        for (uint i = 0; i < authorizedUsers.length; i++) {
            vm.prank(authorizedUsers[i]);
            lstBTCBridge.pauseBridge();
            assertTrue(lstBTCBridge.paused());

            vm.prank(authorizedUsers[i]);
            lstBTCBridge.unpauseBridge();
            assertFalse(lstBTCBridge.paused());
        }

        address[] memory unauthorizedUsers = new address[](3);
        unauthorizedUsers[0] = upgrader1;
        unauthorizedUsers[1] = relayer1;
        unauthorizedUsers[2] = user1;

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            vm.prank(unauthorizedUsers[i]);
            vm.expectRevert(
                abi.encodePacked(
                    "AccessControl: account ",
                    StringsUpgradeable.toHexString(unauthorizedUsers[i]),
                    " is missing role ",
                    StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
                )
            );
            lstBTCBridge.pauseBridge();
        }

        assertFalse(lstBTCBridge.paused());
    }

    function test_RevertIf_NotGovernorUnpauseBridge() public {
        vm.prank(govAddress);
        lstBTCBridge.pauseBridge();
        assertTrue(lstBTCBridge.paused());

        address[] memory unauthorizedUsers = new address[](3);
        unauthorizedUsers[0] = upgrader1;
        unauthorizedUsers[1] = relayer1;
        unauthorizedUsers[2] = user1;

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            vm.prank(unauthorizedUsers[i]);
            vm.expectRevert(
                abi.encodePacked(
                    "AccessControl: account ",
                    StringsUpgradeable.toHexString(unauthorizedUsers[i]),
                    " is missing role ",
                    StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
                )
            );
            lstBTCBridge.unpauseBridge();
        }
        assertTrue(lstBTCBridge.paused());
    }

    function test_IsRelayer() public {
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer2));
    }

    function test_RevertIf_NotGovernorAddRelayer() public {
        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
        address[] memory unauthorizedUsers = new address[](4);
        unauthorizedUsers[0] = upgrader1;
        unauthorizedUsers[1] = relayer1;
        unauthorizedUsers[2] = user1;
        unauthorizedUsers[3] = adminAddress;

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            vm.prank(unauthorizedUsers[i]);
            vm.expectRevert();
            lstBTCBridge.grantRole(ROLE_RELAYER, relayer2);
            assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer2));
        }
    }

    function test_RevertIf_NotGovernorRemoveRelayer() public {
        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
        vm.prank(govAddress);
        lstBTCBridge.revokeRole(ROLE_RELAYER, relayer1);
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));

        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer2);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer2));
        address[] memory unauthorizedUsers = new address[](4);
        unauthorizedUsers[0] = upgrader1;
        unauthorizedUsers[1] = relayer1;
        unauthorizedUsers[2] = user1;
        unauthorizedUsers[3] = adminAddress;

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            vm.prank(unauthorizedUsers[i]);
            vm.expectRevert();
            lstBTCBridge.revokeRole(ROLE_RELAYER, relayer2);
            assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer2));
        }
    }

    function test_RevertIf_NotGovernorSetConfigRegistry() public {
        address newConfigRegistry = address(3000);

        address[] memory authorizedUsers = new address[](2);
        authorizedUsers[0] = govAddress;
        authorizedUsers[1] = adminAddress;

        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);

        for (uint i = 0; i < authorizedUsers.length; i++) {
            vm.prank(authorizedUsers[i]);
            lstBTCBridge.setConfigRegistry(newConfigRegistry);
        }

        address[] memory unauthorizedUsers = new address[](3);
        unauthorizedUsers[0] = user1;
        unauthorizedUsers[1] = relayer1;
        unauthorizedUsers[2] = upgrader1;

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            vm.prank(unauthorizedUsers[i]);
            vm.expectRevert(
                abi.encodePacked(
                    "AccessControl: account ",
                    StringsUpgradeable.toHexString(unauthorizedUsers[i]),
                    " is missing role ",
                    StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
                )
            );
            lstBTCBridge.setConfigRegistry(address(3001));
        }
    }

    function test_RevertIf_NotGovernorSetWhitelistRegistry() public {
        address newWhitelistRegistry = address(3002);

        address[] memory authorizedUsers = new address[](2);
        authorizedUsers[0] = govAddress;
        authorizedUsers[1] = adminAddress;

        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);

        for (uint i = 0; i < authorizedUsers.length; i++) {
            vm.prank(authorizedUsers[i]);
            lstBTCBridge.setWhitelistRegistry(newWhitelistRegistry);
        }

        vm.prank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(user1),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
            )
        );
        lstBTCBridge.setWhitelistRegistry(address(3003));
    }

    function test_RevertIf_NotGovernorSetNavProvider() public {
        address newNavProvider = address(3004);

        address[] memory authorizedUsers = new address[](2);
        authorizedUsers[0] = govAddress;
        authorizedUsers[1] = adminAddress;

        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);

        for (uint i = 0; i < authorizedUsers.length; i++) {
            vm.prank(authorizedUsers[i]);
            lstBTCBridge.setNavProvider(newNavProvider);
        }
        vm.prank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(user1),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        lstBTCBridge.setNavProvider(address(3005));
    }

    function test_RevertIf_NotGovernorSetBitcoinTxStore() public {
        address newBitcoinTxStore = address(3006);

        address[] memory authorizedUsers = new address[](2);
        authorizedUsers[0] = govAddress;
        authorizedUsers[1] = adminAddress;

        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);

        for (uint i = 0; i < authorizedUsers.length; i++) {
            vm.prank(authorizedUsers[i]);
            lstBTCBridge.setBitcoinTxStore(newBitcoinTxStore);
        }
        vm.prank(relayer1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(relayer1),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
            )
        );
        lstBTCBridge.setBitcoinTxStore(address(3007));
    }

    function test_RevertIf_NotGovernorSetLstBTC() public {
        address newLstBTC = address(3008);

        address[] memory authorizedUsers = new address[](2);
        authorizedUsers[0] = govAddress;
        authorizedUsers[1] = adminAddress;

        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);

        for (uint i = 0; i < authorizedUsers.length; i++) {
            vm.prank(authorizedUsers[i]);
            lstBTCBridge.setLstBTC(newLstBTC);
        }

        vm.prank(upgrader1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(upgrader1),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(ROLE_GOVERNOR), 32)
            )
        );
        lstBTCBridge.setLstBTC(address(3009));
    }

    function test_RevertIf_NotRelayerSubmitTransactionProof() public {
        bytes memory rawTx = hex"0100000001";
        uint32 blockHeight = 800000;
        bytes memory fromPkScript = new bytes(0);
        bytes[] memory toPkScripts = new bytes[](1);
        toPkScripts[0] = hex"";
        vm.prank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account 0x00000000000000000000000000000000000007d0 is missing role 0xb09a19c371b337eaa25850aa48ed3337e1a7e093d787f29bfba2349c3f732f31"
            )
        );
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }

    function test_RevertIf_NotLstBTCOnLstBTCTransfer() public {
        address from = user1;
        address to = user2;
        uint64 amount = 1000;

        vm.prank(relayer1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlBase.Unauthorized.selector,
                relayer1
            )
        );
        lstBTCBridge.onLstBTCTransfer(from, to, amount);
    }

    function test_RevertWhen_PausedProcessPegRequestBatch() public {
        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](0);

        assertFalse(lstBTCBridge.paused());
        vm.prank(govAddress);
        lstBTCBridge.pauseBridge();
        assertTrue(lstBTCBridge.paused());

        vm.expectRevert("Pausable: paused");
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_PausedRejectPegRequestBatch() public {
        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](0);
        assertFalse(lstBTCBridge.paused());
        vm.prank(govAddress);
        lstBTCBridge.pauseBridge();
        assertTrue(lstBTCBridge.paused());

        vm.expectRevert("Pausable: paused");
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_ClaimFees() public {
        vm.prank(user1);
        lstBTCBridge.claimFees();
    }

    // ============ pauseBridge() & unpauseBridge() Tests ============

    function test_PauseBridge_Success() public {
        assertFalse(lstBTCBridge.paused());
        vm.prank(govAddress);
        lstBTCBridge.pauseBridge();
        assertTrue(lstBTCBridge.paused());
    }

    function test_RevertWhen_AlreadyPaused() public {
        vm.prank(govAddress);
        lstBTCBridge.pauseBridge();
        assertTrue(lstBTCBridge.paused());

        vm.prank(govAddress);
        vm.expectRevert("Pausable: paused");
        lstBTCBridge.pauseBridge();

        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);

        vm.prank(adminAddress);
        vm.expectRevert("Pausable: paused");
        lstBTCBridge.pauseBridge();
    }

    function test_UnpauseBridge_Success() public {
        vm.prank(govAddress);
        lstBTCBridge.pauseBridge();
        assertTrue(lstBTCBridge.paused());

        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);

        vm.prank(adminAddress);
        lstBTCBridge.unpauseBridge();
        assertFalse(lstBTCBridge.paused());
    }

    function test_RevertWhen_AlreadyUnpaused() public {
        assertFalse(lstBTCBridge.paused());
        vm.prank(govAddress);
        vm.expectRevert("Pausable: not paused");
        lstBTCBridge.unpauseBridge();

        vm.prank(adminAddress);
        lstBTCBridge.grantRole(ROLE_GOVERNOR, adminAddress);

        vm.prank(adminAddress);
        vm.expectRevert("Pausable: not paused");
        lstBTCBridge.unpauseBridge();
    }

    // ============ addRelayer() & removeRelayer() Tests ============
    function test_GrantRoleRelayer() public {
        vm.startPrank(govAddress);

        lstBTCBridge.grantRole(ROLE_RELAYER, user1);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, user1));

        lstBTCBridge.grantRole(ROLE_RELAYER, adminAddress);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, adminAddress));

        vm.stopPrank();
    }

    function test_GrantRoleRelayer_ZeroAddress() public {
        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, address(0));
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, address(0)));
    }

    function test_GrantRoleRelayer_DuplicateAllowed() public {
        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));

        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
    }

    function test_RemoveRelayer() public {
        vm.prank(govAddress);
        lstBTCBridge.revokeRole(ROLE_RELAYER, user1);
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, user1));
    }

    function test_RevokeRoleRelayer_ZeroAddress() public {
        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, address(0));
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, address(0)));
        vm.prank(govAddress);
        lstBTCBridge.revokeRole(ROLE_RELAYER, address(0));
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, address(0)));
    }

    function test_RemoveRelayerNotExists() public {
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, user1));
        vm.prank(govAddress);
        lstBTCBridge.revokeRole(ROLE_RELAYER, user1);
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, user1));
    }

    function test_RemoveRelayer_DuplicateAllowed() public {
        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));

        vm.prank(govAddress);
        lstBTCBridge.revokeRole(ROLE_RELAYER, relayer1);
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));

        vm.prank(govAddress);
        lstBTCBridge.revokeRole(ROLE_RELAYER, relayer1);
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
    }

    function test_GrantAndRevokeRelayer_CompleteFlow() public {
        vm.startPrank(govAddress);

        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer2);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer2));

        lstBTCBridge.revokeRole(ROLE_RELAYER, relayer1);
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer2));

        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
        assertTrue(lstBTCBridge.hasRole(ROLE_RELAYER, relayer2));

        lstBTCBridge.revokeRole(ROLE_RELAYER, relayer1);
        lstBTCBridge.revokeRole(ROLE_RELAYER, relayer2);
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer1));
        assertFalse(lstBTCBridge.hasRole(ROLE_RELAYER, relayer2));

        vm.stopPrank();
    }

    // ============ setConfigRegistry() Tests ============
    function test_SetConfigRegistry() public {
        address oldConfigRegistry = address(lstBTCBridge.configRegistry());
        address newConfigRegistry = address(3000);

        vm.prank(govAddress);
        vm.expectEmit(true, true, false, false);
        emit ConfigRegistryUpdated(oldConfigRegistry, newConfigRegistry);
        lstBTCBridge.setConfigRegistry(newConfigRegistry);
        assertEq(address(lstBTCBridge.configRegistry()), newConfigRegistry);
    }

    function test_SetConfigRegistry_SameAddress() public {
        address newConfigRegistry = address(3100);
        vm.prank(govAddress);
        lstBTCBridge.setConfigRegistry(newConfigRegistry);
        assertEq(address(lstBTCBridge.configRegistry()), newConfigRegistry);

        vm.prank(govAddress);
        lstBTCBridge.setConfigRegistry(newConfigRegistry);
        assertEq(address(lstBTCBridge.configRegistry()), newConfigRegistry);
    }

    function test_SetConfigRegistry_WhenZeroAddress() public {
        vm.prank(govAddress);
        lstBTCBridge.setConfigRegistry(address(0));

        assertEq(lstBTCBridge.configRegistry(), address(0));
    }

    function test_SetConfigRegistry_ContractAddress() public {
        MockContract mockContract = new MockContract();
        vm.prank(govAddress);
        lstBTCBridge.setConfigRegistry(address(mockContract));
        assertEq(address(lstBTCBridge.configRegistry()), address(mockContract));
    }

    function test_SetConfigRegistry_MultipleUpdates() public {
        address[] memory newAddresses = new address[](3);
        newAddresses[0] = address(3020);
        newAddresses[1] = address(3021);
        newAddresses[2] = address(3022);

        vm.startPrank(govAddress);
        for (uint i = 0; i < newAddresses.length; i++) {
            lstBTCBridge.setConfigRegistry(newAddresses[i]);
            assertEq(address(lstBTCBridge.configRegistry()), newAddresses[i]);
        }
        vm.stopPrank();
    }

    // ============ setWhitelistRegistry() Tests ============
    function test_SetWhitelistRegistry() public {
        address oldWhitelistRegistry = address(
            lstBTCBridge.whitelistRegistry()
        );
        address newWhitelistRegistry = address(3001);

        vm.prank(govAddress);
        vm.expectEmit(true, true, false, false);
        emit WhitelistRegistryUpdated(
            oldWhitelistRegistry,
            newWhitelistRegistry
        );
        lstBTCBridge.setWhitelistRegistry(newWhitelistRegistry);
        assertEq(
            address(lstBTCBridge.whitelistRegistry()),
            newWhitelistRegistry
        );
    }

    function test_SetWhitelistRegistry_SameAddress() public {
        address newWhitelistRegistry = address(3101);
        vm.prank(govAddress);
        lstBTCBridge.setWhitelistRegistry(newWhitelistRegistry);
        assertEq(
            address(lstBTCBridge.whitelistRegistry()),
            newWhitelistRegistry
        );

        vm.prank(govAddress);
        lstBTCBridge.setWhitelistRegistry(newWhitelistRegistry);
        assertEq(
            address(lstBTCBridge.whitelistRegistry()),
            newWhitelistRegistry
        );
    }

    function test_SetWhitelistRegistry_WhenZeroAddress() public {
        vm.prank(govAddress);
        lstBTCBridge.setWhitelistRegistry(address(0));

        assertEq(lstBTCBridge.whitelistRegistry(), address(0));
    }

    // ============ setNavProvider() Tests ============
    function test_SetNavProvider() public {
        address oldNavProvider = address(lstBTCBridge.navProvider());
        address newNavProvider = address(3002);

        vm.prank(govAddress);
        vm.expectEmit(true, true, false, false);
        emit NavProviderUpdated(oldNavProvider, newNavProvider);
        lstBTCBridge.setNavProvider(newNavProvider);
        assertEq(address(lstBTCBridge.navProvider()), newNavProvider);
    }

    function test_SetNavProvider_SameAddress() public {
        address newNavProvider = address(3102);
        vm.prank(govAddress);
        lstBTCBridge.setNavProvider(newNavProvider);
        assertEq(address(lstBTCBridge.navProvider()), newNavProvider);

        vm.prank(govAddress);
        lstBTCBridge.setNavProvider(newNavProvider);
        assertEq(address(lstBTCBridge.navProvider()), newNavProvider);
    }

    function test_SetNavProvider_WhenZeroAddress() public {
        vm.prank(govAddress);
        lstBTCBridge.setNavProvider(address(0));

        assertEq(lstBTCBridge.navProvider(), address(0));
    }

    // ============ setBitcoinTxStore() Tests ============
    function test_SetBitcoinTxStore() public {
        address oldBitcoinTxStore = address(lstBTCBridge.bitcoinTxStore());
        address newBitcoinTxStore = address(3003);

        vm.prank(govAddress);
        vm.expectEmit(true, true, false, false);
        emit BitcoinTxStoreUpdated(oldBitcoinTxStore, newBitcoinTxStore);
        lstBTCBridge.setBitcoinTxStore(newBitcoinTxStore);
        assertEq(address(lstBTCBridge.bitcoinTxStore()), newBitcoinTxStore);
    }

    function test_SetBitcoinTxStore_SameAddress() public {
        address newBitcoinTxStore = address(3103);
        vm.prank(govAddress);
        lstBTCBridge.setBitcoinTxStore(newBitcoinTxStore);
        assertEq(address(lstBTCBridge.bitcoinTxStore()), newBitcoinTxStore);

        vm.prank(govAddress);
        lstBTCBridge.setBitcoinTxStore(newBitcoinTxStore);
        assertEq(address(lstBTCBridge.bitcoinTxStore()), newBitcoinTxStore);
    }

    function test_SetBitcoinTxStore_WhenZeroAddress() public {
        vm.prank(govAddress);
        lstBTCBridge.setBitcoinTxStore(address(0));

        assertEq(lstBTCBridge.bitcoinTxStore(), address(0));
    }

    // ============ setLstBTC() Tests ============
    function test_SetLstBTC() public {
        address oldLstBTC = address(lstBTCBridge.lstBTC());
        address newLstBTC = address(3004);

        vm.prank(govAddress);
        vm.expectEmit(true, true, false, false);
        emit LstBTCUpdated(oldLstBTC, newLstBTC);
        lstBTCBridge.setLstBTC(newLstBTC);
        assertEq(address(lstBTCBridge.lstBTC()), newLstBTC);
    }

    function test_SetLstBTC_SameAddress() public {
        address newLstBTC = address(3104);
        vm.prank(govAddress);
        lstBTCBridge.setLstBTC(newLstBTC);
        assertEq(address(lstBTCBridge.lstBTC()), newLstBTC);

        vm.prank(govAddress);
        lstBTCBridge.setLstBTC(newLstBTC);
        assertEq(address(lstBTCBridge.lstBTC()), newLstBTC);
    }

    function test_SetLstBTC_WhenZeroAddress() public {
        vm.prank(govAddress);
        lstBTCBridge.setLstBTC(address(0));

        assertEq(lstBTCBridge.lstBTC(), address(0));
    }

    // ============ submitTransactionProof() Tests ============
    function test_RevertWhen_NotRelayerSubmitTransactionProof() public {
        bytes memory rawTx = hex"0100000001";
        uint32 blockHeight = 800000;
        bytes memory fromPkScript = new bytes(0);
        bytes[] memory toPkScripts = new bytes[](1);
        toPkScripts[0] = OPERATIONS_BTC_ADDRESS;

        vm.prank(user1);
        vm.expectRevert();
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }


    function test_RevertWhen_EmptyToPkScripts() public {
        bytes memory rawTx = hex"0100000001";
        uint32 blockHeight = 800000;
        bytes memory fromPkScript = OUTBOUND_BTC_ADDRESS;
        bytes[] memory toPkScripts = new bytes[](0);

        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);

        vm.prank(relayer1);
        vm.expectRevert(LstBTCBridgeLogic.WhitelistedPkScriptNotFound.selector);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }

    function test_SubmitTransactionProof_TransferTypeUnknown_FromNotWhitelisted() public {
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, OPERATIONS_BTC_ADDRESS, 1e8, bytes(""), 0);

        mockCheckTxProof(txId, 90000, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            90000,
            new bytes32[](1),
            0,
            hex"0014999999999999999999999999999999999999",
            toPkScripts
        );
        assertEq(bitcoinTxStore.getOutputCount(txId), 1);

    }


    function test_SubmitTransactionProof_TransferTypeUnknown_ToNotWhitelisted() public {
        bytes memory unknownToAddress = hex"0014888888888888888888888888888888888888";

        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, unknownToAddress, 1e8, hex"", 0);

        mockCheckTxProof(txId, 90000, true);

        vm.prank(govAddress);
        lstBTCBridge.grantRole(ROLE_RELAYER, relayer1);

        vm.prank(relayer1);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            90000,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_SubmitTransactionProof_TransferTypeUnknown_InvalidCrossCustodian() public {
        _setupSecondCustodianGroup();
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, INBOUND_BTC_ADDRESS_GROUP2, 1e8, hex"", 0);

        mockCheckTxProof(txId, 90000, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            90000,
            new bytes32[](1),
            0,
            FIRST_TO_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_SubmitTransactionProof_TransferTypeUnknown() public {
        bytes memory unknownToAddress = hex"0014111111111111111111111111111111111111";

        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, unknownToAddress, 1e8, hex"", 0);

        mockCheckTxProof(txId, 90000, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            90000,
            new bytes32[](1),
            0,
            hex"0014000000000000000000000000000000000000",
            toPkScripts
        );
    }


    function test_RevertWhen_InvalidToPkScriptsCount() public {
        (bytes memory rawTx, bytes32 txId,) = buildBtcRawTx(outboundBtcUtxo, 0, OPERATIONS_BTC_ADDRESS, 1e8, bytes(""), 0);
        bytes[] memory toPkScripts = new bytes[](2);
        toPkScripts[0] = OPERATIONS_BTC_ADDRESS;
        toPkScripts[1] = OUTBOUND_BTC_ADDRESS;
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectRevert(bytes("PegRequestHelper: invalid toPkScripts"));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_RevertWhen_TooManyOutputs() public {
        BtcInput[] memory inputs = new BtcInput[](1);
        BtcOutput[] memory outputs = new BtcOutput[](3);
        inputs[0] = createInput(outboundBtcUtxo, FIRST_INPUT_INDEX);
        outputs[0] = createOutput(OPERATIONS_BTC_ADDRESS, 1e8);
        outputs[1] = createOutput(OUTBOUND_BTC_ADDRESS, 5e7);
        outputs[2] = createOutput(INBOUND_BTC_ADDRESS, 1e7);
        bytes memory rawTx = buildRawTxFlexible(inputs, outputs);
        bytes32 txId = BitcoinHelper.calculateTxId(rawTx);
        bytes[] memory toPkScripts = new bytes[](3);
        toPkScripts[0] = OPERATIONS_BTC_ADDRESS;
        toPkScripts[1] = OUTBOUND_BTC_ADDRESS;
        toPkScripts[2] = INBOUND_BTC_ADDRESS;
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectEmit(false, false, false, false);
        emit TransactionSubmitted(txId, blockHeight, 0);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_RevertWhen_InputsNotFromClaimedSource() public {
        bytes32 utxo0 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OUTBOUND_BTC_ADDRESS, 2e8, hex"", 0);
        bytes32 utxo1 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(utxo1, 0, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
        BtcInput[] memory inputs = new BtcInput[](2);
        inputs[0] = createInput(utxo0, 0);
        inputs[1] = createInput(utxo1, 0);
        BtcOutput[] memory outputs = new BtcOutput[](1);
        outputs[0] = createOutput(OPERATIONS_BTC_ADDRESS, 1e8);
        bytes memory rawTx2 = buildRawTxFlexible(inputs, outputs);
        bytes32 txId2 = BitcoinHelper.calculateTxId(rawTx2);
        mockCheckTxProof(txId2, blockHeight, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx2,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );

    }


    function test_RevertWhen_DuplicateOutputAddresses() public {
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, OPERATIONS_BTC_ADDRESS, 6e7, OPERATIONS_BTC_ADDRESS, 4e7);
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_RevertWhen_InvalidChangeAddress() public {
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, OPERATIONS_BTC_ADDRESS, 7e7, INBOUND_BTC_ADDRESS, 3e7);

        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_RevertWhen_ChangeOutputNotInTx() public {
        (bytes memory rawTx, bytes32 txId,) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, OPERATIONS_BTC_ADDRESS, 6e7, INBOUND_BTC_ADDRESS, 4e7);

        bytes[] memory toPkScripts = new bytes[](2);
        toPkScripts[0] = OPERATIONS_BTC_ADDRESS;
        toPkScripts[1] = OUTBOUND_BTC_ADDRESS;
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectRevert(bytes("PegRequestHelper: invalid output pkScript"));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_RevertWhen_MainOutputNotInTx() public {
        (bytes memory rawTx, bytes32 txId,) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, INBOUND_BTC_ADDRESS, 6e7, OUTBOUND_BTC_ADDRESS, 4e7);
        bytes[] memory toPkScripts = new bytes[](2);
        toPkScripts[0] = OPERATIONS_BTC_ADDRESS;
        toPkScripts[1] = OUTBOUND_BTC_ADDRESS;

        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectRevert(bytes("PegRequestHelper: invalid output pkScript"));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_RevertWhen_ZeroAmountOutput() public {
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, OPERATIONS_BTC_ADDRESS, 0, hex"", 0);
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);

        vm.prank(relayerAddress);
        vm.expectRevert(bytes("PegRequestHelper: invalid output pkScript"));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OUTBOUND_BTC_ADDRESS,
            toPkScripts
        );
    }


    function test_RevertWhen_DuplicateTransaction() public {
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 1e7);
        bytes memory fromPkScript = OUTBOUND_BTC_ADDRESS;
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        mockBTCBlockTimestamp(blockHeight, BTC_TX_TIMESTAMP);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );

        vm.prank(relayerAddress);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.DuplicateTransaction.selector, txId));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }

    // TransferType.PegInDeposited
    function test_SubmitTransactionProof_TransferTypePegInDeposited() public {
        uint64 amount = 10e8;
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, OPERATIONS_BTC_ADDRESS, amount, FIRST_TO_BTC_ADDRESS, amount / 2);
        bytes memory fromPkScript = FIRST_TO_BTC_ADDRESS;
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        mockBTCBlockTimestamp(blockHeight, BTC_TX_TIMESTAMP);
        vm.expectEmit(true, true, true, true);
        address[] memory recipients = new address[](2);
        recipients[0] = DEFAULT_PEG_IN_RECIPIENTS[0];
        recipients[1] = DEFAULT_PEG_IN_RECIPIENTS[1];
        uint64[] memory recipientAmounts = new uint64[](2);
        uint64 treasuryFee = amount * DEFAULT_PEG_IN_TREASURY_FEE_RATE / 10000;

        recipientAmounts[0] = treasuryFee * 6000 / 10000;
        recipientAmounts[1] = treasuryFee * 4000 / 10000;
        uint64 netAmount = amount - treasuryFee;
        emit PegInCreated(1, 10001, txId, fromPkScript, toPkScripts[0], 10e8, 1e8, recipients, recipientAmounts, netAmount);
        vm.prank(relayerAddress);
        vm.warp(BTC_TX_TIMESTAMP + 1000);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
        (
            uint64 amount1,
            uint64 treasuryFee1,
            uint64 transactionFee,
            uint64 netAmount1,
            uint64 depositedAt,
            PegStatus status,
            uint32 finalityHeight,
            uint32 custodianId,
            uint32 batchId
        ) = lstBTCBridge.pegInRequests(1);

        assertEq(amount1, 10e8);
        assertEq(treasuryFee1, treasuryFee);
        assertEq(transactionFee, 0);
        assertEq(netAmount1, netAmount);
        assertEq(depositedAt, BTC_TX_TIMESTAMP + 1000);
        assertEq(uint256(status), uint256(PegStatus.Pending));
        assertEq(finalityHeight, 90000 + DEFAULT_BITCOIN_CONFIRMATIONS);
        assertEq(custodianId, 10001);
        assertEq(batchId, 0);

    }

    function test_RevertWhen_DepositAmountBelowMinimum() public {
        uint64 minDepositAmount = 20e8; // 20 BTC
        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        configRegistry.setPegInDepositDustAmount(minDepositAmount);

        uint64 amount = 10e8;
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(
            outboundBtcUtxo,
            FIRST_INPUT_INDEX,
            OPERATIONS_BTC_ADDRESS,
            amount,
            OUTBOUND_BTC_ADDRESS,
            amount / 2
        );

        bytes memory fromPkScript = OUTBOUND_BTC_ADDRESS;
        uint32 blockHeight = 90000;

        mockCheckTxProof(txId, blockHeight, true);
        mockBTCBlockTimestamp(blockHeight, BTC_TX_TIMESTAMP);

        vm.prank(relayerAddress);
        vm.warp(BTC_TX_TIMESTAMP + 1000);
        vm.expectRevert(bytes("PegRequestHelper: low deposit amount"));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );

    }

    function test_RevertWhen_ExchangeRateIsZero() public {
        uint64 zeroExchangeRate = 0;
        uint8 decimals = 8;
        vm.mockCall(
            address(navProvider),
            abi.encodeWithSelector(navProvider.getExchangeRate.selector),
            abi.encode(zeroExchangeRate, decimals)
        );

        uint64 amount = 10e8;
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(
            outboundBtcUtxo,
            FIRST_INPUT_INDEX,
            OPERATIONS_BTC_ADDRESS,
            amount,
            FIRST_TO_BTC_ADDRESS,
            amount / 2
        );

        bytes memory fromPkScript = FIRST_TO_BTC_ADDRESS;
        uint32 blockHeight = 90000;

        mockCheckTxProof(txId, blockHeight, true);
        mockBTCBlockTimestamp(blockHeight, BTC_TX_TIMESTAMP);

        vm.prank(relayerAddress);
        vm.warp(BTC_TX_TIMESTAMP + 1000);
        vm.expectRevert(bytes("PegRequestHelper: exchange rate is zero"));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }

    function test_PegInWithZeroTreasuryFee() public {
        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        configRegistry.setPegInTreasuryFeeRate(0);

        bytes32 txId;
        bytes memory rawTx;
        {
            (rawTx, txId,) = buildBtcRawTx(
                outboundBtcUtxo,
                0,
                OPERATIONS_BTC_ADDRESS,
                10e8,
                OUTBOUND_BTC_ADDRESS,
                5e8
            );

            mockCheckTxProof(txId, 90000, true);
            mockBTCBlockTimestamp(90000, BTC_TX_TIMESTAMP);
        }

        uint64 netAmount = uint64(10e8) * 1e8 / 105000000;
        {
            address[] memory emptyRecipients = new address[](0);
            uint64[] memory emptyRecipientAmounts = new uint64[](0);
            vm.expectEmit(true, true, true, true);
            emit PegInCreated(
                1,
                10001,
                txId,
                FIRST_TO_BTC_ADDRESS,
                OPERATIONS_BTC_ADDRESS,
                10e8,
                105000000, // exchange rate
                emptyRecipients,
                emptyRecipientAmounts,
                netAmount // net amount = amount when no treasury fee
            );
        }
        uint64 exchangeRate = 105000000;
        uint8 decimals = 8;
        vm.mockCall(
            address(navProvider),
            abi.encodeWithSelector(navProvider.getExchangeRate.selector),
            abi.encode(exchangeRate, decimals)
        );
        {
            bytes[] memory toPkScripts = new bytes[](2);
            toPkScripts[0] = OPERATIONS_BTC_ADDRESS;
            toPkScripts[1] = FIRST_TO_BTC_ADDRESS;

            vm.prank(relayerAddress);
            vm.warp(BTC_TX_TIMESTAMP + 1000);
            lstBTCBridge.submitTransactionProof(
                rawTx,
                90000,
                merkleProof,
                blockIndex,
                FIRST_TO_BTC_ADDRESS,
                toPkScripts
            );
        }

        {
            (
                uint64 amount1,
                uint64 treasuryFee1,
                uint64 transactionFee,
                uint64 netAmount1,
                uint64 depositedAt,
                PegStatus status,
                uint32 finalityHeight,
                uint32 custodianId,
                uint32 batchId
            ) = lstBTCBridge.pegInRequests(1);

            assertEq(amount1, 10e8);
            assertEq(treasuryFee1, 0); // Treasury fee should be 0
            assertEq(transactionFee, 0);
            assertEq(netAmount1, netAmount); // Net amount = full amount when no treasury fee
            assertEq(depositedAt, BTC_TX_TIMESTAMP + 1000);
            assertEq(uint256(status), uint256(PegStatus.Pending));
            assertEq(finalityHeight, 90000 + DEFAULT_BITCOIN_CONFIRMATIONS);
            assertEq(custodianId, 10001);
            assertEq(batchId, 0);
        }
    }

    function test_PegInWithTreasuryFee() public {
        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        configRegistry.setPegInTreasuryFeeRate(500);

        bytes32 txId;
        bytes memory rawTx;
        {
            (rawTx, txId,) = buildBtcRawTx(
                outboundBtcUtxo,
                0,
                OPERATIONS_BTC_ADDRESS,
                10e8,
                OUTBOUND_BTC_ADDRESS,
                5e8
            );

            mockCheckTxProof(txId, 90000, true);
        }
        uint64 mintableAmount = uint64(10e8) * 1e8 / 12000000;
        uint64 expectedTreasuryFee = mintableAmount * 500 / 10000; // 5% fee
        uint64 expectedNetAmount = mintableAmount - expectedTreasuryFee;
        {
            address[] memory expectedRecipients = new address[](2);
            expectedRecipients[0] = DEFAULT_PEG_IN_RECIPIENTS[0];
            expectedRecipients[1] = DEFAULT_PEG_IN_RECIPIENTS[1];

            uint64[] memory expectedRecipientAmounts = new uint64[](2);
            expectedRecipientAmounts[0] = expectedTreasuryFee * 6000 / 10000;
            expectedRecipientAmounts[1] = expectedTreasuryFee * 4000 / 10000;

            vm.expectEmit(true, true, true, true);
            emit PegInCreated(
                1,
                10001,
                txId,
                FIRST_TO_BTC_ADDRESS,
                OPERATIONS_BTC_ADDRESS,
                10e8,
                12000000,
                expectedRecipients,
                expectedRecipientAmounts,
                expectedNetAmount
            );
        }
        uint64 exchangeRate = 12000000;
        uint8 decimals = 8;
        vm.mockCall(
            address(navProvider),
            abi.encodeWithSelector(navProvider.getExchangeRate.selector),
            abi.encode(exchangeRate, decimals)
        );

        {
            bytes[] memory toPkScripts = new bytes[](2);
            toPkScripts[0] = OPERATIONS_BTC_ADDRESS;
            toPkScripts[1] = FIRST_TO_BTC_ADDRESS;

            vm.prank(relayerAddress);
            vm.warp(BTC_TX_TIMESTAMP + 1000);
            lstBTCBridge.submitTransactionProof(
                rawTx,
                90000,
                merkleProof,
                blockIndex,
                FIRST_TO_BTC_ADDRESS,
                toPkScripts
            );
        }

        {
            (
                uint64 amount1,
                uint64 treasuryFee1,
                uint64 transactionFee,
                uint64 netAmount1,
                uint64 depositedAt,
                PegStatus status,
                uint32 finalityHeight,
                uint32 custodianId,
                uint32 batchId
            ) = lstBTCBridge.pegInRequests(1);

            assertEq(amount1, 10e8);
            assertEq(treasuryFee1, expectedTreasuryFee);
            assertEq(transactionFee, 0);
            assertEq(netAmount1, expectedNetAmount);
            assertEq(depositedAt, BTC_TX_TIMESTAMP + 1000);
            assertEq(uint256(status), uint256(PegStatus.Pending));
            assertEq(finalityHeight, 90000 + DEFAULT_BITCOIN_CONFIRMATIONS);
            assertEq(custodianId, 10001);
            assertEq(batchId, 0);
        }
    }

    function test_PegInCreated_TwoStep() public {
        bytes32 txId = submitBtcTx(outboundBtcUtxo, 0, OPERATIONS_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        (,,,,,PegStatus status,,,) = lstBTCBridge.pegInRequests(1);
        assertEq(uint256(status), uint256(PegStatus.Unknown));
        (uint16 outputCount) = bitcoinTxStore.getOutputCount(txId);
        assertEq(outputCount, 1);
        (uint16 inputCount) = bitcoinTxStore.getInputCount(txId);
        assertEq(inputCount, 1);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegInRequests(1);
        assertEq(uint256(status2), uint256(PegStatus.Pending));
    }

    //  TransferType.PegInRefunded
    function test_SubmitTransactionProof_TransferTypePegInRefunded() public {
        bytes32 txId = _setupPegIn();
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](0);
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
        (bytes memory rawTx, bytes32 txId1, bytes[] memory toPkScripts) = buildBtcRawTx(txId, 0, OUTBOUND_BTC_ADDRESS, 10e8, hex"", 0);
        bytes memory fromPkScript = OPERATIONS_BTC_ADDRESS;
        uint32 blockHeight = 90001;
        mockCheckTxProof(txId1, blockHeight, true);
        (,,,,,PegStatus beforeStatus,,,) = lstBTCBridge.pegInRequests(1);
        assertEq(uint256(beforeStatus), uint256(PegStatus.PendingRefund));
        vm.prank(relayerAddress);
        vm.expectEmit(true, true, true, true);
        uint256[] memory settledRequestIds = new uint256[](1);
        settledRequestIds[0] = 1;
        emit PegInBatchRefunded(1, txId1, settledRequestIds, 10e8, true);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
        (,,,,,PegStatus afterStatus,,,) = lstBTCBridge.pegInRequests(1);
        assertEq(uint256(afterStatus), uint256(PegStatus.Refunded));
        (bool isPegInSettled,) = lstBTCBridge.batches(1);
        assertEq(isPegInSettled, true);
    }

    function test_RevertWhen_PegInRefunded_BatchNotFound() public {
        bytes32 operationsBtcUtxo = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        (bytes memory rawTx, bytes32 txId1, bytes[] memory toPkScripts) = buildBtcRawTx(operationsBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, 1e8, hex"", 0);
        bytes memory fromPkScript = OPERATIONS_BTC_ADDRESS;
        uint32 blockHeight = 90001;
        mockCheckTxProof(txId1, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.BatchNotFound.selector, 10001));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }

    function test_RevertWhen_PegInRefunded_NoPegInToSettle() public {
        bytes32 txId = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](0);

        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (bytes memory rawTx1, bytes32 txId1, bytes[] memory toPkScripts1) = buildBtcRawTx(txId, 0, OUTBOUND_BTC_ADDRESS, 10e8, hex"", 0);
        bytes memory fromPkScript = OPERATIONS_BTC_ADDRESS;
        uint32 blockHeight = 90001;

        mockCheckTxProof(txId1, blockHeight, true);

        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx1,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts1
        );

        (bool isPegInSettled,) = lstBTCBridge.batches(1);
        assertEq(isPegInSettled, true);
        (bytes memory refundRawTx, bytes32 refundTxId, bytes[] memory toPkScripts2) = buildBtcRawTx(txId, 0, OUTBOUND_BTC_ADDRESS, 1e8, hex"", 0);
        uint32 blockHeight2 = 90002;
        mockCheckTxProof(refundTxId, blockHeight2, true);
        vm.prank(relayerAddress);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.NoPegInToSettle.selector, 10001, 1));
        lstBTCBridge.submitTransactionProof(
            refundRawTx,
            blockHeight2,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts2
        );
    }

    function test_RevertWhen_PegInRefunded_InvalidSettlementAmount() public {
        bytes32 txId = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](0);
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
        (bytes memory rawTx, bytes32 txId1, bytes[] memory toPkScripts) = buildBtcRawTx(txId, 0, OUTBOUND_BTC_ADDRESS, 5e8, hex"", 0);
        bytes memory fromPkScript = OPERATIONS_BTC_ADDRESS;
        uint32 blockHeight = 90001;

        mockCheckTxProof(txId1, blockHeight, true);

        vm.prank(relayerAddress);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.InvalidSettlementAmount.selector, 10001, 1, 10e8, 5e8));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }

    function test_PegInRefunded_MultipleRequests() public {
        bytes32 txId1 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0); // requestId = 1
        bytes32 txId2 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 15e8, OUTBOUND_BTC_ADDRESS, 1e8);
        bytes32 txId3 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 8e8, OPERATIONS_BTC_ADDRESS, 15e8);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegInRequests(2);
        assertEq(uint256(status2), uint256(PegStatus.Pending));

        uint256[] memory pegInIds = new uint256[](2);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        uint256[] memory pegOutIds = new uint256[](0);

        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (,,,,,PegStatus status1After,,,) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus status2After,,,) = lstBTCBridge.pegInRequests(2);
        assertEq(uint256(status1After), uint256(PegStatus.PendingRefund));
        assertEq(uint256(status2After), uint256(PegStatus.PendingRefund));
        BtcInput[] memory inputs = new BtcInput[](2);
        inputs[0] = createInput(txId1, 0);
        inputs[1] = createInput(txId3, 1);
        BtcOutput[] memory outputs = new BtcOutput[](1);
        outputs[0] = createOutput(OUTBOUND_BTC_ADDRESS, 25e8);
        bytes memory rawTxRefund = buildRawTxFlexible(inputs, outputs);
        bytes32 txIdRefund = BitcoinHelper.calculateTxId(rawTxRefund);
        bytes memory fromPkScriptRefund = OPERATIONS_BTC_ADDRESS;
        bytes[] memory toPkScriptsRefund = new bytes[](1);
        toPkScriptsRefund[0] = OUTBOUND_BTC_ADDRESS;
        uint32 blockHeightRefund = 90001;
        mockCheckTxProof(txIdRefund, blockHeightRefund, true);
        vm.prank(address(lstBTCBridge));
        bitcoinTxStore.verifyAndStoreTransaction(rawTxRefund, blockHeightRefund, merkleProof, blockIndex);
        vm.prank(relayerAddress);
        vm.expectEmit(true, true, true, true);
        uint256[] memory settledRequestIds = new uint256[](2);
        settledRequestIds[0] = 1;
        settledRequestIds[1] = 2;
        emit PegInBatchRefunded(1, txIdRefund, settledRequestIds, 25e8, true);

        lstBTCBridge.submitTransactionProof(
            rawTxRefund,
            blockHeightRefund,
            merkleProof,
            blockIndex,
            fromPkScriptRefund,
            toPkScriptsRefund
        );

        (,,,,,PegStatus finalStatus1,,,) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus finalStatus2,,,) = lstBTCBridge.pegInRequests(2);
        assertEq(uint256(finalStatus1), uint256(PegStatus.Refunded));
        assertEq(uint256(finalStatus2), uint256(PegStatus.Refunded));

        (bool isPegInSettled,) = lstBTCBridge.batches(1);
        assertEq(isPegInSettled, true);
    }

    function test_PegInRefunded_wrongRequestStatus() public {
        bytes32 txId = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 10e8);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 2;
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
        (bytes memory rawTx, bytes32 txId1, bytes[] memory toPkScripts) = buildBtcRawTx(txId, 0, INBOUND_BTC_ADDRESS, 10e8, hex"", 0);
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId1, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectRevert("PegRequestHelper: mismatch request status");
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OPERATIONS_BTC_ADDRESS,
            toPkScripts
        );
    }
    //  TransferType.PegOutPaid
    function test_SubmitTransactionProof_TransferTypePegOutPaid() public {
        uint256 mint_amount = 10e8;
        bytes32 txId = _setupPegIn();
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](0);
        mockGetChainTipHeight(90010);
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
        uint256 balance = lstBTC.balanceOf(operationsNativeAddress);
        uint256 treasuryFee = mint_amount * DEFAULT_PEG_IN_TREASURY_FEE_RATE / 10000;
        uint256 netAmount = mint_amount - treasuryFee;
        assertEq(balance, netAmount);
        uint256 mintedAmount = lstBTC.totalSupply();
        assertEq(mintedAmount, mint_amount);
        vm.prank(operationsNativeAddress);
        lstBTC.transfer(inboundNativeAddress, netAmount);
        vm.prank(inboundNativeAddress);
        lstBTC.transfer(user1, netAmount);
        vm.prank(user1);
        lstBTC.transfer(outboundNativeAddress, netAmount);
        vm.prank(outboundNativeAddress);
        lstBTC.transfer(operationsNativeAddress, 2e8);
        uint256[] memory pegInIds1 = new uint256[](0);
        uint256[] memory pegOutIds1 = new uint256[](1);
        pegOutIds1[0] = 2;
        vm.roll(14);
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 2e8);
        (,,,,,PegStatus status,,,) = lstBTCBridge.pegOutRequests(2);
        vm.prank(operationsNativeAddress);
        assertEq(uint256(status), uint256(PegStatus.Pending));
        lstBTCBridge.processPegRequestBatch(pegInIds1, pegOutIds1);
        (bytes memory rawTx, bytes32 txId1, bytes[] memory toPkScripts) = buildBtcRawTx(txId, 0, INBOUND_BTC_ADDRESS, 2e8 - 2e6 - 1000, hex"", 0);
        bytes memory fromPkScript = OPERATIONS_BTC_ADDRESS;
        uint32 blockHeight = 90001;
        (,,,,,PegStatus beforeStatus,,,) = lstBTCBridge.pegOutRequests(2);
        assertEq(uint256(beforeStatus), uint256(PegStatus.PendingPayout));
        mockCheckTxProof(txId1, blockHeight, true);
        vm.expectEmit(true, true, true, true);
        uint256[] memory settledRequestIds = new uint256[](1);
        settledRequestIds[0] = 2;
        uint64 actualPaidAmount = 2e8 - 2e6 - 1000;
        emit PegOutBatchPaid(2, txId1, settledRequestIds, actualPaidAmount, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
        (,,,,,PegStatus afterStatus,,,) = lstBTCBridge.pegOutRequests(2);
        assertEq(uint256(afterStatus), uint256(PegStatus.Paid));
    }

    function test_RevertWhen_PegOutPaid_BatchNotFound() public {
        bytes32 operationsUtxo = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        (bytes memory rawTx, bytes32 txId1, bytes[] memory toPkScripts) = buildBtcRawTx(operationsUtxo, 0, OUTBOUND_BTC_ADDRESS, 1e8, hex"", 0);
        uint32 blockHeight = 90001;
        mockCheckTxProof(txId1, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.BatchNotFound.selector, 10001));
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            OPERATIONS_BTC_ADDRESS,
            toPkScripts
        );
    }

    function test_RevertWhen_PegOutPaid_WrongRequestStatus() public {
        bytes32 txId = submitBtcTx(bytes32('utxo'), 0, OPERATIONS_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        bytes32 txId1 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(address(outboundNativeAddress), 1e8);
        lstBTC.mint(address(operationsNativeAddress), 1e8);
        lstBTC.mint(address(inboundNativeAddress), 1e8);
        vm.stopPrank();
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 2e8);
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(1e8);
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](1);
        pegInIds[0] = 1;
        pegOutIds[0] = 2;
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
        (bytes memory rawTx, bytes32 txId2, bytes[] memory toPkScripts) = buildBtcRawTx(txId1, 0, OUTBOUND_BTC_ADDRESS, 1e8, hex"", 0);
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId2, blockHeight, true);
        vm.prank(relayerAddress);
        vm.expectRevert("PegRequestHelper: mismatch request status");
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0,
            OPERATIONS_BTC_ADDRESS,
            toPkScripts
        );

    }

    function test_RevertWhen_PegOutPaid_NoPegOutToSettle() public {
        bytes32 txId = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        uint64 mintAmount = 2e8;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(outboundNativeAddress, mintAmount);
        navProvider.increasePeggedBTC(mintAmount);
        vm.stopPrank();
        vm.prank(outboundNativeAddress);
        lstBTC.transfer(operationsNativeAddress, mintAmount);
        vm.roll(14);
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), mintAmount);
        uint256[] memory pegInIds1 = new uint256[](1);
        uint256[] memory pegOutIds1 = new uint256[](1);
        pegInIds1[0] = 1;
        pegOutIds1[0] = 2;
        vm.prank(operationsNativeAddress);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds1, pegOutIds1);

        (bytes memory rawTx1, bytes32 txId1, bytes[] memory toPkScripts1) = buildBtcRawTx(
        txId,
        0,
        INBOUND_BTC_ADDRESS,
        2e8 - 2e6 - 1000,
        hex"",
        0
        );
        uint32 blockHeight1 = 90001;
        mockCheckTxProof(txId1, blockHeight1, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx1,
            blockHeight1,
            merkleProof,
            blockIndex,
            OPERATIONS_BTC_ADDRESS,
            toPkScripts1
        );

        (bytes memory rawTx2, bytes32 txId2, bytes[] memory toPkScripts2) = buildBtcRawTx(
        txId,
        0,
        INBOUND_BTC_ADDRESS,
        2e8,
        hex"",
        0
        );
        mockCheckTxProof(txId2, blockHeight1, true);
        uint32 custodianId = 10001;
        uint32 batchId = 1;
        vm.expectRevert(abi.encodeWithSignature("NoPegOutToSettle(uint32,uint32)", custodianId, batchId));
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx2,
            blockHeight1,
            merkleProof,
            blockIndex,
            OPERATIONS_BTC_ADDRESS,
            toPkScripts2
        );
    }

    function test_RevertWhen_PegOutPaid_InvalidSettlementAmount() public {
        bytes32 txId = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        uint64 mintAmount = 2e8;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(outboundNativeAddress, mintAmount);
        navProvider.increasePeggedBTC(mintAmount);
        vm.stopPrank();
        vm.prank(outboundNativeAddress);
        lstBTC.transfer(operationsNativeAddress, mintAmount);
        vm.roll(14);
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), mintAmount);
        uint256[] memory pegInIds1 = new uint256[](0);
        uint256[] memory pegOutIds1 = new uint256[](1);
        pegOutIds1[0] = 2;
        vm.prank(operationsNativeAddress);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds1, pegOutIds1);
        uint64 wrongAmount = 2e8 + 1e6;
        (bytes memory rawTx, bytes32 txId1, bytes[] memory toPkScripts) = buildBtcRawTx(
        txId,
        0,
        INBOUND_BTC_ADDRESS,
        wrongAmount,
        hex"",
        0
        );
        bytes memory fromPkScript = OPERATIONS_BTC_ADDRESS;
        uint32 blockHeight = 90001;
        mockCheckTxProof(txId1, blockHeight, true);

        uint32 custodianId = 10001;
        uint32 batchId = 1;
        vm.expectRevert(abi.encodeWithSignature("InvalidSettlementAmount(uint32,uint32,uint64,uint64)", custodianId, batchId, 2e8 - 2e6 - 1000, wrongAmount));
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }

    function test_MultipleRequests_PegOutPaid() public {
        bytes32 txId = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);
        bytes32 txId2 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OPERATIONS_BTC_ADDRESS, 10e8);
        uint64 mintAmount = 2e8;
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(outboundNativeAddress, mintAmount);
        navProvider.increasePeggedBTC(mintAmount);
        vm.stopPrank();

        vm.startPrank(outboundNativeAddress);
        lstBTC.transfer(operationsNativeAddress, 1e7);
        lstBTC.transfer(operationsNativeAddress, 2e7);
        lstBTC.transfer(operationsNativeAddress, 3e7);
        vm.stopPrank();
        uint256[] memory pegInIds1 = new uint256[](0);
        uint256[] memory pegOutIds1 = new uint256[](3);
        pegOutIds1[0] = 2;
        pegOutIds1[1] = 3;
        pegOutIds1[2] = 4;
        vm.roll(14);
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 10e8);
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds1, pegOutIds1);

        (,,,uint64 netAmount1,,,,,) = lstBTCBridge.pegOutRequests(2);
        (,,,uint64 netAmount2,,,,,) = lstBTCBridge.pegOutRequests(3);
        (,,,uint64 netAmount3,,,,,) = lstBTCBridge.pegOutRequests(4);
        uint64 totalNetAmount = netAmount1 + netAmount2 + netAmount3;

        BtcInput[] memory inputs = new BtcInput[](2);
        inputs[0] = createInput(txId, 0);
        inputs[1] = createInput(txId2, 1);
        BtcOutput[] memory outputs = new BtcOutput[](2);
        outputs[0] = createOutput(INBOUND_BTC_ADDRESS, totalNetAmount - netAmount3);
        outputs[1] = createOutput(OPERATIONS_BTC_ADDRESS, 1e8);
        bytes[] memory toPkScripts = new bytes[](2);
        toPkScripts[0] = INBOUND_BTC_ADDRESS;
        toPkScripts[1] = OPERATIONS_BTC_ADDRESS;
        bytes memory rawTxError = buildRawTxFlexible(inputs, outputs);
        bytes32 txIdPayError = BitcoinHelper.calculateTxId(rawTxError);
        uint32 blockHeightError = 90001;
        mockCheckTxProof(txIdPayError, blockHeightError, true);
        vm.prank(relayerAddress);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.InvalidSettlementAmount.selector, 10001, 1, totalNetAmount, totalNetAmount - netAmount3));
        lstBTCBridge.submitTransactionProof(
            rawTxError,
            blockHeightError,
            merkleProof,
            blockIndex,
            OPERATIONS_BTC_ADDRESS,
            toPkScripts
        );
        outputs[0] = createOutput(INBOUND_BTC_ADDRESS, totalNetAmount);
        bytes memory rawTx = buildRawTxFlexible(inputs, outputs);
        bytes32 txIdPay = BitcoinHelper.calculateTxId(rawTx);
        uint32 blockHeight = 90001;
        mockCheckTxProof(txIdPay, blockHeight, true);
        vm.expectEmit(true, true, true, true);
        uint256[] memory settledRequestIds = new uint256[](3);
        settledRequestIds[0] = 2;
        settledRequestIds[1] = 3;
        settledRequestIds[2] = 4;
        emit PegOutBatchPaid(1, txIdPay, settledRequestIds, totalNetAmount, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            OPERATIONS_BTC_ADDRESS,
            toPkScripts
        );

        (,,,,,PegStatus status1,,,) = lstBTCBridge.pegOutRequests(2);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegOutRequests(3);
        assertEq(uint256(status1), uint256(PegStatus.Paid));
        assertEq(uint256(status2), uint256(PegStatus.Paid));

        (, bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertEq(isPegOutSettled, true);
    }

    //  TransferType.YieldReceived
    function test_SubmitTransactionProof_TransferTypeYieldReceived() public {
        uint64 mintAmount = 2e8;
        vm.prank(address(lstBTCBridge));
        lstBTC.mint(address(lstBTCBridge), mintAmount);
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(mintAmount);
        bytes32 yieldTxId = _transferBTCToScript(YIELD_BTC_ADDRESS);
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(yieldTxId, 0, OPERATIONS_BTC_ADDRESS, 1e7, hex"", 0);

        bytes memory fromPkScript = YIELD_BTC_ADDRESS;

        uint32 blockHeight = 90001;

        mockCheckTxProof(txId, blockHeight, true);
        vm.expectEmit(true, true, true, true);
        emit YieldReceived(10001, txId, 1e7, 1e7);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
        (,uint64 exchangeRate, uint8 decimals) = navProvider.getLatestExchangeRate();
        assertEq(exchangeRate, 105000000);
        assertEq(decimals, 8);
    }
    //  TransferType.Borrowed
    function test_SubmitTransactionProof_TransferTypeBorrowed() public {
        bytes32 borrowTxId = _transferBTCToScript(BORROW_BTC_ADDRESS);
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(borrowTxId, 0, OPERATIONS_BTC_ADDRESS, 2e7, hex"", 0);
        bytes memory fromPkScript = BORROW_BTC_ADDRESS;
        uint32 blockHeight = 90001;

        mockCheckTxProof(txId, blockHeight, true);
        uint32 custodianId = 10001;
        uint64 debtBefore = lstBTCBridge.getCustodianDebt(custodianId);
        assertEq(debtBefore, 0);
        vm.prank(relayerAddress);
        vm.expectEmit(true, true, true, true);
        emit Borrowed(custodianId, txId, 2e7, 2e7, 2e7);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );

        uint64 debtAfter = lstBTCBridge.getCustodianDebt(custodianId);
        assertEq(debtAfter, debtBefore + 2e7);
    }

    //  TransferType.Repaid
    function test_SubmitTransactionProof_TransferTypeRepaid() public {
        bytes32 operationsInputTxId = _setupDebtScenario();

        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(operationsInputTxId, 0, REPAYMENT_BTC_ADDRESS, 1e6, hex"", 0);

        bytes memory fromPkScript = OPERATIONS_BTC_ADDRESS;

        uint32 blockHeight = 90001;

        mockCheckTxProof(txId, blockHeight, true);
        uint32 custodianId = 10001;
        uint64 debtBefore = lstBTCBridge.getCustodianDebt(custodianId);
        assertEq(debtBefore, 2e7);
        vm.expectEmit(true, true, true, true);
        emit Repaid(custodianId, txId, 1e6, 2e7 - 1e6, 2e7 - 1e6);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );

        uint64 debtAfter = lstBTCBridge.getCustodianDebt(custodianId);
        assertEq(debtAfter, debtBefore - 1e6);
    }

    function test_RevertWhenRepayAmountExceedsDebt() public {
        bytes32 operationsInputTxId = _setupDebtScenario();

        uint32 custodianId = 10001;
        uint64 currentDebt = lstBTCBridge.getCustodianDebt(custodianId);
        assertEq(currentDebt, 2e7);

        uint64 repayAmount = currentDebt + 1e6;

        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(
        operationsInputTxId,
        0,
        REPAYMENT_BTC_ADDRESS,
        repayAmount,
        hex"",
        0
        );
        bytes memory fromPkScript = OPERATIONS_BTC_ADDRESS;
        uint32 blockHeight = 90001;

        mockCheckTxProof(txId, blockHeight, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                LstBTCBridgeLogic.RepaymentAmountExceeds.selector,
                custodianId,
                repayAmount,
                currentDebt
            )
        );
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
    }

    // ============ onLstBTCTransfer() Tests ============


    function test_onLstBTCTransfer_FromAddressNotWhitelisted() public {
        address nonWhitelistedFrom = makeAddr("nonWhitelistedFrom");
        address validTo = outboundNativeAddress;
        uint64 amount = 1e8;

        vm.recordLogs();
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(nonWhitelistedFrom, validTo, amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(validTo, nonWhitelistedFrom, amount);
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }


    function test_onLstBTCTransfer_ToAddressNotWhitelisted() public {
        address validFrom = outboundNativeAddress;
        address nonWhitelistedTo = makeAddr("nonWhitelistedTo");
        uint64 amount = 1e8;

        vm.recordLogs();
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(validFrom, nonWhitelistedTo, amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_onLstBTCTransfer_BothAddressesNotWhitelisted() public {
        address nonWhitelistedFrom = makeAddr("nonWhitelistedFrom");
        address nonWhitelistedTo = makeAddr("nonWhitelistedTo");
        uint64 amount = 1e8;

        vm.recordLogs();
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(nonWhitelistedFrom, nonWhitelistedTo, amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_onLstBTCTransfer_CrossCustodianTransfer() public {
        address fromAddress = outboundNativeAddress;  // Group 1
        address toAddress = operationsNativeAddress;   // Group 1
        address group2Outbound = makeAddr("group2Outbound");
        address group2Operations = makeAddr("group2Operations");
        bytes[] memory rawAddresses = new bytes[](2);
        rawAddresses[0] = abi.encodePacked(group2Outbound);
        rawAddresses[1] = abi.encodePacked(group2Operations);
        uint8[] memory formats = new uint8[](2);
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        uint8[] memory usages = new uint8[](2);
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.OPERATIONS;

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        address group2From = group2Outbound;
        address group1To = operationsNativeAddress;
        uint64 amount = 1e8;
        vm.recordLogs();
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(group2From, group1To, amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_onLstBTCTransfer_InvalidAddressUsageCombination() public {
        address fromAddress = inboundNativeAddress;    // INBOUND usage
        address toAddress = outboundNativeAddress;     // OUTBOUND usage
        uint64 amount = 1e8;
        vm.recordLogs();
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    // PegOutDeposited
    function test_PegOutDeposited_Success() public {
        address fromAddress = outboundNativeAddress;   // OUTBOUND usage
        address toAddress = operationsNativeAddress;   // OPERATIONS usage
        uint64 amount = 1e8;
        uint64 netAmount = amount - amount * 100 / 10000 - DEFAULT_PEG_OUT_TRANSACTION_FEE;
        uint64[] memory recipientAmounts = new uint64[](2);
        recipientAmounts[0] = 7e5;
        recipientAmounts[1] = 3e5;
        vm.prank(address(lstBTC));
        vm.expectEmit(true, true, true, true);
        emit PegOutCreated(1, 10001, fromAddress, toAddress, amount, 1e8, DEFAULT_PEG_OUT_RECIPIENTS, recipientAmounts, netAmount);
        vm.warp(BTC_TX_TIMESTAMP);
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);
        (
            uint64 amount1,
            uint64 treasuryFee1,
            uint64 transactionFee,
            uint64 netAmount1,
            uint64 depositedAt,
            PegStatus status,
            uint32 finalityHeight,
            uint32 custodianId,
            uint32 batchId
        ) = lstBTCBridge.pegOutRequests(1);
        assertEq(amount1, 1e8);
        assertEq(treasuryFee1, 1e6);
        assertEq(transactionFee, 1000);
        assertEq(netAmount1, netAmount);
        assertEq(depositedAt, BTC_TX_TIMESTAMP);
        assertEq(uint256(status), uint256(PegStatus.Pending));
        assertEq(finalityHeight, 13);
        assertEq(custodianId, 10001);
        assertEq(batchId, 0);
    }

    function test_RevertWhen_PegOutDeposited_ExchangeRateZero() public {
        vm.mockCall(
            address(navProvider),
            abi.encodeWithSelector(navProvider.getExchangeRate.selector),
            abi.encode(0, 8)
        );

        address fromAddress = outboundNativeAddress;
        address toAddress = operationsNativeAddress;
        uint64 amount = 1e8;
        vm.expectRevert("PegRequestHelper: exchange rate is zero");
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);
    }

    function test_PegOutDeposited_ZeroTreasuryFee() public {
        vm.warp(BTC_TX_TIMESTAMP + 1000);
        vm.startPrank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(0);
        vm.stopPrank();

        address fromAddress = outboundNativeAddress;
        address toAddress = operationsNativeAddress;
        uint64 amount = 1e8;
        uint64 netAmount = amount - DEFAULT_PEG_OUT_TRANSACTION_FEE;

        address[] memory emptyRecipients = new address[](0);
        uint64[] memory emptyAmounts = new uint64[](0);

        vm.expectEmit(true, true, true, true);
        emit PegOutCreated(1, 10001, fromAddress, toAddress, amount, 1e8, emptyRecipients, emptyAmounts, netAmount);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);

        (,uint64 treasuryFee, uint64 transactionFee, uint64 netAmount1,,,,,) = lstBTCBridge.pegOutRequests(1);

        assertEq(treasuryFee, 0);
        assertEq(transactionFee, DEFAULT_PEG_OUT_TRANSACTION_FEE);
        assertEq(netAmount1, netAmount);
    }

    function test_RevertWhen_PegOutDeposited_LowRedeemAmount() public {
        address fromAddress = outboundNativeAddress;
        address toAddress = operationsNativeAddress;
        uint64 amount = DEFAULT_PEG_OUT_REDEEM_DUST_AMOUNT - 1;
        vm.expectRevert("PegRequestHelper: low redeem amount");
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);
    }

    function test_PegOutDeposited_MinimumRedeemAmount() public {
        address fromAddress = outboundNativeAddress;
        address toAddress = operationsNativeAddress;

        uint64 amount = 8100;

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);

        (uint64 amount1, uint64 treasuryFee1, uint64 transactionFee, uint64 netAmount1,,,,,) = lstBTCBridge.pegOutRequests(1);
        assertEq(amount1, amount);
        assertGt(treasuryFee1, 0);
        assertEq(transactionFee, DEFAULT_PEG_OUT_TRANSACTION_FEE);
        assertGt(netAmount1, 0);
    }

    function test_PegOutDeposited_DifferentExchangeRate() public {
        vm.mockCall(
            address(navProvider),
            abi.encodeWithSelector(navProvider.getExchangeRate.selector),
            abi.encode(2e8, 8)
        );

        address fromAddress = outboundNativeAddress;
        address toAddress = operationsNativeAddress;
        uint64 amount = 1e8;
        uint64 treasuryFee = amount * 100 / 10000; // 1%
        uint64 burnAmount = amount - treasuryFee;
        uint64 redeemableAmount = burnAmount * 2;
        uint64 netAmount = redeemableAmount - DEFAULT_PEG_OUT_TRANSACTION_FEE;

        uint64[] memory recipientAmounts = new uint64[](2);
        recipientAmounts[0] = treasuryFee * 7000 / 10000;
        recipientAmounts[1] = treasuryFee * 3000 / 10000;

        vm.expectEmit(true, true, true, true);
        emit PegOutCreated(1, 10001, fromAddress, toAddress, amount, 2e8, DEFAULT_PEG_OUT_RECIPIENTS, recipientAmounts, netAmount);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);

        (uint64 amount1, uint64 treasuryFee1, uint64 transactionFee, uint64 netAmount1,,,,,) = lstBTCBridge.pegOutRequests(1);
        assertEq(amount1, amount);
        assertEq(treasuryFee1, treasuryFee);
        assertEq(transactionFee, DEFAULT_PEG_OUT_TRANSACTION_FEE);
        assertEq(netAmount1, netAmount);
    }

    // PegOutRefunded
    function test_onLstBTCTransfer_Success_PegOutRefunded() public {
        uint64 amount = 1e8;
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, amount);
        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        vm.prank(address(lstBTC));
        vm.expectEmit(true, true, true, true);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 1;
        emit PegOutBatchRefunded(1, requestIds, amount, true);
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, amount);
        (
            uint64 amount1,
            uint64 treasuryFee1,
            uint64 transactionFee,
            uint64 netAmount,
            uint64 depositedAt,
            PegStatus status,
            uint32 finalityHeight,
            uint32 custodianId,
            uint32 batchId
        ) = lstBTCBridge.pegOutRequests(1);
        assertEq(amount1, amount);
        assertEq(treasuryFee1, 1e6);
        assertEq(transactionFee, 1000);
        assertEq(netAmount, netAmount);
        assertEq(depositedAt, INIT_ADD_CONFIG_TIMESTAMP);
        assertEq(uint256(status), uint256(PegStatus.Refunded));
    }

    function test_RevertWhen_PegOutRefunded_BatchNotFound() public {
        address fromAddress = operationsNativeAddress; // OPERATIONS usage
        address toAddress = outboundNativeAddress;     // OUTBOUND usage
        uint64 amount = 1e8;

        vm.expectRevert(
            abi.encodeWithSelector(
                LstBTCBridgeLogic.BatchNotFound.selector,
                10001 // custodianId
            )
        );
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);
    }

    function test_RevertWhen_PegOutRefunded_AlreadySettled() public {
        uint64 amount = 1e8;
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, amount);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                LstBTCBridgeLogic.NoPegOutToSettle.selector,
                10001, // custodianId
                1      // batchId
            )
        );
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, amount);
    }

    function test_RevertWhen_PegOutRefunded_InvalidSettlementAmount() public {
        uint64 amount = 1e8;
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, amount);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        uint64 wrongAmount = amount + 1e6;

        vm.expectRevert(
            abi.encodeWithSelector(
                LstBTCBridgeLogic.InvalidSettlementAmount.selector,
                10001,
                1,
                amount,
                wrongAmount
            )
        );
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, wrongAmount);
    }

    function test_PegOutRefunded_MultipleRequestsSuccess() public {
        bytes32 txId = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        uint64 amount1 = 1e8;
        uint64 amount2 = 2e8;
        uint64 totalAmount = amount1 + amount2;

        vm.startPrank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, amount1);
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, amount2);
        vm.stopPrank();

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](2);
        pegInIds[0] = 1;
        pegOutIds[0] = 2;
        pegOutIds[1] = 3;
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        vm.expectEmit(true, true, true, true);
        emit PegOutBatchRefunded(1, pegOutIds, totalAmount, false);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, totalAmount);

        (,,,,,PegStatus status1,,,) = lstBTCBridge.pegOutRequests(2);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegOutRequests(3);
        assertEq(uint256(status1), uint256(PegStatus.Refunded));
        assertEq(uint256(status2), uint256(PegStatus.Refunded));

        (bool isPegInSettled,bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertFalse(isPegInSettled);
        assertTrue(isPegOutSettled);

        submitBtcTx(txId, 0, OPERATIONS_BTC_ADDRESS, OUTBOUND_BTC_ADDRESS, 1e8, hex"", 0);

        (bool isPegInSettled1,bool isPegOutSettled1) = lstBTCBridge.batches(1);
        assertTrue(isPegInSettled1);
        assertTrue(isPegOutSettled1);
    }

    function test_RevertWhen_PegOutRefunded_WrongRequestStatus() public {
        uint64 amount = 1e7;
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, amount);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;

        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(address(outboundNativeAddress), amount);
        lstBTC.mint(address(operationsNativeAddress), amount);
        lstBTC.mint(address(inboundNativeAddress), amount);
        vm.stopPrank();
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 2e8);
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(amount);
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
        vm.expectRevert("PegRequestHelper: mismatch request status");
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, 1e7);
    }

    // PegInPaid
    function test_onLstBTCTransfer_Success_PegInPaid() public {
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(200000000, 8));
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](0);
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
        uint64 amount = 1e8;
        vm.prank(address(lstBTC));
        uint64 payAmount = amount / 2 - (amount / 2 * 50 / 10000);
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, payAmount);
        (
            uint64 amount1,
            uint64 treasuryFee1,
            uint64 transactionFee,
            uint64 netAmount,
            uint64 depositedAt,
            PegStatus status,
            uint32 finalityHeight,
            uint32 custodianId,
            uint32 batchId
        ) = lstBTCBridge.pegInRequests(1);
        assertEq(amount1, 1e8);
        assertEq(treasuryFee1, 250000);
        assertEq(transactionFee, 0);
        assertEq(netAmount, payAmount);
        assertEq(depositedAt, INIT_ADD_CONFIG_TIMESTAMP);
        assertEq(uint256(status), uint256(PegStatus.Paid));
        assertEq(custodianId, 10001);
        assertEq(batchId, 1);
    }

    function test_RevertWhen_PegInPaid_BatchNotFound() public {
        address fromAddress = operationsNativeAddress; // OPERATIONS usage
        address toAddress = inboundNativeAddress;      // INBOUND usage
        uint64 amount = 1e8;

        vm.expectRevert(
            abi.encodeWithSelector(
                LstBTCBridgeLogic.BatchNotFound.selector,
                10001 // custodianId
            )
        );
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(fromAddress, toAddress, amount);
    }

    function test_RevertWhen_PegInPaid_AlreadySettled() public {
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(200000000, 8));
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](0);
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        uint64 amount = 1e8;
        uint64 payAmount = amount / 2 - (amount / 2 * 50 / 10000);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, payAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                LstBTCBridgeLogic.NoPegInToSettle.selector,
                10001, // custodianId
                1      // batchId
            )
        );
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, payAmount);
    }

    function test_RevertWhen_PegInPaid_InvalidSettlementAmount() public {
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(200000000, 8));
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        pegInIds[0] = 1;
        uint256[] memory pegOutIds = new uint256[](0);
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        uint64 amount = 1e8;
        uint64 correctPayAmount = amount / 2 - (amount / 2 * 50 / 10000);
        uint64 wrongPayAmount = correctPayAmount + 1e6;

        vm.expectRevert(
            abi.encodeWithSelector(
                LstBTCBridgeLogic.InvalidSettlementAmount.selector,
                10001,
                1,
                correctPayAmount,
                wrongPayAmount
            )
        );
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, wrongPayAmount);
    }

    function test_RevertWhen_PegInPaid_WrongRequestStatus() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        uint64 amount = 1e8;
        vm.expectRevert("PegRequestHelper: mismatch request status");
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, amount);
    }

    function test_PegInPaid_MultipleRequestsSuccess() public {
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(200000000, 8));
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        bytes32 txId2 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        uint64 amount1 = 1e8;
        uint64 amount2 = 2e8;
        uint64 payAmount1 = amount1 / 2 - (amount1 / 2 * 50 / 10000);
        uint64 payAmount2 = amount2 / 2 - (amount2 / 2 * 50 / 10000);
        uint64 totalPayAmount = payAmount1 + payAmount2;

        vm.expectEmit(true, true, true, true);
        emit PegInBatchPaid(1, pegInIds, totalPayAmount, true);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, totalPayAmount);

        (,,,,,PegStatus status1,,,) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegInRequests(2);
        assertEq(uint256(status1), uint256(PegStatus.Paid));
        assertEq(uint256(status2), uint256(PegStatus.Paid));

        (bool isPegInSettled,) = lstBTCBridge.batches(1);
        assertTrue(isPegInSettled);
    }

    function test_PegInPaid_PartialBatchCompletion() public {
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(200000000, 8));
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](1);
        pegInIds[0] = 1;
        pegOutIds[0] = 3;
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, 1e8);

        (bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertFalse(isPegInSettled);
        assertTrue(isPegOutSettled);

        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegInRequests(2);
        assertEq(uint256(status2), uint256(PegStatus.Pending));
        (,,,,,PegStatus status3,,,) = lstBTCBridge.pegInRequests(1);
        assertEq(uint256(status3), uint256(PegStatus.PendingRefund));
    }

    // ============ processPegRequestBatch() ============

    function test_RevertWhen_ProcessBatch_EmptyBatch() public {
        uint256[] memory emptyPegInIds = new uint256[](0);
        uint256[] memory emptyPegOutIds = new uint256[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LstBTCBridgeLogic.BatchRequestsEmpty.selector
            )
        );
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(emptyPegInIds, emptyPegOutIds);
    }


    function test_RevertWhen_ProcessBatch_Unauthorized() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        address unauthorizedAddress = outboundNativeAddress;
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlBase.Unauthorized.selector,
                unauthorizedAddress
            )
        );
        vm.prank(unauthorizedAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }


    function test_RevertWhen_ProcessBatch_PendingBatch() public {
        vm.prank(address(lstBTCBridge));
        lstBTC.mint(address(operationsNativeAddress), 1e8);
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 2e8);
        vm.prank(address(lstBTCBridge));
        navProvider.increasePeggedBTC(1e8);
        bytes32 operationsBtcUtxo = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        uint256[] memory pegInIds1 = new uint256[](1);
        uint256[] memory pegOutIds1 = new uint256[](1);
        pegInIds1[0] = 1;
        pegOutIds1[0] = 2;
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds1, pegOutIds1);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);
        uint256[] memory pegInIds2 = new uint256[](1);
        uint256[] memory pegOutIds2 = new uint256[](0);
        pegInIds2[0] = 3;
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.PendingBatchFound.selector, 10001, 1));
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds2, pegOutIds2);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, 99500000);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.PendingBatchFound.selector, 10001, 1));
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds2, pegOutIds2);
        submitBtcTx(operationsBtcUtxo, 0, OPERATIONS_BTC_ADDRESS, INBOUND_BTC_ADDRESS, 98999000, hex"", 0);
        vm.expectEmit(false, false, false, false);
        emit BatchProcessed(1, pegInIds2, pegOutIds2, 0, 98999000);
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds2, pegOutIds2);
    }


    function test_ProcessBatch_OnlyPegInRequests() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(2e8, 8));
        uint64 expectedPendingPayWrappedAmount = 3e8 - 3e8 * 50 / 10000;

        vm.expectEmit(true, true, true, true);
        emit BatchProcessed(1, pegInIds, pegOutIds, expectedPendingPayWrappedAmount, 0);

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        (bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertFalse(isPegInSettled);
        assertTrue(isPegOutSettled);

        (,,,,,PegStatus status1,,,) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegInRequests(2);
        assertEq(uint256(status1), uint256(PegStatus.PendingPayout));
        assertEq(uint256(status2), uint256(PegStatus.PendingPayout));
        assertEq(lstBTC.totalSupply(), 3e8);
        assertEq(lstBTC.balanceOf(address(lstBTCBridge)), 3e8 * 50 / 10000);
        assertEq(lstBTC.balanceOf(operationsNativeAddress), expectedPendingPayWrappedAmount);
    }


    function test_RevertWhen_ProcessPegInBatch_InvalidRequestStatus() public {
        bytes32 utxo1 = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
        submitBtcTx(utxo1, 0, OPERATIONS_BTC_ADDRESS, OUTBOUND_BTC_ADDRESS, 1e8, hex"", 0);

        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.InvalidRequestStatus.selector, 1, uint256(PegStatus.Pending), uint256(PegStatus.Refunded)));
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_ProcessPegInBatch_RequestNotFinalized() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        uint32 lowBlockHeight = 90005;
        mockGetChainTipHeight(lowBlockHeight);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.RequestNotFinalized.selector, 1, lowBlockHeight + 1));
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }


    function test_RevertWhen_ProcessPegInBatch_InvalidRequestCustodian() public {
        address group2Operations = makeAddr("group2Operations");
        bytes[] memory rawAddresses = new bytes[](3);
        rawAddresses[0] = abi.encodePacked(makeAddr("group2Outbound"));
        rawAddresses[1] = abi.encodePacked(group2Operations);
        rawAddresses[2] = abi.encodePacked(makeAddr("group2Inbound"));

        uint8[] memory formats = new uint8[](3);
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        formats[2] = ADDRESS_FORMAT_NATIVE;

        uint8[] memory usages = new uint8[](3);
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.OPERATIONS;
        usages[2] = AddressUsage.INBOUND;
        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.InvalidRequestCustodian.selector, 1, 10002, 10001));
        vm.prank(group2Operations);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }


    function test_ProcessPegInBatch_TreasuryFeeZero() public {
        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        configRegistry.setPegInTreasuryFeeRate(0);

        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(2e8, 8));
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        uint256 bridgeBalanceBefore = lstBTC.balanceOf(address(lstBTCBridge));
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        uint256 bridgeBalanceAfter = lstBTC.balanceOf(address(lstBTCBridge));
        assertEq(bridgeBalanceAfter, bridgeBalanceBefore);

        assertEq(lstBTC.balanceOf(operationsNativeAddress), 1e8 / 2);
        assertEq(lstBTC.totalSupply(), 1e8 / 2);

        (,,,,,PegStatus status,,,) = lstBTCBridge.pegInRequests(1);
        assertEq(uint256(status), uint256(PegStatus.PendingPayout));
    }


    function test_ProcessPegInBatch_WithTreasuryFee() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        uint256 recipient1BalanceBefore = lstBTCBridge.claimableFees(DEFAULT_PEG_IN_RECIPIENTS[0]);
        uint256 recipient2BalanceBefore = lstBTCBridge.claimableFees(DEFAULT_PEG_IN_RECIPIENTS[1]);

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        uint64 expectedTreasuryFee = 1e8 * 50 / 10000;
        uint64 expectedRecipient1Amount = expectedTreasuryFee * 6000 / 10000;
        uint64 expectedRecipient2Amount = expectedTreasuryFee * 4000 / 10000;

        uint256 recipient1BalanceAfter = lstBTCBridge.claimableFees(DEFAULT_PEG_IN_RECIPIENTS[0]);
        uint256 recipient2BalanceAfter = lstBTCBridge.claimableFees(DEFAULT_PEG_IN_RECIPIENTS[1]);

        assertEq(recipient1BalanceAfter - recipient1BalanceBefore, expectedRecipient1Amount);
        assertEq(recipient2BalanceAfter - recipient2BalanceBefore, expectedRecipient2Amount);

        uint64 expectedNetAmount = 1e8 - expectedTreasuryFee;
        assertEq(lstBTC.totalSupply(), 1e8);
        assertEq(lstBTC.balanceOf(address(lstBTCBridge)), expectedTreasuryFee);
        assertEq(lstBTC.balanceOf(operationsNativeAddress), expectedNetAmount);


        (,,,,,PegStatus status,,,uint32 batchId) = lstBTCBridge.pegInRequests(1);
        assertEq(batchId, 1);
        assertEq(uint256(status), uint256(PegStatus.PendingPayout));
    }

    function test_ProcessPegInBatch_MultipleRequests() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 2e8);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 3e8);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 4e8);

        uint256[] memory pegInIds = new uint256[](3);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        pegInIds[2] = 3;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        (,,,,,PegStatus status1,,,uint32 batchId1) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus status2,,,uint32 batchId2) = lstBTCBridge.pegInRequests(2);
        (,,,,,PegStatus status3,,,uint32 batchId3) = lstBTCBridge.pegInRequests(3);
        assertEq(batchId1, 1);
        assertEq(batchId2, 1);
        assertEq(batchId3, 1);
        assertEq(uint256(status1), uint256(PegStatus.PendingPayout));
        assertEq(uint256(status2), uint256(PegStatus.PendingPayout));
        assertEq(uint256(status3), uint256(PegStatus.PendingPayout));

        assertEq(lstBTC.totalSupply(), 1e8 * 3);
        assertEq(lstBTC.balanceOf(address(lstBTCBridge)), 1e8 * 50 / 10000 * 3);
        assertEq(lstBTC.balanceOf(operationsNativeAddress), 1e8 * 3 - 1e8 * 50 / 10000 * 3);
    }

    function test_ProcessBatch_OnlyPegOutRequests() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 2e8);
        navProvider.increasePeggedBTC(2e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 2e8);

        vm.startPrank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.stopPrank();

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](2);
        pegOutIds[0] = 1;
        pegOutIds[1] = 2;

        uint64 netAmount1 = 1e8 - 1e8 * 100 / 10000 - DEFAULT_PEG_OUT_TRANSACTION_FEE;
        uint64 netAmount2 = 1e8 - 1e8 * 100 / 10000 - DEFAULT_PEG_OUT_TRANSACTION_FEE;
        uint64 expectedPendingPayBTCAmount = netAmount1 + netAmount2;

        vm.expectEmit(true, true, true, true);
        emit BatchProcessed(1, pegInIds, pegOutIds, 0, expectedPendingPayBTCAmount);

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        (bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertTrue(isPegInSettled);
        assertFalse(isPegOutSettled);

        (,,,,,PegStatus status1,,,) = lstBTCBridge.pegOutRequests(1);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegOutRequests(2);
        assertEq(uint256(status1), uint256(PegStatus.PendingPayout));
        assertEq(uint256(status2), uint256(PegStatus.PendingPayout));
    }

    function test_RevertWhen_ProcessPegOutBatch_RequestNotFinalized() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 1e8);
        navProvider.increasePeggedBTC(1e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 1e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.RequestNotFinalized.selector, 1, 13));
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_ProcessPegOutBatch_InvalidRequestStatus() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 1e8);
        navProvider.increasePeggedBTC(1e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 1e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, 1e8);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.InvalidRequestStatus.selector, 1, uint256(PegStatus.Pending), uint256(PegStatus.Refunded)));
        vm.prank(operationsNativeAddress);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_ProcessPegOutBatch_InvalidRequestCustodian() public {
        address group2Operations = makeAddr("group2Operations");
        bytes[] memory rawAddresses = new bytes[](3);
        rawAddresses[0] = abi.encodePacked(makeAddr("group2Outbound"));
        rawAddresses[1] = abi.encodePacked(group2Operations);
        rawAddresses[2] = abi.encodePacked(makeAddr("group2Inbound"));

        uint8[] memory formats = new uint8[](3);
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        formats[2] = ADDRESS_FORMAT_NATIVE;

        uint8[] memory usages = new uint8[](3);
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.OPERATIONS;
        usages[2] = AddressUsage.INBOUND;

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 1e8);
        navProvider.increasePeggedBTC(1e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 1e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.InvalidRequestCustodian.selector, 1, 10002, 10001));
        vm.prank(group2Operations);
        vm.roll(14);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_ProcessPegOutBatch_WithTreasuryFee() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 1e8);
        navProvider.increasePeggedBTC(2e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 1e8);

        vm.prank(address(lstBTC));
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(2e8, 8));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;

        uint256 initialBridgeBalance = lstBTC.balanceOf(address(lstBTCBridge));

        uint256 initialTotalSupply = lstBTC.totalSupply();

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        uint64 treasuryFee = 1e8 * 100 / 10000;
        uint64 burnAmount = 1e8 - treasuryFee;

        assertEq(lstBTC.totalSupply(), initialTotalSupply - burnAmount);

        assertEq(lstBTC.balanceOf(address(lstBTCBridge)), initialBridgeBalance + treasuryFee);

        (,,,,,PegStatus status,,,) = lstBTCBridge.pegOutRequests(1);
        assertEq(uint256(status), uint256(PegStatus.PendingPayout));
        assertEq(navProvider.peggedBTC(), treasuryFee * 2);
    }

    function test_ProcessPegOutBatch_ZeroTreasuryFee() public {
        vm.warp(BTC_TX_TIMESTAMP + 3000);
        vm.startPrank(govAddress);
        configRegistry.setPegOutTreasuryFeeRate(0);
        vm.stopPrank();

        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 1e8);
        navProvider.increasePeggedBTC(1e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 1e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;

        uint256 initialBridgeBalance = lstBTC.balanceOf(address(lstBTCBridge));
        uint256 initialTotalSupply = lstBTC.totalSupply();

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        assertEq(lstBTC.totalSupply(), initialTotalSupply - 1e8);

        assertEq(lstBTC.balanceOf(address(lstBTCBridge)), initialBridgeBalance);

        (,,,,,PegStatus status,,,) = lstBTCBridge.pegOutRequests(1);
        assertEq(uint256(status), uint256(PegStatus.PendingPayout));
    }

    function test_ProcessPegOutBatch_MultipleRequests() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 3e8);
        navProvider.increasePeggedBTC(3e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 3e8);

        vm.startPrank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.stopPrank();

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](3);
        pegOutIds[0] = 1;
        pegOutIds[1] = 2;
        pegOutIds[2] = 3;

        uint256 initialTotalSupply = lstBTC.totalSupply();

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        (,,,,,PegStatus status1,,,) = lstBTCBridge.pegOutRequests(1);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegOutRequests(2);
        (,,,,,PegStatus status3,,,) = lstBTCBridge.pegOutRequests(3);
        assertEq(uint256(status1), uint256(PegStatus.PendingPayout));
        assertEq(uint256(status2), uint256(PegStatus.PendingPayout));
        assertEq(uint256(status3), uint256(PegStatus.PendingPayout));

        uint64 treasuryFeePerRequest = 1e8 * 100 / 10000;
        uint64 totalBurnAmount = 3 * (1e8 - treasuryFeePerRequest);
        assertEq(lstBTC.totalSupply(), initialTotalSupply - totalBurnAmount);
        assertEq(navProvider.peggedBTC(), treasuryFeePerRequest * 3);
        address pegOutRecipient0 = DEFAULT_PEG_OUT_RECIPIENTS[0];
        address pegOutRecipient1 = DEFAULT_PEG_OUT_RECIPIENTS[1];
        assertEq(lstBTCBridge.claimableFees(pegOutRecipient0), treasuryFeePerRequest * 7000 / 10000 * 3);
        assertEq(lstBTCBridge.claimableFees(pegOutRecipient1), treasuryFeePerRequest * 3000 / 10000 * 3);
    }

    function test_ProcessBatch_MixedRequests() public {
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(2e8, 8));
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 2e8);

        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 5e8);
        navProvider.increasePeggedBTC(10e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 5e8);
        vm.mockCall(address(navProvider), abi.encodeWithSelector(navProvider.getExchangeRate.selector), abi.encode(2e8, 8));
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](2);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        pegOutIds[0] = 3;
        pegOutIds[1] = 4;

        uint64 expectedPendingPayWrappedAmount = 1e8 - 1e8 * 50 / 10000;
        uint64 expectedPendingPayBTCAmount = 2e8 * 2 - 2e8 * 2 * 100 / 10000 - DEFAULT_PEG_OUT_TRANSACTION_FEE * 2;
        vm.expectEmit(true, true, true, true);
        emit BatchProcessed(1, pegInIds, pegOutIds, expectedPendingPayWrappedAmount, expectedPendingPayBTCAmount);

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
        (bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertFalse(isPegInSettled);
        assertFalse(isPegOutSettled);

        (,,,,,PegStatus pegInStatus,,,) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus pegOutStatus,,,) = lstBTCBridge.pegOutRequests(3);
        assertEq(uint256(pegInStatus), uint256(PegStatus.PendingPayout));
        assertEq(uint256(pegOutStatus), uint256(PegStatus.PendingPayout));
        uint32[] memory batches = lstBTCBridge.getCustodianBatchIds(10001);
        assertEq(batches.length, 1);
        assertEq(batches[0], 1);
    }

    function test_RevertWhen_ProcessBatch_DuplicatePegInIds() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 2e8);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 3e8);

        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        pegInIds[1] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        vm.expectRevert();
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_ProcessBatch_DuplicatePegOutIds() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 2e8);
        navProvider.increasePeggedBTC(2e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 2e8);

        vm.startPrank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.stopPrank();

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](2);
        pegOutIds[0] = 1;
        pegOutIds[1] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        vm.expectRevert();
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_ProcessBatch_PegInAndPegOutIdsOverlap() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 2e8);

        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 1e8);
        navProvider.increasePeggedBTC(1e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 1e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](1);
        pegInIds[0] = 1;
        pegOutIds[0] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        vm.expectRevert();
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_ProcessBatch_PegOutIdsEmpty() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 2e8);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](1);
        pegInIds[0] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        vm.expectRevert();
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);


    }

    // ============ rejectPegRequestBatch() ============

    function test_RevertWhen_RejectBatch_BatchRequestsEmpty() public {
        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.BatchRequestsEmpty.selector));
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_RejectBatch_NotWhitelistedOperator() public {
        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        address unauthorizedUser = inboundNativeAddress;
        vm.expectRevert(abi.encodeWithSelector(AccessControlBase.Unauthorized.selector, unauthorizedUser));
        vm.prank(unauthorizedUser);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_RejectBatch_PendingBatchExists() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);
        pegInIds[0] = 2;

        vm.expectRevert(abi.encodeWithSelector(LstBTCBridgeLogic.PendingBatchFound.selector, 10001, 1));
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RejectBatch_OnlyPegInRequests() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        pegInIds[1] = 2;

        uint64 expectedPendingRefundBTC = 3e8;

        vm.expectEmit(true, true, true, true);
        emit BatchRejected(1, pegInIds, pegOutIds, expectedPendingRefundBTC, 0);

        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertFalse(isPegInSettled);
        assertTrue(isPegOutSettled);

        (,,,,,PegStatus status1,,,) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegInRequests(2);
        assertEq(uint256(status1), uint256(PegStatus.PendingRefund));
        assertEq(uint256(status2), uint256(PegStatus.PendingRefund));
    }

    function test_RevertWhen_RejectPegInBatch_InvalidRequestStatus() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, 99500000);
        vm.prank(operationsNativeAddress);
        vm.roll(15);
        pegInIds[0] = 1;
        vm.expectRevert("PegRequestHelper: mismatch request status");
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_RejectPegInBatch_InvalidRequestCustodian() public {
        address group2Operations = makeAddr("group2Operations");
        bytes[] memory rawAddresses = new bytes[](3);
        rawAddresses[0] = abi.encodePacked(makeAddr("group2Outbound"));
        rawAddresses[1] = abi.encodePacked(group2Operations);
        rawAddresses[2] = abi.encodePacked(makeAddr("group2Inbound"));

        uint8[] memory formats = new uint8[](3);
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        formats[2] = ADDRESS_FORMAT_NATIVE;

        uint8[] memory usages = new uint8[](3);
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.OPERATIONS;
        usages[2] = AddressUsage.INBOUND;

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        vm.expectRevert("PegRequestHelper: mismatch request custodianId");
        vm.prank(group2Operations);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RejectPegInBatch_MultipleRequests() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 2e8);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 3e8);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 4e8);

        uint256[] memory pegInIds = new uint256[](3);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        pegInIds[2] = 3;

        uint64 expectedPendingRefundBTC = 3e8;

        vm.expectEmit(true, true, true, true);
        emit BatchRejected(1, pegInIds, pegOutIds, expectedPendingRefundBTC, 0);

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (,,,,,PegStatus status1,,,uint32 batchId1) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus status2,,,uint32 batchId2) = lstBTCBridge.pegInRequests(2);
        (,,,,,PegStatus status3,,,uint32 batchId3) = lstBTCBridge.pegInRequests(3);

        assertEq(uint256(status1), uint256(PegStatus.PendingRefund));
        assertEq(uint256(status2), uint256(PegStatus.PendingRefund));
        assertEq(uint256(status3), uint256(PegStatus.PendingRefund));
        assertEq(batchId1, 1);
        assertEq(batchId2, 1);
        assertEq(batchId3, 1);

        (
            uint256[] memory storedPegInIds,
            uint256[] memory storedPegOutIds,
            bool isPegInSettled,
            bool isPegOutSettled
        ) = lstBTCBridge.getBatch(1);

        assertEq(storedPegInIds.length, 3);
        assertEq(storedPegInIds[0], 1);
        assertEq(storedPegInIds[1], 2);
        assertEq(storedPegInIds[2], 3);
        assertEq(storedPegOutIds.length, 0);
        assertFalse(isPegInSettled);
        assertTrue(isPegOutSettled);
    }

    function test_RejectPegInBatch_RefundAmountCalculation() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);   // 1 BTC
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);   // 2 BTC
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 15e7, hex"", 0);  // 1.5 BTC

        uint256[] memory pegInIds = new uint256[](3);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        pegInIds[2] = 3;

        uint64 expectedPendingRefundBTC = 1e8 + 2e8 + 15e7; // 4.5 BTC

        vm.expectEmit(true, true, true, true);
        emit BatchRejected(1, pegInIds, pegOutIds, expectedPendingRefundBTC, 0);

        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (uint64 amount1,,,,,,,,) = lstBTCBridge.pegInRequests(1);
        (uint64 amount2,,,,,,,,) = lstBTCBridge.pegInRequests(2);
        (uint64 amount3,,,,,,,,) = lstBTCBridge.pegInRequests(3);

        assertEq(amount1, 1e8);
        assertEq(amount2, 2e8);
        assertEq(amount3, 15e7);
        assertEq(amount1 + amount2 + amount3, expectedPendingRefundBTC);
    }

    function test_RejectBatch_OnlyPegOutRequests() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 3e8);
        navProvider.increasePeggedBTC(3e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 3e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 2e8);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](2);
        pegOutIds[0] = 1;
        pegOutIds[1] = 2;

        uint64 expectedPendingRefundWrappedBTC = 3e8;

        vm.expectEmit(true, true, true, true);
        emit BatchRejected(1, pegInIds, pegOutIds, 0, expectedPendingRefundWrappedBTC);

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertTrue(isPegInSettled);
        assertFalse(isPegOutSettled);

        (,,,,,PegStatus status1,,,) = lstBTCBridge.pegOutRequests(1);
        (,,,,,PegStatus status2,,,) = lstBTCBridge.pegOutRequests(2);
        assertEq(uint256(status1), uint256(PegStatus.PendingRefund));
        assertEq(uint256(status2), uint256(PegStatus.PendingRefund));
    }

    function test_RevertWhen_RejectPegOutBatch_InvalidRequestStatus() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 1e8);
        navProvider.increasePeggedBTC(1e8);
        vm.stopPrank();
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 1e8);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, outboundNativeAddress, 1e8);

        pegOutIds[0] = 1;
        vm.expectRevert("PegRequestHelper: mismatch request status");
        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_RejectPegOutBatch_InvalidRequestCustodian() public {
        address group2Operations = makeAddr("group2Operations");
        bytes[] memory rawAddresses = new bytes[](3);
        rawAddresses[0] = abi.encodePacked(makeAddr("group2Outbound"));
        rawAddresses[1] = abi.encodePacked(group2Operations);
        rawAddresses[2] = abi.encodePacked(makeAddr("group2Inbound"));

        uint8[] memory formats = new uint8[](3);
        formats[0] = ADDRESS_FORMAT_NATIVE;
        formats[1] = ADDRESS_FORMAT_NATIVE;
        formats[2] = ADDRESS_FORMAT_NATIVE;

        uint8[] memory usages = new uint8[](3);
        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.OPERATIONS;
        usages[2] = AddressUsage.INBOUND;

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);

        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 1e8);
        navProvider.increasePeggedBTC(1e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 1e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](1);
        pegOutIds[0] = 1;

        vm.expectRevert("PegRequestHelper: mismatch request custodianId");
        vm.prank(group2Operations);
        vm.roll(14);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RejectPegOutBatch_MultipleRequests() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 6e8);
        navProvider.increasePeggedBTC(6e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 6e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 2e8);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 3e8);

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](3);
        pegOutIds[0] = 1;
        pegOutIds[1] = 2;
        pegOutIds[2] = 3;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        vm.expectEmit(true, true, true, true);
        emit BatchRejected(1, pegInIds, pegOutIds, 0, 6e8);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (,,,,,PegStatus status1,,,uint32 batchId1) = lstBTCBridge.pegOutRequests(1);
        (,,,,,PegStatus status2,,,uint32 batchId2) = lstBTCBridge.pegOutRequests(2);
        (,,,,,PegStatus status3,,,uint32 batchId3) = lstBTCBridge.pegOutRequests(3);

        assertEq(batchId1, 1);
        assertEq(batchId2, 1);
        assertEq(batchId3, 1);
        assertEq(uint256(status1), uint256(PegStatus.PendingRefund));
        assertEq(uint256(status2), uint256(PegStatus.PendingRefund));
        assertEq(uint256(status3), uint256(PegStatus.PendingRefund));

    }

    function test_RejectBatch_BothPegInAndPegOut() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);

        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 5e8);
        navProvider.increasePeggedBTC(10e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 5e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 2e8);

        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](2);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        pegOutIds[0] = 3;
        pegOutIds[1] = 4;

        uint64 expectedPendingRefundBTC = 3e8;
        uint64 expectedPendingRefundWrappedBTC = 3e8;

        vm.expectEmit(true, true, true, true);
        emit BatchRejected(1, pegInIds, pegOutIds, expectedPendingRefundBTC, expectedPendingRefundWrappedBTC);

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (bool isPegInSettled, bool isPegOutSettled) = lstBTCBridge.batches(1);
        assertFalse(isPegInSettled);
        assertFalse(isPegOutSettled);

        (,,,,,PegStatus pegInStatus1,,,) = lstBTCBridge.pegInRequests(1);
        (,,,,,PegStatus pegInStatus2,,,) = lstBTCBridge.pegInRequests(2);
        (,,,,,PegStatus pegOutStatus1,,,) = lstBTCBridge.pegOutRequests(3);
        (,,,,,PegStatus pegOutStatus2,,,) = lstBTCBridge.pegOutRequests(4);

        assertEq(uint256(pegInStatus1), uint256(PegStatus.PendingRefund));
        assertEq(uint256(pegInStatus2), uint256(PegStatus.PendingRefund));
        assertEq(uint256(pegOutStatus1), uint256(PegStatus.PendingRefund));
        assertEq(uint256(pegOutStatus2), uint256(PegStatus.PendingRefund));

        uint32[] memory batches = lstBTCBridge.getCustodianBatchIds(10001);
        assertEq(batches.length, 1);
        assertEq(batches[0], 1);
    }

    function test_RevertWhen_RejectBatch_DuplicatePegInIds() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 2e8);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 3e8);

        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;
        pegInIds[1] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        vm.expectRevert();
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RevertWhen_RejectBatch_DuplicatePegOutIds() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 2e8);
        navProvider.increasePeggedBTC(2e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 2e8);

        vm.startPrank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        vm.stopPrank();

        uint256[] memory pegInIds = new uint256[](0);
        uint256[] memory pegOutIds = new uint256[](2);
        pegOutIds[0] = 1;
        pegOutIds[1] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        vm.expectRevert();
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);
    }

    function test_RejectBatch_BatchStateValidation() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        vm.prank(operationsNativeAddress);
        lstBTCBridge.rejectPegRequestBatch(pegInIds, pegOutIds);

        (
            uint256[] memory storedPegInIds,
            uint256[] memory storedPegOutIds,
            bool isPegInSettled,
            bool isPegOutSettled
        ) = lstBTCBridge.getBatch(1);

        assertEq(storedPegInIds.length, 1);
        assertEq(storedPegInIds[0], 1);
        assertEq(storedPegOutIds.length, 0);
        assertFalse(isPegInSettled);
        assertTrue(isPegOutSettled);

        uint32 latestBatchId = lstBTCBridge.getCustodianLatestBatchId(10001);
        assertEq(latestBatchId, 1);

        (
            uint32 returnedBatchId,
            uint256[] memory returnedPegInIds,
            uint256[] memory returnedPegOutIds,
            bool returnedIsPegInSettled,
            bool returnedIsPegOutSettled
        ) = lstBTCBridge.getCustodianLatestBatch(10001);

        assertEq(returnedBatchId, 1);
        assertEq(returnedPegInIds.length, 1);
        assertEq(returnedPegInIds[0], 1);
        assertEq(returnedPegOutIds.length, 0);
        assertFalse(returnedIsPegInSettled);
        assertTrue(returnedIsPegOutSettled);
    }

    // ============ claimFees ============

    function test_ClaimFees_Success() public {
        address feeRecipient = makeAddr("feeRecipient");

        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        address[] memory recipients = new address[](1);
        uint16[] memory shares = new uint16[](1);
        recipients[0] = feeRecipient;
        shares[0] = 10000; // 100%
        configRegistry.setPegInTreasuryFeeShares(recipients, shares);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        uint64 claimableAmount = lstBTCBridge.claimableFees(feeRecipient);
        assertEq(claimableAmount, 1e6);

        uint256 balanceBefore = lstBTC.balanceOf(feeRecipient);

        vm.expectEmit(true, true, true, true);
        emit FeesClaimed(feeRecipient, claimableAmount);

        vm.prank(feeRecipient);
        lstBTCBridge.claimFees();

        uint256 balanceAfter = lstBTC.balanceOf(feeRecipient);
        assertEq(balanceAfter - balanceBefore, claimableAmount);

        assertEq(lstBTCBridge.claimableFees(feeRecipient), 0);
    }

    function test_ClaimFees_ZeroAmount() public {
        address user = makeAddr("user");

        assertEq(lstBTCBridge.claimableFees(user), 0);

        uint256 balanceBefore = lstBTC.balanceOf(user);

        vm.prank(user);
        lstBTCBridge.claimFees();

        uint256 balanceAfter = lstBTC.balanceOf(user);
        assertEq(balanceAfter, balanceBefore);

        assertEq(lstBTCBridge.claimableFees(user), 0);
    }

    function test_ClaimFees_AccumulatedFees() public {
        address feeRecipient2 = makeAddr("feeRecipient2");
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 10e8);
        navProvider.increasePeggedBTC(2e8);
        vm.stopPrank();
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 10e8);

        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        address[] memory recipients = new address[](2);
        uint16[] memory shares = new uint16[](2);
        recipients[0] = user1;
        shares[0] = 7000; // 70%
        recipients[1] = feeRecipient2;
        shares[1] = 3000; // 30%
        configRegistry.setPegInTreasuryFeeShares(recipients, shares);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        bytes32 utxo = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 2e8);
        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](1);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        pegOutIds[0] = 3;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, 2e8 - 1e6);
        submitBtcTx(utxo, 0, OPERATIONS_BTC_ADDRESS, INBOUND_BTC_ADDRESS, 98999000, hex"", 0);

        uint64 totalClaimable = lstBTCBridge.claimableFees(user1);
        uint64 totalClaimable2 = lstBTCBridge.claimableFees(feeRecipient2);
        uint64 totalClaimable3 = lstBTCBridge.claimableFees(DEFAULT_PEG_OUT_RECIPIENTS[0]);
        uint64 totalClaimable4 = lstBTCBridge.claimableFees(DEFAULT_PEG_OUT_RECIPIENTS[1]);
        assertEq(totalClaimable, 1e6 * 7000 / 10000);
        assertEq(totalClaimable2, 1e6 * 3000 / 10000);
        assertEq(totalClaimable3, 1e6 * 7000 / 10000);
        assertEq(totalClaimable4, 1e6 * 3000 / 10000);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, OUTBOUND_BTC_ADDRESS, 3e8);
        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        uint256[] memory pegInIds1 = new uint256[](1);
        uint256[] memory pegOutIds1 = new uint256[](0);
        pegInIds1[0] = 4;
        lstBTCBridge.processPegRequestBatch(pegInIds1, pegOutIds1);
        uint64 totalClaimable5 = lstBTCBridge.claimableFees(user1);
        assertEq(totalClaimable5, 1e6 * 7000 / 10000 + 5e5 * 7000 / 10000);

        uint256 balanceBefore = lstBTC.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit FeesClaimed(user1, totalClaimable5);

        vm.prank(user1);
        lstBTCBridge.claimFees();

        uint256 balanceAfter = lstBTC.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, totalClaimable5);

        assertEq(lstBTCBridge.claimableFees(user1), 0);
    }

    function test_ClaimFees_MultipleRecipients() public {
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");

        vm.prank(govAddress);
        vm.warp(BTC_TX_TIMESTAMP);
        address[] memory recipients = new address[](2);
        uint16[] memory shares = new uint16[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        shares[0] = 6000; // 60%
        shares[1] = 4000; // 40%
        configRegistry.setPegInTreasuryFeeShares(recipients, shares);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 10e8, hex"", 0);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](0);
        pegInIds[0] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        uint64 totalFee = 10e8 * 50 / 10000;
        uint64 recipient1Fee = totalFee * 6000 / 10000;
        uint64 recipient2Fee = totalFee * 4000 / 10000;

        assertEq(lstBTCBridge.claimableFees(recipient1), recipient1Fee);
        assertEq(lstBTCBridge.claimableFees(recipient2), recipient2Fee);

        uint256 recipient1BalanceBefore = lstBTC.balanceOf(recipient1);

        vm.expectEmit(true, true, true, true);
        emit FeesClaimed(recipient1, recipient1Fee);

        vm.prank(recipient1);
        lstBTCBridge.claimFees();

        assertEq(lstBTC.balanceOf(recipient1) - recipient1BalanceBefore, recipient1Fee);
        assertEq(lstBTCBridge.claimableFees(recipient1), 0);

        assertEq(lstBTCBridge.claimableFees(recipient2), recipient2Fee);

        uint256 recipient2BalanceBefore = lstBTC.balanceOf(recipient2);

        vm.expectEmit(true, true, true, true);
        emit FeesClaimed(recipient2, recipient2Fee);

        vm.prank(recipient2);
        lstBTCBridge.claimFees();

        assertEq(lstBTC.balanceOf(recipient2) - recipient2BalanceBefore, recipient2Fee);
        assertEq(lstBTCBridge.claimableFees(recipient2), 0);
    }

    // ============ getBatch ============

    function test_GetBatch_ExistingBatch() public {
        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 3e8);
        navProvider.increasePeggedBTC(3e8);
        vm.stopPrank();
        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 3e8);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);
        vm.startPrank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 2e8);
        vm.stopPrank();
        uint256[] memory pegInIds = new uint256[](2);
        uint256[] memory pegOutIds = new uint256[](2);
        pegInIds[0] = 1;
        pegInIds[1] = 2;
        pegOutIds[0] = 3;
        pegOutIds[1] = 4;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        (
            uint256[] memory returnedPegInIds,
            uint256[] memory returnedPegOutIds,
            bool isPegInSettled,
            bool isPegOutSettled
        ) = lstBTCBridge.getBatch(1);

        assertEq(returnedPegInIds.length, 2);
        assertEq(returnedPegInIds[0], 1);
        assertEq(returnedPegInIds[1], 2);

        assertEq(returnedPegOutIds.length, 2);
        assertEq(returnedPegOutIds[0], 3);
        assertEq(returnedPegOutIds[1], 4);

        assertFalse(isPegInSettled);
        assertFalse(isPegOutSettled);
    }

    function test_GetBatch_NonExistentBatch() public {
        (
            uint256[] memory pegInIds,
            uint256[] memory pegOutIds,
            bool isPegInSettled,
            bool isPegOutSettled
        ) = lstBTCBridge.getBatch(999);

        assertEq(pegInIds.length, 0);
        assertEq(pegOutIds.length, 0);
        assertFalse(isPegInSettled);
        assertFalse(isPegOutSettled);
    }

    // ============ getCustodianBatchIds ============

    function test_GetCustodianBatchIds_ExistingCustodian() public {
        bytes32 utxo = submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds1 = new uint256[](1);
        uint256[] memory pegOutIds1 = new uint256[](0);
        pegInIds1[0] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.rejectPegRequestBatch(pegInIds1, pegOutIds1);
        submitBtcTx(utxo, 0, OPERATIONS_BTC_ADDRESS, OUTBOUND_BTC_ADDRESS, 1e8, hex"", 0);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);
        uint256[] memory pegInIds2 = new uint256[](1);
        uint256[] memory pegOutIds2 = new uint256[](0);
        pegInIds2[0] = 2;

        vm.prank(operationsNativeAddress);
        vm.roll(15);
        mockGetChainTipHeight(90011);
        lstBTCBridge.processPegRequestBatch(pegInIds2, pegOutIds2);
        uint32[] memory batchIds = lstBTCBridge.getCustodianBatchIds(10001);
        assertEq(batchIds.length, 2);
        assertEq(batchIds[0], 1);
        assertEq(batchIds[1], 2);
    }

    function test_GetCustodianBatchIds_NonExistentCustodian() public {
        uint32[] memory batchIds = lstBTCBridge.getCustodianBatchIds(999);

        assertEq(batchIds.length, 0);
    }

    // ============ getCustodianLatestBatchId ============

    function test_GetCustodianLatestBatchId_ExistingCustodian() public {
        uint32 latestBatchId = lstBTCBridge.getCustodianLatestBatchId(10001);
        assertEq(latestBatchId, 0);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        uint256[] memory pegInIds1 = new uint256[](1);
        uint256[] memory pegOutIds1 = new uint256[](0);
        pegInIds1[0] = 1;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds1, pegOutIds1);

        latestBatchId = lstBTCBridge.getCustodianLatestBatchId(10001);
        assertEq(latestBatchId, 1);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(operationsNativeAddress, inboundNativeAddress, 99500000);

        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 2e8, hex"", 0);

        uint256[] memory pegInIds2 = new uint256[](1);
        uint256[] memory pegOutIds2 = new uint256[](0);
        pegInIds2[0] = 2;

        vm.prank(operationsNativeAddress);
        vm.roll(15);
        mockGetChainTipHeight(90011);
        lstBTCBridge.processPegRequestBatch(pegInIds2, pegOutIds2);

        latestBatchId = lstBTCBridge.getCustodianLatestBatchId(10001);
        assertEq(latestBatchId, 2);
    }

    function test_GetCustodianLatestBatchId_NonExistentCustodian() public {
        uint32 latestBatchId = lstBTCBridge.getCustodianLatestBatchId(999);
        assertEq(latestBatchId, 0);
    }

    // ============ getCustodianLatestBatch ============

    function test_GetCustodianLatestBatch_ExistingCustodian() public {
        submitBtcTx(outboundBtcUtxo, 0, OUTBOUND_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);

        vm.startPrank(address(lstBTCBridge));
        lstBTC.mint(operationsNativeAddress, 2e8);
        navProvider.increasePeggedBTC(2e8);
        vm.stopPrank();

        vm.prank(operationsNativeAddress);
        lstBTC.approve(address(lstBTCBridge), 2e8);

        vm.prank(address(lstBTC));
        lstBTCBridge.onLstBTCTransfer(outboundNativeAddress, operationsNativeAddress, 1e8);

        uint256[] memory pegInIds = new uint256[](1);
        uint256[] memory pegOutIds = new uint256[](1);
        pegInIds[0] = 1;
        pegOutIds[0] = 2;

        vm.prank(operationsNativeAddress);
        vm.roll(14);
        mockGetChainTipHeight(90010);
        lstBTCBridge.processPegRequestBatch(pegInIds, pegOutIds);

        (
            uint32 latestBatchId,
            uint256[] memory returnedPegInIds,
            uint256[] memory returnedPegOutIds,
            bool isPegInSettled,
            bool isPegOutSettled
        ) = lstBTCBridge.getCustodianLatestBatch(10001);

        assertEq(latestBatchId, 1);
        assertEq(returnedPegInIds.length, 1);
        assertEq(returnedPegInIds[0], 1);
        assertEq(returnedPegOutIds.length, 1);
        assertEq(returnedPegOutIds[0], 2);
        assertFalse(isPegInSettled);
        assertFalse(isPegOutSettled);
    }

    function test_GetCustodianLatestBatch_NonExistentCustodian() public {
        (
            uint32 latestBatchId,
            uint256[] memory pegInIds,
            uint256[] memory pegOutIds,
            bool isPegInSettled,
            bool isPegOutSettled
        ) = lstBTCBridge.getCustodianLatestBatch(999);

        assertEq(latestBatchId, 0);
        assertEq(pegInIds.length, 0);
        assertEq(pegOutIds.length, 0);
        assertFalse(isPegInSettled);
        assertFalse(isPegOutSettled);
    }

    // ============ getCustodianDebt ============

    function test_GetCustodianDebt_NoDebt() public {
        uint64 debt = lstBTCBridge.getCustodianDebt(10001);
        assertEq(debt, 0);
    }

    function test_GetCustodianDebt_WithDebt() public {
        bytes32 borrowTxId = _transferBTCToScript(BORROW_BTC_ADDRESS);
        bytes32 operationsTxId = submitBtcTx(borrowTxId, 0, BORROW_BTC_ADDRESS, OPERATIONS_BTC_ADDRESS, 1e8, hex"", 0);
        uint64 debt = lstBTCBridge.getCustodianDebt(10001);
        assertEq(debt, 1e8);
        submitBtcTx(operationsTxId, 0, OPERATIONS_BTC_ADDRESS, REPAYMENT_BTC_ADDRESS, 2e7, hex"", 0);
        debt = lstBTCBridge.getCustodianDebt(10001);
        assertEq(debt, 8e7); // 1e8 - 1e7 = 9e7
    }

    function test_GetCustodianDebt_NonExistentCustodian() public {
        uint64 debt = lstBTCBridge.getCustodianDebt(999);

        assertEq(debt, 0);
    }

    // ============ Helper Functions for Complex Test Scenarios ============

    function _setupPegIn() internal returns (bytes32) {
        uint64 amount = 10e8;
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(outboundBtcUtxo, FIRST_INPUT_INDEX, OPERATIONS_BTC_ADDRESS, amount, FIRST_TO_BTC_ADDRESS, amount / 2);
        bytes memory fromPkScript = FIRST_TO_BTC_ADDRESS;
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        mockBTCBlockTimestamp(blockHeight, BTC_TX_TIMESTAMP);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
        return txId;
    }

    // ============ helper functions ============
    function mockBTCBlockTimestamp(uint32 blockHeight, uint64 timestamp) internal {
        bytes32 blockHash = keccak256(abi.encodePacked('test'));
        mockHeight2HashMap(blockHeight, blockHash);
        mockGetTimestamp(blockHash, timestamp);
    }

    function _initWhitelistRegistry() internal {
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
        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
        (uint32 groupId1, uint8 usage1) = whitelistRegistry.getWhitelistEntry(FIRST_TO_BTC_ADDRESS);
        uint32 groupId = whitelistRegistry.RESERVED_GROUP_ID();
        vm.prank(groupMemberOperator);
        whitelistRegistry.addEntriesToGroup(
            groupId,
            rawAddresses1,
            formats1,
            usages1
        );
    }

    function _initToOutBoundBTC() internal returns (bytes32) {
        //  build raw tx
        bytes32 inputTxId = keccak256("first_transation");
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(inputTxId, FIRST_INPUT_INDEX, OUTBOUND_BTC_ADDRESS, FIRST_TO_BTC_AMOUNT, FIRST_CHANGE_BTC_ADDRESS, FIRST_CHANGE_AMOUNT);
        // mock check tx proof
        uint32 blockHeight = 89900;
        mockCheckTxProof(txId, blockHeight, true);
        mockGetChainTipHeight(20000);
        // submit transaction proof
        bytes memory fromPkScript = FIRST_FROM_BTC_ADDRESS;
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
        return txId;
    }

    function _transferBTCToScript(bytes memory to) internal returns (bytes32) {
        uint64 amount = 10e8;
        bytes32 inputTxId = keccak256("address1");
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(inputTxId, FIRST_INPUT_INDEX, to, amount, FIRST_CHANGE_BTC_ADDRESS, 1e8);
        bytes memory fromPkScript = FIRST_TO_BTC_ADDRESS;
        uint32 blockHeight = 90000;
        mockCheckTxProof(txId, blockHeight, true);
        mockBTCBlockTimestamp(blockHeight, BTC_TX_TIMESTAMP);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
        return txId;
    }

    function _setupDebtScenario() internal returns (bytes32) {
        bytes32 borrowTxId = _transferBTCToScript(BORROW_BTC_ADDRESS);
        (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) = buildBtcRawTx(borrowTxId, 0, OPERATIONS_BTC_ADDRESS, 2e7, hex"", 0);
        bytes memory fromPkScript = BORROW_BTC_ADDRESS;
        uint32 blockHeight = 90001;
        mockCheckTxProof(txId, blockHeight, true);
        vm.prank(relayerAddress);
        lstBTCBridge.submitTransactionProof(
            rawTx,
            blockHeight,
            merkleProof,
            blockIndex,
            fromPkScript,
            toPkScripts
        );
        return txId;
    }

    function _setupSecondCustodianGroup() internal {
        bytes[] memory rawAddresses = new bytes[](3);
        uint8[] memory formats = new uint8[](3);
        uint8[] memory usages = new uint8[](3);

        rawAddresses[0] = OUTBOUND_BTC_ADDRESS_GROUP2;
        rawAddresses[1] = INBOUND_BTC_ADDRESS_GROUP2;
        rawAddresses[2] = OPERATIONS_BTC_ADDRESS_GROUP2;

        formats[0] = ADDRESS_FORMAT_BTC;
        formats[1] = ADDRESS_FORMAT_BTC;
        formats[2] = ADDRESS_FORMAT_BTC;

        usages[0] = AddressUsage.OUTBOUND;
        usages[1] = AddressUsage.INBOUND;
        usages[2] = AddressUsage.OPERATIONS;

        vm.prank(govAddress);
        whitelistRegistry.createGroup(rawAddresses, formats, usages);
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
