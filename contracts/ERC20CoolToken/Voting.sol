// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Tradeable.sol";

abstract contract Voting is Tradeable {
    error VotingAlreadyInProgress();
    error NotEnoughTokensToStartVoting();
    error NoActiveVoting();
    error VotingPeriodOver();
    error PriceMustBeGreaterThanZero();
    error NotEnoughTokensToVote();
    error VotingStillInProgress();

    uint256 public votingTimeLength; 
    bool public isVotingInProgress;
    uint256 public votingNumber;
    uint256 public votingStartedTime;

    uint256 public leadingPrice;
    uint256 public leadingPriceVotes;

    mapping(uint256 => mapping(uint256 => uint256)) public priceVotes;
    mapping(address => uint256) public tokensStaked;
    mapping(address => uint256) public stakingClaimTips;

    event VotingStarted(uint256 indexed votingNumber, uint256 startTime);
    event Voted(
        address indexed voter,
        uint256 indexed votingNumber,
        uint256 price,
        uint256 votingPower
    );
    event VotingEnded(
        uint256 indexed votingNumber,
        uint256 winningPrice,
        uint256 totalVotingPower
    );
    event Claimed(
        address indexed claimer, 
        address indexed account, 
        uint256 tokensClaimed, 
        uint256 ethTip
    );

    function __Voting_init(
        uint256 votingTimeLength_
    ) internal onlyInitializing {
        votingTimeLength = votingTimeLength_;
    }

    function startVoting() external {
        if (isVotingInProgress) revert VotingAlreadyInProgress();

        uint256 minToStart = (totalSupply() * 10) / BPS_DENOMINATOR; 
        if (balanceOf(msg.sender) <= minToStart) revert NotEnoughTokensToStartVoting();

        isVotingInProgress = true;
        votingNumber += 1;
        votingStartedTime = block.timestamp;

        leadingPrice = 0;
        leadingPriceVotes = 0;

        emit VotingStarted(votingNumber, votingStartedTime);
    }

    function vote(uint256 price, uint256 tokensAmount) external payable {
        if (!isVotingInProgress) revert NoActiveVoting();
        if (block.timestamp > votingStartedTime + votingTimeLength) revert VotingPeriodOver();
        if (price == 0) revert PriceMustBeGreaterThanZero();

        uint256 balance = balanceOf(msg.sender);
        if (balance < tokensAmount) revert NotEnoughTokens();

        uint256 minToVote = (totalSupply() * 5) / BPS_DENOMINATOR;
        if (balance <= minToVote) revert NotEnoughTokensToVote();

        _transfer(msg.sender, address(this), tokensAmount);
        
        uint256 newTotalVotesForPrice = priceVotes[votingNumber][price] + tokensAmount;
        priceVotes[votingNumber][price] = newTotalVotesForPrice;
        tokensStaked[msg.sender] += tokensAmount;
        
        stakingClaimTips[msg.sender] += msg.value;

        if (newTotalVotesForPrice > leadingPriceVotes) {
            leadingPriceVotes = newTotalVotesForPrice;
            leadingPrice = price;
        }

        emit Voted(msg.sender, votingNumber, price, tokensAmount);
    }

    function endVoting() external {
        if (!isVotingInProgress) revert NoActiveVoting();
        if (block.timestamp < votingStartedTime + votingTimeLength) revert VotingStillInProgress();

        isVotingInProgress = false;

        if (leadingPriceVotes > 0) {
            currentPrice = leadingPrice; 
        }

        emit VotingEnded(votingNumber, leadingPrice, leadingPriceVotes);
    }
    
    function claim(address account) external nonReentrant {
        if (isVotingInProgress) revert NoActiveVoting();

        uint256 tokensToClaim = tokensStaked[account];
        _transfer(address(this), account, tokensToClaim);
        tokensStaked[account] = 0;

        uint256 tip = stakingClaimTips[account];
        if (tip > 0) {
            stakingClaimTips[account] = 0;
            (bool sent, ) = msg.sender.call{value: tip}("");
            if (!sent) revert ETHTransferFailed();
        }
        
        emit Claimed(msg.sender, account, tokensToClaim, tip);
    }
}