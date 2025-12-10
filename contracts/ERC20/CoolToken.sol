// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Voting.sol";

/// @title CoolToken
/// @notice Upgradeable ERC20 token with trading and on-chain price discovery voting.
/// @dev Composes ERC20Base, Tradeable and Voting. Uses initializer pattern (UUPS). Constructor disables initializers.
contract CoolToken is Voting {
    /// @dev Disable initializers for implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the token and modules (callable once via proxy).
    /// @dev Must be called on the proxy. Initializes ERC20Base, Tradeable and Voting modules.
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @param votingTimeLength_ Voting round length.
    /// @param currentPrice_ Initial price.
    /// @param feeBps_ Initial fee in basis points.
    /// @param initialOwner Owner address for upgradeability and admin actions.
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 votingTimeLength_,
        uint256 currentPrice_,
        uint256 feeBps_,
        address initialOwner
    ) public initializer {
        __ERC20Base_init(name_, symbol_, initialOwner);
        __Tradeable_init(currentPrice_, feeBps_);
        __Voting_init(votingTimeLength_);
    }

    /// @notice Authorize contract upgrade (UUPS).
    /// @dev Only owner may authorize an implementation upgrade.
    /// @param newImplementation Address of the new implementation.
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @dev Storage gap for future variable additions (upgrade safety).
    uint256[50] private __gap;
}
