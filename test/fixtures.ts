import { BigNumberish } from "ethers";
import {
  CoolToken,
  CoolToken__factory,
  BasicProxy__factory,
} from "../types/ethers-contracts/index.js";

export const TOKEN_NAME: string = "CoolToken";
export const SYMBOL: string = "CT";
export const VOTING_LENGTH: BigNumberish = 1n * 24n * 60n * 60n; // 1 day
export const INIT_PRICE: BigNumberish = 1n * 10n ** 17n; // 0.1 ETH
export const FEE_BPS: BigNumberish = 100n;

export async function deployFixture(ethers: any) {
  const signers = await ethers.getSigners();
  const deployer = signers[0];
  const friend = signers[1];
  const user2 = signers[2];

  const CoolTokenFactory = (await ethers.getContractFactory(
    "CoolToken",
  )) as CoolToken__factory;
  const BasicProxyFactory = (await ethers.getContractFactory(
    "BasicProxy",
  )) as BasicProxy__factory;

  const initParams = [
    TOKEN_NAME,
    SYMBOL,
    VOTING_LENGTH,
    INIT_PRICE,
    FEE_BPS,
    deployer.address,
  ];

  const implementation = await CoolTokenFactory.deploy();
  const implAddress = await implementation.getAddress();

  const initData = CoolTokenFactory.interface.encodeFunctionData(
    "initialize",
    initParams,
  );

  const proxy = await BasicProxyFactory.deploy(implAddress, initData);
  const proxyAddress = await proxy.getAddress();

  const coolTokenProxy = CoolTokenFactory.attach(proxyAddress) as CoolToken;

  return {
    coolTokenProxy,
    deployer,
    friend,
    user2,
    CoolTokenFactory,
  };
}
