import { expect } from "chai";
import { network } from "hardhat";
import { CoolToken } from "../types/ethers-contracts/index.js";
import { deployFixture } from "./fixtures.js";
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
let VOTING_TIME_LENGTH: bigint;
let SEVEN_DAYS: bigint;

describe("CoolToken: Voting Logic Coverage", function () {
  let coolTokenProxy: CoolToken;
  let deployer: any;
  let friend: any;
  let voterC: any;
  let deployerAddress: string;

  let currentBPSDenominator: bigint;
  let initialSupply: bigint;
  let MIN_TO_START: bigint;
  let MIN_TO_VOTE: bigint;

  beforeEach(async function () {
    const networkConnection = await network.connect();
    _ethers = networkConnection.ethers;
    _networkHelpers = networkConnection.networkHelpers;

    [deployer, friend, voterC] = await _ethers.getSigners();
    deployerAddress = deployer.address;

    ({ coolTokenProxy } = await _networkHelpers.loadFixture(localFixture));

    DECIMALS = await coolTokenProxy.decimals();
    ONE_ETH = _ethers.parseEther("1.0");
    SEVEN_DAYS = 7n * 24n * 60n * 60n;
    ONE_TOKEN = _ethers.parseUnits("1", DECIMALS);

    VOTING_TIME_LENGTH = await coolTokenProxy.votingTimeLength();
    currentBPSDenominator = await coolTokenProxy.BPS_DENOMINATOR();

    await coolTokenProxy.buy({ value: ONE_ETH * 100n });
    initialSupply = await coolTokenProxy.totalSupply();

    MIN_TO_START = (initialSupply * 10n) / currentBPSDenominator; // 0.1%
    MIN_TO_VOTE = (initialSupply * 5n) / currentBPSDenominator; // 0.05%
  });

  describe("Start voting Logic", function () {
    it("Start voting should properly update state", async function () {
      const initialVotingNumber: bigint = await coolTokenProxy.votingNumber();
      expect(await coolTokenProxy.isVotingInProgress()).to.be.false;
      expect(await coolTokenProxy.startVoting()).to.emit(
        coolTokenProxy,
        "VotingStarted",
      );

      expect(await coolTokenProxy.votingNumber()).to.equal(
        initialVotingNumber + 1n,
      );
      expect(await coolTokenProxy.isVotingInProgress()).to.be.true;
    });

    it("Start voting function should revert if caller has not enough tokens or if voting is still in progress", async function () {
      const isVotingInprogress: boolean =
        await coolTokenProxy.isVotingInProgress();

      expect(isVotingInprogress).to.be.false;

      await coolTokenProxy.transfer(friend.address, MIN_TO_START - 1n);

      await expect(
        coolTokenProxy.connect(friend).startVoting(),
      ).to.be.revertedWithCustomError(
        coolTokenProxy,
        "NotEnoughTokensToStartVoting",
      );

      await coolTokenProxy.startVoting();

      expect(await coolTokenProxy.isVotingInProgress()).to.be.true;

      await expect(coolTokenProxy.startVoting()).to.be.revertedWithCustomError(
        coolTokenProxy,
        "VotingAlreadyInProgress",
      );
    });
  });

  describe("Vote Logic", function () {
    let somePrice: bigint;
    let tokensToVote: bigint;
    it("Vote function should revert if voting is not active", async function () {
      somePrice = ONE_ETH / 5n;
      tokensToVote = ONE_TOKEN * 10n;

      expect(await coolTokenProxy.isVotingInProgress()).to.be.false;
      await expect(
        coolTokenProxy.vote(somePrice, tokensToVote, 0, 0),
      ).to.be.revertedWithCustomError(coolTokenProxy, "NoActiveVoting");
    });

    describe("When Voting is active", function () {
      beforeEach(async function () {
        await coolTokenProxy.startVoting();
      });

      it("Vote function should revert if price is 0", async function () {
        tokensToVote = ONE_TOKEN * 10n;
        await expect(
          coolTokenProxy.vote(0, tokensToVote, 0, 0),
        ).to.be.revertedWithCustomError(
          coolTokenProxy,
          "PriceMustBeGreaterThanZero",
        );
      });

      it("Vote function should revert if voter try to pass more tokens than he has", async function () {
        somePrice = ONE_ETH / 5n;
        tokensToVote = (await coolTokenProxy.balanceOf(deployerAddress)) + 1n;

        await expect(
          coolTokenProxy.vote(somePrice, tokensToVote, 0, 0),
        ).to.be.revertedWithCustomError(coolTokenProxy, "NotEnoughTokens");
      });
      it("Vote function should revert if voter try to pass 0 tokens", async function () {
        somePrice = ONE_ETH / 5n;
        await expect(
          coolTokenProxy.vote(somePrice, 0, 0, 0),
        ).to.be.revertedWithCustomError(coolTokenProxy, "NotEnoughTokens");
      });

      it("Vote function should revert if voting time period is over", async function () {
        somePrice = ONE_ETH / 5n;
        tokensToVote = ONE_TOKEN * 10n;

        const { time } = _networkHelpers;
        const votingTimeLength: bigint =
          await coolTokenProxy.votingTimeLength();
        const currentTime: bigint = BigInt(await time.latest());
        await time.increaseTo(currentTime + votingTimeLength + 1n);
        await expect(
          coolTokenProxy.vote(somePrice, tokensToVote, 0, 0),
        ).to.be.revertedWithCustomError(coolTokenProxy, "VotingPeriodOver");
      });

      it("Vote function should revert if user has not enough tokens percent to vote", async function () {
        somePrice = ONE_ETH / 5n;
        tokensToVote = MIN_TO_VOTE - 1n;
        await coolTokenProxy.transfer(friend.address, tokensToVote);

        await expect(
          coolTokenProxy.connect(friend).vote(somePrice, tokensToVote, 0, 0),
        ).to.be.revertedWithCustomError(
          coolTokenProxy,
          "NotEnoughTokensToVote",
        );
      });

      it("Vote should correctly position nodes based on power and use hints", async function () {
        const currentVN = await coolTokenProxy.votingNumber();

        await coolTokenProxy.connect(friend).buy({ value: ONE_ETH * 100n });

        const priceP1 = 100n;
        const priceP2 = 200n;
        const priceP3 = 300n;

        const stakeP1 = 10n * ONE_TOKEN;
        const stakeP2 = 20n * ONE_TOKEN;
        const stakeP3 = 15n * ONE_TOKEN;

        const getNodeData = async (price: bigint) => {
          return coolTokenProxy.getNode(currentVN, price);
        };

        const getWinningPrice = async () => {
          const listData = await coolTokenProxy.votingLists(currentVN);
          return listData[0]; // head
        };

        await coolTokenProxy.vote(priceP1, stakeP1, 0n, 0n);

        let p1Node = await getNodeData(priceP1);
        expect(await getWinningPrice()).to.equal(priceP1);
        expect(p1Node.nextPrice).to.equal(0n);
        expect(p1Node.power).to.equal(stakeP1);

        await coolTokenProxy.vote(priceP2, stakeP2, 0n, priceP1);

        let p2Node = await getNodeData(priceP2);
        p1Node = await getNodeData(priceP1);

        expect(await getWinningPrice()).to.equal(priceP2);
        expect(p2Node.nextPrice).to.equal(priceP1);
        expect(p1Node.prevPrice).to.equal(priceP2);
        expect(p1Node.nextPrice).to.equal(0n);
        expect(p2Node.power).to.equal(stakeP2);

        await coolTokenProxy
          .connect(friend)
          .vote(priceP3, stakeP3, priceP2, priceP1);

        let p3Node = await getNodeData(priceP3);
        p2Node = await getNodeData(priceP2);
        p1Node = await getNodeData(priceP1);

        expect(await getWinningPrice()).to.equal(priceP2);

        expect(p2Node.nextPrice).to.equal(priceP3);
        expect(p3Node.prevPrice).to.equal(priceP2);

        expect(p3Node.nextPrice).to.equal(priceP1);
        expect(p1Node.prevPrice).to.equal(priceP3);

        expect(p1Node.nextPrice).to.equal(0n);
        expect(p3Node.power).to.equal(stakeP3);

        const stakeP3_update = 15n * ONE_TOKEN;
        const totalStakeP3 = stakeP3 + stakeP3_update;

        await coolTokenProxy
          .connect(friend)
          .vote(priceP3, stakeP3_update, 0n, priceP2);

        p3Node = await getNodeData(priceP3);
        p2Node = await getNodeData(priceP2);
        p1Node = await getNodeData(priceP1);

        expect(p3Node.power).to.equal(totalStakeP3);

        expect(await getWinningPrice()).to.equal(priceP3);

        expect(p3Node.prevPrice).to.equal(0n);
        expect(p3Node.nextPrice).to.equal(priceP2);

        expect(p2Node.prevPrice).to.equal(priceP3);
        expect(p2Node.nextPrice).to.equal(priceP1);

        expect(p1Node.prevPrice).to.equal(priceP2);
        expect(p1Node.nextPrice).to.equal(0n);
      });
    });
  });

  describe("Claim Logic", function () {
    let finishedVN: bigint;
    let priceC: bigint;
    let tokensC: bigint;
    let ethTip: bigint;

    beforeEach(async function () {
      await coolTokenProxy.connect(friend).buy({ value: ONE_ETH * 5n });

      await coolTokenProxy.startVoting();
      finishedVN = await coolTokenProxy.votingNumber();

      priceC = 2000n;
      tokensC = ONE_TOKEN * 5n;
      ethTip = ONE_ETH / 10n;

      await coolTokenProxy
        .connect(friend)
        .vote(priceC, tokensC, 0n, 0n, { value: ethTip });

      const { time } = _networkHelpers;
      const votingTimeLength: bigint = await coolTokenProxy.votingTimeLength();
      const currentTime: bigint = BigInt(await time.latest());
      await time.increaseTo(currentTime + votingTimeLength + 1n);
      await coolTokenProxy.endVoting();
    });

    it("Claim should revert if voting is still in progress", async function () {
      await coolTokenProxy.startVoting();

      expect(await coolTokenProxy.isVotingInProgress()).to.be.true;

      await expect(
        coolTokenProxy.claim(friend.address, finishedVN, priceC),
      ).to.be.revertedWithCustomError(
        coolTokenProxy,
        "CannotClaimDuringVoting",
      );
    });

    it("Claim should successfully transfer tokens and ETH tip to caller and reset state", async function () {
      const accountToClaim = friend.address;
      const claimer = deployer;

      const initialBalanceETH = await _ethers.provider.getBalance(
        claimer.address,
      );
      const initialBalanceToken =
        await coolTokenProxy.balanceOf(accountToClaim);

      expect(
        await coolTokenProxy.tokensStakedByVoterOnPrice(
          finishedVN,
          priceC,
          accountToClaim,
        ),
      ).to.equal(tokensC);
      expect(
        await coolTokenProxy.voterTipByPrice(
          finishedVN,
          priceC,
          accountToClaim,
        ),
      ).to.equal(ethTip);

      const claimTx = await coolTokenProxy
        .connect(claimer)
        .claim(accountToClaim, finishedVN, priceC);
      const receipt = await claimTx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;

      const finalBalanceETH = await _ethers.provider.getBalance(
        claimer.address,
      );
      const finalBalanceToken = await coolTokenProxy.balanceOf(accountToClaim);

      expect(finalBalanceToken).to.equal(initialBalanceToken + tokensC);

      expect(finalBalanceETH).to.be.closeTo(
        initialBalanceETH + ethTip - gasUsed,
        ONE_ETH / 1000n,
      );

      expect(
        await coolTokenProxy.tokensStakedByVoterOnPrice(
          finishedVN,
          priceC,
          accountToClaim,
        ),
      ).to.equal(0n);
      expect(
        await coolTokenProxy.voterTipByPrice(
          finishedVN,
          priceC,
          accountToClaim,
        ),
      ).to.equal(0n);

      await expect(claimTx)
        .to.emit(coolTokenProxy, "Claimed")
        .withArgs(claimer.address, accountToClaim, tokensC, ethTip);
    });

    it("Claim should handle zero staked tokens and zero tips correctly", async function () {
      const zeroPrice = 1111n;
      const accountToClaim = friend.address;

      expect(
        await coolTokenProxy.tokensStakedByVoterOnPrice(
          finishedVN,
          zeroPrice,
          accountToClaim,
        ),
      ).to.equal(0n);

      const initialBalanceETH = await _ethers.provider.getBalance(
        deployer.address,
      );
      const initialBalanceToken =
        await coolTokenProxy.balanceOf(accountToClaim);

      const claimTx = await coolTokenProxy.claim(
        accountToClaim,
        finishedVN,
        zeroPrice,
      );
      const receipt = await claimTx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;

      const finalBalanceETH = await _ethers.provider.getBalance(
        deployer.address,
      );
      const finalBalanceToken = await coolTokenProxy.balanceOf(accountToClaim);

      expect(finalBalanceToken).to.equal(initialBalanceToken);
      expect(finalBalanceETH).to.be.closeTo(
        initialBalanceETH - gasUsed,
        ONE_ETH / 1000n,
      );

      expect(
        await coolTokenProxy.tokensStakedByVoterOnPrice(
          finishedVN,
          zeroPrice,
          accountToClaim,
        ),
      ).to.equal(0n);
      expect(
        await coolTokenProxy.voterTipByPrice(
          finishedVN,
          zeroPrice,
          accountToClaim,
        ),
      ).to.equal(0n);

      await expect(claimTx)
        .to.emit(coolTokenProxy, "Claimed")
        .withArgs(deployer.address, accountToClaim, 0n, 0n);
    });
  });

  describe("Withdraw Logic", function () {
    let vn: bigint;
    let priceW: bigint;
    let tokensW: bigint;

    const getWinningPrice = async (votingNumber: bigint) => {
      const listData = await coolTokenProxy.votingLists(votingNumber);
      return listData[0];
    };

    beforeEach(async function () {
      await coolTokenProxy.connect(friend).buy({ value: ONE_ETH * 100n });

      await coolTokenProxy.startVoting();
      vn = await coolTokenProxy.votingNumber();

      priceW = 1000n;
      tokensW = ONE_TOKEN * 50n;

      await coolTokenProxy.connect(friend).vote(priceW, tokensW, 0n, 0n);
    });

    it("Withdraw should revert if voter tries to withdraw more tokens than staked", async function () {
      await expect(
        coolTokenProxy.connect(friend).withdraw(priceW, tokensW + 1n, 0n, 0n),
      ).to.be.revertedWithCustomError(coolTokenProxy, "NotEnoughTokens");
    });

    it("Withdraw should revert if node price does not exist (InvalidNodePosition)", async function () {
      const nonExistentPrice = 9999n;
      await expect(
        coolTokenProxy.connect(friend).withdraw(nonExistentPrice, 1n, 0n, 0n),
      ).to.be.revertedWithCustomError(coolTokenProxy, "NotEnoughTokens");
    });

    it("Withdraw should successfully decrease power and remain in list if power > 0", async function () {
      const tokensToWithdraw = ONE_TOKEN * 10n;
      const initialBalance = await coolTokenProxy.balanceOf(friend.address);
      const initialStaked = await coolTokenProxy.tokensStakedByVoterOnPrice(
        vn,
        priceW,
        friend.address,
      );
      const initialNodePower = (await coolTokenProxy.getNode(vn, priceW)).power;

      await coolTokenProxy
        .connect(friend)
        .withdraw(priceW, tokensToWithdraw, 0n, 0n);

      const finalBalance = await coolTokenProxy.balanceOf(friend.address);
      const finalStaked = await coolTokenProxy.tokensStakedByVoterOnPrice(
        vn,
        priceW,
        friend.address,
      );
      const finalNodePower = (await coolTokenProxy.getNode(vn, priceW)).power;

      expect(finalBalance).to.equal(initialBalance + tokensToWithdraw);
      expect(finalStaked).to.equal(initialStaked - tokensToWithdraw);

      expect(finalNodePower).to.equal(initialNodePower - tokensToWithdraw);

      const nodeAfterWithdraw = await coolTokenProxy.getNode(vn, priceW);
      expect(nodeAfterWithdraw.price).to.equal(priceW);
    });

    it("Withdraw should successfully remove node from list if final power is 0", async function () {
      const initialBalance = await coolTokenProxy.balanceOf(friend.address);

      await coolTokenProxy.connect(friend).withdraw(priceW, tokensW, 0n, 0n);

      const finalBalance = await coolTokenProxy.balanceOf(friend.address);
      const finalStaked = await coolTokenProxy.tokensStakedByVoterOnPrice(
        vn,
        priceW,
        friend.address,
      );

      expect(finalBalance).to.equal(initialBalance + tokensW);
      expect(finalStaked).to.equal(0n);

      const nodeAfterWithdraw = await coolTokenProxy.getNode(vn, priceW);
      expect(nodeAfterWithdraw.power).to.equal(0n);
      expect(nodeAfterWithdraw.prevPrice).to.equal(0n);
      expect(nodeAfterWithdraw.nextPrice).to.equal(0n);
    });

    it("Withdraw should maintain linked list integrity when removing a middle node", async function () {
      const priceA = 100n;
      const priceB = 200n;
      const priceC = 300n;
      const stakeA = 100n * ONE_TOKEN;
      const stakeB = 200n * ONE_TOKEN;
      const stakeC = 300n * ONE_TOKEN;

      await coolTokenProxy.connect(friend).vote(priceA, stakeA, 0n, 0n);
      await coolTokenProxy.connect(friend).vote(priceC, stakeC, 0n, priceA);

      await coolTokenProxy.connect(friend).vote(priceB, stakeB, priceC, priceA);

      let nodeB = await coolTokenProxy.getNode(vn, priceB);
      let nodeA = await coolTokenProxy.getNode(vn, priceA);
      let nodeC = await coolTokenProxy.getNode(vn, priceC);

      expect(nodeC.nextPrice).to.equal(priceB, "C -> B");
      expect(nodeB.prevPrice).to.equal(priceC, "C <- B");
      expect(nodeB.nextPrice).to.equal(priceA, "B -> A");
      expect(nodeA.prevPrice).to.equal(priceB, "B <- A");

      await coolTokenProxy
        .connect(friend)
        .withdraw(priceB, stakeB, priceC, priceA);

      nodeB = await coolTokenProxy.getNode(vn, priceB);
      nodeA = await coolTokenProxy.getNode(vn, priceA);
      nodeC = await coolTokenProxy.getNode(vn, priceC);

      expect(nodeB.power).to.equal(0n);

      expect(nodeC.nextPrice).to.equal(priceA, "C -> A");
      expect(nodeA.prevPrice).to.equal(priceC, "C <- A");
      expect(await getWinningPrice(vn)).to.equal(priceC);
    });
  });
});
