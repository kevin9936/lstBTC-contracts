import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {verify} from "../helper-functions"
import config from 'config'
import { ethers } from 'hardhat';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const lstBTCLogic = await deployments.get("LstBTCLogic");

    const tokenName     = config.get("lst_btc.token_name");
    const tokenSymbol   = config.get("lst_btc.token_symbol");

    const methodSig = ethers.utils.id(
        "initialize(string,string)"
    );
    const params = ethers.utils.defaultAbiCoder.encode(
        ['string','string'],
        [tokenName, tokenSymbol]
    );

    const initCode = ethers.utils.solidityPack(
        ['bytes', 'bytes'],
        [methodSig.slice(0,10), params]
    );

    const args = [
        lstBTCLogic.address,
        initCode
    ];

    const deployedContract = await deploy("LstBTCProxy", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: args
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(
            deployedContract.address,
            args,
            "contracts/token/LstBTCProxy.sol:LstBTCProxy",
            hre
        )
    }
};

export default func;
func.tags = ["LstBTCProxy"];
