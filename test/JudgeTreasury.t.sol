// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeTreasury.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeStaking.sol";
import "../src/SampleErc20.sol";

contract JudgeTreasuryTest is Test {
    JudgeToken public judgeToken;
    JudgeTreasury public judgeTreasury;
    RewardsManager public rewardsManager;
    JudgeStaking public judgeStaking;
    SampleErc20 public sampleErc20;
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public zeroAddress;
    uint8 private decimals = 18;
    uint256 public initialSupply = 100_000 * 10 ** uint256(decimals);
    uint8 public earlyWithdrawalPercentForMaxLockUp = 10;

    error EOANotAllowed();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidIndex();
    error InsufficientBalance();
    error CannotInputThisContractAddress();
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error ExceedsRemainingAllocation();
    error AmountExceedsMintableUnallocatedJudge();
    error NotUpToThreshold();
    error DurationTooLow();
    error DurationBeyondQuarterEnd();
    error BonusTooSmall();
    error LastBonusStillRunning();
    error JudgeTokenRecoveryNotAllowed();
    error InsufficientContractBalance();
    error ValueHigherThanThreshold();
    error RewardsInputedOutOfDefinedRange();
    error CurrentQuarterAllocationNotYetFunded();
    error QuarterAllocationAlreadyFunded();

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
            earlyWithdrawalPercentForMaxLockUp
        );
        judgeTreasury = new JudgeTreasury(
            address(judgeToken),
            address(rewardsManager),
            address(judgeStaking)
        );
        bytes32 allocationMinterRole = judgeToken.ALLOCATION_MINTER_ROLE();
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        bytes32 rewardsManagerPreciseBalanceUpdater = rewardsManager
            .REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
        bytes32 rewardsPerBlockCalculator = judgeStaking
            .REWARDS_PER_BLOCK_CALCULATOR();
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        judgeToken.grantRole(allocationMinterRole, address(judgeTreasury));
        judgeTreasury.grantRole(treasuryAdmin, owner);
        judgeStaking.grantRole(stakingAdmin, owner);
        rewardsManager.grantRole(
            rewardsManagerPreciseBalanceUpdater,
            address(judgeTreasury)
        );
        judgeStaking.grantRole(
            rewardsPerBlockCalculator,
            address(judgeTreasury)
        );
        judgeTreasury.updateFeePercent(10);
        judgeTreasury.updateJudgeRecoveryMinimumThreshold(
            200 * 10 ** uint256(decimals)
        );
        judgeStaking.setRewardsManagerAddress(address(rewardsManager));
        judgeStaking.setJudgeTreasuryAddress(address(judgeTreasury));
        rewardsManager.setJudgeTreasuryAddress(address(judgeTreasury));

        sampleErc20 = new SampleErc20();
    }

    function testDecimals() public {
        (, uint8 decimal) = judgeTreasury.settings();
        assertEq(decimal, decimals);
    }

    function testDeployerIsOwner() public {
        bytes32 defaultAdmin = judgeTreasury.DEFAULT_ADMIN_ROLE();
        assertTrue(judgeTreasury.hasRole(defaultAdmin, owner));
    }

    function testSetRewardsManagerAddress() public {
        bytes32 defaultAdmin = judgeTreasury.DEFAULT_ADMIN_ROLE();

        vm.expectRevert(EOANotAllowed.selector);
        judgeTreasury.setRewardsManagerAddress(user1);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.setRewardsManagerAddress(zeroAddress);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.setRewardsManagerAddress(address(judgeTreasury));

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                defaultAdmin
            )
        );
        vm.prank(user1);
        judgeTreasury.setRewardsManagerAddress(address(judgeToken));

        // using judgeToken contract as example for input. Test purposes only
        judgeTreasury.setRewardsManagerAddress(address(judgeToken));
        assertEq(address(judgeTreasury.rewardsManager()), address(judgeToken));
    }

    function testSetJudgeStakingAddress() public {
        bytes32 defaultAdmin = judgeTreasury.DEFAULT_ADMIN_ROLE();

        vm.expectRevert(EOANotAllowed.selector);
        judgeTreasury.setJudgeStakingAddress(user1);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.setJudgeStakingAddress(zeroAddress);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.setJudgeStakingAddress(address(judgeTreasury));

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                defaultAdmin
            )
        );
        vm.prank(user1);
        judgeTreasury.setJudgeStakingAddress(address(judgeToken));

        // using judgeToken contract as example for input. Test purposes only
        judgeTreasury.setJudgeStakingAddress(address(judgeToken));
        assertEq(address(judgeTreasury.judgeStaking()), address(judgeToken));
    }

    function testUpdateMinBonus() public {
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        uint256 invalidMinBonus;
        uint256 newMinBonus = 10_000e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user2,
                treasuryAdmin
            )
        );
        vm.prank(user2);
        judgeTreasury.updateMinBonus(newMinBonus);

        vm.expectRevert(InvalidAmount.selector);
        judgeTreasury.updateMinBonus(invalidMinBonus);

        assertEq(judgeTreasury.minBonus(), 1000e18);

        judgeTreasury.updateMinBonus(newMinBonus);
        assertEq(judgeTreasury.minBonus(), newMinBonus);
    }

    function testSetNewQuarterlyRewards() public {
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        uint256 firstQuarterRewards = 1_000_000 * 10 ** uint256(decimals);
        uint256 secondQuarterRewards = 1_250_000 * 10 ** uint256(decimals);

        uint256 invalidReward;
        uint256 rewardsLowerThanMin = 416_665 * 10 ** uint256(decimals);
        uint256 rewardsHigherThanMax = 1_250_001 * 10 ** uint256(decimals);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user2,
                treasuryAdmin
            )
        );
        vm.prank(user2);
        judgeTreasury.setNewQuarterlyRewards(firstQuarterRewards);

        vm.expectRevert(RewardsInputedOutOfDefinedRange.selector);
        judgeTreasury.setNewQuarterlyRewards(invalidReward);

        vm.expectRevert(RewardsInputedOutOfDefinedRange.selector);
        judgeTreasury.setNewQuarterlyRewards(rewardsLowerThanMin);

        vm.expectRevert(RewardsInputedOutOfDefinedRange.selector);
        judgeTreasury.setNewQuarterlyRewards(rewardsHigherThanMax);

        judgeTreasury.setNewQuarterlyRewards(firstQuarterRewards);

        judgeTreasury.setNewQuarterlyRewards(secondQuarterRewards);

        JudgeTreasury.QuarterInfo memory q1 = judgeTreasury.getQuarterInfo(1);
        JudgeTreasury.QuarterInfo memory q2 = judgeTreasury.getQuarterInfo(2);
        assertEq(q1.baseReward, firstQuarterRewards);
        assertEq(q2.baseReward, secondQuarterRewards);
    }

    function testOverrideNonFundedQuarterBaseReward() public {
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        bytes32 fundManagerAdmin = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 defaultAdmin = judgeTreasury.DEFAULT_ADMIN_ROLE();
        uint256 firstQuarterRewards = 1_000_000 * 10 ** uint256(decimals);
        uint256 secondQuarterRewards = 1_250_000 * 10 ** uint256(decimals);
        uint256 thirdQuarterRewards = 500_000 * 10 ** uint256(decimals);

        uint256 invalidReward;
        uint256 rewardsLowerThanMin = 416_665 * 10 ** uint256(decimals);
        uint256 rewardsHigherThanMax = 1_250_001 * 10 ** uint256(decimals);

        judgeTreasury.grantRole(treasuryAdmin, user2);
        judgeTreasury.grantRole(fundManagerAdmin, owner);

        judgeTreasury.setNewQuarterlyRewards(firstQuarterRewards);
        judgeTreasury.setNewQuarterlyRewards(secondQuarterRewards);
        judgeTreasury.setNewQuarterlyRewards(thirdQuarterRewards);

        JudgeTreasury.QuarterInfo memory q1RewardBefore = judgeTreasury
            .getQuarterInfo(1);
        assertEq(q1RewardBefore.baseReward, firstQuarterRewards);
        JudgeTreasury.QuarterInfo memory q2RewardBefore = judgeTreasury
            .getQuarterInfo(2);
        assertEq(q2RewardBefore.baseReward, secondQuarterRewards);
        JudgeTreasury.QuarterInfo memory q3RewardBefore = judgeTreasury
            .getQuarterInfo(3);
        assertEq(q3RewardBefore.baseReward, thirdQuarterRewards);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user2,
                defaultAdmin
            )
        );
        vm.prank(user2);
        judgeTreasury.overrideNonFundedQuarterBaseReward(
            1,
            firstQuarterRewards
        );

        vm.expectRevert(RewardsInputedOutOfDefinedRange.selector);
        judgeTreasury.overrideNonFundedQuarterBaseReward(1, invalidReward);

        vm.expectRevert(RewardsInputedOutOfDefinedRange.selector);
        judgeTreasury.overrideNonFundedQuarterBaseReward(
            1,
            rewardsLowerThanMin
        );

        vm.expectRevert(RewardsInputedOutOfDefinedRange.selector);
        judgeTreasury.overrideNonFundedQuarterBaseReward(
            1,
            rewardsHigherThanMax
        );

        judgeTreasury.fundRewardsManager(1);

        vm.expectRevert(QuarterAllocationAlreadyFunded.selector);
        judgeTreasury.overrideNonFundedQuarterBaseReward(1, 600_000e18);

        vm.expectRevert(InvalidIndex.selector);
        judgeTreasury.overrideNonFundedQuarterBaseReward(4, 600_000e18);

        vm.expectRevert(InvalidIndex.selector);
        judgeTreasury.overrideNonFundedQuarterBaseReward(5, 600_000e18);

        judgeTreasury.overrideNonFundedQuarterBaseReward(2, 800_000e18);
        judgeTreasury.overrideNonFundedQuarterBaseReward(3, 1_000_000e18);

        JudgeTreasury.QuarterInfo memory q1RewardAfter = judgeTreasury
            .getQuarterInfo(1);
        assertEq(q1RewardAfter.baseReward, firstQuarterRewards);
        JudgeTreasury.QuarterInfo memory q2RewardAfter = judgeTreasury
            .getQuarterInfo(2);
        assertEq(q2RewardAfter.baseReward, 800_000e18);
        JudgeTreasury.QuarterInfo memory q3RewardAfter = judgeTreasury
            .getQuarterInfo(3);
        assertEq(q3RewardAfter.baseReward, 1_000_000e18);
    }

    function testAddBonusToQuarterReward() public {
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        uint256 q1Start = judgeStaking.stakingPoolStartBlock();
        uint256 firstQuarterRewards = 1_000_000 * 10 ** uint256(decimals);
        uint256 secondQuarterRewards = 1_250_000 * 10 ** uint256(decimals);
        uint256 bonus = 20_000 * 10 ** uint256(decimals);
        uint256 bonus2 = 999e18;
        uint256 invalidRewards;
        uint256 q2Start = q1Start + 648_000;

        judgeTreasury.grantRole(fundManager, owner);

        judgeTreasury.setNewQuarterlyRewards(firstQuarterRewards);

        judgeTreasury.setNewQuarterlyRewards(secondQuarterRewards);

        vm.expectRevert(CurrentQuarterAllocationNotYetFunded.selector);
        judgeTreasury.addBonusToQuarterReward(bonus, 100_000);

        judgeToken.approve(
            address(judgeTreasury),
            60_000 * 10 ** uint256(decimals)
        );
        vm.roll(q1Start);
        judgeTreasury.fundRewardsManager(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                fundManager
            )
        );
        vm.prank(user1);
        judgeTreasury.addBonusToQuarterReward(bonus, 100_000);

        vm.expectRevert(DurationTooLow.selector);
        judgeTreasury.addBonusToQuarterReward(bonus, 50_399);

        vm.roll(q1Start + 500_000);

        vm.expectRevert(DurationBeyondQuarterEnd.selector);
        judgeTreasury.addBonusToQuarterReward(bonus, 148_001);
        vm.expectRevert(BonusTooSmall.selector);
        judgeTreasury.addBonusToQuarterReward(bonus2, 100_000);

        judgeTreasury.addBonusToQuarterReward(bonus, 80_000);

        vm.roll(q1Start + 560_000);
        vm.expectRevert(LastBonusStillRunning.selector);
        judgeTreasury.addBonusToQuarterReward(bonus, 60_000);

        assertEq(
            judgeToken.balanceOf(address(rewardsManager)),
            1_020_000 * 10 ** uint256(decimals)
        );
        assertEq(judgeToken.balanceOf(owner), 80_000 * 10 ** uint256(decimals));

        vm.roll(q2Start);
        judgeTreasury.fundRewardsManager(2);
        judgeTreasury.addBonusToQuarterReward(bonus, 100_000);

        assertEq(
            judgeToken.balanceOf(address(rewardsManager)),
            2_290_000 * 10 ** uint256(decimals)
        );
        assertEq(judgeToken.balanceOf(owner), 60_000 * 10 ** uint256(decimals));
    }

    function testUpdateFeePercent() public {
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        uint8 newFeePercent = 15;
        uint8 incorrectFeePercent = 31;
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user3,
                treasuryAdmin
            )
        );
        vm.prank(user3);
        judgeTreasury.updateFeePercent(newFeePercent);

        vm.expectRevert(ValueHigherThanThreshold.selector);
        judgeTreasury.updateFeePercent(incorrectFeePercent);

        judgeTreasury.updateFeePercent(newFeePercent);
        (uint8 feePercent, ) = judgeTreasury.settings();
        assertEq(feePercent, newFeePercent);
    }

    function testUpdateJudgeRecoveryMinimumThreshold() public {
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        uint256 newJudgeRecoveryMinimumThreshold = 1000 *
            10 ** uint256(decimals);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user2,
                treasuryAdmin
            )
        );
        vm.prank(user2);
        judgeTreasury.updateJudgeRecoveryMinimumThreshold(
            newJudgeRecoveryMinimumThreshold
        );

        judgeTreasury.updateJudgeRecoveryMinimumThreshold(
            newJudgeRecoveryMinimumThreshold
        );
        assertEq(
            judgeTreasury.judgeRecoveryMinimumThreshold(),
            newJudgeRecoveryMinimumThreshold
        );
    }

    function testFundRewardsManager() public {
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint256 maxAllocation = judgeToken.MAX_STAKING_REWARD_ALLOCATION();
        uint256 stakingRewardsFundFromTreasury1 = 49_000_001 *
            10 ** uint256(decimals);
        uint256 stakingRewardsFundFromTreasury2 = 40_000_000 *
            10 ** uint256(decimals);
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        uint32 index = 1;

        judgeTreasury.setNewQuarterlyRewards(rewards);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                fundManager
            )
        );
        judgeTreasury.fundRewardsManager(index);

        judgeTreasury.grantRole(fundManager, owner);

        vm.store(
            address(judgeTreasury),
            bytes32(uint256(5)),
            bytes32(maxAllocation)
        );
        vm.expectRevert(ExceedsRemainingAllocation.selector);
        judgeTreasury.fundRewardsManager(index);

        vm.store(
            address(judgeTreasury),
            bytes32(uint256(5)),
            bytes32(stakingRewardsFundFromTreasury1)
        );
        vm.expectRevert(ExceedsRemainingAllocation.selector);
        judgeTreasury.fundRewardsManager(index);

        vm.store(
            address(judgeTreasury),
            bytes32(uint256(5)),
            bytes32(stakingRewardsFundFromTreasury2)
        );

        vm.expectRevert(InvalidIndex.selector);
        judgeTreasury.fundRewardsManager(2);

        judgeTreasury.fundRewardsManager(index);
        assertEq(
            judgeTreasury.totalBaseRewardsFunded(),
            41_000_000 * 10 ** uint256(decimals)
        );

        vm.expectRevert(QuarterAllocationAlreadyFunded.selector);
        judgeTreasury.fundRewardsManager(index);
    }

    function testMintToTreasuryReserve() public {
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        uint256 amount = 2_000_000 * 10 * 10 ** uint256(decimals);
        uint256 invalidAmount;
        uint256 assumedMintable = 1_000_000 * 10 * 10 ** uint256(decimals);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                fundManager
            )
        );
        judgeTreasury.mintToTreasuryReserve(amount);

        judgeTreasury.grantRole(fundManager, owner);

        vm.expectRevert(InvalidAmount.selector);
        judgeTreasury.mintToTreasuryReserve(invalidAmount);

        judgeToken.grantRole(minterRole, address(judgeTreasury));
        judgeTreasury.mintToTreasuryReserve(amount);
        assertEq(judgeToken.balanceOf(address(judgeTreasury)), amount);
        assertEq(judgeTreasury.treasuryPreciseBalance(), amount);

        vm.store(
            address(judgeToken),
            bytes32(uint256(12)),
            bytes32(assumedMintable)
        );
        vm.expectRevert(AmountExceedsMintableUnallocatedJudge.selector);
        judgeTreasury.mintToTreasuryReserve(amount);
    }

    function testFundTeamDevelopment() public {
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        uint256 amount = 2_000_000 * 10 ** uint256(decimals);
        uint256 invalidAmount;
        uint256 maxAllocation = judgeToken.MAX_TEAM_ALLOCATION();
        uint256 assumedTeamFundReceived = 49_000_000 * 10 ** uint256(decimals);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                fundManager
            )
        );
        judgeTreasury.fundTeamDevelopment(owner, amount);

        judgeTreasury.grantRole(fundManager, owner);
        vm.expectRevert(InvalidAmount.selector);
        judgeTreasury.fundTeamDevelopment(owner, invalidAmount);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.fundTeamDevelopment(zeroAddress, amount);

        judgeTreasury.fundTeamDevelopment(owner, amount);
        assertEq(judgeToken.balanceOf(owner), amount + initialSupply);

        vm.store(
            address(judgeTreasury),
            bytes32(uint256(6)),
            bytes32(maxAllocation)
        );
        vm.expectRevert(ExceedsRemainingAllocation.selector);
        judgeTreasury.fundTeamDevelopment(owner, amount);

        vm.store(
            address(judgeTreasury),
            bytes32(uint256(6)),
            bytes32(assumedTeamFundReceived)
        );
        vm.expectRevert(ExceedsRemainingAllocation.selector);
        judgeTreasury.fundTeamDevelopment(owner, amount);
    }

    function testTransferFromTreasury() public {
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        uint256 amount = 2_000_000 * 10 ** uint256(decimals);
        uint256 amountToTransfer = 1_000_000 * 10 ** uint256(decimals);
        uint256 amountHigherThanTreasuryBalance = 2_000_001 *
            10 ** uint256(decimals);
        uint256 invalidAmount;

        judgeTreasury.grantRole(fundManager, owner);
        judgeToken.grantRole(minterRole, address(judgeTreasury));
        judgeTreasury.mintToTreasuryReserve(amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                fundManager
            )
        );
        vm.prank(user1);
        judgeTreasury.transferFromTreasury(owner, amountToTransfer);

        vm.expectRevert(InvalidAmount.selector);
        judgeTreasury.transferFromTreasury(user1, invalidAmount);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.transferFromTreasury(zeroAddress, amountToTransfer);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.transferFromTreasury(
            address(judgeTreasury),
            amountToTransfer
        );

        vm.expectRevert(InsufficientBalance.selector);
        judgeTreasury.transferFromTreasury(
            user1,
            amountHigherThanTreasuryBalance
        );

        judgeTreasury.transferFromTreasury(user1, amountToTransfer);
        assertEq(judgeToken.balanceOf(user1), amountToTransfer);
        assertEq(
            judgeTreasury.treasuryPreciseBalance(),
            amount - amountToTransfer
        );
    }

    function testRemainingStakingAllocation() public {
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint256 startBlock = judgeStaking.stakingPoolStartBlock();
        vm.roll(startBlock);
        judgeTreasury.setNewQuarterlyRewards(rewards);
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(1);

        assertEq(judgeTreasury.remainingStakingAllocation(), 49_000_000e18);
        assertEq(judgeToken.balanceOf(address(rewardsManager)), 1_000_000e18);
    }

    function testRemainingTeamAllocation() public {
        uint256 teamFundAmount = 20_000_000 * 10 ** uint256(decimals);
        uint256 startBlock = judgeStaking.stakingPoolStartBlock();
        vm.roll(startBlock);
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundTeamDevelopment(user1, teamFundAmount);

        assertEq(judgeTreasury.remainingTeamAllocation(), 30_000_000e18);
        assertEq(judgeToken.balanceOf(user1), 20_000_000e18);
    }

    function testCurrentFeePercent() public {
        assertEq(judgeTreasury.currentFeePercent(), 10);
        judgeTreasury.updateFeePercent(0);
        assertEq(judgeTreasury.currentFeePercent(), 0);
    }

    function testGetQuarterInfo() public {
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint256 bonus = 200_000 * 10 ** uint256(decimals);
        uint256 bonusDuration = 100_000;
        uint256 startBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, 270_000 * 10 ** uint256(decimals));
        vm.roll(startBlock);
        judgeTreasury.setNewQuarterlyRewards(rewards);
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(1);
        vm.roll(startBlock + 324_000);

        judgeTreasury.grantRole(fundManagerAdminTreasury, user1);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeTreasury), bonus);
        judgeTreasury.addBonusToQuarterReward(bonus, bonusDuration);

        vm.expectRevert(InvalidIndex.selector);
        judgeTreasury.getQuarterInfo(2);

        JudgeTreasury.QuarterInfo memory q = judgeTreasury.getQuarterInfo(1);
        assertEq(q.baseReward, 1_000_000e18);
        assertEq(q.currentBonus, 200_000e18);
        assertEq(q.currentBonusEndBlock, startBlock + 424_000);
        assertTrue(q.isFunded);
    }

    function testCalculateMisplacedJudge() public {
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        uint256 amount = 2_000_000 * 10 ** uint256(decimals);
        uint256 amountToTransfer = 500_000 * 10 ** uint256(decimals);
        uint256 misplacedAmount = 200_000 * 10 ** uint256(decimals);

        judgeTreasury.grantRole(fundManager, owner);
        judgeToken.grantRole(minterRole, address(judgeTreasury));
        judgeTreasury.mintToTreasuryReserve(amount);
        judgeTreasury.transferFromTreasury(user2, amountToTransfer);
        assertEq(judgeTreasury.calculateMisplacedJudge(), 0);

        vm.prank(user2);
        judgeToken.transfer(address(judgeTreasury), misplacedAmount);
        assertEq(judgeTreasury.calculateMisplacedJudge(), misplacedAmount);
    }

    function testRecoverMisplacedJudge() public {
        bytes32 tokenRecoveryAdmin = judgeTreasury.TOKEN_RECOVERY_ROLE();
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        uint256 amount = 2_000_000 * 10 ** uint256(decimals);
        uint256 amountToTransfer = 500_000 * 10 ** uint256(decimals);
        uint256 misplacedAmount = 200_000 * 10 ** uint256(decimals);
        uint256 invalidAmount = 300_000 * 10 ** uint256(decimals);
        uint256 amountLessThanThreshold = 20 * 10 * uint256(decimals);

        judgeTreasury.grantRole(fundManager, owner);
        judgeToken.grantRole(minterRole, address(judgeTreasury));
        judgeTreasury.mintToTreasuryReserve(amount);
        judgeTreasury.transferFromTreasury(user2, amountToTransfer);

        uint256 totalSupply1 = judgeToken.totalSupply();

        vm.prank(user2);
        judgeToken.transfer(address(judgeTreasury), misplacedAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                tokenRecoveryAdmin
            )
        );
        judgeTreasury.recoverMisplacedJudge(user2, misplacedAmount);

        judgeTreasury.grantRole(tokenRecoveryAdmin, owner);

        vm.expectRevert(InvalidAmount.selector);
        judgeTreasury.recoverMisplacedJudge(user2, 0);

        vm.expectRevert(InvalidAmount.selector);
        judgeTreasury.recoverMisplacedJudge(user2, invalidAmount);

        vm.expectRevert(NotUpToThreshold.selector);
        judgeTreasury.recoverMisplacedJudge(user2, amountLessThanThreshold);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.recoverMisplacedJudge(
            address(judgeTreasury),
            misplacedAmount
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.recoverMisplacedJudge(zeroAddress, misplacedAmount);

        uint256 oldBalanceOfUser2 = judgeToken.balanceOf(user2);
        judgeTreasury.recoverMisplacedJudge(user2, misplacedAmount);
        uint256 totalSupply2 = judgeToken.totalSupply();
        uint256 newBalanceOfUser2 = judgeToken.balanceOf(user2);
        assertEq(
            newBalanceOfUser2 - oldBalanceOfUser2,
            (misplacedAmount * 90) / 100
        );
        assertEq(totalSupply1 - totalSupply2, (misplacedAmount * 10) / 100); //proof that the fee was burned
    }

    function testRecoverErc20() public {
        bytes32 tokenRecoveryAdmin = judgeTreasury.TOKEN_RECOVERY_ROLE();
        address strandedTokenAddr = address(sampleErc20);
        uint256 misplacedAmount = 1000 ether;
        uint256 tooHighAmount = 1001 ether;
        uint256 invalidAmount;
        sampleErc20.mint(user1, misplacedAmount);

        vm.prank(user1);

        sampleErc20.transfer(address(judgeTreasury), misplacedAmount);
        assertEq(
            sampleErc20.balanceOf(address(judgeTreasury)),
            misplacedAmount
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                tokenRecoveryAdmin
            )
        );
        judgeTreasury.recoverErc20(strandedTokenAddr, user1, misplacedAmount);

        judgeTreasury.grantRole(tokenRecoveryAdmin, owner);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        judgeTreasury.recoverErc20(
            strandedTokenAddr,
            address(judgeTreasury),
            misplacedAmount
        );

        vm.expectRevert(InvalidAmount.selector);
        judgeTreasury.recoverErc20(strandedTokenAddr, user1, invalidAmount);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.recoverErc20(zeroAddress, user1, misplacedAmount);

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.recoverErc20(
            strandedTokenAddr,
            zeroAddress,
            misplacedAmount
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.recoverErc20(zeroAddress, zeroAddress, misplacedAmount);

        vm.expectRevert(InsufficientContractBalance.selector);
        judgeTreasury.recoverErc20(strandedTokenAddr, user1, tooHighAmount);

        vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
        judgeTreasury.recoverErc20(address(judgeToken), user1, misplacedAmount);

        judgeTreasury.recoverErc20(strandedTokenAddr, user1, misplacedAmount);
        assertEq(sampleErc20.balanceOf(user1), (misplacedAmount * 9) / 10);
        assertEq(
            judgeTreasury.feeBalanceOfStrandedToken(strandedTokenAddr),
            (misplacedAmount * 1) / 10
        );
    }

    function testTransferFeesFromOtherTokensOutOfTreasury() public {
        bytes32 tokenRecoveryAdmin = judgeTreasury.TOKEN_RECOVERY_ROLE();
        bytes32 fundManagerRole = judgeTreasury.FUND_MANAGER_ROLE();
        address strandedTokenAddr = address(sampleErc20);
        uint256 misplacedAmount = 1000 ether;
        uint256 invalidAmount;
        sampleErc20.mint(user1, misplacedAmount);

        vm.prank(user1);
        sampleErc20.transfer(address(judgeTreasury), misplacedAmount);

        judgeTreasury.grantRole(tokenRecoveryAdmin, owner);
        judgeTreasury.recoverErc20(strandedTokenAddr, user1, misplacedAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                fundManagerRole
            )
        );
        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            strandedTokenAddr,
            user2,
            misplacedAmount / 10
        );

        judgeTreasury.grantRole(fundManagerRole, owner);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            strandedTokenAddr,
            address(judgeTreasury),
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAmount.selector);
        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            strandedTokenAddr,
            user2,
            invalidAmount
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            zeroAddress,
            user2,
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            strandedTokenAddr,
            zeroAddress,
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            zeroAddress,
            zeroAddress,
            misplacedAmount / 10
        );

        assertEq(
            judgeTreasury.feeBalanceOfStrandedToken(strandedTokenAddr),
            misplacedAmount / 10
        );
        uint256 amountHigherThanBalance = 2 *
            (judgeTreasury.feeBalanceOfStrandedToken(strandedTokenAddr));
        vm.expectRevert(InsufficientBalance.selector);
        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            strandedTokenAddr,
            user2,
            amountHigherThanBalance
        );

        uint256 currentBal = judgeTreasury.feeBalanceOfStrandedToken(
            strandedTokenAddr
        );
        vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            address(judgeToken),
            user2,
            currentBal
        );

        judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(
            strandedTokenAddr,
            user2,
            currentBal
        );
        assertEq(sampleErc20.balanceOf(user2), misplacedAmount / 10);
        assertEq(judgeTreasury.feeBalanceOfStrandedToken(strandedTokenAddr), 0);
    }
}
