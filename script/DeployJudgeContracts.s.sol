// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "forge-std/Script.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeTreasury.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeStaking.sol";

contract DeployJudgeContracts is Script{
     function run() external {
        uint8 decimals = 18;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 initialSupply = 100_000 * 10 ** uint256(decimals);
        vm.startBroadcast(deployerPrivateKey);
        JudgeToken judgeToken = new JudgeToken(initialSupply);
        vm.stopBroadcast();
    }
}