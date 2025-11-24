// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract CoolToken is
    Initializable,
    IERC20,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // ---- Errors ----
    error VotingAlreadyInProgress();
    error NotEnoughTokensToStartVoting();
    error NoActiveVoting();
    error VotingPeriodOver();
    error PriceMustBeGreaterThanZero();
    error NotEnoughTokens();
    error NotEnoughTokensToVote();
    error ZeroAddress();
    error InsufficientAllowance();
    error InsufficientBalance();
    error MaxFeeExceeded();
    error ETHTransferFailed();
    error TooEarlyToBurnFees();
    error PriceNotSet();
    error VotingStillInProgress();

    uint256 public currentPrice;
    uint256 private _feeBps;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_BPS = 1000; // 10%
    uint256 public feeTokensAccrued;
    uint256 public lastFeeBurn;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Voting state
    uint256 public votingTimeLength;
    bool public isVotingInProgress;
    uint256 public votingNumber;
    uint256 public votingStartedTime;

    uint256 public leadingPrice;
    uint256 public leadingPriceVotes;

    mapping(uint256 => mapping(uint256 => uint256)) public priceVotes;
    mapping(address => uint256) public tokensStaked;
    mapping(address => uint256) public stakingClaimTips;

    event FeeUpdated(uint256 currentFeeBps, uint256 newFeeBps);
    event Buy(
        address buyer,
        uint256 ethIn,
        uint256 tokensOut,
        uint256 feeTokens,
        uint256 price
    );
    event Sell(
        address seller,
        uint256 tokensIn,
        uint256 ethOut,
        uint256 feeTokens,
        uint256 price
    );
    event FeeBurned(uint256 amount, uint256 timestamp);

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

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 votingTimeLength_,
        uint256 currentPrice_,
        uint256 feeBps_,
        address initialOwner
    ) public initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
        votingTimeLength = votingTimeLength_;
        currentPrice = currentPrice_;
        _feeBps = feeBps_;
        lastFeeBurn = block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function feeBps() external view returns (uint256) {
        return _feeBps;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(address to, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        uint256 current = _allowances[msg.sender][spender];
        if (amount != 0 && current != 0) revert NotEnoughTokens();
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        returns (bool)
    {
        if (_allowances[from][msg.sender] < amount) revert InsufficientAllowance();

        _transfer(from, to, amount);
        unchecked {
            _allowances[from][msg.sender] -= amount;
        }

        return true;
    }

    function startVoting() external {
        if (isVotingInProgress) revert VotingAlreadyInProgress();

        uint256 minToStart = (_totalSupply * 10) / BPS_DENOMINATOR;
        if (_balances[msg.sender] <= minToStart) revert NotEnoughTokensToStartVoting();

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

        uint256 balance = _balances[msg.sender];
        if (balance < tokensAmount) revert NotEnoughTokens();

        uint256 minToVote = (_totalSupply * 5) / BPS_DENOMINATOR;
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

    function endVoting() external {
        if (!isVotingInProgress) revert NoActiveVoting();
        if (block.timestamp < votingStartedTime + votingTimeLength) revert VotingStillInProgress();

        isVotingInProgress = false;

        if (leadingPriceVotes > 0) {
            currentPrice = leadingPrice;
        }

        emit VotingEnded(votingNumber, leadingPrice, leadingPriceVotes);
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert MaxFeeExceeded();
        emit FeeUpdated(_feeBps, newFeeBps);
        _feeBps = newFeeBps;
    }

    function _update(address from, address to, uint256 amount) internal virtual {
        if (from == address(0)) {
            _totalSupply += amount;
        } else {
            if (_balances[from] < amount) revert InsufficientBalance();
            unchecked {
                _balances[from] -= amount;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= amount;
            }
        } else {
            unchecked {
                _balances[to] += amount;
            }
        }
        emit Transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        _update(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        _update(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        _update(account, address(0), amount);
    }

    function buy() external payable {
        uint256 tokensGross = msg.value * (10 ** _decimals) / currentPrice;
        uint256 fee = tokensGross * _feeBps / BPS_DENOMINATOR;
        uint256 tokensNet = tokensGross - fee;

        _mint(address(this), fee);
        feeTokensAccrued += fee;
        _mint(msg.sender, tokensNet);

        emit Buy(msg.sender, msg.value, tokensNet, fee, currentPrice);
    }

    function sell(uint256 tokensAmount)
        external
        nonReentrant
    {
        if (_balances[msg.sender] < tokensAmount) revert InsufficientBalance();
        if (currentPrice == 0) revert PriceNotSet();

        uint256 fee = tokensAmount * _feeBps / BPS_DENOMINATOR;
        uint256 tokensNet = tokensAmount - fee;

        uint256 ethOut = tokensNet * currentPrice / (10 ** _decimals);
        if (address(this).balance < ethOut) revert InsufficientBalance();

        _transfer(msg.sender, address(this), fee);
        feeTokensAccrued += fee;
        _burn(msg.sender, tokensNet);

        (bool sent, ) = msg.sender.call{value: ethOut}("");
        if (!sent) revert ETHTransferFailed();

        emit Sell(msg.sender, tokensAmount, ethOut, fee, currentPrice);
    }

    function burnFees() external {
        if (block.timestamp < lastFeeBurn + 7 days) revert TooEarlyToBurnFees();

        uint256 toBurn = feeTokensAccrued;
        uint256 bal = _balances[address(this)];
        if (toBurn > bal) {
            toBurn = bal;
        }

        feeTokensAccrued -= toBurn;
        lastFeeBurn = block.timestamp;

        _burn(address(this), toBurn);
        emit FeeBurned(toBurn, block.timestamp);
    }

    uint256[50] private __gap;
}
