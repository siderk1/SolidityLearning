// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InsecureVoting.sol";


contract InsecureCoolToken is InsecureVoting {
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
