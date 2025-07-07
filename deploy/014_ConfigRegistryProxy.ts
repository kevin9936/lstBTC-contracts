import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {verify} from "../helper-functions"
import config from 'config'
import { ethers } from 'hardhat';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const configRegistryLogic = await deployments.get("ConfigRegistryLogic");

    const defaultAdmiin         = config.get("access_control.default_admin");
    const governor              = config.get("access_control.governor");

    const methodSig = ethers.utils.id(
        "initialize(address,address)"
    );
    const params = ethers.utils.defaultAbiCoder.encode(
        ['address','address'],
        [defaultAdmiin,governor]
    );

    const initCode = ethers.utils.solidityPack(
        ['bytes', 'bytes'],
        [methodSig.slice(0,10), params]
    );

    const args = [
        configRegistryLogic.address,
        initCode
    ];

    const deployedContract = await deploy("ConfigRegistryProxy", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: args
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(
            deployedContract.address,
            args,
            "contracts/configuration/ConfigRegistryProxy.sol:ConfigRegistryProxy",
            hre
        );
    }
};

export default func;
func.tags = ["ConfigRegistryProxy"];
