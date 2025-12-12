// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../ERC20/Tradeable.sol";
/// @title Voting (price discovery)
/// @notice Manages voting rounds where token holders stake tokens to vote for a price.
/// @dev Uses an internal sorted linked-list (library) to pick the leading price per round.
abstract contract InsecureVoting is Tradeable {
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

    /// @notice Mapping from votingNumber to the price array of voting
    mapping(uint256 => uint256[]) public votingLists;
    /// @notice mapping[votingNumber][price] = power;
    mapping(uint256 => mapping(uint256 => uint256)) public votedPower;
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
    function vote(
        uint256 price,
        uint256 tokensAmount
    ) external payable {
        if (!isVotingInProgress) revert NoActiveVoting();
        if (block.timestamp > votingStartedTime + votingTimeLength)
            revert VotingPeriodOver();
        if (price == 0) revert PriceMustBeGreaterThanZero();

        uint256 balance = balanceOf(msg.sender);
        if (balance < tokensAmount) revert NotEnoughTokens();

        if (tokensAmount == 0) revert NotEnoughTokens();

        _transfer(msg.sender, address(this), tokensAmount);
        tokensStakedByVoterOnPrice[votingNumber][price][
            msg.sender
        ] += tokensAmount;
        voterTipByPrice[votingNumber][price][msg.sender] += msg.value;

        uint256[] storage list = votingLists[votingNumber];
        uint256 prevPower = votedPower[votingNumber][price];
        if(prevPower == 0){
            list.push(price);
        }
        uint256 newPower = prevPower + tokensAmount;

        votedPower[votingNumber][price] = newPower;

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

        uint256[] storage list = votingLists[votingNumber];
        uint256 leadingPrice = 0;
        uint256 winnerPower = 0;
        for(uint256 i = 0; i< list.length; i++){
            uint256 cPrice = list[i]; 
            uint256 cPower = votedPower[votingNumber][cPrice];
            if (cPower > winnerPower){
                leadingPrice = cPrice;
                winnerPower = cPower;
            }
        }

        if (leadingPrice > 0) {
            currentPrice = leadingPrice;
        }

        emit VotingEnded(votingNumber, leadingPrice, winnerPower);
    }
    
    function claim(
        address account,
        uint256 votingRound,
        uint256 price
    ) external {
        if (isVotingInProgress) revert CannotClaimDuringVoting();

        uint256 tokensToClaim = tokensStakedByVoterOnPrice[votingRound][price][
            account
        ];
        _transfer(address(this), account, tokensToClaim);

        tokensStakedByVoterOnPrice[votingRound][price][
            account
        ] = 0;

        uint256 tip = voterTipByPrice[votingRound][price][account];
        if (tip > 0) {
            (bool sent, ) = msg.sender.call{value: tip}("");
            if (!sent) revert ETHTransferFailed();
            voterTipByPrice[votingRound][price][account] = 0;
        }

        emit Claimed(msg.sender, account, tokensToClaim, tip);
    }
}
