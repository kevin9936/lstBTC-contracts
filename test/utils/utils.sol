pragma solidity 0.8.4;

import "forge-std/Test.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

import {AccessControlBase} from "contracts/access/AccessControlBase.sol";
import {LstBTCBridgeLogic} from "contracts/bridge/LstBTCBridgeLogic.sol";
import {LstBTCBridgeProxy} from "contracts/bridge/LstBTCBridgeProxy.sol";
import {ConfigRegistryLogic} from "contracts/configuration/ConfigRegistryLogic.sol";
import {ConfigRegistryProxy} from "contracts/configuration/ConfigRegistryProxy.sol";
import {NavProviderLogic} from "contracts/nav/NavProviderLogic.sol";
import {NavProviderProxy} from "contracts/nav/NavProviderProxy.sol";
import {BitcoinTxStoreLogic} from "contracts/bitcoin-tx-store/BitcoinTxStoreLogic.sol";
import {BitcoinTxStoreProxy} from "contracts/bitcoin-tx-store/BitcoinTxStoreProxy.sol";

import {LstBTCLogic} from "contracts/token/LstBTCLogic.sol";
import {LstBTCProxy} from "contracts/token/LstBTCProxy.sol";

import {WhitelistRegistryLogic} from "contracts/whitelist/WhitelistRegistryLogic.sol";
import {WhitelistRegistryProxy} from "contracts/whitelist/WhitelistRegistryProxy.sol";
import "contracts/libraries/BitcoinHelper.sol";


contract Utils is Test {
    struct BtcInput {
        bytes32 txid;
        uint32 index;
    }

    struct BtcOutput {
        bytes script;
        uint64 amount;
    }
    // BTC address formats
    bytes public constant P2PKH_ADDRESS = hex"76a914389ffce9cd9ae88dcc0631e88a821ffdbe9bfe2688ac";
    bytes public constant P2WPKH_ADDRESS = hex"0014aba3d53c88109b0819109f55fc8df68f5074dda7";
    bytes public constant P2PK_ADDRESS = hex"210333976279e369e613f4d93a5157ef1c3d4e91ad01af411e954c9ad3c73f329639ac";
    bytes public constant P2SH_ADDRESS = hex"a914aefe1b9da069b2a69137ecac18143875f0e3846287";
    bytes public constant P2TR_ADDRESS = hex"5120fa4aba8acdbe972b36e8113a1d8c85f53deacaa84f9ae3dd4e8ab1623e6dbe31";
    bytes public constant P2WSH_ADDRESS = hex"00204aa3c6fd06dbd5742622ec58f7b85a8ed34dbdb6791c346ab03f3f64da6ae1be";
    bytes public constant P2MS_ADDRESS = hex"51210000000000000000000000000000000000000000000000000000000000000000012100000000000000000000000000000000000000000000000000000000000000000252ae";
    // Native address
    bytes public constant LST_ADDRESS1 = hex"C33B9734003154A6e1C305F313201AC247C42392";
    bytes public constant LST_ADDRESS2 = hex"DcE49E20aEA8be32C182E4f3429258001A101767";
    bytes public constant LST_ADDRESS3 = hex"0e3d18A5703c2f7b024d79b878b586Cbd844C159";

    address btcLightClient = address(1007);

    function mockCheckTxProof(
        bytes32 txId,
        uint32 blockHeight,
        bool isFinalized
    ) public {
        vm.mockCall(
            btcLightClient,
            abi.encodeWithSignature(
                "checkTxProof(bytes32,uint32,uint32,bytes32[],uint256)",
                txId,
                blockHeight,
                2,
                new bytes32[](1),
                0
            ),
            abi.encode(isFinalized)
        );
    }

    function mockGetChainTipHeight(uint32 chainTipHeight) public {
        vm.mockCall(
            btcLightClient,
            abi.encodeWithSignature("getChainTipHeight()"),
            abi.encode(chainTipHeight)
        );
    }

    function mockHeight2HashMap(uint32 blockHeight, bytes32 result) public {
        vm.mockCall(
            btcLightClient,
            abi.encodeWithSignature("height2HashMap(uint32)", blockHeight),
            abi.encode(result)
        );
    }

    function mockGetTimestamp(bytes32 blockHash, uint64 timestamp) public {
        vm.mockCall(
            btcLightClient,
            abi.encodeWithSignature("getTimestamp(bytes32)", blockHash),
            abi.encode(timestamp)
        );
    }

    function buildRawTxFlexible(
        BtcInput[] memory inputs,
        BtcOutput[] memory outputs
    ) public pure returns (bytes memory) {
        bytes memory rawTx;

        rawTx = abi.encodePacked(rawTx, hex"02000000");

        rawTx = abi.encodePacked(rawTx, uint8(inputs.length));

        for (uint i = 0; i < inputs.length; i++) {
            rawTx = abi.encodePacked(rawTx, inputs[i].txid);
            rawTx = abi.encodePacked(rawTx, _toLE32(inputs[i].index));
            rawTx = abi.encodePacked(rawTx, uint8(106));
            rawTx = abi.encodePacked(
                rawTx,
                hex"473044022046e23b8f6b749a15b0571848fe2b86bfbe7e158b23f37fb0335be0a71f48a5dd022076640b2d39659c26224c9e67101b34e1394a38ff08a4bdd88d7503f63e54adc5012103b3e19c8169b81d15ec21f9d0f3ed4b2f18c7c9e1149ce5f7ddebed7732724b9f"
            );
            rawTx = abi.encodePacked(rawTx, uint32(0xffffffff));
        }

        rawTx = abi.encodePacked(rawTx, uint8(outputs.length));

        for (uint j = 0; j < outputs.length; j++) {
            rawTx = abi.encodePacked(rawTx, btcValue2Hex(outputs[j].amount));
            rawTx = abi.encodePacked(rawTx, uint8(outputs[j].script.length));
            rawTx = abi.encodePacked(rawTx, outputs[j].script);
        }

        rawTx = abi.encodePacked(rawTx, uint32(0));

        return rawTx;
    }

    function createInput(
        bytes32 txid,
        uint32 index
    ) internal pure returns (BtcInput memory) {
        return BtcInput({txid: txid, index: index});
    }

    function createOutput(
        bytes memory script,
        uint64 amount
    ) internal pure returns (BtcOutput memory) {
        return BtcOutput({script: script, amount: amount});
    }

    function btcValue2Hex(uint64 amount) internal pure returns (bytes memory) {
        bytes memory result = new bytes(8);
        for (uint i = 0; i < 8; i++) {
            result[i] = bytes1(uint8(amount >> (i * 8)));
        }
        return result;
    }

    function buildBtcRawTx(bytes32 utxo, uint32 index, bytes memory toPkScript, uint64 amount, bytes memory changePkScript, uint64 changeAmount) public
    returns (bytes memory rawTx, bytes32 txId, bytes[] memory toPkScripts) {
        BtcInput[] memory inputs = new BtcInput[](1);
        uint8 outputCount = 1;
        if (changeAmount > 0) {
            outputCount = 2;
        }
        BtcOutput[] memory outputs = new BtcOutput[](outputCount);
        inputs[0] = createInput(utxo, index);
        outputs[0] = createOutput(toPkScript, amount);
        if (changeAmount > 0) {
            outputs[1] = createOutput(changePkScript, changeAmount);
        }
        rawTx = buildRawTxFlexible(inputs, outputs);
        txId = BitcoinHelper.calculateTxId(rawTx);
        toPkScripts = new bytes[](outputCount);
        toPkScripts[0] = toPkScript;
        if (changeAmount > 0) {
            toPkScripts[1] = changePkScript;
        }
    }

    function _toLE32(uint32 value) internal pure returns (bytes memory) {
        bytes memory result = new bytes(4);
        result[0] = bytes1(uint8(value));
        result[1] = bytes1(uint8(value >> 8));
        result[2] = bytes1(uint8(value >> 16));
        result[3] = bytes1(uint8(value >> 24));
        return result;
    }
}
