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
    error InvalidNodePosition();
    error CannotClaimDuringVoting();

    uint256 public votingTimeLength;
    bool public isVotingInProgress;
    uint256 public votingNumber;
    uint256 public votingStartedTime;

    struct Node {
        uint256 price;
        uint256 votingPower;
        uint256 prevPrice;
        uint256 nextPrice;
        bool exists;
    }

    // mapping[votingNumber] = leadingPrice
    mapping(uint256 => uint256) public leadingPrices;
    // mapping[votingNumber][price] = Node;
    mapping(uint256 => mapping(uint256 => Node)) public pricesNodes;
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

        emit VotingStarted(votingNumber, votingStartedTime);
    }

    function vote(
        uint256 price,
        uint256 tokensAmount,
        uint256 prevPrice,
        uint256 nextPrice
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

        uint256 newPower = pricesNodes[votingNumber][price].votingPower +
            tokensAmount;
        if (!_isValidNodePosition(price, newPower, prevPrice, nextPrice))
            revert InvalidNodePosition();
        _insertNode(price, newPower, prevPrice, nextPrice);

        emit Voted(msg.sender, votingNumber, price, tokensAmount);
    }

    function endVoting() external {
        if (!isVotingInProgress) revert NoActiveVoting();
        if (block.timestamp < votingStartedTime + votingTimeLength)
            revert VotingStillInProgress();

        isVotingInProgress = false;

        uint256 leadingPrice = leadingPrices[votingNumber];
        uint256 winnerPower = pricesNodes[votingNumber][leadingPrice]
            .votingPower;
        if (leadingPrice > 0) {
            currentPrice = leadingPrice;
        }

        emit VotingEnded(votingNumber, leadingPrice, winnerPower);
    }

    function withdraw(
        uint256 price,
        uint256 tokensAmount,
        uint256 prevPrice,
        uint256 nextPrice
    ) external nonReentrant {
        uint256 vn = votingNumber;

        uint256 staked = tokensStakedByVoterOnPrice[vn][price][msg.sender];
        if (staked < tokensAmount) revert NotEnoughTokens();

        Node storage node = pricesNodes[vn][price];
        if (!node.exists) revert InvalidNodePosition();

        if (node.votingPower < tokensAmount) revert InvalidNodePosition();
        uint256 newPower = node.votingPower - tokensAmount;

        if (newPower > 0) {
            if (!_isValidNodePosition(price, newPower, prevPrice, nextPrice))
                revert InvalidNodePosition();
        }
        tokensStakedByVoterOnPrice[vn][price][msg.sender] =
            staked - tokensAmount;

        if (newPower == 0) {
            uint256 oldPrev = node.prevPrice;
            uint256 oldNext = node.nextPrice;

            if (oldPrev != 0) {
                pricesNodes[vn][oldPrev].nextPrice = oldNext;
            } else {
                leadingPrices[vn] = oldNext;
            }

            if (oldNext != 0) {
                pricesNodes[vn][oldNext].prevPrice = oldPrev;
            }

            delete pricesNodes[vn][price];
        } else {
            _insertNode(price, newPower, prevPrice, nextPrice);
        }
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

    function _isValidNodePosition(
        uint256 price,
        uint256 newPricePower,
        uint256 prevPrice,
        uint256 nextPrice
    ) private view returns (bool) {
        uint256 vn = votingNumber;

        if (price == prevPrice || price == nextPrice) return false;

        Node memory prev = pricesNodes[vn][prevPrice];
        Node memory next = pricesNodes[vn][nextPrice];
        uint256 currentLeadingPrice = leadingPrices[vn];

        // prev and next prices must exist
        if (prevPrice != 0 && !prev.exists) return false;
        if (nextPrice != 0 && !next.exists) return false;

        // links check
        if (prevPrice != 0) {
            if (prev.nextPrice != nextPrice) return false;
        } else {
            // prev = 0 => head insertion => next must be current head
            if (nextPrice != currentLeadingPrice) return false;
        }

        if (nextPrice != 0) {
            if (next.prevPrice != prevPrice) return false;
        }

        // prevPower >= newPower >= nextPower
        uint256 prevPower = prevPrice == 0
            ? type(uint256).max
            : prev.votingPower;
        uint256 nextPower = nextPrice == 0 ? 0 : next.votingPower;

        if (prevPower < newPricePower) return false;
        if (nextPower > newPricePower) return false;

        // Tie-break: price desc
        if (prevPrice != 0 && newPricePower == prevPower) {
            if (prevPrice < price) return false;
        }

        if (nextPrice != 0 && newPricePower == nextPower) {
            if (price < nextPrice) return false;
        }

        return true;
    }

    function _insertNode(
        uint256 price,
        uint256 newPricePower,
        uint256 prevPrice,
        uint256 nextPrice
    ) private {
        uint256 vn = votingNumber;

        Node storage node = pricesNodes[vn][price];

        if (node.exists) {
            uint256 oldPrev = node.prevPrice;
            uint256 oldNext = node.nextPrice;

            if (oldPrev != 0) {
                pricesNodes[vn][oldPrev].nextPrice = oldNext;
            } else {
                leadingPrices[vn] = oldNext;
            }

            if (oldNext != 0) {
                pricesNodes[vn][oldNext].prevPrice = oldPrev;
            }
        } else {
            node.exists = true;
            node.price = price;
        }

        node.votingPower = newPricePower;
        node.prevPrice = prevPrice;
        node.nextPrice = nextPrice;

        if (prevPrice != 0) {
            pricesNodes[vn][prevPrice].nextPrice = price;
        } else {
            leadingPrices[vn] = price;
        }

        if (nextPrice != 0) {
            pricesNodes[vn][nextPrice].prevPrice = price;
        }
    }
}
