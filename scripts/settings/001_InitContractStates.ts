import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getContractInst } from '../../helper-functions';
import { ethers } from 'hardhat';
import { assert } from 'chai';
import config from 'config';
const logger = require('node-color-log');

async function setLstBTCBridgeStates(
    bridgeInst: any,
    configRegistryInst: any,
    whitelistRegistryInst: any,
    bitcoinRelayInst: any,
    lstBTCInst: any,
    navProviderInst: any
) {
    logger.color('blue').log("=========================================");
    logger.color('blue').bold().log("🔧 Setting LstBTCBridge States...");
    logger.color('blue').log("=========================================");
    if (!bridgeInst) return;

    const oldConfigRegistry = await bridgeInst.configRegistry();
    if (oldConfigRegistry != configRegistryInst.address) {
        const tx = await bridgeInst.setConfigRegistry(configRegistryInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ LstBTCBridge.configRegistry = ${configRegistryInst.address} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTCBridge.configRegistry already set to ${oldConfigRegistry}`);
    }

    const oldWhitelistRegistry = await bridgeInst.whitelistRegistry();
    if (oldWhitelistRegistry != whitelistRegistryInst.address) {
        const tx = await bridgeInst.setWhitelistRegistry(whitelistRegistryInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ LstBTCBridge.whitelistRegistry = ${whitelistRegistryInst.address} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTCBridge.whitelistRegistry already set to ${oldWhitelistRegistry}`);
    }

    const oldBitcoinRelay = await bridgeInst.bitcoinRelay();
    if (oldBitcoinRelay != bitcoinRelayInst.address) {
        const tx = await bridgeInst.setBitcoinRelay(bitcoinRelayInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ LstBTCBridge.bitcoinRelay = ${bitcoinRelayInst.address} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTCBridge.bitcoinRelay already set to ${oldBitcoinRelay}`);
    }

    const oldLstBTC = await bridgeInst.lstBTC();
    if (oldLstBTC != lstBTCInst.address) {
        const tx = await bridgeInst.setLstBTC(lstBTCInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ LstBTCBridge.lstBTC = ${lstBTCInst.address} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTCBridge.lstBTC already set to ${oldLstBTC}`);
    }

    const oldNavProvider = await bridgeInst.navProvider();
    if (oldNavProvider != navProviderInst.address) {
        const tx = await bridgeInst.setNavProvider(navProviderInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ LstBTCBridge.navProvider = ${navProviderInst.address} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTCBridge.navProvider already set to ${oldNavProvider}`);
    }

    const ROLE_RELAYER = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE_RELAYER"));
    const relayer = config.get("access_control.relayer");
    if (!await bridgeInst.hasRole(ROLE_RELAYER, relayer)) {
        const tx = await bridgeInst.grantRole(ROLE_RELAYER, relayer);
        await tx.wait(1);

        assert(await bridgeInst.hasRole(ROLE_RELAYER, relayer));
        logger.color('green').log(`✅ LstBTCBridge.ROLE_RELAYER granted to ${relayer} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTCBridge.ROLE_RELAYER already granted to ${relayer}`);
    }
}

async function setBitcoinRelayStates(bitcoinRelayInst: any, bridgeInst: any) {
    logger.color('blue').log("=========================================");
    logger.color('blue').bold().log("🔧 Setting BitcoinRelay States...");
    logger.color('blue').log("=========================================");
    if (!bitcoinRelayInst) return;

    const ROLE_RELAYER = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE_RELAYER"));
    if (!await bitcoinRelayInst.hasRole(ROLE_RELAYER, bridgeInst.address)) {
        const tx = await bitcoinRelayInst.grantRole(ROLE_RELAYER, bridgeInst.address);
        await tx.wait(1);
        assert(await bitcoinRelayInst.hasRole(ROLE_RELAYER, bridgeInst.address))
        logger.color('green').log(`✅ BitcoinRelay.ROLE_RELAYER granted to ${bridgeInst.address} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  BitcoinRelay.ROLE_RELAYER already granted to ${bridgeInst.address}`);
    }
}

async function setLstBTCStates(lstBTCInst: any, bridgeInst: any) {
    logger.color('blue').log("=========================================");
    logger.color('blue').bold().log("🔧 Setting LstBTC States...");
    logger.color('blue').log("=========================================");
    if (!lstBTCInst) return;

    const oldBridgeInLstBTC = await lstBTCInst.bridge();
    if (oldBridgeInLstBTC != bridgeInst.address) {
        const tx = await lstBTCInst.setBridge(bridgeInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ LstBTC.bridge = ${bridgeInst.address} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTC.bridge already set to ${oldBridgeInLstBTC}`);
    }

    if (!await lstBTCInst.minters(bridgeInst.address)) {
        const tx = await lstBTCInst.addMinter(bridgeInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ LstBTC.minters[${bridgeInst.address}] = true (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTC.minters[${bridgeInst.address}] already set to true`);
    }

    if (!await lstBTCInst.burners(bridgeInst.address)) {
        const tx = await lstBTCInst.addBurner(bridgeInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ LstBTC.burners[${bridgeInst.address}] = true (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  LstBTC.burners[${bridgeInst.address}] already set to true`);
    }
}

async function setNavProviderStates(navProviderInst: any, bridgeInst: any) {
    logger.color('blue').log("=========================================");
    logger.color('blue').bold().log("🔧 Setting NavProvider States...");
    logger.color('blue').log("=========================================");
    if (!navProviderInst) return;

    const oldBridgeInNavProvider = await navProviderInst.bridge();
    if (oldBridgeInNavProvider != bridgeInst.address) {
        const tx = await navProviderInst.setBridge(bridgeInst.address);
        await tx.wait(1);
        logger.color('green').log(`✅ NavProvider.bridge = ${bridgeInst.address} (tx: ${tx.hash})`);
    } else {
        logger.color('yellow').log(`⏭️  NavProvider.bridge already set to ${oldBridgeInNavProvider}`);
    }
}

async function setConfigRegistryStates(configRegistryInst: any) {
    logger.color('blue').log("=========================================");
    logger.color('blue').bold().log("🔧 Setting ConfigRegistry States...");
    logger.color('blue').log("=========================================");
    if (!configRegistryInst) return;

    const depositDustAmount     = config.get("minter.deposit_dust_amount");
    const pegInTreasuryFeeRate  = config.get("minter.treasury_fee_rate");
    const pegInRecipients       = config.get("minter.recipients");
    const pegInShares           = config.get("minter.shares");

    logger.color('cyan').log("-----------------------------------------");
    logger.color('cyan').bold().log("💰 Setting PegIn Fee Configs...");
    logger.color('cyan').log("-----------------------------------------");

    {
        const tx = await configRegistryInst.setPegInDepositDustAmount(depositDustAmount);
        await tx.wait(1);
        logger.color('green').log(`✅ ConfigRegistry.pegInDepositDustAmount = ${depositDustAmount} (tx: ${tx.hash})`);

        const result = await configRegistryInst.getPegInDepositDustAmount(Math.floor(Date.now() / 1000))
        logger.color('blue').log(`📊 Verified: deposit dust amount = ${result.toString()}`);
    }

    {
        const tx = await configRegistryInst.setPegInTreasuryFeeRate(pegInTreasuryFeeRate);
        await tx.wait(1);
        logger.color('green').log(`✅ ConfigRegistry.pegInTreasuryFeeRate = ${pegInTreasuryFeeRate} (tx: ${tx.hash})`);

        const result = await configRegistryInst.getPegInTreasuryFeeRate(Math.floor(Date.now() / 1000))
        logger.color('blue').log(`📊 Verified: treasury fee rate = ${result.toString()}`);
    }

    {
        const tx = await configRegistryInst.setPegInTreasuryFeeShares(pegInRecipients, pegInShares);
        await tx.wait(1);
        logger.color('green').log(`✅ ConfigRegistry.pegInTreasuryFeeShares set (tx: ${tx.hash})`);

        const result = await configRegistryInst.getPegInTreasuryFeeShares(Math.floor(Date.now() / 1000))
        logger.color('blue').log(`📊 Verified: recipients = ${result[0]}`);
        logger.color('blue').log(`📊 Verified: shares = ${result[1]}`);
    }

    logger.color('cyan').log("-----------------------------------------");
    logger.color('cyan').bold().log("💰 Setting PegOut Fee Configs...");
    logger.color('cyan').log("-----------------------------------------");

    const redeemDustAmount      = config.get("burner.redeem_dust_amount");
    const transactionFee        = config.get("burner.transaction_fee");
    const pegOutTreasuryFeeRate = config.get("burner.treasury_fee_rate");
    const pegOutRecipients      = config.get("burner.recipients");
    const pegOutShares          = config.get("burner.shares");

    {
        const tx = await configRegistryInst.setPegOutRedeemDustAmount(redeemDustAmount);
        await tx.wait(1);
        logger.color('green').log(`✅ ConfigRegistry.pegOutRedeemDustAmount = ${redeemDustAmount} (tx: ${tx.hash})`);

        const result = await configRegistryInst.getPegOutRedeemDustAmount(Math.floor(Date.now() / 1000))
        logger.color('blue').log(`📊 Verified: redeem dust amount = ${result.toString()}`);
    }

    {
        const tx = await configRegistryInst.setPegOutTransactionFee(transactionFee);
        await tx.wait(1);
        logger.color('green').log(`✅ ConfigRegistry.pegOutTransactionFee = ${transactionFee} (tx: ${tx.hash})`);

        const result = await configRegistryInst.getPegOutTransactionFee(Math.floor(Date.now() / 1000))
        logger.color('blue').log(`📊 Verified: transaction fee = ${result.toString()}`);
    }

    {
        const tx = await configRegistryInst.setPegOutTreasuryFeeRate(pegOutTreasuryFeeRate);
        await tx.wait(1);
        logger.color('green').log(`✅ ConfigRegistry.pegOutTreasuryFeeRate = ${pegOutTreasuryFeeRate} (tx: ${tx.hash})`);

        const result = await configRegistryInst.getPegOutTreasuryFeeRate(Math.floor(Date.now() / 1000))
        logger.color('blue').log(`📊 Verified: treasury fee rate = ${result.toString()}`);
    }

    {
        const tx = await configRegistryInst.setPegOutTreasuryFeeShares(pegOutRecipients, pegOutShares);
        await tx.wait(1);
        logger.color('green').log(`✅ ConfigRegistry.pegOutTreasuryFeeShares set (tx: ${tx.hash})`);

        const result = await configRegistryInst.getPegOutTreasuryFeeShares(Math.floor(Date.now() / 1000));
        logger.color('blue').log(`📊 Verified: recipients = ${result[0]}`);
        logger.color('blue').log(`📊 Verified: shares = ${result[1]}`);
    }
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;

    logger.color('magenta').log("🚀 Starting Contract State Initialization...");
    logger.color('magenta').log("=========================================");

    const configRegistryInst    = await getContractInst(deployments, "ConfigRegistryProxy", "ConfigRegistryLogic", "");
    const whitelistRegistryInst = await getContractInst(deployments, "WhitelistRegistryProxy", "WhitelistRegistryLogic", "BtcUtils");
    const bitcoinRelayInst      = await getContractInst(deployments, "BitcoinRelayProxy", "BitcoinRelayLogic", "");
    const lstBTCInst            = await getContractInst(deployments, "LstBTCProxy", "LstBTCLogic", "");
    const navProviderInst       = await getContractInst(deployments, "NavProviderProxy", "NavProviderLogic", "");
    const bridgeInst            = await getContractInst(deployments, "LstBTCBridgeProxy", "LstBTCBridgeLogic", "PegRequestHelper");

    if (!configRegistryInst) return;
    if (!whitelistRegistryInst) return;
    if (!bitcoinRelayInst) return;
    if (!lstBTCInst) return;
    if (!navProviderInst) return;
    if (!bridgeInst) return;

    // Set LstBTCBridge states
    await setLstBTCBridgeStates(
        bridgeInst,
        configRegistryInst,
        whitelistRegistryInst,
        bitcoinRelayInst,
        lstBTCInst,
        navProviderInst
    );

    // Set BitcoinRelay states
    await setBitcoinRelayStates(bitcoinRelayInst, bridgeInst);

    // Set ConfigRegistry states
    await setConfigRegistryStates(configRegistryInst);

    // Set LstBTC states
    await setLstBTCStates(lstBTCInst, bridgeInst);

    // Set NavProvider states
    await setNavProviderStates(navProviderInst, bridgeInst);

    logger.color('magenta').log("=========================================");
    logger.color('magenta').bold().log("🎉 Contract State Initialization Complete!");
    logger.color('magenta').log("=========================================");
};

export default func;
