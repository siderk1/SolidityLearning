// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title ERC20Base (upgradeable)
/// @notice Minimal upgradeable ERC20 backbone used by higher-level modules (Tradeable, Voting, etc.)
/// @dev Upgradeable (UUPS). Initializer must be called once by the implementation proxy.
abstract contract ERC20Base is
    Initializable,
    IERC20,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    error ZeroAddress();
    error InsufficientAllowance();
    error InsufficientBalance();
    error NotEnoughTokens();

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @notice Initialize ERC20 base storage
    /// @dev Must be called from an initializer of the concrete implementation (onlyInitializing).
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @param initialOwner Owner address for OwnableUpgradeable.
    function __ERC20Base_init(
        string memory name_,
        string memory symbol_,
        address initialOwner
    ) internal onlyInitializing {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    /// @notice Token name
    /// @return Token name string
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /// @notice Token symbol
    /// @return Token symbol string
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /// @notice Token decimals (fixed to 18)
    /// @return Number of decimals
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    /// @notice Total token supply
    /// @return Total supply
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /// @notice Balance of `account`
    /// @param account Address to query
    /// @return Token balance
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /// @notice Transfer tokens from caller to `to`
    /// @dev Emits Transfer. Reverts on zero address.
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return True on success
    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Allowance of `spender` for `owner`
    /// @param owner Owner address
    /// @param spender Spender address
    /// @return Remaining allowance
    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @notice Approve `spender` to spend `amount` on caller's behalf
    /// @dev Restricted approve pattern: to change a non-zero allowance to a non-zero value you must first set it to 0.
    ///      Emits Approval.
    /// @param spender Spender address
    /// @param amount Allowance amount
    /// @return True on success
    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        uint256 current = _allowances[msg.sender][spender];
        if (amount != 0 && current != 0) revert NotEnoughTokens();
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from `from` to `to` using allowance
    /// @dev Decreases allowance and emits Transfer. Reverts on insufficient allowance.
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return True on success
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (_allowances[from][msg.sender] < amount)
            revert InsufficientAllowance();

        _transfer(from, to, amount);
        unchecked {
            _allowances[from][msg.sender] -= amount;
        }

        return true;
    }

    /// @notice Authorize UUPS upgrade
    /// @dev Only owner may authorize upgrade. Override to change policy.
    /// @param newImplementation Address of new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

    /// @dev Internal unified state update for mint/transfer/burn.
    ///      Emits Transfer after state mutation.
    /// @param from Source address (address(0) for mint)
    /// @param to Destination address (address(0) for burn)
    /// @param amount Amount to move
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
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

    /// @dev Internal transfer helper. Reverts on zero addresses.
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        _update(from, to, amount);
    }

    /// @dev Internal mint helper. Reverts on zero address.
    function _mint(address account, uint256 amount) internal virtual {
        if (account == address(0)) revert ZeroAddress();
        _update(address(0), account, amount);
    }

    /// @dev Internal burn helper. Reverts on zero address.
    function _burn(address account, uint256 amount) internal virtual {
        if (account == address(0)) revert ZeroAddress();
        _update(account, address(0), amount);
    }
}
