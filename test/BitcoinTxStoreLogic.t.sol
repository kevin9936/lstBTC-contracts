// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {Deployer} from "./utils/Deployer.sol";
import {BitcoinTxStoreLogic} from "contracts/bitcoin-tx-store/BitcoinTxStoreLogic.sol";
import {BitcoinTxStoreProxy} from "contracts/bitcoin-tx-store/BitcoinTxStoreProxy.sol";
import {AccessControlBase} from "contracts/access/AccessControlBase.sol";
import "contracts/libraries/BitcoinHelper.sol";

contract BitcoinTxStoreLogicTest is Deployer {
    address public user1;
    address public user2;
    address public relayer1;
    address public relayer2;
    bytes32 public validTxId;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant nonExistentTxid = keccak256("nonExistentTxid");

    event TransactionSubmitted(
        bytes32 indexed txId,
        uint32 indexed blockNumber,
        uint32 currentBlockNumber
    );
    event NewFinalizationParameter(
        uint32 oldFinalizationParameter,
        uint32 newFinalizationParameter
    );

    function setUp() public {
        user1 = address(2000);
        user2 = address(2001);
        relayer1 = address(2002);
        relayer2 = address(2003);
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(relayer1, "Relayer1");
        vm.label(relayer2, "Relayer2");
        vm.prank(govAddress);
        bitcoinTxStore.grantRole(ROLE_RELAYER, relayer2);
        validTxId = setupVerifyAndStoreTransaction();
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertFalse(bitcoinTxStore.paused());
        assertTrue(bitcoinTxStore.hasRole(DEFAULT_ADMIN_ROLE, adminAddress));
        assertTrue(bitcoinTxStore.hasRole(ROLE_GOVERNOR, govAddress));
        assertEq(bitcoinTxStore.getRoleAdmin(ROLE_GOVERNOR), DEFAULT_ADMIN_ROLE);
        assertEq(bitcoinTxStore.getRoleAdmin(ROLE_RELAYER), ROLE_GOVERNOR);
        assertEq(bitcoinTxStore.btcLightClient(), address(btcLightClient));
        assertEq(bitcoinTxStore.initialHeight(), initialHeight);
        assertEq(bitcoinTxStore.finalizationParameter(), finalizationParameter);
    }

    function test_RevertWhen_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        bitcoinTxStore.initialize(
            adminAddress,
            govAddress,
            address(btcLightClient),
            initialHeight,
            finalizationParameter
        );
    }

    function test_Initialize_WithZeroAddress() public {
        BitcoinTxStoreLogic logic = new BitcoinTxStoreLogic();
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,uint32,uint32)",
            address(0),
            govAddress,
            btcLightClient,
            initialHeight,
            finalizationParameter
        );
        BitcoinTxStoreProxy proxy = new BitcoinTxStoreProxy(
            address(logic),
            initData
        );

        BitcoinTxStoreLogic inst = BitcoinTxStoreLogic(address(proxy));
        assertTrue(inst.hasRole(DEFAULT_ADMIN_ROLE, address(0)));
    }

    // ============ Access Control Tests ============

    function test_RevertIf_NotGovernorPauseRelay() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(user1),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        bitcoinTxStore.pauseTxStore();
    }

    function test_RevertIf_NotGovernorUnpauseTxStore() public {
        vm.prank(govAddress);
        bitcoinTxStore.pauseTxStore();
        assertTrue(bitcoinTxStore.paused());

        vm.prank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(user1),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        bitcoinTxStore.unpauseTxStore();
    }

    function test_RevertIf_NotGovernorSetFinalizationParameter() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(user1),
                " is missing role ",
                vm.toString(ROLE_GOVERNOR)
            )
        );
        bitcoinTxStore.setFinalizationParameter(1);
    }

    function test_RevertIf_NotRelayerVerifyAndStoreTransaction() public {
        bytes memory rawTx = hex"0100000001";
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0);
        uint32 index = 0;

        vm.prank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(user1),
                " is missing role ",
                vm.toString(ROLE_RELAYER)
            )
        );
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
    }

    function test_RevertWhen_PausedVerifyAndStoreTransaction() public {
        bytes memory rawTx = hex"0100000001";
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0);
        uint32 index = 0;

        vm.prank(govAddress);
        bitcoinTxStore.pauseTxStore();
        assertTrue(bitcoinTxStore.paused());

        vm.prank(relayer1);
        vm.expectRevert("Pausable: paused");
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
    }

    // ============ pauseTxStore() & unpauseTxStore() Tests ============
    function test_PauseTxStore() public {
        vm.prank(govAddress);
        bitcoinTxStore.pauseTxStore();
        assertTrue(bitcoinTxStore.paused());
    }

    function test_RevertWhen_AlreadyPaused() public {
        vm.prank(govAddress);
        bitcoinTxStore.pauseTxStore();

        vm.prank(govAddress);
        vm.expectRevert("Pausable: paused");
        bitcoinTxStore.pauseTxStore();
    }

    function test_UnpauseTxStore() public {
        vm.prank(govAddress);
        bitcoinTxStore.pauseTxStore();

        vm.prank(govAddress);
        bitcoinTxStore.unpauseTxStore();
        assertFalse(bitcoinTxStore.paused());
    }

    function test_RevertWhen_AlreadyUnpaused() public {
        vm.prank(govAddress);
        vm.expectRevert("Pausable: not paused");
        bitcoinTxStore.unpauseTxStore();
    }

    // ============ Contract Query Method Tests ============

    // lastSubmittedHeight
    function test_GetLastSubmittedHeight() public {
        mockGetChainTipHeight(30000);
        uint32 height = bitcoinTxStore.lastSubmittedHeight();
        assertEq(height, 30000);
    }
    // getBlockTimestamp
    function test_GetBlockTimestamp() public {
        uint32 blockHeight = 800000;
        bytes32 blockHash = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        mockHeight2HashMap(blockHeight, blockHash);
        mockGetTimestamp(blockHash, uint64(1751608556));
        uint64 timestamp = bitcoinTxStore.getBlockTimestamp(blockHeight);
        assertEq(timestamp, uint64(1751608556));
    }

    function test_RevertWhen_GetBlockTimeBlockNotFound() public {
        uint32 blockHeight = 800000;
        bytes32 blockHash = bytes32(0);
        mockHeight2HashMap(blockHeight, blockHash);
        vm.expectRevert("BitcoinTxStore: block does not exist");
        bitcoinTxStore.getBlockTimestamp(blockHeight);
        bytes32 blockHash1 = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        mockHeight2HashMap(blockHeight, blockHash1);
        mockGetTimestamp(blockHash1, uint64(0));
        vm.expectRevert("BitcoinTxStore: invalid block timestamp");
        bitcoinTxStore.getBlockTimestamp(blockHeight);
    }

    // getTransactionLockTime
    function test_GetTransactionLockTime() public view {
        uint32 lockTime = bitcoinTxStore.transactions(validTxId);
        assertEq(lockTime, 201);
    }

    function test_GetTransactionLockTime_WhenTxNotExist() public view {
        uint32 lockTime = bitcoinTxStore.transactions(nonExistentTxid);
        assertEq(lockTime, 0);
    }
    // getInputCount
    function test_GetInputCount() public view {
        uint32 count = bitcoinTxStore.getInputCount(validTxId);
        assertEq(count, 1);
    }

    function test_GetInputCount_WhenTxNotExist() public view {
        uint32 count = bitcoinTxStore.getInputCount(nonExistentTxid);
        assertEq(count, 0);
    }
    // getOutputCount
    function test_GetOutputCount() public view {
        uint32 count = bitcoinTxStore.getOutputCount(validTxId);
        assertEq(count, 2);
    }

    function test_GetOutputCount_WhenTxNotExist() public view {
        uint32 count = bitcoinTxStore.getOutputCount(nonExistentTxid);
        assertEq(count, 0);
    }
    // getTransactionInput
    function test_GetTransactionInput() public view {
        uint16 index = 0;
        (bytes32 prevTxid, uint32 prevIndex) = bitcoinTxStore.getTransactionInput(
            validTxId,
            index
        );
        assertEq(
            prevTxid,
            hex"e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f"
        );
        assertEq(prevIndex, 1);
    }

    function test_RevertWhen_TxNotExistForInput() public {
        uint16 index = 0;
        vm.expectRevert("BitcoinTxStore: input index out of bounds");
        bitcoinTxStore.getTransactionInput(nonExistentTxid, index);
    }

    function test_RevertWhen_InputIndexOutOfBounds() public {
        uint16 invalidIndex = 999;
        vm.expectRevert("BitcoinTxStore: input index out of bounds");
        bitcoinTxStore.getTransactionInput(validTxId, invalidIndex);
    }
    // getTransactionOutput
    function test_GetTransactionOutput() public view {
        uint16 index = 0;
        (bytes32 pkScript, uint64 value) = bitcoinTxStore.getTransactionOutput(
            validTxId,
            index
        );
        assertEq(
            pkScript,
            keccak256(hex"76a914fcde266346ea26ec16fbb96ea573b1855cd0528f88ac")
        );
        assertEq(value, 17899761);
    }

    function test_RevertWhen_TxNotExistForOutput() public {
        uint16 index = 0;
        vm.expectRevert("BitcoinTxStore: output index out of bounds");
        bitcoinTxStore.getTransactionOutput(nonExistentTxid, index);
    }

    function test_RevertWhen_OutputIndexOutOfBounds() public {
        uint16 invalidIndex = 999;
        vm.expectRevert("BitcoinTxStore: output index out of bounds");
        bitcoinTxStore.getTransactionOutput(validTxId, invalidIndex);
    }
    // findTxOutputByPkScript
    function test_FindTxOutputByPkScript() public view {
        bytes
        memory pkScript = hex"76a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac";
        (bool found, uint64 amount, uint16 index) = bitcoinTxStore
            .findTxOutputByPkScript(validTxId, pkScript);
        assertTrue(found);
        assertEq(amount, 2100000);
        assertEq(index, 1);
    }

    function test_FindTxOutputByPkScript_WhenTxNotExist() public view {
        bytes
        memory pkScript = hex"76a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac";
        (bool found, uint64 amount, uint16 index) = bitcoinTxStore
            .findTxOutputByPkScript(nonExistentTxid, pkScript);
        assertFalse(found);
        assertEq(amount, 0);
        assertEq(index, 0);
    }

    function test_FindTxOutputByPkScript_WhenPkScriptNotFound() public view {
        bytes memory wrongPkScript = hex"0000";
        (bool found, uint64 amount, uint16 index) = bitcoinTxStore
            .findTxOutputByPkScript(validTxId, wrongPkScript);
        assertFalse(found);
        assertEq(amount, 0);
        assertEq(index, 0);
    }
    // areAllInputsFromPkScript
    function test_AreAllInputsFromPkScript() public {
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        bytes32 txId1 = setupAndExecuteTransaction(
            hex"0100000001c44f415aa1d30c40921c0e28f38171544fea58ad3bc0257c7fcaca4e6d27a9c5010000006a473044022001a76cf2f03d4dcd9319786bd86c22bcc7f6ffc23460b2114f3ea66e3a60b3b302202c4b1b541d390e63803e7dd7ea963fa2867e6b1b896fb311955b4803c53673a80121021d7c862349152f9a0a74fe2176f07d6c140248244ad2a7c64d9bd5aecd08dc0bffffffff022c4c00000000000017a91436681af231207a3b3ead41a63b8b6ee28d13b13e87fa74cf00000000001976a9146d74dcfb7a1e4aaae5fe53a356cd8b01a3024fa788ac00000000",
            initialHeight + 1,
            merkleProof,
            0
        );
        bytes32 txId2 = setupAndExecuteTransaction(
            hex"010000000166544eb7781cb1a81114c29faf151dc78a1f893a216206b19f2c96297e17dca9000000008b48304502201620f18726e2015272602d0fb7d3e9200752bc76e9089a08b5658075040ce33f022100a8512096188ddc28a07fadb0adec44fc729bde70caaf3cca5254df9a8fcf7bee014104606bf18bd8b5994b1e37ce13e7eed33e8508234a40d8795cfa6fe1f875c7e7eea13d31dc6fc77d2cc02880a9848d1573005d246a7a215b6b1ef48f7296a9d0b3ffffffff02289a0100000000001976a91452a9f45e6907d346f924cde5312a98a7f28adc8f88ac784e3d010000000017a91436681af231207a3b3ead41a63b8b6ee28d13b13e8700000000",
            initialHeight + 1,
            merkleProof,
            0
        );
        bytes32 txId3 = setupAndExecuteTransaction(
            hex"0100000002e8c2dd748a2c8b74e92b344035c0b031722896383ee6a0a071da7c0b7bf9945a000000008c493046022100bf43303c2848c7eaf2ab1e13af7fd0faab7c41e966533a8d1a107fd732585afb022100c1e29c86971553af0a22da185844d1b85f98948ebef995165d80b07f2a10f34a0141042283e9c5f10a2bc9aa9f2f67107de9dde627558ec7deec0e499374acbb820e1843e30572898b21c22f0636d1f3eafe33c077009af44d47e998530e470f6fd6e8ffffffffdea54444d60917755e67878b83693928ad4f779dece60f788b5d3fdd0f73aa3f010000008b4830450220152dc4c541c8ee4f910335341f229c30740af96ac9c377aa202ab9d1d1dfbff00221009938e29456b417d545e6c4f87b42a7df2e8c70dbba3aa8447f160140dabc4cc5014104ee0e2a4438785f693b6d3ece91ab915f9e329c7bfa65fe68d21e8ab3ef4107d3c0d42c218d9a4f80561eb6f83a5f6644d4b47ace4adb5a123bdd287e5cfb358dffffffff02400d0300000000001976a9146f2c8baee0e9e205d6a23fb8c6a1c2e55675335188ac44cd8d03000000001976a914e04d22e13420d48e8ea69ac8b7abfb229b9d6bf188ac00000000",
            initialHeight + 1,
            merkleProof,
            0
        );
        bytes
        memory pkScript = hex"a91436681af231207a3b3ead41a63b8b6ee28d13b13e87";

        bool result = bitcoinTxStore.areAllInputsFromPkScript(txId3, pkScript);
        assertTrue(result);
    }

    function test_RevertWhen_PrevTxNotFound() public {
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        bytes32 txId1 = setupAndExecuteTransaction(
            hex"0200000001b573acd42646f4419ccfe1cfb0c66ec25f99b11de06e468c467648bf94f87f58000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff02204e00000000000017a914cdf3d02dd323c14bea0bed94962496c80c09334487409c00000000000017a91400000000000000000000000000000000000000008700000000",
            initialHeight + 1,
            merkleProof,
            0
        );
        bytes32 txId2 = setupAndExecuteTransaction(
            hex"0200000001e0139d5d32d3a857de4c92332b5d52561a4e90f58375d6607e90448f368c7679000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff02102700000000000017a914000000000000000000000000000000000000000087204e00000000000017a914cdf3d02dd323c14bea0bed94962496c80c0933448700000000",
            initialHeight + 1,
            merkleProof,
            0
        );
        bytes32 txId3 = setupAndExecuteTransaction(
            hex"0200000003286bcbbc41b3033c0aec275f344cf5c9138e4c1a8116ffcb07cfe01d5163a954000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffffb5ddbb0ac7c09f62c1dd1083f683168bfa3dd4f759c586f0acad3a3d22c6caec010000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff658706a735c6ddec12617fba9f8a683267aca597d1f84f7df338530ca309ccdc000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff02a08601000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc0287e09304000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc028700000000",
            initialHeight + 1,
            merkleProof,
            0
        );
        vm.expectRevert("BitcoinTxStore: referenced tx not found");
        bytes
        memory pkScript = hex"a914cdf3d02dd323c14bea0bed94962496c80c09334487";
        bool result = bitcoinTxStore.areAllInputsFromPkScript(txId3, pkScript);
        assertFalse(result);
    }

    function test_RevertWhen_PrevOutputIndexOutOfBounds() public {
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        bytes32 txId1 = setupAndExecuteTransaction(
            hex"02000000011637a4c30a5b8809db13793e10af2c55729902f49d19c2d268fe28e956e5a220000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff02204e00000000000017a914cdf3d02dd323c14bea0bed94962496c80c09334487409c00000000000017a91400000000000000000000000000000000000000008700000000",
            initialHeight + 1,
            merkleProof,
            0
        );
        bytes32 txId2 = setupAndExecuteTransaction(
            hex"0200000001ce76c331de78db0a93a2937042e3ad5454943da6c6e1e1bc2fe1f7b960e3d587020000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff02a08601000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc0287e09304000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc028700000000",
            initialHeight + 1,
            merkleProof,
            0
        );

        bytes
        memory pkScript = hex"a914cdf3d02dd323c14bea0bed94962496c80c09334487";

        vm.expectRevert("BitcoinTxStore: output index out of bounds");
        bitcoinTxStore.areAllInputsFromPkScript(txId2, pkScript);
    }

    function test_ReturnFalse_WhenNotAllInputsFromSamePkScript() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes32 txId1 = setupAndExecuteTransaction(
            hex"0200000001392b9b80b5d5deb73435f153181963dd53714e6d0769f154989656e8ec3808cd000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff02204e00000000000017a914cdf3d02dd323c14bea0bed94962496c80c09334487409c00000000000017a91400000000000000000000000000000000000000008700000000",
            blockHeight,
            merkleProof,
            0
        );

        bytes32 txId2 = setupAndExecuteTransaction(
            hex"0200000001b9948eabc3ad19e629eaa821fa97387afe00504e1d5cceaefe3eb585ec3c9bcc000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff02102700000000000017a914000000000000000000000000000000000000000087204e00000000000017a914cdf3d02dd323c14bea0bed94962496c80c0933448700000000",
            blockHeight,
            merkleProof,
            0
        );

        bytes32 txId3 = setupAndExecuteTransaction(
            hex"02000000026366dd2cd1662794dbd5dbbb088ee5d309dc795409199fdeb9ca4f4c4cbde797000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff095a7cc93c1c34866cd76b8f02e1dc6ede6ffa75a381bd5d8c93162b93446d28000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff02a08601000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc0287e09304000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc028700000000",
            blockHeight,
            merkleProof,
            0
        );

        bytes
        memory pkScript = hex"a914cdf3d02dd323c14bea0bed94962496c80c09334487";
        bool result = bitcoinTxStore.areAllInputsFromPkScript(txId3, pkScript);
        assertFalse(result);
        vm.stopPrank();
    }

    function test_AreAllInputsFromPkScript_WhenTxNotExist() public view {
        bytes memory pkScript = hex"";
        bool result = bitcoinTxStore.areAllInputsFromPkScript(nonExistentTxid, pkScript);
        assertFalse(result);
    }

    // ============ Contract Method Tests ============

    // setFinalizationParameter
    function test_SetFinalizationParameter() public {
        uint32 newParam = 10;
        vm.expectEmit(true, true, true, true);
        emit NewFinalizationParameter(finalizationParameter, newParam);

        vm.prank(govAddress);
        bitcoinTxStore.setFinalizationParameter(newParam);

        assertEq(bitcoinTxStore.finalizationParameter(), newParam);
    }

    function test_RevertWhen_SetZeroFinalizationParameter() public {
        uint32 newParam = 0;
        vm.expectRevert("BitcoinTxStore: invalid finalization param");

        vm.prank(govAddress);
        bitcoinTxStore.setFinalizationParameter(newParam);
    }

    function test_RevertWhen_SetTooLargeFinalizationParameter() public {
        uint32 newParam = type(uint32).max;
        vm.expectRevert("BitcoinTxStore: invalid finalization param");

        vm.prank(govAddress);
        bitcoinTxStore.setFinalizationParameter(newParam);
    }

    // verifyAndStoreTransaction
    function test_VerifyAndStoreTransaction() public {
        bytes
        memory rawTx = hex"0200000001cd11d099d538907b77aa3a44ea79da38923b0f04bd825ec0e5602b594910c2ad000000006a47304402204b1552356ec793076034d32fa183bca4afb5f6c945732b74d97503d53055690802204e275bf5d5658719d41f2d9b2c9c787c16e40d44234043d331ef99d485e7a9800121020f6e1103917a312fec20143688fbc3c1c0f95228689ca4b5090cbeb33e19b2f1ffffffff0240420f00000000002251208be6a1760a26b924d8d64ba280c8fb63e1508a76b221296afe20453401ed9b8ef0352157000000001976a914cac38fc22cce89ca3607121385fc091a9318467788ac00000000";
        uint32 blockHeight = 800000;
        bytes32 txId = BitcoinHelper.calculateTxId(rawTx);
        mockCheckTxProof(
            txId,
            blockHeight,
            true
        );
        mockGetChainTipHeight(20000);
        // Execute transaction verification and storage
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(txId, blockHeight, 20000);

        vm.prank(relayer2);
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0
        );
        bytes32 inputHash = hex"cd11d099d538907b77aa3a44ea79da38923b0f04bd825ec0e5602b594910c2ad";
        bytes
        memory outputScript = hex"51208be6a1760a26b924d8d64ba280c8fb63e1508a76b221296afe20453401ed9b8e";
        bytes
        memory outputScript2 = hex"76a914cac38fc22cce89ca3607121385fc091a9318467788ac";
        verifyTransactionInput(txId, inputHash, 0, 0);
        verifyTransactionBasics(txId, blockHeight, 1, 2);
        verifyTransactionOutputs(txId, outputScript, 1000000, 0);
        verifyTransactionOutputs(txId, outputScript2, 1461794288, 1);
    }

    function test_VerifyAndStoreTransaction_P2PK() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f120110100000000434104faa1d42f953fee4dcb8f5ad977112febf3e9e9d25b66f6bc429a6dbc31591910753938d1645c829d066172d7f97f0a03efff5ef9a488ef6b48347b5f304a37f6ac200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac00000000";
        bytes
        memory scriptPubKey0 = hex"4104faa1d42f953fee4dcb8f5ad977112febf3e9e9d25b66f6bc429a6dbc31591910753938d1645c829d066172d7f97f0a03efff5ef9a488ef6b48347b5f304a37f6ac";
        bytes
        memory scriptPubKey1 = hex"76a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac";

        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 1, 2);
        verifyTransactionOutputs(txId, scriptPubKey0, 17899761, 0);
        verifyTransactionOutputs(txId, scriptPubKey1, 2100000, 1);
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransation_P2PKH() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f1201101000000001976a9143fd4c866d4af1f06f78f3e572375f9dbb20d581488ac200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac00000000";
        bytes
        memory scriptPubKey = hex"76a9143fd4c866d4af1f06f78f3e572375f9dbb20d581488ac";

        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 1, 2);
        verifyTransactionOutputs(txId, scriptPubKey, 17899761, 0);
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_P2MS() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f1201101000000004751210000000000000000000000000000000000000000000000000000000000000000012100000000000000000000000000000000000000000000000000000000000000000252ae200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac00000000";
        bytes
        memory scriptPubKey = hex"51210000000000000000000000000000000000000000000000000000000000000000012100000000000000000000000000000000000000000000000000000000000000000252ae";

        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 1, 2);
        verifyTransactionOutputs(txId, scriptPubKey, 17899761, 0);
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_P2SH() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f12011010000000017a914666a9ebe102613f33e32fea253fb7894bf1a543187200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac00000000";
        bytes
        memory scriptPubKey = hex"a914666a9ebe102613f33e32fea253fb7894bf1a543187";

        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 1, 2);
        verifyTransactionOutputs(txId, scriptPubKey, 17899761, 0);
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_P2WPKH() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f1201101000000001600146b08dfab52020129ad24bac51dbf0c4ad61f26eb200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac00000000";
        bytes
        memory scriptPubKey = hex"00146b08dfab52020129ad24bac51dbf0c4ad61f26eb";

        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 1, 2);
        verifyTransactionOutputs(txId, scriptPubKey, 17899761, 0);
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_P2WSH() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f12011010000000022002071b7a2b6a2b39b604a9bfb3441113ca316aaf2c6151b7fe45e36a6c0ecc92c7e200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac00000000";
        bytes
        memory scriptPubKey = hex"002071b7a2b6a2b39b604a9bfb3441113ca316aaf2c6151b7fe45e36a6c0ecc92c7e";

        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 1, 2);
        verifyTransactionOutputs(txId, scriptPubKey, 17899761, 0);
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_P2TR() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f1201101000000002251203620708f7e1f3f023853f146a18876a58bf6ca2cbebe290f1e724dc2388b98a7200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88ac00000000";
        bytes
        memory scriptPubKey = hex"51203620708f7e1f3f023853f146a18876a58bf6ca2cbebe290f1e724dc2388b98a7";

        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 1, 2);
        verifyTransactionOutputs(txId, scriptPubKey, 17899761, 0);
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_Segwit() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"010000000568c541c5b14cbeb0b76a628d855d4bfce9b66a18b6442e9b440d3aa5277ec80c1000000023220020405ad5dc37c98e2e70902504ce62d9941c0c7af074b9519b9172e084bdfdb471ffffffffb018416c903bb0a86943f1225c3eca363420ea6a691788d87e684115cf3eaea0010000002322002062d57e2cd1a94f96a349204e4b911d7767db88453769b1045b6bb2fa53c6a07affffffff5b82625eaab0a1ef9541a7fa0258f2f7c5b6f735d8d475bfa95c8b674684ce520000000023220020ff984a148f9e961e0253d96e45db1ba1fb1859a24393e564cb522828707da222ffffffff5266ee50df1c4145622c0e05a534411729726ef71009b2587ef0414b402f37cc0000000023220020795e28d36704b5bf613bd4548ff66ee54ce7d2760b8a37e3cd52828e586d7033ffffffff489f5e2695ad86196f0b9e3bd6fc0b87c1530a005695fb52556cfb6c44b8778500000000232200208965e6e3cb2c649f5d0491f22be09d008f39e93f81ba52209b1d880b9c84f772ffffffff0294062e010000000017a9142f3156b26e4405d3314be7349648f95f87c9cb0f87899c4e000000000017a914949b5949805ca106d8f3a412f5f0cc43ed63c3d18700000000";
        bytes
        memory scriptPubKey = hex"a9142f3156b26e4405d3314be7349648f95f87c9cb0f87";

        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 5, 2);
        verifyTransactionInput(
            txId,
            hex"b018416c903bb0a86943f1225c3eca363420ea6a691788d87e684115cf3eaea0",
            1,
            1
        );
        verifyTransactionOutputs(txId, scriptPubKey, 19793556, 0);
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_MultipleInputsAndOutputs() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        // Transaction with 15 inputs and 20 outputs
        bytes
        memory rawTx = hex"010000000fadd85512f94c6234dc1d6463d526ead9f0f9ade559959f96c7b01cf2da001c6800000000109145f760a9769412000aaa80171cbf36ffffffffc7d7531c62b45ab61d51a9547a5868ea3849a848d63721af2bae88f9fd5d824c05000000237c6c387c5d795f944a64f102ea64bb93bfbe972cedc8b05be05b437e41e3c78335801dfffffffffd78a3c3afa84fd4f88e7ad6042af0004a70dc787d56034fd823b6afcc9be83a070000000cf2337dd5916b05b5dce5f259ffffffff1b13da44236d84b366a67dc425801edbb9910849f997a103f9cc424224d78b08010000002b9e9e2bfb111edb9741256ffcae33018573e6c0fb1d0cf8a12a8544291ad7e962924017245264e7e35900c0ffffffff3c21b9ce7bf98aa73932b49859b87e397bfdb7e4bdb2aa55c682eab50a355f45070000001becc4803f867f81c8cf01f00af09db2c3462cb1159f28dadc9f1684ffffffff436892f69070f2d55eb047fd33c57426cc7bd13e2bce9eb2a160db86121b328a01000000119344c1e37d365a0ff0b881525dc2814ea6ffffffff4787e6a84e25aa72569c1f132dd23eae9f6dd69ba70008ceb02c85ab590342e4040000000b46e3a28b8a14fa20806986ffffffff673bb9beeacfd9deff8eeb8821f8cf1c68551d568c8c5d4b1db5dc2bb52f4692060000000b5efd63fb1071488ab4fd08ffffffffc452660fea2bd02f69f244f036d9232de97feea93adf592700190d8ac06eb5a7090000000d6ce95d5a20176dcb934391a29cffffffff34ec239b85268980370410aaa201a6de51a2f3532ab804cd90b4672d6b94c8ff0500000020d7bebffd9277736db3ee5969eac7a90191f1098556aa49b4231395009d09e7e7ffffffff077fbf74ab3815f3d42f28c046967cc6dbb0699274b42f8b42a8c870225382be08000000282046412dcbfa92296f4fd2f9ea078d5079cac0a9cf686d91cb6ff154d9f4e885a8a19a19a5bc13a2ffffffffa17a47fd3322d2e1717e7b2dbb7c869aa486c1a5a207aa241238e6a5a8805f540100000020300a327d45f54ca3d1c7169c8a85570ca78d8e7120b1017525d0a4cbbc3f7d84ffffffff83064c05d789460d943bd16c15fa265190bdf52b7f98894606ddc0595c9d89c0050000001b8eec7c96711fa9f90145cececb0b43d9d668b5c7e98ab0be724734ffffffffbcc61ff88b5bf9a94e423bdb7d3151fa3d7fafb0707aca4ffb93b2562956005f0500000012e87965ba9b6e71c0bca5faeaa0ede17e128effffffff8cdba5431103906af360865a78b96db4005e1285d8f1ced16f359b7eba74fd9505000000211e583948037434aed3539bb882a558e8b4996ac20a630b0f647bd511e91cfd6f36ffffffff14ea6708000000000017aa5a2734986539263e142043ec4ca5929608985373a2c97d470d00000000001feb895709bb5a6f330db9ed8a9290a47e321f019eb6079832f0d52b7e59474fec2b07000000000015ca4a99706d3934b4cfe2ee79a3a2d7d349157985917cb0040000000000151e9e73e15de78fd2577ad4da1982ddc76a1f7ff2bd4a7d0c0000000000156d8076b55ee901faa99c468ab732b7548cd0e8634c774c03000000000014da09381570b01df8641b932ef2c616cfb8ad00c7cdba0000000000001a0f08366a2d752bb8b6d8bed95638bd77484e0d0b5dd085855d5f50b2080000000000184e3ec9354ad604c2e68a24e127bccd591a89db66c7625e9b05770800000000001da9dd06ae7697e7266e7631b9946f17a8d3de4e9a59611625348b9c73ed5ac009000000000020aa7feb0b5278e8c5b9b7b02b10ed2b443cd8d4fda521437de53a2ebb6325039d7bcc0200000000001af591fc4bd3a74b9a51188ba3ee9d105f27feea833e578a6a99f05d200400000000001e6f4bcc6fbd1c761c48fe33b5fd0db91820ea1ddf78b9784ed48cedf962a6aa150d000000000017d930fd9d34b008f57652e1a63c45536a68ce4b080c6fc48db800000000000021c37dc2a619fa6fd14ec9bf00ebc5aa82024161b0ad142412bee99ac34a7d0baee1d471050000000000163cca5cf894b137f847fc3b92b106dc9b705c3d8b5becd4090400000000001ca468f1c88fc03232827cac1009d8654235306031d660d4ddea0725ae724c0b00000000001c90429c11ad13e07584bd268e08587f811a127e3e655316c4f23c7ec155b60500000000001b88dab926721955452bebe5dabc9f3d08012b5d7afbeada10d853dcad03020000000000185415acb59f991cf6ffe449bd09fa51a4cdef2f4b8585ae4167ba0700000000002197fe73c2b499c2f5383650293f3451716ec38be58b625bd2ddec6a5ca83c7d7ae700000000";
        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        verifyTransactionBasics(txId, blockHeight, 15, 20);
        verifyTransactionInput(
            txId,
            hex"bcc61ff88b5bf9a94e423bdb7d3151fa3d7fafb0707aca4ffb93b2562956005f",
            5,
            13
        );
        verifyTransactionOutputs(
            txId,
            hex"97fe73c2b499c2f5383650293f3451716ec38be58b625bd2ddec6a5ca83c7d7ae7",
            506471,
            19
        );
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_WithMultipleOpReturns() public {
        vm.startPrank(relayer2);
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);

        bytes
        memory rawTx = hex"0100000001addfff484aed206dfd9d121861324e5168f4236c77e7157fb4c6abd999a515d5000000008a4730440220271476946d612f20e1c869e607992ac601f17496e2d1da41dc0d972a5030f1040220023ae259bec309a3558f78741656c6fe870ee192c041c7b4fbd4e38602907130014104d0f9cf61a61bf841a723f416ff1191689cec2c9ed0d4433cad1d99ff15b73ca2fe7e920a78595eca3c2796df0daecb61ab98e6cc7439276b472cbf73d10b1aacffffffff040024f400000000001976a914dde0028109cbd723a6b4a0564327d5186ffd08ad88ac50536001000000001976a9143f517f53e32714055decb218150f47534e9d64cb88ac00000000000000000d6a0b68656c6c6f20776f726c640000000000000000126a1068656c6c6f20776f726c64788823111200000000";
        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );

        verifyTransactionBasics(txId, blockHeight, 1, 4);

        verifyTransactionOutputs(
            txId,
            hex"76a914dde0028109cbd723a6b4a0564327d5186ffd08ad88ac",
            16000000,
            0
        );
        verifyTransactionOutputs(
            txId,
            hex"76a9143f517f53e32714055decb218150f47534e9d64cb88ac",
            23090000,
            1
        );
        verifyTransactionOpReturn(txId, 2);
        verifyTransactionOpReturn(txId, 3);

        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_WithMultipleInputs() public {
        bytes
        memory rawTx = hex"02000000038a656ab2c7280ecb24ff658978205253ec0a2e9c561346fe30133efdac9b229b000000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffffa2941707619c4c713a4d6a04622dfe7644d6fa4ea565fab5030e8ff7af67a754030000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff567accc21bd9b571081ff76ce71c39e96f0bb43b0ccf09dddf8c1de603542e26020000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff026c0700000000000017a914cdf3d02dd323c14bea0bed94962496c80c09334487701700000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc028700000000";
        uint32 blockHeight = 800000;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        mockGetChainTipHeight(20000);
        vm.startPrank(relayer2);
        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        uint32 lockTime = bitcoinTxStore.transactions(txId);
        assertEq(lockTime, 0);
        verifyTransactionBasics(txId, blockHeight, 3, 2);
        bytes32 inputHash = hex"8a656ab2c7280ecb24ff658978205253ec0a2e9c561346fe30133efdac9b229b";
        bytes32 inputHash2 = hex"a2941707619c4c713a4d6a04622dfe7644d6fa4ea565fab5030e8ff7af67a754";
        bytes32 inputHash3 = hex"567accc21bd9b571081ff76ce71c39e96f0bb43b0ccf09dddf8c1de603542e26";
        verifyTransactionInput(txId, inputHash, 0, 0);
        verifyTransactionInput(txId, inputHash2, 3, 1);
        verifyTransactionInput(txId, inputHash3, 2, 2);

        verifyTransactionOutputs(
            txId,
            hex"a914cdf3d02dd323c14bea0bed94962496c80c09334487",
            1900,
            0
        );
        verifyTransactionOutputs(
            txId,
            hex"a914047b9ba09367c1b213b5ba2184fba3fababcdc0287",
            6000,
            1
        );
        vm.stopPrank();
    }

    function test_VerifyAndStoreTransaction_WithOpReturn() public {
        bytes
        memory rawTx = hex"020000000294547117a06307ff3d291f9a12c11792bc0b740281a02f593547e31c9282b9e2010000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff9a929266910474fa0da753a4d5ca383ff3d6a33e94fd3ee52e2ab0175b689f6c020000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff036c0700000000000017a914cdf3d02dd323c14bea0bed94962496c80c0933448700000000000000001e6a1c5341542b0204589fb29aac15b9a4b7f17c3385939b007540f4d79101701700000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc028700000000";
        uint32 blockHeight = initialHeight + 1;
        bytes32 txId = BitcoinHelper.calculateTxId(rawTx);
        mockCheckTxProof(
            txId,
            blockHeight,
            true
        );
        mockGetChainTipHeight(20000);

        vm.prank(relayer2);
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0
        );

        verifyTransactionInput(
            txId,
            hex"94547117a06307ff3d291f9a12c11792bc0b740281a02f593547e31c9282b9e2",
            1,
            0
        );
        verifyTransactionInput(
            txId,
            hex"9a929266910474fa0da753a4d5ca383ff3d6a33e94fd3ee52e2ab0175b689f6c",
            2,
            1
        );
        verifyTransactionOpReturn(
            txId,
            1
        );
        verifyTransactionOutputs(
            txId,
            hex"a914cdf3d02dd323c14bea0bed94962496c80c09334487",
            1900,
            0
        );
        verifyTransactionOutputs(
            txId,
            hex"a914047b9ba09367c1b213b5ba2184fba3fababcdc0287",
            6000,
            2
        );
    }

    function test_VerifyAndStoreTransaction_WithZeroValueOutput() public {
        bytes
        memory rawTx = hex"02000000024978d17d616d89c565330cd5956e036afd1751119f1c52966ac89188cb84cdde010000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff5c1eddabfeea9ef4203943aa6715cd11bcdc6bcd46a23d69f571574466bd6cd5020000006a473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9fffffffff03000000000000000017a914cdf3d02dd323c14bea0bed94962496c80c0933448700000000000000001e6a1c5341542b0204589fb29aac15b9a4b7f17c3385939b007540f4d79101701700000000000017a914047b9ba09367c1b213b5ba2184fba3fababcdc028700000000";
        uint32 blockHeight = initialHeight + 1;
        bytes32 txId = BitcoinHelper.calculateTxId(rawTx);
        mockCheckTxProof(
            txId,
            blockHeight,
            true
        );
        mockGetChainTipHeight(20000);

        vm.prank(relayer2);
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0
        );
        verifyTransactionOutputs(
            txId,
            hex"a914cdf3d02dd323c14bea0bed94962496c80c09334487",
            0,
            0
        );
    }

    function test_VerifyAndStoreTransaction_WithLockTime() public {
        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f1201101000000001976a914fcde266346ea26ec16fbb96ea573b1855cd0528f88ac200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88acc7000000"; // locktime set to 199
        uint32 blockHeight = initialHeight + 1;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        uint32 lockTime = bitcoinTxStore.transactions(txId);
        assertEq(lockTime, 199);
    }

    function test_RevertWhen_InvalidTransaction() public {
        bytes
        memory rawTx = hex"01000000000101e1e6b4b4a4afe9e4f6537df6021b38c309927a8cbac295787080b8168cde07b40b000000232200203717bedc8adee5454bb9654a58ffd7e7a4893427a22525705064df35ecd719e5ffffffff0219130e000000000017a914ff16716d61ae0a7fe86f34e68595aa39da1e904787c7e0760000000000220020d3cbc58beb53ddfb926e897cf1504757710283cbf4d69a5c421944e46cedb11f0300483045022100ee5f92b0d5b568323efd67107dae3b8d9551a98e1b50df9215531192ffa3eae1022062fbd32ca3d5b08cff407d5f4ec49c7a33299d74b67982bb4d799afe51d7946c012551210240636e2f89a910a3304a21a881a2bff001cedef1f836191aab0ba359a56b24b951ae00000000"; // Invalid transaction data
        uint32 blockHeight = initialHeight + 1;
        bytes32 txId = BitcoinHelper.calculateTxId(rawTx);
        vm.startPrank(relayer2);
        mockCheckTxProof(
            txId,
            blockHeight,
            true
        );
        vm.expectRevert("BitcoinHelper: invalid tx");
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0
        );
        vm.stopPrank();
    }

    function test_RevertWhen_BlockHeightBelowInitial() public {
        bytes
        memory rawTx = hex"0200000001cd11d099d538907b77aa3a44ea79da38923b0f04bd825ec0e5602b594910c2ad000000006a47304402204b1552356ec793076034d32fa183bca4afb5f6c945732b74d97503d53055690802204e275bf5d5658719d41f2d9b2c9c787c16e40d44234043d331ef99d485e7a9800121020f6e1103917a312fec20143688fbc3c1c0f95228689ca4b5090cbeb33e19b2f1ffffffff0240420f00000000002251208be6a1760a26b924d8d64ba280c8fb63e1508a76b221296afe20453401ed9b8ef0352157000000001976a914cac38fc22cce89ca3607121385fc091a9318467788ac00000000";
        uint32 blockHeight = initialHeight - 1;
        bytes32[] memory merkleProof = new bytes32[](1);
        uint16 index = 0;
        vm.prank(relayer2);
        vm.expectRevert("BitcoinTxStore: block number below initial height");
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
    }

    function test_RevertWhen_EmptyMerkleProof() public {
        bytes
        memory rawTx = hex"0200000001cd11d099d538907b77aa3a44ea79da38923b0f04bd825ec0e5602b594910c2ad000000006a47304402204b1552356ec793076034d32fa183bca4afb5f6c945732b74d97503d53055690802204e275bf5d5658719d41f2d9b2c9c787c16e40d44234043d331ef99d485e7a9800121020f6e1103917a312fec20143688fbc3c1c0f95228689ca4b5090cbeb33e19b2f1ffffffff0240420f00000000002251208be6a1760a26b924d8d64ba280c8fb63e1508a76b221296afe20453401ed9b8ef0352157000000001976a914cac38fc22cce89ca3607121385fc091a9318467788ac00000000";
        uint32 blockHeight = initialHeight + 1;
        bytes32[] memory merkleProof = new bytes32[](0);
        uint16 index = 0;
        vm.prank(relayer2);
        vm.expectRevert("BitcoinTxStore: empty merkle proof");
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
    }

    function test_RevertWhen_TxNotFinalized() public {
        bytes
        memory rawTx = hex"0200000001cd11d099d538907b77aa3a44ea79da38923b0f04bd825ec0e5602b594910c2ad000000006a47304402204b1552356ec793076034d32fa183bca4afb5f6c945732b74d97503d53055690802204e275bf5d5658719d41f2d9b2c9c787c16e40d44234043d331ef99d485e7a9800121020f6e1103917a312fec20143688fbc3c1c0f95228689ca4b5090cbeb33e19b2f1ffffffff0240420f00000000002251208be6a1760a26b924d8d64ba280c8fb63e1508a76b221296afe20453401ed9b8ef0352157000000001976a914cac38fc22cce89ca3607121385fc091a9318467788ac00000000";
        uint32 blockHeight = initialHeight + 1;
        bytes32 txId = BitcoinHelper.calculateTxId(rawTx);
        mockCheckTxProof(
            txId,
            blockHeight,
            false
        );
        mockGetChainTipHeight(blockHeight + finalizationParameter - 1);
        vm.prank(relayer2);
        vm.expectRevert("BitcoinTxStore: transaction not finalized");
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0
        );
    }

    function test_RevertWhen_DuplicateSubmission() public {
        bytes
        memory rawTx = hex"0200000001cd11d099d538907b77aa3a44ea79da38923b0f04bd825ec0e5602b594910c2ad000000006a47304402204b1552356ec793076034d32fa183bca4afb5f6c945732b74d97503d53055690802204e275bf5d5658719d41f2d9b2c9c787c16e40d44234043d331ef99d485e7a9800121020f6e1103917a312fec20143688fbc3c1c0f95228689ca4b5090cbeb33e19b2f1ffffffff0240420f00000000002251208be6a1760a26b924d8d64ba280c8fb63e1508a76b221296afe20453401ed9b8ef0352157000000001976a914cac38fc22cce89ca3607121385fc091a9318467788ac00000000";
        uint32 blockHeight = initialHeight + 1;
        bytes32 txId = BitcoinHelper.calculateTxId(rawTx);

        mockCheckTxProof(
            txId,
            blockHeight,
            true
        );
        mockCheckTxProof(
            txId,
            blockHeight + 2,
            true
        );
        mockGetChainTipHeight(20000);

        vm.prank(relayer2);
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0
        );

        vm.prank(relayer2);
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight + 2,
            new bytes32[](1),
            0
        );

    }

    // Internal functions
    function verifyTransactionBasics(
        bytes32 txId,
        uint32 /*blockHeight*/,
        uint16 inputCount,
        uint16 outputCount
    ) internal view {
        assertEq(bitcoinTxStore.getInputCount(txId), inputCount);
        assertEq(bitcoinTxStore.getOutputCount(txId), outputCount);
    }

    function verifyTransactionOutputs(
        bytes32 txId,
        bytes memory scriptPubKey,
        uint64 expectedValue,
        uint16 index
    ) internal view {
        (bytes32 outputScript1, uint64 outputValue1) = bitcoinTxStore
            .getTransactionOutput(txId, index);
        assertEq(outputValue1, expectedValue);
        assertEq(outputScript1, keccak256(scriptPubKey));
    }

    function verifyTransactionOpReturn(
        bytes32 txId,
        uint16 index
    ) internal view {
        (bytes32 outputScript, uint64 outputValue) = bitcoinTxStore
            .getTransactionOutput(txId, index);
        assertEq(outputValue, 0);
        assertEq(outputScript, bytes32(0));
    }

    function verifyTransactionInput(
        bytes32 txId,
        bytes32 inputHash,
        uint32 expectedIndex,
        uint16 index
    ) internal view {
        (bytes32 inputHash1, uint64 index1) = bitcoinTxStore.getTransactionInput(
            txId,
            index
        );
        assertEq(inputHash, inputHash1);
        assertEq(expectedIndex, index1);
    }

    function setupAndExecuteTransaction(
        bytes memory rawTx,
        uint32 blockHeight,
        bytes32[] memory merkleProof,
        uint16 index
    ) internal returns (bytes32) {
        bytes32 txId = BitcoinHelper.calculateTxId(rawTx);
        vm.startPrank(relayer2);
        mockCheckTxProof(
            txId,
            blockHeight,
            true
        );
        bitcoinTxStore.verifyAndStoreTransaction(
            rawTx,
            blockHeight,
            merkleProof,
            index
        );
        vm.stopPrank();
        return txId;
    }

    function setupVerifyAndStoreTransaction() internal returns (bytes32) {
        vm.startPrank(relayer2);
        bytes
        memory rawTx = hex"0100000001e8906c50bdbb57d2c2e3c38a06d16ec700bf7926d99cfff7956041e77eb5005f010000006b48304502210094e440e8b81d5b216df5a01f9b76ab58e7039ac3f1bf0f75d6ef414cacd653b802204492c0b8aaa6fd15dc18b0e75b13766df3f38228f2f7b09c946787d8c4454c9b012102be79b7f211e14cb043542bc004cd74aa51a25e73e5250003ee8621f04897c6d4feffffff02f1201101000000001976a914fcde266346ea26ec16fbb96ea573b1855cd0528f88ac200b2000000000001976a9143d7dc254df426266efd5a3aa165c5ceb6af10a1e88acc9000000";
        uint32 blockHeight = initialHeight + 1;
        mockGetChainTipHeight(20000);
        bytes32 txId = setupAndExecuteTransaction(
            rawTx,
            blockHeight,
            new bytes32[](1),
            0
        );
        vm.stopPrank();
        return txId;
    }
}
