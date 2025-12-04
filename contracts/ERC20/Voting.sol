// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Tradeable.sol";
import "./VotingLinkedList.sol";

abstract contract Voting is Tradeable {
    error VotingAlreadyInProgress();
    error NotEnoughTokensToStartVoting();
    error NoActiveVoting();
    error VotingPeriodOver();
    error PriceMustBeGreaterThanZero();
    error NotEnoughTokensToVote();
    error VotingStillInProgress();
    error InvalidNodePosition();
    error CannotClaimDuringVoting();

    uint256 public votingTimeLength;
    bool public isVotingInProgress;
    uint256 public votingNumber;
    uint256 public votingStartedTime;

    // mapping[votingNumver] = LinkedList
    mapping(uint256 => VotingLinkedList) public votingLists;
    // mapping[votingNumber][price][address] = power
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        public tokensStakedByVoterOnPrice;
    // mapping[votingNumber][price][address] = tip
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        public voterTipByPrice;

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
        if (balanceOf(msg.sender) <= minToStart)
            revert NotEnoughTokensToStartVoting();

        isVotingInProgress = true;
        votingNumber += 1;
        votingStartedTime = block.timestamp;

        VotingLinkedList list = new VotingLinkedList();
        votingLists[votingNumber] = list;

        emit VotingStarted(votingNumber, votingStartedTime);
    }

    function vote(
        uint256 price,
        uint256 tokensAmount,
        uint256 prevPriceHint,
        uint256 nextPriceHint
    ) external payable {
        if (!isVotingInProgress) revert NoActiveVoting();
        if (block.timestamp > votingStartedTime + votingTimeLength)
            revert VotingPeriodOver();
        if (price == 0) revert PriceMustBeGreaterThanZero();

        uint256 balance = balanceOf(msg.sender);
        if (balance < tokensAmount) revert NotEnoughTokens();

        uint256 minToVote = (totalSupply() * 5) / BPS_DENOMINATOR;
        if (balance <= minToVote) revert NotEnoughTokensToVote();

        _transfer(msg.sender, address(this), tokensAmount);
        tokensStakedByVoterOnPrice[votingNumber][price][
            msg.sender
        ] += tokensAmount;
        voterTipByPrice[votingNumber][price][msg.sender] += msg.value;

        VotingLinkedList list = votingLists[votingNumber];
        uint256 prevPower = list.getPower(price);
        uint256 newPower = prevPower + tokensAmount;

        if (list.contains(price)) {
            list.update(price, newPower, prevPriceHint, nextPriceHint);
        } else {
            list.insert(price, newPower, prevPriceHint, nextPriceHint);
        }

        emit Voted(msg.sender, votingNumber, price, tokensAmount);
    }

    function endVoting() external {
        if (!isVotingInProgress) revert NoActiveVoting();
        if (block.timestamp < votingStartedTime + votingTimeLength)
            revert VotingStillInProgress();

        isVotingInProgress = false;

        VotingLinkedList list = votingLists[votingNumber];
        uint256 leadingPrice = list.getWinnerPrice();
        uint256 winnerPower = 0;
        if (leadingPrice > 0) {
            winnerPower = list.getPower(leadingPrice);
            currentPrice = leadingPrice;
        }

        emit VotingEnded(votingNumber, leadingPrice, winnerPower);
    }

    function withdraw(
        uint256 price,
        uint256 tokensAmount,
        uint256 prevPriceHint,
        uint256 nextPriceHint
    ) external nonReentrant {
        uint256 vn = votingNumber;

        uint256 staked = tokensStakedByVoterOnPrice[vn][price][msg.sender];
        if (staked < tokensAmount) revert NotEnoughTokens();

        VotingLinkedList list = votingLists[vn];
        if (!list.contains(price)) revert InvalidNodePosition();

        uint256 nodePower = list.getPower(price);
        if (nodePower < tokensAmount) revert InvalidNodePosition();

        uint256 newPower = nodePower - tokensAmount;

        if (newPower > 0) {
            list.update(price, newPower, prevPriceHint, nextPriceHint);
        } else {
            list.remove(price);
        }
        tokensStakedByVoterOnPrice[vn][price][msg.sender] =
            staked - tokensAmount;
        _transfer(address(this), msg.sender, tokensAmount);
    }

    function claim(
        address account,
        uint256 votingRound,
        uint256 price
    ) external nonReentrant {
        if (isVotingInProgress) revert CannotClaimDuringVoting();

        uint256 tokensToClaim = tokensStakedByVoterOnPrice[votingRound][price][
            account
        ];
        _transfer(address(this), account, tokensToClaim);

        tokensStakedByVoterOnPrice[votingRound][price][
            account
        ] -= tokensToClaim;

        uint256 tip = voterTipByPrice[votingRound][price][account];
        if (tip > 0) {
            voterTipByPrice[votingRound][price][account] -= tip;
            (bool sent, ) = msg.sender.call{value: tip}("");
            if (!sent) revert ETHTransferFailed();
        }

        emit Claimed(msg.sender, account, tokensToClaim, tip);
    }

}
