// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Token} from "../src/Token.sol";
import {VotingManager} from "../src/Voting.sol";
import {ShopManager} from "../src/Shop.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Configuration
        address trustedForwarder = 0x447Fd5eC2D383091C22B8549cb231a3bAD6d3fAf;
        uint256 initialSupply = 1_000_000; // 1M S20 tokens

        // Start deployment
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Token contract first
        Token token = new Token(initialSupply, trustedForwarder);
        console.log("Token deployed at:", address(token));

        // Deploy VotingManager contract with token address
        VotingManager votingManager = new VotingManager(address(token));
        console.log("VotingManager deployed at:", address(votingManager));

        // Deploy ShopManager contract with token address
        ShopManager shopManager = new ShopManager(address(token));
        console.log("ShopManager deployed at:", address(shopManager));

        vm.stopBroadcast();

        // Output all contract addresses
        console.log("\nDeployment Summary:");
        console.log("------------------");
        console.log("Token (S20): ", address(token));
        console.log("VotingManager: ", address(votingManager));
        console.log("ShopManager: ", address(shopManager));
    }
}
