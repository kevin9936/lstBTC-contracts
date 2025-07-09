import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {verify} from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    // Deploy BTCUtils library first since it contains public methods that need to be linked
    const btcUtils = await deploy("BtcUtils", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        contract: "contracts/libraries/BtcUtils.sol:BtcUtils"
    });

    // Deploy WhitelistRegistryLogic with library linking
    const deployedContract = await deploy("WhitelistRegistryLogic", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        libraries: {
            "BtcUtils": btcUtils.address
        },
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(
            btcUtils.address,
            [],
            "contracts/libraries/BtcUtils.sol:BtcUtils"
        )

        await verify(
            deployedContract.address,
            [],
            "contracts/whitelist/WhitelistRegistryLogic.sol:WhitelistRegistryLogic")
    }
};

export default func;
func.tags = ["WhitelistRegistryLogic"];
