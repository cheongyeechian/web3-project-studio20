// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";

contract DeployToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address trustedForwarder = 0x67454E169d613a8e9BA6b06af2D267696EAaAf41; // Correct checksummed address
        uint256 initialSupply = 1_000_000; // 1M S20

        vm.startBroadcast(deployerPrivateKey);
        Token token = new Token(initialSupply, trustedForwarder);
        vm.stopBroadcast();
    }
}
