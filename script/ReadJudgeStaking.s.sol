// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "forge-std/Script.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeStaking.sol";

contract ReadJudgeStaking is Script {
    JudgeStaking staking;

    function run() external {
        address stakingAddr = vm.envAddress("STAKING_ADDRESS");

        staking = JudgeStaking(stakingAddr);
        uint16 index = 3;

        vm.startBroadcast();
        uint256 pendingRewards = staking.viewMyPendingRewards(index);
        console.log("Pendng rewards for user at index 3", pendingRewards);
        vm.stopBroadcast();
    }
}
