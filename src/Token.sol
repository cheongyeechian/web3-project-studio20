// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

contract Token is ERC20, Ownable, ERC2771Context {
    uint256 public constant MAX_SUPPLY = 1_000_000 * 10 ** 18; // Fixed supply of 1M S20
    uint256 public constant CLAIM_AMOUNT = 10 * 10 ** 18; // 10 S20 per claim
    uint256 public constant CLAIM_INTERVAL = 24 hours; // Cooldown of 24 hour per claim

    mapping(address => uint256) public lastClaimedTime; // Track last claim per address

    constructor(
        uint256 initialSupply,
        address trustedForwarder
    )
        ERC20("Studio20", "S20")
        Ownable(msg.sender)
        ERC2771Context(trustedForwarder)
    {
        require(
            initialSupply * 10 ** decimals() == MAX_SUPPLY,
            "Initial supply must match max supply"
        );
        _mint(address(this), initialSupply * 10 ** decimals()); // Mint all tokens to contract itself
    }

    function claim() external {
        require(
            balanceOf(address(this)) >= CLAIM_AMOUNT,
            "Not enough tokens in contract"
        );

        // Allow first-time claims (when lastClaimedTime is 0)
        if (lastClaimedTime[_msgSender()] != 0) {
            require(
                block.timestamp >=
                    lastClaimedTime[_msgSender()] + CLAIM_INTERVAL,
                "Claim cooldown active"
            );
        }

        lastClaimedTime[_msgSender()] = block.timestamp;
        _transfer(address(this), _msgSender(), CLAIM_AMOUNT); // Transfer from contract balance
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    // Override functions for ERC2771 meta-transactions
    function _msgSender()
        internal
        view
        override(Context, ERC2771Context)
        returns (address)
    {
        return ERC2771Context._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, ERC2771Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        override(Context, ERC2771Context)
        returns (uint256)
    {
        return ERC2771Context._contextSuffixLength();
    }
}
