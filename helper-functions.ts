import { run } from "hardhat"
import * as readline from "readline";
import { ethers } from "hardhat";
import { assert } from 'console';
import axios from "axios";
import { HardhatRuntimeEnvironment } from 'hardhat/types';
const chalk  = require('chalk');
import config from 'config'

const verify = async (contractAddress: string, args: any[], codePath: string, hre?: HardhatRuntimeEnvironment | null) => {
  console.log("");
  console.log("VERIFYING CONTRACT:", codePath);
  console.log("ADDRESS:", contractAddress);
  let isVerified: boolean = true;

  try {
    await run("verify:verify", {
      address: contractAddress,
      constructorArguments: args,
      contract: codePath,
    });
  } catch (e: any) {
    const msg = e.message.toLowerCase();
    if (msg.includes("already verified")) {
      console.log("    Already verified!");
    } else if (msg.includes("should be checked manually")) {
      console.log("   Verify successful and should be checked manually!");
    } else {
      console.log("    Verify failed!");
      console.log("   ", msg);
      isVerified = false;
    }

    console.log("\r\n\r\n");
  }

  if (isVerified && hre != null) {
    isVerified = await verifyAsProxy(contractAddress, codePath, hre);
  }

  return isVerified;
}

const verifyAsProxy = async (contractAddress: string, codePath: string, hre: HardhatRuntimeEnvironment) => {
  let isVerified: boolean = false;

  try {
    console.log("VERIFYING AS PROXY:", codePath);
    console.log("ADDRESS:", contractAddress);

    const etherscanConfig = getEtherscanConfig(hre);
    const apiUrl = etherscanConfig?.urls.apiURL;
    const apiKey = process.env.ETHERSCAN_API_KEY;
    const url = `${apiUrl}?module=contract&action=verifyproxycontract&apikey=${apiKey}&address=${contractAddress}`;

    console.log("VERIFY URL:", url);
    const res = await axios.get(url);

    if (res.data && res.data.status == '1') {
      console.log("   Verify as proxy is successful");
      isVerified = true;
    } else {
      console.log("   Verify as proxy failed:",res.data? res.data.message : "unknown");
    }
  } catch (e: any) {
    console.log("   ", e);
  }

  console.log("\r\n\r\n");
  return isVerified;
}

const getEtherscanConfig = (hre: HardhatRuntimeEnvironment) => {
  assert(
    hre != null && hre.config != null &&
      hre.config.etherscan != null && hre.config.etherscan.customChains != null,
    "Etherscan customChains config error!"
  );

  const chain = hre.config.etherscan.customChains.find(chain => chain.network === hre.network.name);
  assert(
    chain != null && chain.urls != null,
    "Etherscan customChains config error!"
  );

  return chain;
}

const waitForInput = (message:string) => {
  const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
  });
  return new Promise((resolve) => {
      rl.question(chalk.blue(message), (input) => {
          rl.close();
          input = input.trim();
          resolve(input);
      });
  });
}

async function checkValue(message: string, defaultVal: any) {
  let val = defaultVal;

  let ans = await waitForInput(`${message}, default value is ${defaultVal}, need replace? (y/n):`);
  if (ans === 'y') {
    val = await waitForInput(`Enter new value:`);
  }

  return val;
}

async function checkComponentAddress(deployments:any, libOrCotractName: string) {
  let componentAddress: any = '0x';

  const component = await deployments.get(libOrCotractName);
  if (component && ethers.utils.isAddress(component.address)) {
    componentAddress = component.address;
  }

  let ans = await waitForInput(`${libOrCotractName} default address is ${componentAddress}, need replace? (y/n):`);
  if (ans === 'y') {
      componentAddress = await waitForInput(`Enter new ${libOrCotractName} address:`);
  }

  assert(ethers.utils.isAddress(componentAddress), `${libOrCotractName} address is invalid!`);
  return componentAddress;
}

function isEnableMultipleCollaterals() {
  const enableMultipleCollaterals = config.get("features.enable_multiple_collaterals");
  return enableMultipleCollaterals as boolean;
}

function isEnableMockPriceProxy() {
  try {
    const enableMockPriceProxy = config.get("features.enable_mock_price_proxy");
    return enableMockPriceProxy as boolean;
  } catch (error) {
    return false;
  }

}

async function getContractInst(component: any, proxyName: any, logicName: any, libName: any) {
  let libraries:{[key:string]: string} = {};
  if (libName && libName.length > 0) {
    const libAddress = await checkComponentAddress(component, libName);
    assert(ethers.utils.isAddress(libAddress), "Library address is invalid");

    if (ethers.utils.isAddress(libAddress)) {
      libraries[libName as string] = libAddress as string;
    }
  }

  const logicFactory = await ethers.getContractFactory(
    logicName, {
        libraries: libraries
    }
  );;

  let attachAddress: any;
  if (!proxyName || proxyName.length === 0) {
    attachAddress = await checkComponentAddress(component, logicName);
  } else {
    attachAddress = await checkComponentAddress(component, proxyName);
  }

  assert(ethers.utils.isAddress(attachAddress), "Instance address is invalid");
  if (!ethers.utils.isAddress(attachAddress)) return;

  return await logicFactory.attach(attachAddress);
}

export {
  waitForInput,
  verify,
  checkComponentAddress,
  isEnableMultipleCollaterals,
  isEnableMockPriceProxy,
  getContractInst,
  checkValue
}