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
        uint8 earlyWithdrawPenaltyPercentForMaxLockupPeriod = 10;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 initialSupply = 100_000 * 10 ** uint256(decimals);
        vm.startBroadcast(deployerPrivateKey);

        JudgeToken judgeToken = new JudgeToken(initialSupply);
        RewardsManager rewardsManager = new RewardsManager(address(judgeToken));
        JudgeStaking judgeStaking = new JudgeStaking(address(judgeToken), earlyWithdrawPenaltyPercentForMaxLockupPeriod);
        JudgeTreasury judgeTreasury = new JudgeTreasury(address(judgeToken), address(rewardsManager), address(judgeStaking));

        bytes32 minterRole = judgeToken.MINTER_ROLE();
        bytes32 rewardsManagerPreciseBalanceUpdater = rewardsManager.REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
        bytes32 rewardsPerBlockCalculator = judgeStaking.REWARDS_PER_BLOCK_CALCULATOR();
        bytes32 rewardsDistributor = rewardsManager.REWARDS_DISTRIBUTOR_ROLE();
        bytes32 treasuryPreciseBalanceUpdater = judgeTreasury.TREASURY_PRECISE_BALANCE_UPDATER();

        rewardsManager.setKeyParameter(address(judgeTreasury));
        judgeStaking.setKeyParameters(address(rewardsManager), address(judgeTreasury));

        judgeToken.grantRole(minterRole, address(judgeTreasury));

        rewardsManager.grantRole(rewardsManagerPreciseBalanceUpdater, address(judgeTreasury));
        judgeStaking.grantRole(rewardsPerBlockCalculator, address(judgeTreasury));
        rewardsManager.grantRole(rewardsDistributor, address(judgeStaking));
        judgeTreasury.grantRole(treasuryPreciseBalanceUpdater, address(judgeStaking));
        judgeTreasury.grantRole(treasuryPreciseBalanceUpdater, address(rewardsManager));

        vm.stopBroadcast();
    }
}