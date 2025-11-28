// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Voting.sol";

contract CoolToken is Voting {
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

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    uint256[50] private __gap;
}
