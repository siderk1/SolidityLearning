import { expect } from "chai";
import { network } from "hardhat";
import { CoolToken } from "../types/ethers-contracts/index.js";
import { deployFixture, TOKEN_NAME, SYMBOL } from "./fixtures.js";
import { HardhatEthers } from "@nomicfoundation/hardhat-ethers/types";
import { NetworkHelpers } from "@nomicfoundation/hardhat-network-helpers/types";

let _ethers: HardhatEthers;
let _networkHelpers: NetworkHelpers;

function localFixture() {
  return deployFixture(_ethers);
}

let ONE_ETH: bigint;
let ONE_TOKEN: bigint;
let DECIMALS: bigint;

describe("CoolToken: ERC20Base Coverage", function () {
  let coolTokenProxy: CoolToken;
  let deployer: any;
  let friend: any;
  let user2: any;

  beforeEach(async function () {
    const networkConnection = await network.connect();
    _ethers = networkConnection.ethers;
    _networkHelpers = networkConnection.networkHelpers;
    ({ coolTokenProxy, deployer, friend, user2 } =
      await _networkHelpers.loadFixture(localFixture));
    DECIMALS = await coolTokenProxy.decimals();
    ONE_ETH = _ethers.parseEther("1.0");
    ONE_TOKEN = _ethers.parseUnits("1", DECIMALS);
    await coolTokenProxy.buy({ value: ONE_ETH });
  });

  it("Should initialize and view basic parameters correctly", async function () {
    expect(await coolTokenProxy.name()).to.equal(TOKEN_NAME);
    expect(await coolTokenProxy.symbol()).to.equal(SYMBOL);
    expect(await coolTokenProxy.decimals()).to.equal(DECIMALS);
    expect(await coolTokenProxy.owner()).to.equal(deployer.address);
    expect(await coolTokenProxy.totalSupply()).to.be.gt(0n);
    expect(await coolTokenProxy.balanceOf(deployer.address)).to.be.gt(0n);
  });

  it("Should handle standard transfers, allowances, transferFrom, and all related reverts", async function () {
    const amount = ONE_TOKEN;
    const newAmount = amount * 2n;
    const initialBalanceDeployer = await coolTokenProxy.balanceOf(
      deployer.address,
    );
    const excessiveAmount = initialBalanceDeployer + amount;

    const initialBalanceFriend = await coolTokenProxy.balanceOf(friend.address);

    await expect(coolTokenProxy.transfer(friend.address, amount))
      .to.emit(coolTokenProxy, "Transfer")
      .withArgs(deployer.address, friend.address, amount);

    expect(await coolTokenProxy.balanceOf(deployer.address)).to.equal(
      initialBalanceDeployer - amount,
    );
    expect(await coolTokenProxy.balanceOf(friend.address)).to.equal(
      initialBalanceFriend + amount,
    );

    const balanceDeployerAfterTransfer = initialBalanceDeployer - amount;

    await expect(
      coolTokenProxy.transfer(friend.address, excessiveAmount),
    ).to.be.revertedWithCustomError(coolTokenProxy, "InsufficientBalance");

    await expect(coolTokenProxy.approve(friend.address, amount))
      .to.emit(coolTokenProxy, "Approval")
      .withArgs(deployer.address, friend.address, amount);

    expect(
      await coolTokenProxy.allowance(deployer.address, friend.address),
    ).to.equal(amount);

    await expect(
      coolTokenProxy.approve(friend.address, newAmount),
    ).to.be.revertedWithCustomError(coolTokenProxy, "NotEnoughTokens");

    await coolTokenProxy.approve(friend.address, 0n);
    await expect(coolTokenProxy.approve(friend.address, newAmount))
      .to.emit(coolTokenProxy, "Approval")
      .withArgs(deployer.address, friend.address, newAmount);

    expect(
      await coolTokenProxy.allowance(deployer.address, friend.address),
    ).to.equal(newAmount);

    const tooMuch = newAmount + 1n;
    await expect(
      coolTokenProxy
        .connect(friend)
        .transferFrom(deployer.address, user2.address, tooMuch),
    ).to.be.revertedWithCustomError(coolTokenProxy, "InsufficientAllowance");

    const balanceBeforeUser2 = await coolTokenProxy.balanceOf(user2.address);
    await expect(
      coolTokenProxy
        .connect(friend)
        .transferFrom(deployer.address, user2.address, newAmount),
    )
      .to.emit(coolTokenProxy, "Transfer")
      .withArgs(deployer.address, user2.address, newAmount);

    expect(
      await coolTokenProxy.allowance(deployer.address, friend.address),
    ).to.equal(0n);

    const totalSpent = amount + newAmount;

    expect(await coolTokenProxy.balanceOf(deployer.address)).to.equal(
      initialBalanceDeployer - totalSpent,
    );
    expect(await coolTokenProxy.balanceOf(user2.address)).to.equal(
      balanceBeforeUser2 + newAmount,
    );
  });
});
