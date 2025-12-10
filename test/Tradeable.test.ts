import { expect } from "chai";
import { network } from "hardhat";
import { CoolToken } from "../types/ethers-contracts/index.js";
import { deployFixture, TOKEN_NAME, SYMBOL } from "./fixtures.js";
import { ContractTransactionResponse } from "ethers";

let _ethers: any;
let _networkHelpers: any;

function localFixture() {
  return deployFixture(_ethers);
}
let ONE_ETH: bigint;
let DECIMALS: bigint;
const SEVEN_DAYS: bigint = 7n * 24n * 60n * 60n;

function buyOutput(
  ethIn: bigint,
  fee: bigint,
  price: bigint,
  bpsDenominator: bigint,
): [bigint, bigint] {
  let tokensGross = (ethIn * 10n ** DECIMALS) / price;
  let feeTokens = (tokensGross * fee) / bpsDenominator;
  let tokensNet = tokensGross - feeTokens;
  return [tokensNet, feeTokens];
}

function sellOutput(
  tokensIn: bigint,
  feeBPS: bigint,
  price: bigint,
  bpsDenominator: bigint,
): [bigint, bigint] {
  let feeTokens: bigint = (tokensIn * feeBPS) / bpsDenominator;
  let tokensNet: bigint = tokensIn - feeTokens;
  let ethOut: bigint = (tokensNet * price) / 10n ** DECIMALS;
  return [ethOut, feeTokens];
}

describe("CoolToken: Tradeable Coverage", function () {
  let coolTokenProxy: CoolToken;
  let deployer: any;
  let friend: any;
  let contractAddress: string;
  let deployerAddress: string;

  let currentFee: bigint;
  let currentPrice: bigint;
  let currentBPSDenominator: bigint;

  beforeEach(async function () {
    const networkConnection = await network.connect();
    _ethers = networkConnection.ethers;
    _networkHelpers = networkConnection.networkHelpers;

    ({ coolTokenProxy, deployer, friend } =
      await _networkHelpers.loadFixture(localFixture));

    DECIMALS = await coolTokenProxy.decimals();
    ONE_ETH = _ethers.parseEther("1.0");

    contractAddress = await coolTokenProxy.getAddress();
    deployerAddress = deployer.address;

    currentFee = await coolTokenProxy.feeBps();
    currentBPSDenominator = await coolTokenProxy.BPS_DENOMINATOR();
    currentPrice = await coolTokenProxy.currentPrice();
  });

  describe("Buy Logic", function () {
    it("Buy should spend ETH and mint tokens to buyer", async function () {
      const [expectedTokensBought] = buyOutput(
        ONE_ETH,
        currentFee,
        currentPrice,
        currentBPSDenominator,
      );

      expect(
        await coolTokenProxy.buy({
          value: ONE_ETH,
        }),
      ).changeEtherBalances(
        _ethers,
        [contractAddress, deployerAddress],
        [ONE_ETH, -ONE_ETH],
      );

      expect(await coolTokenProxy.balanceOf(deployerAddress)).to.equal(
        expectedTokensBought,
      );
    });
  });

  describe("Sell Logic", function () {
    it("Sell should burn tokens from seller, transfer ETH to seller", async function () {
      await coolTokenProxy.buy({ value: ONE_ETH * 50n });

      const currentTokenBalance: bigint =
        await coolTokenProxy.balanceOf(deployerAddress);
      const [expectedEth] = sellOutput(
        currentTokenBalance,
        currentFee,
        currentPrice,
        currentBPSDenominator,
      );

      expect(
        await coolTokenProxy.sell(currentTokenBalance),
      ).changeEtherBalances(
        _ethers,
        [contractAddress, deployerAddress],
        [-expectedEth, expectedEth],
      );

      expect(await coolTokenProxy.balanceOf(deployerAddress)).to.equal(0n);
    });
  });

  describe("Fee Logic", function () {
    it("Fee calculation logic should work properly", async function () {
      const ethSpent: bigint = ONE_ETH * 50n;

      await coolTokenProxy.buy({ value: ethSpent });

      const [, expectedBuyFee] = buyOutput(
        ethSpent,
        currentFee,
        currentPrice,
        currentBPSDenominator,
      );

      expect(await coolTokenProxy.feeTokensAccrued()).to.equal(expectedBuyFee);
      const tokensToSell = await coolTokenProxy.balanceOf(deployerAddress);

      const [, expectedSellFee] = sellOutput(
        tokensToSell,
        currentFee,
        currentPrice,
        currentBPSDenominator,
      );
      await coolTokenProxy.sell(tokensToSell);

      expect(await coolTokenProxy.feeTokensAccrued()).to.equal(
        expectedBuyFee + expectedSellFee,
      );
    });

    it("Fee burn logic should work properly", async function () {
      const { time } = _networkHelpers;
      const ethSpent: bigint = ONE_ETH * 10n;

      await coolTokenProxy.buy({ value: ethSpent });
      const T_buy_block = BigInt(await time.latest());
      const [, accruedFee] = buyOutput(
        ethSpent,
        currentFee,
        currentPrice,
        currentBPSDenominator,
      );

      const initialSupply = await coolTokenProxy.totalSupply();

      const T_burn_enabled = T_buy_block + SEVEN_DAYS;

      const T_too_early = T_burn_enabled - 1n * 60n * 60n;

      await time.increaseTo(T_too_early);

      await expect(coolTokenProxy.burnFees()).to.be.revertedWithCustomError(
        coolTokenProxy,
        "TooEarlyToBurnFees",
      );

      const T_burn_final = T_burn_enabled + 1n;
      await time.increaseTo(T_burn_final);

      await expect(coolTokenProxy.burnFees()).to.emit(
        coolTokenProxy,
        "FeeBurned",
      );

      expect(await coolTokenProxy.feeTokensAccrued()).to.equal(0n);
      expect(await coolTokenProxy.balanceOf(contractAddress)).to.equal(0n);
      expect(await coolTokenProxy.totalSupply()).to.equal(
        initialSupply - accruedFee,
      );
    });

    it("setFeeBps function should be protected, Fee should not exceed max fee", async function () {
      const newFee = 50n;
      const initialFee = await coolTokenProxy.feeBps();
      const MAX_FEE_BPS = await coolTokenProxy.MAX_FEE_BPS();

      const nonOwner = friend;

      await expect(
        coolTokenProxy.connect(nonOwner).setFeeBps(newFee),
      ).to.be.revert(_ethers);

      expect(await coolTokenProxy.feeBps()).to.equal(initialFee);

      const excessiveFee = MAX_FEE_BPS + 1n;

      await expect(
        coolTokenProxy.setFeeBps(excessiveFee),
      ).to.be.revertedWithCustomError(coolTokenProxy, "MaxFeeExceeded");

      expect(await coolTokenProxy.feeBps()).to.equal(initialFee);

      const finalNewFee = 100n;

      await expect(coolTokenProxy.setFeeBps(finalNewFee))
        .to.emit(coolTokenProxy, "FeeUpdated")
        .withArgs(initialFee, finalNewFee);

      expect(await coolTokenProxy.feeBps()).to.equal(finalNewFee);
    });
  });
});
