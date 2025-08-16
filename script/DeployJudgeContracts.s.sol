// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "forge-std/Script.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeTreasury.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeStaking.sol";

contract DeployJudgeContracts is Script{  

        JudgeToken public judgeToken;
        JudgeTreasury public judgeTreasury;
        RewardsManager public rewardsManager;
        JudgeStaking public judgeStaking;

        uint8 decimals = 18;
        uint8 earlyWithdrawPenaltyPercentForMaxLockupPeriod = 10;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        uint256 initialSupply = 100_000 * 10 ** uint256(decimals);
        uint8 feePercent = 10;
        uint256 judgeRecoveryMinimumThreshold = 200;
        uint8 updateEarlyWithdrawPenaltyPercentForMaxLockupPeriod = 10;

        bytes32 minterRole = judgeToken.MINTER_ROLE();
        bytes32 rewardsManagerPreciseBalanceUpdater = rewardsManager.REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
        bytes32 rewardsPerBlockCalculator = judgeStaking.REWARDS_PER_BLOCK_CALCULATOR();
        bytes32 rewardsDistributor = rewardsManager.REWARDS_DISTRIBUTOR_ROLE();
        bytes32 treasuryPreciseBalanceUpdater = judgeTreasury.TREASURY_PRECISE_BALANCE_UPDATER();
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        bytes32 rewardsManagerAdmin = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();

     function run() external {       
        vm.startBroadcast(deployerPrivateKey);

        deployContracts();
        setKeyParameters();
        grantKeyRoles();
        updateOtherParameters();

        vm.stopBroadcast();
    }

    function deployContracts()internal{
       judgeToken = new JudgeToken(initialSupply);
       rewardsManager = new RewardsManager(address(judgeToken));
       judgeStaking = new JudgeStaking(address(judgeToken), earlyWithdrawPenaltyPercentForMaxLockupPeriod);
       judgeTreasury = new JudgeTreasury(address(judgeToken), address(rewardsManager), address(judgeStaking));
    }

    function setKeyParameters()internal{
        rewardsManager.setJudgeTreasuryAddress(address(judgeTreasury));
        judgeStaking.setRewardsManagerAddress(address(rewardsManager));
        judgeStaking.setJudgeTreasuryAddress(address(judgeTreasury));
    }

    function grantKeyRoles()internal{
        judgeToken.grantRole(minterRole, address(judgeTreasury));
        rewardsManager.grantRole(rewardsManagerPreciseBalanceUpdater, address(judgeTreasury));
        judgeStaking.grantRole(rewardsPerBlockCalculator, address(judgeTreasury));
        rewardsManager.grantRole(rewardsDistributor, address(judgeStaking));
        judgeTreasury.grantRole(treasuryPreciseBalanceUpdater, address(judgeStaking));
        judgeTreasury.grantRole(treasuryPreciseBalanceUpdater, address(rewardsManager));

        judgeTreasury.grantRole(treasuryAdmin, deployerAddress);
        rewardsManager.grantRole(rewardsManagerAdmin, deployerAddress);
        judgeStaking.grantRole(stakingAdmin, deployerAddress);
    }

    function updateOtherParameters()internal{
        judgeTreasury.updateFeePercent(feePercent);
        judgeTreasury.updateJudgeRecoveryMinimumThreshold(judgeRecoveryMinimumThreshold);
        rewardsManager.updateFeePercent(feePercent);
        rewardsManager.updateJudgeRecoveryMinimumThreshold(judgeRecoveryMinimumThreshold);
        judgeStaking.updateFeePercent(feePercent);
        judgeStaking.updateJudgeRecoveryMinimumThreshold(judgeRecoveryMinimumThreshold);
        judgeStaking.updateEarlyWithdrawPenaltyPercentForMaxLockupPeriod(updateEarlyWithdrawPenaltyPercentForMaxLockupPeriod);
    }
}