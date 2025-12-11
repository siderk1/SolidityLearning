// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ERC20Base.sol";

/// @title Tradeable
/// @notice ERC20 extension that enables simple buy/sell by a fixed price and accrues fee tokens for periodic burning.
/// @dev Works with decimals() from ERC20Base. Fees are accrued in-token on the contract balance.
abstract contract Tradeable is ERC20Base {
    error MaxFeeExceeded();
    error ETHTransferFailed();
    error TooEarlyToBurnFees();
    error PriceNotSet();

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_BPS = 1000; // 10%

    /// @notice Current price used for buy/sell (price denominator = token decimals)
    uint256 public currentPrice;
    /// @notice Fee in basis points (bps)
    uint256 private _feeBps;
    /// @notice Tokens accrued as fee and held by the contract
    uint256 public feeTokensAccrued;
    /// @notice Timestamp of last fee burn
    uint256 public lastFeeBurn;

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

    /// @notice Initialize tradeable parameters.
    /// @dev Called from initializer of inheriting contract (upgradeable pattern).
    /// @param currentPrice_ Initial price
    /// @param feeBps_ Initial fee in basis points (must be <= MAX_FEE_BPS)
    function __Tradeable_init(
        uint256 currentPrice_,
        uint256 feeBps_
    ) internal onlyInitializing {
        currentPrice = currentPrice_;
        _feeBps = feeBps_;
        lastFeeBurn = block.timestamp;
    }

    /// @notice Return current fee in basis points.
    /// @return Fee in bps.
    function feeBps() external view returns (uint256) {
        return _feeBps;
    }

    /// @notice Update the fee (only owner).
    /// @dev Emits FeeUpdated. Reverts if newFeeBps > MAX_FEE_BPS.
    /// @param newFeeBps New fee in basis points.
    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert MaxFeeExceeded();
        emit FeeUpdated(_feeBps, newFeeBps);
        _feeBps = newFeeBps;
    }

    /// @notice Buy tokens by sending ETH. Mints tokens to buyer and mints fee tokens to the contract.
    /// @dev Requires currentPrice != 0. Token amounts are scaled by decimals().
    /// Emits Buy.
    function buy() external payable {
        if (currentPrice == 0) revert PriceNotSet();

        uint256 ethIn = msg.value;
        uint256 decimals_ = decimals();
        uint256 tokensGross = (ethIn * (10 ** decimals_)) / currentPrice;
        uint256 fee = (tokensGross * _feeBps) / BPS_DENOMINATOR;
        uint256 tokensNet = tokensGross - fee;

        _mint(address(this), fee);
        feeTokensAccrued += fee;
        _mint(msg.sender, tokensNet);

        emit Buy(msg.sender, ethIn, tokensNet, fee, currentPrice);
    }

    /// @notice Sell tokens for ETH. Transfers fee tokens to contract and burns the net tokens.
    /// @dev Caller must have enough balance. Reverts if contract does not hold enough ETH to pay out.
    /// Uses nonReentrant. Emits Sell.
    /// @param tokensAmount Amount of tokens to sell (including fee portion).
    function sell(uint256 tokensAmount) external nonReentrant {
        if (balanceOf(msg.sender) < tokensAmount) revert InsufficientBalance();
        if (currentPrice == 0) revert PriceNotSet();

        uint256 fee = (tokensAmount * _feeBps) / BPS_DENOMINATOR;
        uint256 tokensNet = tokensAmount - fee;

        uint256 ethOut = (tokensNet * currentPrice) / (10 ** decimals());
        if (address(this).balance < ethOut) revert InsufficientBalance();

        _transfer(msg.sender, address(this), fee);
        feeTokensAccrued += fee;

        _burn(msg.sender, tokensNet);

        (bool sent, ) = msg.sender.call{value: ethOut}("");
        if (!sent) revert ETHTransferFailed();

        emit Sell(msg.sender, tokensAmount, ethOut, fee, currentPrice);
    }

    /// @notice Burn accrued fee tokens held by the contract.
    /// @dev Can be called by anyone but only once per 7 days. Burns up to the contract balance.
    /// Emits FeeBurned.
    function burnFees() external {
        if (block.timestamp < lastFeeBurn + 7 days) revert TooEarlyToBurnFees();

        uint256 toBurn = feeTokensAccrued;
        uint256 bal = balanceOf(address(this));
        if (toBurn > bal) {
            toBurn = bal;
        }

        feeTokensAccrued -= toBurn;
        lastFeeBurn = block.timestamp;

        _burn(address(this), toBurn);
        emit FeeBurned(toBurn, block.timestamp);
    }
}
