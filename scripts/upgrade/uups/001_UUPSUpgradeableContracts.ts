import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';
import {checkComponentAddress, verify,waitForInput} from "../../../helper-functions"
import { assert } from 'console';
import { BigNumber } from 'ethers';
const logger = require('node-color-log');
const chalk  = require('chalk');
const Table  = require('cli-table3');

function split(text: string, delimiter: string) {
    if (text.length === 0) return [];

    let arr: string[] = text.split(delimiter);
    for(let i = 0; i < arr.length; i++) {
        arr[i].trim();
    }

    return arr;
}

function isBytes32(str: string): boolean {
    const bytes32Regex = /^(0x)?[0-9A-Fa-f]{64}$/;
    return bytes32Regex.test(str);
}

function isBytes(str: string): boolean {
    const bytesRegex = /^(0x)?[0-9A-Fa-f]+$/;
    return bytesRegex.test(str);
}

async function prepareCallData() {
    let res = {
        result: false,
        data: null
    };

    const ans = await waitForInput("Need To Construct Calldata For UpgradeToAndCall ? (y/n):");
    if ((ans as string).toLowerCase() != 'y') {
        res.result = true;
        res.data = "" as any;
        return res
    }

    const methodSig = await waitForInput(`Function Selector ( e.g. initForMultipleCollateralsFeature(address[]) ):`);
    if ((methodSig as string).length == 0) {
        logger.color('red').bold().log("The function selector is empty");
        return res;
    }

    const extractRes = extractParamTypeList(methodSig as string);
    if (!extractRes.result || !extractRes.data) {
        logger.color('red').bold().log("The function selector is invalid");
        return res;
    }

    if (!checkParamTypeList(extractRes.data as string[])) {
        logger.color('red').bold().log("The paramter list of the function is invalid");
        return res;
    }

    let paramValArr: any[] = [];
    const paramTypeArr = extractRes.data as string[];
    for (let i = 0; i < paramTypeArr.length; i++) {
        const typeName = paramTypeArr[i];

        const parsedRes = parseParam(typeName, await waitForInput(`Enter The Parameter ${i} (Type ${typeName}):`) as string);
        if (!parsedRes.result) {
            logger.color('red').bold().log("Param parsed error");
            return res;
        }

        paramValArr.push(parsedRes.data);
        if (!checkParam(typeName, paramValArr[i])) {
            logger.color('red').bold().log("Param checked error");
            return res;
        }
    }

    console.log("type list:", paramTypeArr);
    console.log("value list:", paramValArr);

    res.result = true;
    res.data = ethers.utils.solidityPack(
        ['bytes', 'bytes'],
        [ethers.utils.id(methodSig as string).slice(0,10), ethers.utils.defaultAbiCoder.encode(paramTypeArr, paramValArr)]
    ) as any;

    return res;
}

async function deployLibrary2(deployFunc:any, deployer:any, dependLibs: any, codePathMap: any) {
    let ans:string = await waitForInput("Add dependency library? (y/n):") as string;

    // deploy libraries
    let libraries:{[key:string]: string};
    libraries = {};
    while (ans.toLowerCase() == 'y') {
        const libName = await waitForInput("Library Name:");
        assert((libName as string).length > 0, "Library name is empty!");

        // deploy library
        const lib = await deployFunc(libName, {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
        })

        assert(ethers.utils.isAddress(lib.address), `Deploy ${libName} failed!`);
        if (!ethers.utils.isAddress(lib.address)) return null;

        // verify library
        let libCodePath = codePathMap[libName as string];
        ans = await waitForInput(`Library ${libName} Code Path is ${libCodePath}, Need Replace (y/n):`) as string;
        if (ans.toLowerCase() == 'y') {
            libCodePath = await waitForInput("Enter New Code Path For Verifying:");
        }
        assert((libCodePath as string).length > 0, 'Code path is empty!');
        if ((libCodePath as string).length == 0) return null;

        const isVerified = await verify(
            lib.address,
            [],
            libCodePath as string
        );
        if (!isVerified) return null;

        libraries[libName as string] = lib.address;
        ans = await waitForInput("Add another library? (y/n):") as string;
    }

    return libraries;
}

async function deployLibrary(deployFunc:any, deployer:any, contractName: any, dependLibMap: any, codePathMap: any) {

    let libraries:{[key:string]: string};
    libraries = {};

    const dependLibs = dependLibMap[contractName as string] ?? [];
    for (let i =0; i < dependLibs.length; i++) {
        const libName = dependLibs[i] as string;
        assert(libName.length > 0, "Library name is empty!");

        let ans = await waitForInput(`Does ${contractName} depend on library ${libName} (y/n):`) as string;
        if (ans.toLowerCase() == 'n') continue;

        // deploy library
        const lib = await deployFunc(libName, {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
        })

        assert(ethers.utils.isAddress(lib.address), `Deploy ${libName} failed!`);
        if (!ethers.utils.isAddress(lib.address)) return null;

        // verify library
        let libCodePath = codePathMap[libName];
        ans = await waitForInput(`Library ${libName} Code Path is ${libCodePath}, Need Replace (y/n):`) as string;
        if (ans.toLowerCase() == 'y') {
            libCodePath = await waitForInput("Enter New Code Path For Verifying:");
        }
        assert((libCodePath as string).length > 0, 'Code path is empty!');
        if ((libCodePath as string).length == 0) return null;

        const isVerified = await verify(
            lib.address,
            [],
            libCodePath as string
        );
        if (!isVerified) return null;

        libraries[libName] = lib.address;
    }

    return libraries;
}

async function deployContract(
    deployFunc: any,
    deployer: any,
    contractName: any,
    libraries: any,
    codePathMap: any
) {
    logger.color('blue').bold().log(`${contractName} deploying...`);
    const contract = await deployFunc(contractName, {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        libraries: libraries
    });

    assert ( ethers.utils.isAddress(contract.address), `Deploy ${contractName} failed!` );
    if (!ethers.utils.isAddress(contract.address)) return null;

    // verify logic contract
    let codePath = codePathMap[contractName as string];
    let ans = await waitForInput(`Contract ${contractName} Code Path is ${codePath}, Need Replace (y/n):`);
    if ((ans as string).toLowerCase() == 'y') {
        codePath = await waitForInput("Enter New Code Path For Verifying:");
    }
    assert((codePath as string).length > 0, 'Code path is empty!');
    if ((codePath as string).length == 0) return null;

    const isVerified = await verify(
        contract.address,
        [],
        codePath as string
    );

    return isVerified ? contract : null;
}

async function upgradeContract(
    proxyAddr: any,
    implAddress:any,
    implName:any,
    libraries: any,
    callData: any
) {
    assert(ethers.utils.isAddress(proxyAddr as string), "Proxy contract address is invalid!");
    if ( !ethers.utils.isAddress(proxyAddr as string) ) return false;

    const implContractFactory  = await ethers.getContractFactory(
        implName,{
            libraries: libraries
        });

    const proxyInst = await implContractFactory.attach( proxyAddr as string );
    let tx: any;
    if (!callData) {
        tx = await proxyInst.upgradeTo(implAddress);
        console.log('Proxy call upgradeTo');
    } else {
        tx = await proxyInst.upgradeToAndCall(implAddress, callData);
        console.log('Proxy call upgradeToAndCall');
    }

    await tx.wait(1);
    logger.color('blue').log("tx hash:", tx.hash);
    return true;
}

function printUUPSConractTable() {
    let codePathMap: Record<string, string> = {
        "BitcoinRelayLogic": "contracts/relay/BitcoinRelayLogic.sol:BitcoinRelayLogic",
        "LstBTCLogic": "contracts/token/LstBTCLogic.sol:LstBTCLogic",
        "LstBTCBridgeLogic": "contracts/bridge/LstBTCBridgeLogic.sol:LstBTCBridgeLogic",
        "ConfigRegistryLogic": "contracts/configuration/ConfigRegistryLogic.sol:ConfigRegistryLogic",
        "NavProviderLogic": "contracts/nav/NavProviderLogic.sol:NavProviderLogic",
        "WhitelistRegistryLogic": "contracts/whitelist/WhitelistRegistryLogic.sol:WhitelistRegistryLogic",
        "PegRequestHelper": "contracts/libraries/PegRequestHelper.sol:PegRequestHelper",
        "BtcUtils": "bitcoin-transaction-helper/contracts/BtcUtils.sol:BtcUtils"
    };

    let proxyNameMap: Record<string, string> = {
        "BitcoinRelayLogic": "BitcoinRelayProxy",
        "LstBTCLogic": "LstBTCProxy",
        "LstBTCBridgeLogic": "LstBTCBridgeProxy",
        "ConfigRegistryLogic": "ConfigRegistryProxy",
        "NavProviderLogic": "NavProviderProxy",
        "WhitelistRegistryLogic": "WhitelistRegistryProxy",
    };

    let dependLibMap: Record<string, string[]> = {
        "LstBTCBridgeLogic": ["PegRequestHelper"],
        "WhitelistRegistryLogic": ["BtcUtils"]
    };

    const table = new Table({
        head: [chalk.blue('UUPSUpgradeable Contract'),chalk.blue('Code Path For Verifying'),chalk.blue('Dependency Lib')],
        colWidths: [30, 70, 30]
    })
    table.push(
        ['BitcoinRelayLogic', codePathMap['BitcoinRelayLogic'], ''],
        ['LstBTCLogic', codePathMap['LstBTCLogic'], ''],
        ['LstBTCBridgeLogic', codePathMap['LstBTCBridgeLogic'], 'PegRequestHelper'],
        ['ConfigRegistryLogic', codePathMap['ConfigRegistryLogic'], ''],
        ['NavProviderLogic', codePathMap['NavProviderLogic'], ''],
        ['WhitelistRegistryLogic', codePathMap['WhitelistRegistryLogic'], 'BtcUtils']
    );

    const libTable = new Table({
        head: [chalk.blue('Library'),chalk.blue('Code Path For Verifying')],
        colWidths: [30, 70]
    })

    libTable.push(
        ['PegRequestHelper', codePathMap['PegRequestHelper']],
        ['BtcUtils', codePathMap['BtcUtils']]
    );

    logger.color('blue').bold().log("UUPSUpgradeable Contract List");
    console.log(table.toString());
    console.log(libTable.toString());

    return {
        codePathMap: codePathMap,
        proxyNameMap: proxyNameMap,
        dependLibMap: dependLibMap
    };
}

function extractParamTypeList(functionSig: string) {
    let res = {
        result: false,
        data: null
    };

    if (!functionSig || functionSig.length == 0 || !functionSig.endsWith(')')) return res;

    const endOffset = functionSig.length - 1;
    const startOffset = functionSig.indexOf('(');
    if (startOffset <= 0 || startOffset >= endOffset) return res;

    if (startOffset + 1 == endOffset) {
        res.result = true;
        res.data = [] as any;
        return res;
    }

    res.result = true;
    res.data = split(functionSig.slice(startOffset + 1, endOffset), ",") as any;
    return res;
}

function checkParamTypeList(typeList: string[]) {
    for (let i = 0; i < typeList.length; i++) {
        if (typeList[i] === "uint") {
            logger.color('red').bold().log("Using uint type may result in exceptions, please replace it with uint256!");
            return false;
        }
    }

    return true;
}

function parseParam(paramType: string, paramValue: string) {
    let res = {
        result: false,
        data: null
    };

    if (paramType.endsWith('[]')) {            // array
        let valueArr = [];
        const tmp = split(paramValue, ',');
        const itemType = paramType.slice(0, paramType.length - 2);

        for (let i = 0; i < tmp.length; i++) {
            const parsedRes = parseParam(itemType, tmp[i]);
            if (!parsedRes.result) return res;

            valueArr.push(parsedRes.data);
        }
        res.result = true;
        res.data = valueArr as any;
    } else if (paramType.startsWith('uint')) {  // uint
        res.result = true;
        res.data = parseInt(paramValue) as any;
    } else {                                    // address、string、bytes、bytes32
        res.result = true;
        res.data = paramValue as any;
    }

    return res;                                 // string, address, bytes, bytes32, ...
}

function checkParam(paramType: string, paramValue: any) {
    const typeOfValue = typeof paramValue;
    if (typeOfValue === 'object') {
        if (Array.isArray(paramValue)) {        // array
            if (!paramType.endsWith('[]')) return false;
            const itemType = paramType.slice(0, paramType.length-2);

            for (let i = 0; i < paramValue.length; i++) {
                if (!checkParam(itemType, paramValue[i])) return false;
            }

            return true;
        } else if (paramValue instanceof BigNumber) {
            return paramType.startsWith('uint');
        }
    } else if (typeOfValue === 'string') {
        if (paramType === 'bytes') {            // bytes
            return isBytes(paramValue);
        } else if (paramType === 'bytes32') {   // bytes32
            return isBytes32(paramValue);
        } else if (paramType === 'address') {   // address
            return ethers.utils.isAddress(paramValue);
        } else {
            return paramType === 'string';      // string
        }
    } else if (typeOfValue === 'number') {      // uint
        return paramType.startsWith('uint');
    }

    console.log(`typeName ${paramType}, typeof value ${typeOfValue}`);
    assert(false, "unknown type")
    return false;                               // unknown
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const resMap = printUUPSConractTable();

    const implContractName = await waitForInput("Enter Logic Contract Name To Be Upgraded:") as string;
    assert(implContractName.length > 0, "Logic contract name is empty!");
    if (implContractName.length == 0) return;

    // init calldata
    const calldataRes = await prepareCallData();
    if (!calldataRes.result) return;

    // deploy libraries
    const libraries = await deployLibrary(deploy, deployer, implContractName, resMap.dependLibMap, resMap.codePathMap);
    if (!libraries) {
        logger.color('red').bold().log("Deploy libraries failed!");
        return;
    }

    // deploy and verify new logic contract
    const implContract = await deployContract(
        deploy,
        deployer,
        implContractName,
        libraries,
        resMap.codePathMap
    );
    if (!implContract) return;

    // upgrade
    const proxyAddr = await checkComponentAddress(deployments, resMap.proxyNameMap[implContractName as string]);
    await upgradeContract(
        proxyAddr,
        implContract.address,
        implContractName,
        libraries,
        calldataRes.data
    );
};

export default func;
