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
import {Utils} from "test/utils/utils.sol";

contract Deployer is Utils {
    LstBTCBridgeLogic public lstBTCBridge;
    ConfigRegistryLogic public configRegistry;
    NavProviderLogic public navProvider;
    BitcoinTxStoreLogic public bitcoinTxStore;
    LstBTCLogic public lstBTC;
    WhitelistRegistryLogic public whitelistRegistry;

    uint64 public constant INIT_ADD_CONFIG_TIMESTAMP = 1640000000;

    bytes32 public constant ROLE_RELAYER = keccak256("ROLE_RELAYER");
    bytes32 public constant ROLE_GOVERNOR = keccak256("ROLE_GOVERNOR");

    address public adminAddress;
    address public govAddress;
    address public relayerAddress;
    uint32 public initialHeight;
    uint32 public finalizationParameter;

    // PegIn Fee Configs
    uint64 public constant DEFAULT_PEG_IN_DEPOSIT_DUST_AMOUNT = 546; // 546 satoshi
    uint16 public constant DEFAULT_PEG_IN_TREASURY_FEE_RATE = 50; // 0.5% (50 / 10000)
    address[] public  DEFAULT_PEG_IN_RECIPIENTS = new address[](2);
    uint16[] public  DEFAULT_PEG_IN_SHARES = new uint16[](2);

    // PegOut Fee Configs  
    uint64 public constant DEFAULT_PEG_OUT_REDEEM_DUST_AMOUNT = 7000; // 7000 satoshi
    uint64 public constant DEFAULT_PEG_OUT_TRANSACTION_FEE = 1000; // 1000 satoshi
    uint16 public constant DEFAULT_PEG_OUT_TREASURY_FEE_RATE = 100; // 1% (100/ 10000)
    address[] public  DEFAULT_PEG_OUT_RECIPIENTS = new address[](2);
    uint16[] public  DEFAULT_PEG_OUT_SHARES = new uint16[](2);
    uint32 public constant DEFAULT_BITCOIN_CONFIRMATIONS = 6;

    function _deployLstBTCBridge(address _admin, address _governor) internal {
        LstBTCBridgeLogic logic = new LstBTCBridgeLogic();
        vm.label(address(logic), "LstBTCBridgeLogic_Implementation");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            _admin,
            _governor
        );
        LstBTCBridgeProxy proxy = new LstBTCBridgeProxy(
            address(logic),
            initData
        );
        lstBTCBridge = LstBTCBridgeLogic(address(proxy));
        vm.label(address(lstBTCBridge), "LstBTCBridge");
    }

    function _deployConfigRegistry(address _admin, address _governor) internal {
        ConfigRegistryLogic logic = new ConfigRegistryLogic();
        vm.label(address(logic), "ConfigRegistryLogic_Implementation");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            _admin,
            _governor
        );
        ConfigRegistryProxy proxy = new ConfigRegistryProxy(
            address(logic),
            initData
        );
        configRegistry = ConfigRegistryLogic(address(proxy));
        vm.label(address(configRegistry), "ConfigRegistry");
    }

    function _deployNavProvider(address _admin, address _governor) internal {
        NavProviderLogic logic = new NavProviderLogic();
        vm.label(address(logic), "NavProviderLogic_Implementation");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            _admin,
            _governor
        );
        NavProviderProxy proxy = new NavProviderProxy(address(logic), initData);
        navProvider = NavProviderLogic(address(proxy));
        vm.label(address(navProvider), "NavProvider");
    }

    function _deployBitcoinTxStore(
        address _admin,
        address _governor,
        address _btcLightClient,
        uint32 _initialHeight,
        uint32 _finalizationParameter
    ) internal {
        BitcoinTxStoreLogic logic = new BitcoinTxStoreLogic();
        vm.label(address(logic), "BitcoinTxStoreLogic_Implementation");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,uint32,uint32)",
            _admin,
            _governor,
            _btcLightClient,
            _initialHeight,
            _finalizationParameter
        );
        BitcoinTxStoreProxy proxy = new BitcoinTxStoreProxy(
            address(logic),
            initData
        );
        bitcoinTxStore = BitcoinTxStoreLogic(address(proxy));
        vm.label(address(bitcoinTxStore), "BitcoinTxStore");
    }

    function _deployLstBTC() internal {
        LstBTCLogic logic = new LstBTCLogic();
        vm.label(address(logic), "LstBTCLogic_Implementation");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(string,string)",
            "Liquid Staked BTC",
            "lstBTC"
        );
        LstBTCProxy proxy = new LstBTCProxy(address(logic), initData);
        lstBTC = LstBTCLogic(address(proxy));
        vm.label(address(lstBTC), "LstBTC");
    }

    function _deployWhitelistRegistry(
        address _admin,
        address _governor
    ) internal {
        WhitelistRegistryLogic logic = new WhitelistRegistryLogic();
        vm.label(address(logic), "WhitelistRegistryLogic_Implementation");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            _admin,
            _governor
        );
        WhitelistRegistryProxy proxy = new WhitelistRegistryProxy(
            address(logic),
            initData
        );
        whitelistRegistry = WhitelistRegistryLogic(address(proxy));
        vm.label(address(whitelistRegistry), "WhitelistRegistry");
    }

    function _deployer(
        address _admin,
        address _governor,
        address _btcLightClient,
        uint32 _initialHeight,
        uint32 _finalizationParameter
    ) internal {
        _deployLstBTCBridge(_admin, _governor);
        _deployConfigRegistry(_admin, _governor);
        _deployNavProvider(_admin, _governor);
        _deployBitcoinTxStore(
            _admin,
            _governor,
            _btcLightClient,
            _initialHeight,
            _finalizationParameter
        );
        _deployLstBTC();
        _deployWhitelistRegistry(_admin, _governor);
    }

    function _initContractAddress() internal {
        // 1. Set dependency contract addresses for LstBTCBridge
        vm.startPrank(govAddress);
        lstBTCBridge.setConfigRegistry(address(configRegistry));
        lstBTCBridge.setWhitelistRegistry(address(whitelistRegistry));
        lstBTCBridge.setNavProvider(address(navProvider));
        lstBTCBridge.setBitcoinTxStore(address(bitcoinTxStore));
        lstBTCBridge.setLstBTC(address(lstBTC));
        // grant relayer role to lstBTCBridge
        lstBTCBridge.grantRole(ROLE_RELAYER, address(relayerAddress));

        // 2. Grant RELAYER role to BitcoinTxStore
        bitcoinTxStore.grantRole(ROLE_RELAYER, address(lstBTCBridge));
        vm.stopPrank();
        // 3. Set LstBTC state
        lstBTC.setBridge(address(lstBTCBridge));
        lstBTC.addMinter(address(lstBTCBridge));
        lstBTC.addBurner(address(lstBTCBridge));

        // 4. Set NavProvider state
        vm.startPrank(govAddress);
        navProvider.setBridge(address(lstBTCBridge));
        vm.stopPrank();
        // 5. Set ConfigRegistry state
        vm.startPrank(govAddress);
        configRegistry.setBridge(address(lstBTCBridge));
        vm.stopPrank();
    }

    function _initFeeConfigs() internal {
        vm.startPrank(govAddress);
        // Initialize fee config arrays
        DEFAULT_PEG_IN_RECIPIENTS[0] = address(40001);
        vm.label(DEFAULT_PEG_IN_RECIPIENTS[0], "DEFAULT_PEG_IN_RECIPIENTS[0]");
        DEFAULT_PEG_IN_RECIPIENTS[1] = address(40002);
        vm.label(DEFAULT_PEG_IN_RECIPIENTS[1], "DEFAULT_PEG_IN_RECIPIENTS[1]");
        DEFAULT_PEG_IN_SHARES[0] = 6000; // 60%
        DEFAULT_PEG_IN_SHARES[1] = 4000; // 40%

        DEFAULT_PEG_OUT_RECIPIENTS[0] = address(40003);
        vm.label(DEFAULT_PEG_OUT_RECIPIENTS[0], "DEFAULT_PEG_OUT_RECIPIENTS[0]");
        DEFAULT_PEG_OUT_RECIPIENTS[1] = address(40004);
        vm.label(DEFAULT_PEG_OUT_RECIPIENTS[1], "DEFAULT_PEG_OUT_RECIPIENTS[1]");
        DEFAULT_PEG_OUT_SHARES[0] = 7000; // 70%
        DEFAULT_PEG_OUT_SHARES[1] = 3000; // 30%

        vm.warp(INIT_ADD_CONFIG_TIMESTAMP);
        // Set PegIn configs
        configRegistry.setPegInDepositDustAmount(DEFAULT_PEG_IN_DEPOSIT_DUST_AMOUNT);
        configRegistry.setPegInTreasuryFeeRate(DEFAULT_PEG_IN_TREASURY_FEE_RATE);
        configRegistry.setPegInTreasuryFeeShares(DEFAULT_PEG_IN_RECIPIENTS, DEFAULT_PEG_IN_SHARES);

        vm.warp(INIT_ADD_CONFIG_TIMESTAMP);
        // Set PegOut configs
        configRegistry.setPegOutRedeemDustAmount(DEFAULT_PEG_OUT_REDEEM_DUST_AMOUNT);
        configRegistry.setPegOutTransactionFee(DEFAULT_PEG_OUT_TRANSACTION_FEE);
        configRegistry.setPegOutTreasuryFeeRate(DEFAULT_PEG_OUT_TREASURY_FEE_RATE);
        configRegistry.setPegOutTreasuryFeeShares(DEFAULT_PEG_OUT_RECIPIENTS, DEFAULT_PEG_OUT_SHARES);
        vm.stopPrank();
    }

    constructor() {
        // admin address
        adminAddress = address(1000);
        // gov address
        govAddress = address(1001);
        relayerAddress = address(1002);
        vm.label(adminAddress, "adminAddress");
        vm.label(govAddress, "govAddress");
        vm.label(btcLightClient, "btcLightClient");
        vm.label(relayerAddress, "relayerAddress");

        initialHeight = 30000;
        finalizationParameter = 2;

        // setup contracts
        _deployer(
            adminAddress,
            govAddress,
            btcLightClient,
            initialHeight,
            finalizationParameter
        );
        _initContractAddress();
        _initFeeConfigs();
    }
}
