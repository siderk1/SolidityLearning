import { BigNumberish } from "ethers";
import {
    InsecureCoolToken,
    InsecureCoolToken__factory,
    BasicProxy__factory,
    AttackerReentry,
    AttackerReentry__factory
} from "../../types/ethers-contracts/index.js";
import { HardhatEthers } from "@nomicfoundation/hardhat-ethers/types";

export const TOKEN_NAME: string = "InsecureCoolToken";
export const SYMBOL: string = "ICT";
export const VOTING_LENGTH: BigNumberish = 1n * 24n * 60n * 60n; // 1 day
export const INIT_PRICE: BigNumberish = 1n * 10n ** 16n; // 0.01 ETH
export const FEE_BPS: BigNumberish = 0n;

export async function deployFixture(ethers: HardhatEthers) {
  const signers = await ethers.getSigners();
  const user1 = signers[0];
  const user2 = signers[1];

  const AttackerReentryFactory = (await ethers.getContractFactory(
    "AttackerReentry",
  )) as AttackerReentry__factory;
  const InsecureCoolTokenFactory = (await ethers.getContractFactory(
    "InsecureCoolToken",
  )) as InsecureCoolToken__factory;
  const BasicProxyFactory = (await ethers.getContractFactory(
    "BasicProxy",
  )) as BasicProxy__factory;

  const initParams = [
    TOKEN_NAME,
    SYMBOL,
    VOTING_LENGTH,
    INIT_PRICE,
    FEE_BPS,
    user1.address,
  ];

  const implementation = await InsecureCoolTokenFactory.deploy();
  const implAddress = await implementation.getAddress();

  const initData = InsecureCoolTokenFactory.interface.encodeFunctionData(
    "initialize",
    initParams,
  );

  const proxy = await BasicProxyFactory.deploy(implAddress, initData);
  const proxyAddress = await proxy.getAddress();

  const token = InsecureCoolTokenFactory.attach(proxyAddress) as InsecureCoolToken;

  const attacker = await ethers.deployContract("AttackerReentry", [proxyAddress]);

  return {
    token,
    attacker,
    user1,
    user2,
  };
}
