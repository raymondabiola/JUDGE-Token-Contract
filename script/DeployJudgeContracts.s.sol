// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "forge-std/Script.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeTreasury.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeStaking.sol";

contract DeployJudgeContracts is Script {
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

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        deployContracts();
        grantNonContractRoles();
        setKeyParameters();
        grantContractKeyRoles();
        updateOtherParameters();

        vm.stopBroadcast();
    }

    function deployContracts() internal {
        judgeToken = new JudgeToken(initialSupply);
        rewardsManager = new RewardsManager(address(judgeToken));
        judgeStaking = new JudgeStaking(
            address(judgeToken),
            earlyWithdrawPenaltyPercentForMaxLockupPeriod
        );
        judgeTreasury = new JudgeTreasury(
            address(judgeToken),
            address(rewardsManager),
            address(judgeStaking)
        );
    }

    function grantNonContractRoles() internal {
        //Treasury non-contract Roles
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        bytes32 fundManagerRoleTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 tokenRecoveryRoleTreasury = judgeTreasury.TOKEN_RECOVERY_ROLE();

        //Staking non-contract Roles
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        bytes32 tokenRecoveryRoleStaking = judgeStaking.TOKEN_RECOVERY_ROLE();

        //RewardsManager non-contract Roles
        bytes32 rewardsManagerAdmin = rewardsManager
            .REWARDS_MANAGER_ADMIN_ROLE();
        bytes32 fundManagerRoleRewardsManager = rewardsManager
            .FUND_MANAGER_ROLE();
        bytes32 tokenRecoveryRoleRewardsmanager = rewardsManager
            .TOKEN_RECOVERY_ROLE();

        //Grant key admin Roles to deployer
        judgeTreasury.grantRole(treasuryAdmin, deployerAddress);
        rewardsManager.grantRole(rewardsManagerAdmin, deployerAddress);
        judgeStaking.grantRole(stakingAdmin, deployerAddress);

        //Grant other roles
        judgeTreasury.grantRole(fundManagerRoleTreasury, deployerAddress);
        judgeTreasury.grantRole(tokenRecoveryRoleTreasury, deployerAddress);
        judgeStaking.grantRole(tokenRecoveryRoleStaking, deployerAddress);
        rewardsManager.grantRole(
            fundManagerRoleRewardsManager,
            deployerAddress
        );
        rewardsManager.grantRole(
            tokenRecoveryRoleRewardsmanager,
            deployerAddress
        );
    }

    function setKeyParameters() internal {
        //Initialize contract address in other deployed contracts.
        rewardsManager.setJudgeTreasuryAddress(address(judgeTreasury));
        judgeStaking.setRewardsManagerAddress(address(rewardsManager));
        judgeStaking.setJudgeTreasuryAddress(address(judgeTreasury));
    }

    function grantContractKeyRoles() internal {
        //Token contract role
        bytes32 allocationMinterRole = judgeToken.ALLOCATION_MINTER_ROLE();
        bytes32 minterRole = judgeToken.MINTER_ROLE();

        //RewardsManager contract Roles
        bytes32 rewardsDistributor = rewardsManager.REWARDS_DISTRIBUTOR_ROLE();
        bytes32 rewardsManagerPreciseBalanceUpdater = rewardsManager
            .REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();

        //Staking contract role
        bytes32 rewardsPerBlockCalculator = judgeStaking
            .REWARDS_PER_BLOCK_CALCULATOR();

        //Treasury contract role
        bytes32 treasuryPreciseBalanceUpdater = judgeTreasury
            .TREASURY_PRECISE_BALANCE_UPDATER();

        //Grant roles to correct contracts
        judgeToken.grantRole(allocationMinterRole, address(judgeTreasury));
        judgeToken.grantRole(minterRole, address(judgeTreasury));

        rewardsManager.grantRole(rewardsDistributor, address(judgeStaking));
        rewardsManager.grantRole(
            rewardsManagerPreciseBalanceUpdater,
            address(judgeTreasury)
        );

        judgeStaking.grantRole(
            rewardsPerBlockCalculator,
            address(judgeTreasury)
        );
        judgeTreasury.grantRole(
            treasuryPreciseBalanceUpdater,
            address(judgeStaking)
        );
        judgeTreasury.grantRole(
            treasuryPreciseBalanceUpdater,
            address(rewardsManager)
        );
    }

    function updateOtherParameters() internal {
        //Treasury
        judgeTreasury.updateFeePercent(feePercent);
        judgeTreasury.updateJudgeRecoveryMinimumThreshold(
            judgeRecoveryMinimumThreshold
        );

        //RewardsManager
        rewardsManager.updateFeePercent(feePercent);
        rewardsManager.updateJudgeRecoveryMinimumThreshold(
            judgeRecoveryMinimumThreshold
        );

        //Staking
        judgeStaking.updateFeePercent(feePercent);
        judgeStaking.updateJudgeRecoveryMinimumThreshold(
            judgeRecoveryMinimumThreshold
        );
    }
}
