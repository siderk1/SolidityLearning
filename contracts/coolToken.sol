// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CoolToken is IERC20, Ownable, ReentrancyGuard {
    uint256 public timeToVote;
    bool public isVotingInProgress;
    uint256 public currentPrice;
    uint256 private _feeBps;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_BPS = 1000;
    uint256 public feeTokensAccrued;
    uint256 public lastFeeBurn;

    uint256 private _totalSupply;
    string private _name = "CoolToken";
    string private _symbol = "COOL";
    uint8 private _decimals = 18;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event FeeUpdated(uint256 currentFeeBps, uint256 newFeeBps);
    event Buy(address buyer, uint256 ethIn, uint256 tokensOut, uint256 feeTokens, uint256 price);
    event Sell(address seller, uint256 tokensIn, uint256 ethOut, uint256 feeTokens, uint256 price);
    event FeeBurned(uint256 amount, uint256 timestamp);


    modifier notDuringVotingIfVoted () {
        _;
    }
    constructor (
        string memory name_,
        string memory symbol_,
        uint256 timeToVote_,
        uint256 currentPrice_,
        uint256 feeBps_
    ) 
        Ownable(msg.sender) 
    {
        _name = name_;
        _symbol = symbol_;
        timeToVote = timeToVote_;
        currentPrice = currentPrice_;
        _feeBps = feeBps_;
        lastFeeBurn = block.timestamp;

    }

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

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override notDuringVotingIfVoted returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        uint256 current = _allowances[msg.sender][spender];
        require(amount == 0 || current == 0, "Should be set to 0 first");

        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override notDuringVotingIfVoted returns (bool) {
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");

        _transfer(from, to, amount);
        unchecked {
            _allowances[from][msg.sender] -= amount;
        }

        return true;
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "Max fee is 10%");
        emit FeeUpdated(_feeBps, newFeeBps);
        _feeBps = newFeeBps;
    }

    function _moveFunds(address from, address to, uint256 amount) internal virtual {
        if (from == address(0)){
            _totalSupply += amount;
        } else {
            require(_balances[from] >= amount, "Insufficient balance");
            unchecked {
                _balances[from] -= amount;
            }
        }

        if (to == address(0)){
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
        require(from != address(0) && to != address(0));
        _moveFunds(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        _moveFunds(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
       _moveFunds(account, address(0), amount);
    }

    function buy() external payable notDuringVotingIfVoted {
        uint256 tokensGross = msg.value * (10 ** _decimals) / currentPrice;
        uint256 fee = tokensGross * _feeBps / BPS_DENOMINATOR;
        uint256 tokensNet = tokensGross - fee;
        _mint(address(this), fee);
        feeTokensAccrued += fee;
        _mint(msg.sender, tokensNet);

        emit Buy(msg.sender, msg.value, tokensNet, fee, currentPrice);
    }

    function sell(uint256 tokensAmount) external nonReentrant notDuringVotingIfVoted {
        require(_balances[msg.sender] >= tokensAmount, "Insufficient balance");
        require(currentPrice > 0, "Price not set");

        uint256 fee = tokensAmount * _feeBps / BPS_DENOMINATOR;
        uint256 tokensNet = tokensAmount - fee;

        uint256 ethOut = tokensNet * currentPrice / (10 ** _decimals);
        require(address(this).balance >= ethOut);
        
        _transfer(msg.sender, address(this), fee);
        feeTokensAccrued += fee;
        _burn(msg.sender, tokensNet);

        (bool sent, ) = msg.sender.call{value: ethOut}("");
        require(sent, "ETH transfer failed");

        emit Sell(msg.sender, tokensAmount, ethOut, fee, currentPrice);
    }

    function burnFees() external {
        require(block.timestamp >= lastFeeBurn + 7 days, "Too early");

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
}