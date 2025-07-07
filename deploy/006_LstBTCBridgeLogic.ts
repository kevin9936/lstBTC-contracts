import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {verify} from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const pegRequestHelper = await deploy("PegRequestHelper", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
    });

    const deployedContract = await deploy("LstBTCBridgeLogic", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        libraries: {
            "PegRequestHelper": pegRequestHelper.address
        },
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(
            pegRequestHelper.address,
            [],
            "contracts/libraries/PegRequestHelper.sol:PegRequestHelper"
        )

        await verify(
            deployedContract.address,
            [],
            "contracts/bridge/LstBTCBridgeLogic.sol:LstBTCBridgeLogic"
        )
    }
};

export default func;
func.tags = ["LstBTCBridgeLogic"];
