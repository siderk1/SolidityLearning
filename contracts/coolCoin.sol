// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CoolCoin is IERC20 {

    uint256 private _totalSupply;
    string private _name = "CoolCoin";
    string private _symbol = "COOL";
    uint8 private _decimals = 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor (string memory name_, string memory symbol_, uint256 initialSupply) {
        _name = name_;
        _symbol = symbol_;
        _mint(msg.sender, initialSupply);
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

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function _transfer(address to, uint256 amount) internal virtual returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");

        unchecked {
            _balances[msg.sender] -= amount;
            _balances[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        return _transfer(to, amount);
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

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");

        _transfer(to, amount);
        unchecked {
            _allowances[from][msg.sender] -= amount;
        }

        return true;
    }

     function _mint(address to, uint256 amount) internal virtual {
        _totalSupply += amount;
        _balances[to] += amount;

        emit Transfer(address(0), to, amount);
    }
}