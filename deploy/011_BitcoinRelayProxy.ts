import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {verify} from "../helper-functions"
import config from 'config'
import { ethers } from 'hardhat';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const bitcoinRelayLogic = await deployments.get("BitcoinRelayLogic");

    const btcLightClientAddress = config.get("bitcoin_light_client");
    const startingBlockHeight   = config.get("starting_block_height");
    const finalizationParameter = config.get("finalization_parameter");
    const defaultAdmiin         = config.get("access_control.default_admin");
    const governor              = config.get("access_control.governor");

    const methodSig = ethers.utils.id(
        "initialize(address,address,address,uint32,uint32)"
    );
    const params = ethers.utils.defaultAbiCoder.encode(
        ['address','address','address','uint32','uint32'],
        [defaultAdmiin,governor,btcLightClientAddress,startingBlockHeight,finalizationParameter]
    );

    const initCode = ethers.utils.solidityPack(
        ['bytes', 'bytes'],
        [methodSig.slice(0,10), params]
    );

    const args = [
        bitcoinRelayLogic.address,
        initCode
    ];

    const deployedContract = await deploy("BitcoinRelayProxy", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: args
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(
            deployedContract.address,
            args,
            "contracts/relay/BitcoinRelayProxy.sol:BitcoinRelayProxy",
            hre
        );
    }
};

export default func;
func.tags = ["BitcoinRelayProxy"];
