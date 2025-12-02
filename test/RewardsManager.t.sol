// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeTreasury.sol";
import "../src/JudgeStaking.sol";
import "../src/SampleErc20.sol";

contract RewardsManagerTest is Test {
    JudgeToken public judgeToken;
    RewardsManager public rewardsManager;
    JudgeTreasury public judgeTreasury;
    JudgeStaking public judgeStaking;
    SampleErc20 public sampleErc20;

    address public owner;
    address public zeroAddress;
    address public user1;
    address public user2;
    address public user3;
    uint8 private decimals = 18;
    uint256 public initialSupply = 100_000 * 10 ** uint256(decimals);
    uint8 public earlyWithdrawalPercent = 10;

    error InvalidAddress();
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error CannotInputThisContractAddress();
    error ValueHigherThanThreshold();
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientContractBalance();
    error JudgeTokenRecoveryNotAllowed();

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        zeroAddress = address(0);

        judgeToken = new JudgeToken(initialSupply);
        rewardsManager = new RewardsManager(address(judgeToken));
        judgeStaking = new JudgeStaking(
            address(judgeToken),
            earlyWithdrawalPercent
        );
        judgeTreasury = new JudgeTreasury(
            address(judgeToken),
            address(rewardsManager),
            address(judgeStaking)
        );
        bytes32 rewardsManagerAdmin = rewardsManager
            .REWARDS_MANAGER_ADMIN_ROLE();
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        rewardsManager.setJudgeTreasuryAddress(address(judgeTreasury));
        bytes32 allocationMinterRole = judgeToken.ALLOCATION_MINTER_ROLE();
        bytes32 rewardsManagerPrecisebalanceUpdater = rewardsManager
            .REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        bytes32 rewardsPerBlockAdmin = judgeStaking
            .REWARDS_PER_BLOCK_CALCULATOR();
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        bytes32 rewardsDistributor = rewardsManager.REWARDS_DISTRIBUTOR_ROLE();
        rewardsManager.grantRole(
            rewardsManagerPrecisebalanceUpdater,
            address(judgeTreasury)
        );
        judgeToken.grantRole(allocationMinterRole, address(judgeTreasury));
        judgeTreasury.grantRole(treasuryAdmin, owner);
        judgeStaking.grantRole(stakingAdmin, owner);
        judgeStaking.grantRole(rewardsPerBlockAdmin, address(judgeTreasury));
        rewardsManager.grantRole(rewardsDistributor, address(judgeStaking));
        judgeStaking.setRewardsManagerAddress(address(rewardsManager));
        judgeStaking.setJudgeTreasuryAddress(address(judgeTreasury));

        sampleErc20 = new SampleErc20();
    }

    function testDeployerIsOwner() public {
        bytes32 defaultAdmin = rewardsManager.DEFAULT_ADMIN_ROLE();
        assertTrue(rewardsManager.hasRole(defaultAdmin, owner));
    }

    function testSetKeyParameter() public {
        bytes32 defaultAdmin = rewardsManager.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                defaultAdmin
            )
        );
        vm.prank(user1);
        rewardsManager.setJudgeTreasuryAddress(address(judgeTreasury));

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.setJudgeTreasuryAddress(zeroAddress);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.setJudgeTreasuryAddress(address(rewardsManager));

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.setJudgeTreasuryAddress(user1);

        // For testing purpose we are using judgeToken address as another contract placeholder for new treasury contract
        rewardsManager.setJudgeTreasuryAddress(address(judgeToken));
        assertEq(address(rewardsManager.judgeTreasury()), address(judgeToken));
    }

    function testUpdateFeePercent() public {
        bytes32 rewardsManagerAdminRole = rewardsManager
            .REWARDS_MANAGER_ADMIN_ROLE();
        uint8 newFeePercent = 20;
        uint8 feePercentHigherThanThreshold = 31;
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                rewardsManagerAdminRole
            )
        );
        vm.prank(user1);
        rewardsManager.updateFeePercent(newFeePercent);

        vm.expectRevert(ValueHigherThanThreshold.selector);
        rewardsManager.updateFeePercent(feePercentHigherThanThreshold);

        rewardsManager.updateFeePercent(newFeePercent);
        assertEq(rewardsManager.feePercent(), newFeePercent);
    }

    function testUpdateJudgeRecoveryMinimumThreshold() public {
        bytes32 rewardsManagerAdminRole = rewardsManager
            .REWARDS_MANAGER_ADMIN_ROLE();
        uint256 newJudgeRecoveryMinimumThreshold = 10_000 *
            10 ** uint256(decimals);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                rewardsManagerAdminRole
            )
        );
        vm.prank(user1);
        rewardsManager.updateJudgeRecoveryMinimumThreshold(
            newJudgeRecoveryMinimumThreshold
        );

        rewardsManager.updateJudgeRecoveryMinimumThreshold(
            newJudgeRecoveryMinimumThreshold
        );
        assertEq(
            rewardsManager.judgeRecoveryMinimumThreshold(),
            newJudgeRecoveryMinimumThreshold
        );
    }

    function testEmergencyWithdrawal() public {
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint32 index = 1;
        judgeTreasury.setNewQuarterlyRewards(rewards);
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 fundManagerAdminRewardsManager = rewardsManager
            .FUND_MANAGER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user2,
                fundManagerAdminRewardsManager
            )
        );
        vm.prank(user2);
        rewardsManager.emergencyWithdrawal(user1);
        rewardsManager.grantRole(fundManagerAdminRewardsManager, owner);

        vm.expectRevert(InsufficientContractBalance.selector);
        rewardsManager.emergencyWithdrawal(user1);

        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(index);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.emergencyWithdrawal(zeroAddress);
        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.emergencyWithdrawal(address(rewardsManager));
        rewardsManager.emergencyWithdrawal(user1);
        assertEq(
            judgeToken.balanceOf(user1),
            1_000_000 * 10 ** uint256(decimals)
        );

        assertEq(rewardsManager.rewardsManagerBaseRewardBalance(), 0);
        assertEq(rewardsManager.rewardsManagerBonusBalance(), 0);
    }

    function testSendBonus() public {}

    function testSendRewards() public {}

    function testTotalRewardsPaid() public {
        uint256 rewards = 972_000 * 10 ** uint256(decimals);
        uint256 bonus = 200_000 * 10 ** uint256(decimals);
        uint256 bonusDuration = 100_000;
        uint256 startBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, 270_000 * 10 ** uint256(decimals));
        vm.startPrank(user1);
        judgeToken.transfer(user2, 20_0000 * 10 ** uint256(decimals));
        judgeToken.approve(
            address(judgeStaking),
            50_000 * 10 ** uint256(decimals)
        );
        judgeStaking.deposit(50_000 * 10 ** uint256(decimals), 180);
        vm.stopPrank();

        vm.startPrank(user2);
        judgeToken.approve(
            address(judgeStaking),
            20_000 * 10 ** uint256(decimals)
        );
        judgeStaking.deposit(20_000 * 10 ** uint256(decimals), 180);
        vm.stopPrank();

        judgeTreasury.setNewQuarterlyRewards(rewards);
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(1);
        vm.roll(startBlock + 324_000);

        vm.prank(user1);
        judgeStaking.claimRewards(0);

        (uint256 base, uint256 bonusClaimed, uint256 total) = rewardsManager
            .totalRewardsPaid();

        assertApproxEqRel(base, 347142e18, 9e17);
        assertEq(bonusClaimed, 0);
        assertApproxEqRel(total, 347142e18, 9e17);

        vm.startPrank(user1);
        judgeToken.approve(
            address(judgeTreasury),
            200_000 * 10 ** uint256(decimals)
        );
        judgeTreasury.addBonusToQuarterReward(bonus, bonusDuration);

        vm.roll(startBlock + 374_000);
        judgeStaking.claimRewards(0);
        vm.stopPrank();
        vm.prank(user2);
        judgeStaking.claimRewards(0);

        (uint256 newBase, uint256 newBonus, uint256 newTotal) = rewardsManager
            .totalRewardsPaid();
        assertApproxEqRel(newBase, 560_999e18, 1e18);
        assertApproxEqRel(newBonus, 100_000e18, 1e6);
        assertApproxEqRel(newTotal, 660_999e18, 1e18);
    }

    function testAvailableRewards() public {}

    function testCalculateMisplacedJudge() public {
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint32 index = 1;
        judgeTreasury.setNewQuarterlyRewards(rewards);
        uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
        judgeToken.generalMint(user3, misplacedAmount);
        vm.prank(user3);
        judgeToken.transfer(address(rewardsManager), misplacedAmount);
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(index);
        assertEq(rewardsManager.calculateMisplacedJudge(), misplacedAmount);
    }

    function testRecoverMisplacedJudgeToken() public {
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 rewardsManagerAdmin = rewardsManager
            .REWARDS_MANAGER_ADMIN_ROLE();
        bytes32 tokenRecoveryAdmin = rewardsManager.TOKEN_RECOVERY_ROLE();
        bytes32 treasuryPreciseBalanceUpdater = judgeTreasury
            .TREASURY_PRECISE_BALANCE_UPDATER();
        judgeTreasury.grantRole(
            treasuryPreciseBalanceUpdater,
            address(rewardsManager)
        );
        uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
        uint256 invalidAmount;
        uint8 feePercent = 10;
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        rewardsManager.updateFeePercent(feePercent);
        judgeToken.generalMint(user3, misplacedAmount);
        vm.prank(user3);
        judgeToken.transfer(address(rewardsManager), misplacedAmount);
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint32 index = 1;
        judgeTreasury.setNewQuarterlyRewards(rewards);
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(index);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                tokenRecoveryAdmin
            )
        );
        rewardsManager.recoverMisplacedJudge(user3, misplacedAmount);
        rewardsManager.grantRole(tokenRecoveryAdmin, owner);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.recoverMisplacedJudge(zeroAddress, misplacedAmount);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.recoverMisplacedJudge(
            address(rewardsManager),
            misplacedAmount
        );

        vm.expectRevert(InvalidAmount.selector);
        rewardsManager.recoverMisplacedJudge(user3, invalidAmount);

        rewardsManager.recoverMisplacedJudge(user3, misplacedAmount);
        assertEq(judgeToken.balanceOf(user3), (misplacedAmount * 9) / 10);
        assertEq(
            judgeToken.balanceOf(address(judgeTreasury)),
            misplacedAmount / 10
        );
    }

    function testRecoverErc20() public {
        bytes32 tokenRecoveryAdmin = rewardsManager.TOKEN_RECOVERY_ROLE();
        bytes32 rewardsManagerAdmin = rewardsManager
            .REWARDS_MANAGER_ADMIN_ROLE();
        address strandedTokenAddr = address(sampleErc20);
        uint256 misplacedAmount = 1000 ether;
        uint256 tooHighAmount = 1001 ether;
        uint256 invalidAmount;
        uint8 feePercent = 10;
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        rewardsManager.updateFeePercent(feePercent);
        sampleErc20.mint(user1, misplacedAmount);

        vm.prank(user1);

        sampleErc20.transfer(address(rewardsManager), misplacedAmount);
        assertEq(
            sampleErc20.balanceOf(address(rewardsManager)),
            misplacedAmount
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                tokenRecoveryAdmin
            )
        );
        rewardsManager.recoverErc20(strandedTokenAddr, user1, misplacedAmount);

        rewardsManager.grantRole(tokenRecoveryAdmin, owner);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.recoverErc20(
            strandedTokenAddr,
            address(rewardsManager),
            misplacedAmount
        );

        vm.expectRevert(InvalidAmount.selector);
        rewardsManager.recoverErc20(strandedTokenAddr, user1, invalidAmount);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.recoverErc20(zeroAddress, user1, misplacedAmount);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.recoverErc20(
            strandedTokenAddr,
            zeroAddress,
            misplacedAmount
        );

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.recoverErc20(zeroAddress, zeroAddress, misplacedAmount);

        vm.expectRevert(InsufficientContractBalance.selector);
        rewardsManager.recoverErc20(strandedTokenAddr, user1, tooHighAmount);

        vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
        rewardsManager.recoverErc20(
            address(judgeToken),
            user1,
            misplacedAmount
        );

        rewardsManager.recoverErc20(strandedTokenAddr, user1, misplacedAmount);
        assertEq(sampleErc20.balanceOf(user1), (misplacedAmount * 9) / 10);
        assertEq(
            rewardsManager.feeBalanceOfStrandedToken(strandedTokenAddr),
            misplacedAmount / 10
        );
    }

    function testTransferFeesFromOtherTokensOutOfRewardsManager() public {
        bytes32 tokenRecoveryAdmin = rewardsManager.TOKEN_RECOVERY_ROLE();
        bytes32 rewardsManagerAdmin = rewardsManager
            .REWARDS_MANAGER_ADMIN_ROLE();
        bytes32 fundManagerRole = rewardsManager.FUND_MANAGER_ROLE();
        address strandedTokenAddr = address(sampleErc20);
        uint256 misplacedAmount = 1000 ether;
        uint256 invalidAmount;
        uint8 feePercent = 10;
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        rewardsManager.updateFeePercent(feePercent);
        sampleErc20.mint(user1, misplacedAmount);

        vm.prank(user1);
        sampleErc20.transfer(address(rewardsManager), misplacedAmount);

        rewardsManager.grantRole(tokenRecoveryAdmin, owner);
        rewardsManager.recoverErc20(strandedTokenAddr, user1, misplacedAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                fundManagerRole
            )
        );
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr,
            user2,
            misplacedAmount / 10
        );

        rewardsManager.grantRole(fundManagerRole, owner);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr,
            address(rewardsManager),
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAmount.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr,
            user2,
            invalidAmount
        );

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            zeroAddress,
            user2,
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr,
            zeroAddress,
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            zeroAddress,
            zeroAddress,
            misplacedAmount / 10
        );

        vm.expectRevert(InsufficientBalance.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr,
            user2,
            (misplacedAmount * 2) / 10
        );

        vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            address(judgeToken),
            user2,
            misplacedAmount / 10
        );

        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr,
            user2,
            misplacedAmount / 10
        );
        assertEq(sampleErc20.balanceOf(user2), misplacedAmount / 10);
        assertEq(
            rewardsManager.feeBalanceOfStrandedToken(strandedTokenAddr),
            0
        );
    }
}
