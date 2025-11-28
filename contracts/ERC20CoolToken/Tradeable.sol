// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Base.sol";

abstract contract Tradeable is ERC20Base {
    error MaxFeeExceeded();
    error ETHTransferFailed();
    error TooEarlyToBurnFees();
    error PriceNotSet();

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_BPS = 1000; // 10%

    uint256 public currentPrice;
    uint256 private _feeBps;
    uint256 public feeTokensAccrued;
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

    function __Tradeable_init(
        uint256 currentPrice_,
        uint256 feeBps_
    ) internal onlyInitializing {
        currentPrice = currentPrice_;
        _feeBps = feeBps_;
        lastFeeBurn = block.timestamp;
    }

    function feeBps() external view returns (uint256) {
        return _feeBps;
    }
    
    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert MaxFeeExceeded();
        emit FeeUpdated(_feeBps, newFeeBps);
        _feeBps = newFeeBps;
    }

    function buy() external payable {
        if (currentPrice == 0) revert PriceNotSet();
        
        uint256 ethIn = msg.value;
        uint256 decimals_ = decimals();
        uint256 tokensGross = ethIn * (10 ** decimals_) / currentPrice;
        uint256 fee = tokensGross * _feeBps / BPS_DENOMINATOR;
        uint256 tokensNet = tokensGross - fee;

        _mint(address(this), fee);
        feeTokensAccrued += fee;
        _mint(msg.sender, tokensNet);

        emit Buy(msg.sender, ethIn, tokensNet, fee, currentPrice);
    }

    function sell(uint256 tokensAmount)
        external
        nonReentrant
    {
        if (balanceOf(msg.sender) < tokensAmount) revert InsufficientBalance();
        if (currentPrice == 0) revert PriceNotSet();

        uint256 fee = tokensAmount * _feeBps / BPS_DENOMINATOR;
        uint256 tokensNet = tokensAmount - fee;

        uint256 ethOut = tokensNet * currentPrice / (10 ** decimals());
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