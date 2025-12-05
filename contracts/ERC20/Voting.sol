// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Tradeable.sol";
import {VotingLinkedListLib as VLL} from "./VotingLinkedListLib.sol";

/// @title Voting (price discovery)
/// @notice Manages voting rounds where token holders stake tokens to vote for a price.
/// @dev Uses an internal sorted linked-list (library) to pick the leading price per round.
abstract contract Voting is Tradeable {
    using VLL for VLL.List;

    error VotingAlreadyInProgress();
    error NotEnoughTokensToStartVoting();
    error NoActiveVoting();
    error VotingPeriodOver();
    error PriceMustBeGreaterThanZero();
    error NotEnoughTokensToVote();
    error VotingStillInProgress();
    error InvalidNodePosition();
    error CannotClaimDuringVoting();

    /// @notice Duration of a voting round in seconds
    uint256 public votingTimeLength;
    /// @notice Whether a voting round is currently active
    bool public isVotingInProgress;
    /// @notice Counter of voting rounds (starts at 0)
    uint256 public votingNumber;
    /// @notice Timestamp when the current voting round started
    uint256 public votingStartedTime;

    /// @notice Mapping from votingNumber to the internal linked-list for that round
    mapping(uint256 => VLL.List) public votingLists;
    /// @notice mapping[votingNumber][price][address] = tokens staked by voter on that price
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        public tokensStakedByVoterOnPrice;
    /// @notice mapping[votingNumber][price][address] = ETH tip provided by voter
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

    /// @notice Initialize voting parameters
    /// @dev Called from initializer of the inheriting contract.
    /// @param votingTimeLength_ Length of each voting round in seconds
    function __Voting_init(
        uint256 votingTimeLength_
    ) internal onlyInitializing {
        votingTimeLength = votingTimeLength_;
    }

    /// @notice Start a new voting round
    /// @dev Caller must hold more than configured fraction of totalSupply (minToStart).
    /// Emits VotingStarted.
    function startVoting() external {
        if (isVotingInProgress) revert VotingAlreadyInProgress();

        uint256 minToStart = (totalSupply() * 10) / BPS_DENOMINATOR;
        if (balanceOf(msg.sender) <= minToStart)
            revert NotEnoughTokensToStartVoting();

        isVotingInProgress = true;
        votingNumber += 1;
        votingStartedTime = block.timestamp;

        emit VotingStarted(votingNumber, votingStartedTime);
    }

    /// @notice Stake tokens and vote for `price` during an active voting round
    /// @dev Caller transfers `tokensAmount` to this contract. Accepts an ETH tip via msg.value.
    /// Hints (prevPriceHint/nextPriceHint) are optional gas optimizations for list insertion.
    /// @param price Price candidate (must be > 0)
    /// @param tokensAmount Amount of tokens to stake for this price
    /// @param prevPriceHint Hint for previous node price (0 if none)
    /// @param nextPriceHint Hint for next node price (0 if none)
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

        if (tokensAmount == 0) revert NotEnoughTokens();

        _transfer(msg.sender, address(this), tokensAmount);
        tokensStakedByVoterOnPrice[votingNumber][price][
            msg.sender
        ] += tokensAmount;
        voterTipByPrice[votingNumber][price][msg.sender] += msg.value;

        VLL.List storage list = votingLists[votingNumber];
        uint256 prevPower = list.getPower(price);
        uint256 newPower = prevPower + tokensAmount;

        if (list.contains(price)) {
            list.update(price, newPower, prevPriceHint, nextPriceHint);
        } else {
            list.insert(price, newPower, prevPriceHint, nextPriceHint);
        }

        emit Voted(msg.sender, votingNumber, price, tokensAmount);
    }

    /// @notice End the current voting round and set `currentPrice` to the winning price
    /// @dev Can be called by anyone after the voting period has elapsed.
    /// Emits VotingEnded.
    function endVoting() external {
        if (!isVotingInProgress) revert NoActiveVoting();
        if (block.timestamp < votingStartedTime + votingTimeLength)
            revert VotingStillInProgress();

        isVotingInProgress = false;

        VLL.List storage list = votingLists[votingNumber];
        uint256 leadingPrice = list.getWinnerPrice();
        uint256 winnerPower = 0;
        if (leadingPrice > 0) {
            winnerPower = list.getPower(leadingPrice);
            currentPrice = leadingPrice;
        }

        emit VotingEnded(votingNumber, leadingPrice, winnerPower);
    }

    /// @notice Withdraw staked tokens from a price node of the most recent round
    /// @dev Uses hints to reposition or remove the node after withdrawal.
    /// @param price Price node to withdraw from
    /// @param tokensAmount Amount of tokens to withdraw (must be <= staked)
    /// @param prevPriceHint Hint for previous node price (0 if none)
    /// @param nextPriceHint Hint for next node price (0 if none)
    function withdraw(
        uint256 price,
        uint256 tokensAmount,
        uint256 prevPriceHint,
        uint256 nextPriceHint
    ) external nonReentrant {
        uint256 vn = votingNumber;

        uint256 staked = tokensStakedByVoterOnPrice[vn][price][msg.sender];
        if (staked < tokensAmount) revert NotEnoughTokens();

        VLL.List storage list = votingLists[vn];
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

    /// @notice Claim staked tokens and optional ETH tip from a finished voting round
    /// @dev Can be called by anyone for `account`. If a tip exists it is sent to the caller.
    /// @param account Account whose staked tokens and tip are claimed
    /// @param votingRound Voting round index to claim from
    /// @param price Price node to claim for
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
