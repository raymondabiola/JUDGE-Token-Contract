// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeStaking.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeTreasury.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../src/SampleErc20.sol";

contract JudgeStakingTest is Test {
    JudgeToken public judgeToken;
    JudgeStaking public judgeStaking;
    RewardsManager public rewardsManager;
    JudgeTreasury public judgeTreasury;
    SampleErc20 public sampleErc20;

    address public owner;
    address public zeroAddress;
    address public user1;
    address public user2;
    address public user3;
    uint8 private decimals = 18;
    uint256 public initialSupply = 100_000 * 10 ** uint256(decimals);
    uint8 public earlyWithdrawalPercent = 10;

    event ClaimedReward(address indexed user, uint256 rewards);

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error InvalidAddress();
    error CannotInputThisContractAddress();
    error EOANotAllowed();
    error InvalidAmount();
    error ValueTooHigh();
    error OverPaidRewards();
    error InvalidLockUpPeriod();
    error InvalidIndex();
    error InsufficientContractBalance();
    error JudgeTokenRecoveryNotAllowed();
    error InsufficientBalance();
    error NotYetMatured();
    error AlreadyMatured();
    error AlreadyTriggered();

    struct UserStake {
        uint64 id;
        uint256 amountStaked;
        uint32 lockUpPeriod;
        uint256 lockUpRatio;
        uint256 stakeWeight;
        uint256 depositBlockNumber;
        uint256 rewardDebt;
        uint256 bonusRewardDebt;
        uint256 maturityBlockNumber;
    }

    function setUp() public {
        owner = address(this);
        zeroAddress = address(0);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        console.log("owner address", owner);
        console.log("user1 address", user1);
        console.log("user2 address", user2);
        console.log("user3 address", user3);

        judgeToken = new JudgeToken(initialSupply);
        judgeStaking = new JudgeStaking(
            address(judgeToken),
            earlyWithdrawalPercent
        );
        rewardsManager = new RewardsManager(address(judgeToken));
        judgeTreasury = new JudgeTreasury(
            address(judgeToken),
            address(rewardsManager),
            address(judgeStaking)
        );
        sampleErc20 = new SampleErc20();

        bytes32 allocationMinterRole = judgeToken.ALLOCATION_MINTER_ROLE();
        bytes32 rewardsManagerPreciseBalanceUpdater = rewardsManager
            .REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
        bytes32 rewardsDistributor = rewardsManager.REWARDS_DISTRIBUTOR_ROLE();
        bytes32 treasuryPreciseBalanceUpdater = judgeTreasury
            .TREASURY_PRECISE_BALANCE_UPDATER();
        bytes32 rewardsManagerAdmin = rewardsManager
            .REWARDS_MANAGER_ADMIN_ROLE();
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 tokenRecoveryRole = judgeStaking.TOKEN_RECOVERY_ROLE();
        bytes32 rewardsPerBlockCalculator = judgeStaking
            .REWARDS_PER_BLOCK_CALCULATOR();
        judgeStaking.grantRole(stakingAdmin, owner);
        judgeStaking.grantRole(
            rewardsPerBlockCalculator,
            address(judgeTreasury)
        );
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        judgeTreasury.grantRole(treasuryAdmin, owner);
        judgeTreasury.grantRole(fundManager, owner);
        judgeStaking.setRewardsManagerAddress(address(rewardsManager));
        judgeStaking.setJudgeTreasuryAddress(address(judgeTreasury));
        rewardsManager.setJudgeTreasuryAddress(address(judgeTreasury));

        rewardsManager.grantRole(
            rewardsManagerPreciseBalanceUpdater,
            address(judgeTreasury)
        );
        rewardsManager.grantRole(rewardsDistributor, address(judgeStaking));
        judgeTreasury.grantRole(
            treasuryPreciseBalanceUpdater,
            address(judgeStaking)
        );
        judgeToken.grantRole(allocationMinterRole, address(judgeTreasury));

        console.log("JudgeTokenAddress", address(judgeToken));
        console.log("JudgeTreasuryAddress", address(judgeTreasury));
        console.log("RewardsmanagerAddress", address(rewardsManager));
        console.log("JudgeStakingAddress", address(judgeStaking));
        console.log("MinterRole is:");
        console.logBytes32(allocationMinterRole);
        console.log("rewardsManagerPreciseBalanceUpdater is:");
        console.logBytes32(rewardsManagerPreciseBalanceUpdater);
        console.log("rewardsDistributor is:");
        console.logBytes32(rewardsDistributor);
        console.log("Treasuryprecisebalanceupdater is:");
        console.logBytes32(treasuryPreciseBalanceUpdater);
        console.log("rewardsManagerAdmin is:");
        console.logBytes32(rewardsManagerAdmin);
        console.log("Staking Admin is:");
        console.logBytes32(stakingAdmin);
        console.log("Treasury Admin is:");
        console.logBytes32(treasuryAdmin);
        console.log("fundManager is:");
        console.logBytes32(fundManager);
        console.log("TokenRecovery role is:");
        console.logBytes32(tokenRecoveryRole);
    }

    function testDeployerIsOwner() public {
        bytes32 defaultAdmin = judgeStaking.DEFAULT_ADMIN_ROLE();
        assertTrue(judgeStaking.hasRole(defaultAdmin, owner));
    }

    function testSetRewardsManagerAddress() public {
        // For testing purpose we are using judgeToken address as placeholder for new rewards manager contract address
        bytes32 defaultAdmin = judgeStaking.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                defaultAdmin
            )
        );
        vm.prank(user1);
        judgeStaking.setRewardsManagerAddress(address(judgeToken));

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.setRewardsManagerAddress(address(0));

        vm.expectRevert(CannotInputThisContractAddress.selector);
        judgeStaking.setRewardsManagerAddress(address(judgeStaking));

        vm.expectRevert(EOANotAllowed.selector);
        judgeStaking.setRewardsManagerAddress(user1);

        judgeStaking.setRewardsManagerAddress(address(judgeToken));
        assertEq(address(judgeStaking.rewardsManager()), address(judgeToken));
    }

    function testSetJudgeTreasuryAddress() public {
        // For testing purpose we are using judgeToken address as placeholder for new treasury contract Address
        bytes32 defaultAdmin = judgeStaking.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                defaultAdmin
            )
        );
        vm.prank(user1);
        judgeStaking.setJudgeTreasuryAddress(address(judgeToken));

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.setJudgeTreasuryAddress(address(0));

        vm.expectRevert(CannotInputThisContractAddress.selector);
        judgeStaking.setJudgeTreasuryAddress(address(judgeStaking));

        vm.expectRevert(EOANotAllowed.selector);
        judgeStaking.setJudgeTreasuryAddress(user1);

        judgeStaking.setJudgeTreasuryAddress(address(judgeToken));
        assertEq(address(judgeStaking.judgeTreasury()), address(judgeToken));
    }

    function testUpdateEarlyWithdrawalPercent() public {
        (uint8 earlyWithdrawPenaltyPercent, , ) = judgeStaking.settings();
        assertEq(earlyWithdrawPenaltyPercent, 10);
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        uint8 newEarlyWithdrawalPercent = 5;
        uint8 earlyWithdrawalPercentHigherThanMax = 21;
        uint8 invalidAmount;

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                stakingAdmin
            )
        );
        vm.prank(user1);
        judgeStaking.updateEarlyWithdrawPenaltyPercentForMaxLockupPeriod(
            newEarlyWithdrawalPercent
        );

        vm.expectRevert(InvalidAmount.selector);
        judgeStaking.updateEarlyWithdrawPenaltyPercentForMaxLockupPeriod(
            invalidAmount
        );

        vm.expectRevert(ValueTooHigh.selector);
        judgeStaking.updateEarlyWithdrawPenaltyPercentForMaxLockupPeriod(
            earlyWithdrawalPercentHigherThanMax
        );

        judgeStaking.updateEarlyWithdrawPenaltyPercentForMaxLockupPeriod(
            newEarlyWithdrawalPercent
        );
        (uint8 newEarlyWithdrawPenaltyPercent, , ) = judgeStaking.settings();
        assertEq(newEarlyWithdrawalPercent, 5);
    }

    function testGetCurrentQuarterIndex() public {
        uint256 startBlock = judgeStaking.stakingPoolStartBlock();
        assertEq(judgeStaking.getCurrentQuarterIndex(), 1);

        vm.roll(startBlock + 648_000);
        assertEq(judgeStaking.getCurrentQuarterIndex(), 2);

        vm.roll(startBlock + 1_296_000);
        assertEq(judgeStaking.getCurrentQuarterIndex(), 3);
    }

    function testSyncQuarterRewardsPerBlock() public {}

    function testGetCurrentApr() public {
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        uint256 firstQuarterRewards = 1_000_000 * 10 ** uint256(decimals);
        uint256 additionalRewards = 20_000 * 10 ** uint256(decimals);

        judgeTreasury.grantRole(treasuryAdmin, owner);
        judgeTreasury.grantRole(fundManager, owner);
        judgeStaking.grantRole(stakingAdmin, owner);

        vm.roll(poolStartBlock);
        judgeTreasury.setNewQuarterlyRewards(firstQuarterRewards);
        judgeTreasury.fundRewardsManager(1);

        uint256 assumedTotalStakeWeight = 10_000_000 * 10 ** uint256(decimals);
        uint256 rewardsPerBlock = judgeStaking.rewardsPerBlockForQuarter(1);
        vm.store(
            address(judgeStaking),
            bytes32(uint256(12)),
            bytes32(assumedTotalStakeWeight)
        );
        uint256 blocksPerYear = 365 days / 12;
        uint256 apr1 = (rewardsPerBlock * blocksPerYear * 1e18) /
            assumedTotalStakeWeight;

        assertEq(judgeStaking.getCurrentApr(), apr1);

        vm.roll(poolStartBlock + 255_000);
        judgeToken.approve(
            address(judgeTreasury),
            40_000 * 10 ** uint256(decimals)
        );
        judgeTreasury.addBonusToQuarterReward(additionalRewards, 100_000);
        uint256 bonusRewardsPerBlock = judgeStaking.bonusPerBlockForQuarter(1);
        uint256 apr2 = (bonusRewardsPerBlock * blocksPerYear * 1e18) /
            assumedTotalStakeWeight;
        assertEq(judgeStaking.getCurrentApr(), apr1 + apr2);
    }

    function testUpdateFeePercent() public {
        (, uint8 feePercent, ) = judgeStaking.settings();
        assertEq(feePercent, 0);
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        uint8 newFeePercent = 15;
        uint8 feePercentHigherThanThreshold = 31;
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                stakingAdmin
            )
        );
        vm.prank(user1);
        judgeStaking.updateFeePercent(newFeePercent);

        vm.expectRevert(ValueTooHigh.selector);
        judgeStaking.updateFeePercent(feePercentHigherThanThreshold);

        judgeStaking.updateFeePercent(newFeePercent);
        (, uint8 feeP, ) = judgeStaking.settings();
        assertEq(feeP, newFeePercent);
    }

    function testUpdateJudgeRecoveryMinimumThreshold() public {
        assertEq(judgeStaking.judgeRecoveryMinimumThreshold(), 0);
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        uint256 newJudgeRecoveryMinimumThreshold = 3000;
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                stakingAdmin
            )
        );
        vm.prank(user1);
        judgeStaking.updateJudgeRecoveryMinimumThreshold(
            newJudgeRecoveryMinimumThreshold
        );

        judgeStaking.updateJudgeRecoveryMinimumThreshold(
            newJudgeRecoveryMinimumThreshold
        );
        assertEq(
            judgeStaking.judgeRecoveryMinimumThreshold(),
            newJudgeRecoveryMinimumThreshold
        );
    }

    function testDeposit() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
        uint256 invalidDepositAmount;
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        uint32 zeroLockUpPeriod;
        uint32 higherThanMaxLockUpPeriod = 361;
        judgeToken.generalMint(user1, amount);

        vm.startPrank(user1);
        vm.expectRevert(InvalidAmount.selector);
        judgeStaking.deposit(invalidDepositAmount, lockUpPeriod);

        vm.expectRevert(InvalidAmount.selector);
        judgeStaking.deposit(depositAmount, zeroLockUpPeriod);

        vm.expectRevert(InvalidLockUpPeriod.selector);
        judgeStaking.deposit(depositAmount, higherThanMaxLockUpPeriod);

        judgeToken.approve(address(judgeStaking), depositAmount);
        uint256 blockNumber = block.number;
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();
        uint256 accJudgePerShare = judgeStaking.accJudgePerShare();
        assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).id, 1);
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).amountStaked,
            depositAmount
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpPeriod,
            lockUpPeriod
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).depositBlockNumber,
            blockNumber
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).maturityBlockNumber,
            blockNumber + (lockUpPeriod * 7200)
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).stakeWeight,
            depositAmount / 2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpRatio,
            Math.mulDiv(lockUpPeriod, 1e18, 360)
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).rewardDebt,
            Math.mulDiv(depositAmount / 2, accJudgePerShare, 1e18)
        );
        assertEq(judgeStaking.totalStaked(), depositAmount);
        assertEq(judgeToken.balanceOf(user1), amount - depositAmount);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeStaking), depositAmount2);
        uint256 blockNumber2 = block.number;
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);

        vm.stopPrank();
        uint256 accJudgePerShare2 = judgeStaking.accJudgePerShare();
        assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).id, 2);
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).amountStaked,
            depositAmount2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).lockUpPeriod,
            lockUpPeriod2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).depositBlockNumber,
            blockNumber2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).maturityBlockNumber,
            blockNumber2 + (lockUpPeriod2 * 7200)
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).stakeWeight,
            depositAmount2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).lockUpRatio,
            Math.mulDiv(lockUpPeriod2, 1e18, 360)
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).rewardDebt,
            Math.mulDiv(depositAmount2, accJudgePerShare2, 1e18)
        );
        assertEq(judgeStaking.totalStaked(), depositAmount + depositAmount2);
        assertEq(
            judgeToken.balanceOf(user1),
            amount - depositAmount - depositAmount2
        );
    }

    function logRewards(
        uint256 balanceAfter,
        uint256 balanceBefore,
        string memory label
    ) internal pure returns (uint256) {
        console.log(label, balanceAfter - balanceBefore);
        return balanceAfter - balanceBefore;
    }

    function testClaimRewards() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 amount2 = 150_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 80_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, amount);
        judgeToken.generalMint(user3, amount2);

        vm.startPrank(user1);
        vm.expectRevert(InvalidIndex.selector);
        judgeStaking.claimRewards(0);

        vm.roll(poolStartBlock);
        judgeToken.approve(address(judgeStaking), depositAmount);
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        uint256 user1BalanceAfterDeposit = judgeToken.balanceOf(user1);
        vm.stopPrank();

        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), depositAmount);
        judgeStaking.deposit(depositAmount, lockUpPeriod2);
        uint256 user2BalanceAfterDeposit = judgeToken.balanceOf(user2);
        vm.stopPrank();

        vm.startPrank(user3);
        judgeToken.approve(address(judgeStaking), depositAmount2);
        judgeStaking.deposit(depositAmount2, lockUpPeriod);
        uint256 user3BalanceAfterDeposit = judgeToken.balanceOf(user3);
        vm.stopPrank();

        judgeTreasury.setNewQuarterlyRewards(
            1_000_000 * 10 ** uint256(decimals)
        );
        judgeTreasury.fundRewardsManager(1);
        uint256 rewardsPerBlock = judgeStaking.rewardsPerBlockForQuarter(1);
        console.log("rewardsPerblock", rewardsPerBlock);

        vm.roll(poolStartBlock + 100_000);
        console.log("blockcount1", block.number);

        vm.prank(user1);
        judgeStaking.claimRewards(0);

        uint256 accJudgePerShareAfter100kBlocks = judgeStaking
            .accJudgePerShare();
        console.log(
            "AccJudgePerShareAfter100kBlocks",
            accJudgePerShareAfter100kBlocks
        );
        uint256 user1BalanceAfterFirstClaim = judgeToken.balanceOf(user1);
        logRewards(
            user1BalanceAfterFirstClaim,
            user1BalanceAfterDeposit,
            "user1 first rewards"
        );

        vm.prank(user2);
        judgeStaking.claimRewards(0);

        uint256 user2BalanceAfterFirstClaim = judgeToken.balanceOf(user2);
        logRewards(
            user2BalanceAfterFirstClaim,
            user2BalanceAfterDeposit,
            "user2 first rewards"
        );

        vm.prank(user3);
        judgeStaking.claimRewards(0);

        uint256 user3BalanceAfterFirstClaim = judgeToken.balanceOf(user3);
        logRewards(
            user3BalanceAfterFirstClaim,
            user3BalanceAfterDeposit,
            "user3 first Rewards"
        );

        assertEq(
            user3BalanceAfterFirstClaim - user3BalanceAfterDeposit,
            user2BalanceAfterFirstClaim - user2BalanceAfterDeposit
        );

        uint256 rewardsManagerBal = judgeToken.balanceOf(
            address(rewardsManager)
        );
        console.log("rewardsManager balance", rewardsManagerBal);

        vm.roll(poolStartBlock + 150_000);
        console.log("blockcount2", block.number);
        console.log("rewardsPerBlock", rewardsPerBlock);

        uint256 accumuJudgePershareBeforeSecondClaim = judgeStaking
            .accJudgePerShare();
        console.log(
            "AccumuJudgePerShareBeforeSecondClaim",
            accumuJudgePershareBeforeSecondClaim
        );

        vm.prank(user1);
        judgeStaking.claimRewards(0);

        uint256 accumuJudgePershareAfterSecondClaim = judgeStaking
            .accJudgePerShare();
        console.log(
            "AccumuJudgePerShareAfterSecondClaim",
            accumuJudgePershareAfterSecondClaim
        );

        uint256 user1BalanceAfterSecondClaim = judgeToken.balanceOf(user1);
        logRewards(
            user1BalanceAfterSecondClaim,
            user1BalanceAfterFirstClaim,
            "user1 second rewards"
        );

        vm.prank(user2);
        judgeStaking.claimRewards(0);

        uint256 user2BalanceAfterSecondClaim = judgeToken.balanceOf(user2);
        logRewards(
            user2BalanceAfterSecondClaim,
            user2BalanceAfterFirstClaim,
            "user2 second rewards"
        );
    }

    function testClaimRewardsAfterAddingBonus() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 amount2 = 150_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 80_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, amount);
        judgeToken.generalMint(user3, amount2);

        vm.startPrank(user1);
        vm.expectRevert(InvalidIndex.selector);
        judgeStaking.claimRewards(0);

        vm.roll(poolStartBlock);
        judgeToken.approve(address(judgeStaking), depositAmount);
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        uint256 user1BalanceAfterDeposit = judgeToken.balanceOf(user1);
        vm.stopPrank();

        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), depositAmount);
        judgeStaking.deposit(depositAmount, lockUpPeriod2);
        uint256 user2BalanceAfterDeposit = judgeToken.balanceOf(user2);
        vm.stopPrank();

        judgeTreasury.setNewQuarterlyRewards(
            1_000_000 * 10 ** uint256(decimals)
        );
        judgeTreasury.fundRewardsManager(1);
        uint256 rewardsPerBlock = judgeStaking.rewardsPerBlockForQuarter(1);
        console.log("rewardsPerblock", rewardsPerBlock);

        vm.roll(poolStartBlock + 100_000);
        console.log("blockcount1", block.number);

        vm.prank(user1);
        judgeStaking.claimRewards(0);

        uint256 accJudgePerShareAfter100kBlocks = judgeStaking
            .accJudgePerShare();
        console.log(
            "AccJudgePerShareAfter100kBlocks",
            accJudgePerShareAfter100kBlocks
        );
        uint256 user1BalanceAfterFirstClaim = judgeToken.balanceOf(user1);
        logRewards(
            user1BalanceAfterFirstClaim,
            user1BalanceAfterDeposit,
            "user1 first rewards"
        );

        vm.prank(user2);
        judgeStaking.claimRewards(0);

        uint256 user2BalanceAfterFirstClaim = judgeToken.balanceOf(user2);
        logRewards(
            user2BalanceAfterFirstClaim,
            user2BalanceAfterDeposit,
            "user2 first rewards"
        );

        uint256 newMintAmount = 500_000 * 10 ** uint256(decimals);
        judgeToken.generalMint(owner, newMintAmount);
        judgeToken.approve(address(judgeTreasury), newMintAmount);
        judgeTreasury.addBonusToQuarterReward(newMintAmount, 100_000);

        vm.startPrank(user3);
        judgeToken.approve(address(judgeStaking), depositAmount2);
        judgeStaking.deposit(depositAmount2, lockUpPeriod);
        uint256 user3BalanceAfterDeposit = judgeToken.balanceOf(user3);
        vm.stopPrank();

        vm.roll(poolStartBlock + 200_000);
        console.log("blockcount2", block.number);

        uint256 newRewardsPerBlock = judgeStaking.rewardsPerBlockForQuarter(1);
        console.log("newRewardsPerBlock", newRewardsPerBlock);

        uint256 accumuJudgePershare = judgeStaking.accJudgePerShare();
        console.log("AccumuJudgePerBeforeThirdClaim", accumuJudgePershare);

        uint256 bonusRewardPerBlock = judgeStaking.bonusPerBlockForQuarter(1);
        console.log("BonusRewardPerBlock", bonusRewardPerBlock);

        uint256 accBonusJudgePerShare = judgeStaking.accBonusJudgePerShare();
        console.log(
            "AccBonusJudgePerShareBeforeSecondClaim",
            accBonusJudgePerShare
        );

        vm.prank(user1);
        judgeStaking.claimRewards(0);

        uint256 accumuJudgePershareAfterClaim = judgeStaking.accJudgePerShare();
        console.log(
            "AccumuJudgePerShareAfterSecondClaim",
            accumuJudgePershareAfterClaim
        );

        uint256 accBonusJudgePerShareAfterClaim = judgeStaking
            .accBonusJudgePerShare();
        console.log(
            "AccBonusJudgePerShareAfterSecondClaim",
            accBonusJudgePerShareAfterClaim
        );

        uint256 user1BalanceAfterSecondClaim = judgeToken.balanceOf(user1);
        logRewards(
            user1BalanceAfterSecondClaim,
            user1BalanceAfterFirstClaim,
            "user1 second rewards"
        );

        vm.prank(user2);
        judgeStaking.claimRewards(0);

        uint256 user2BalanceAfterSecondClaim = judgeToken.balanceOf(user2);
        logRewards(
            user2BalanceAfterSecondClaim,
            user2BalanceAfterFirstClaim,
            "user2 second rewards"
        );

        vm.prank(user3);
        judgeStaking.claimRewards(0);
        uint256 user3BalanceAfterFirstClaim = judgeToken.balanceOf(user3);
        logRewards(
            user3BalanceAfterFirstClaim,
            user3BalanceAfterDeposit,
            "user3 first rewards"
        );
    }

    function testClaimRewardsInSecondQuarter() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 amount2 = 150_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 80_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, amount);
        judgeToken.generalMint(user3, amount2);

        vm.startPrank(user1);

        vm.roll(poolStartBlock);
        judgeToken.approve(address(judgeStaking), depositAmount);
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();

        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), depositAmount);
        judgeStaking.deposit(depositAmount, lockUpPeriod2);
        vm.stopPrank();

        judgeTreasury.setNewQuarterlyRewards(
            1_000_000 * 10 ** uint256(decimals)
        );
        judgeTreasury.setNewQuarterlyRewards(500_000 * 10 ** uint256(decimals));
        judgeTreasury.fundRewardsManager(1);

        vm.roll(poolStartBlock + 100_000);
        console.log("blockcount1", block.number);

        vm.prank(user1);
        judgeStaking.claimRewards(0);

        vm.prank(user2);
        judgeStaking.claimRewards(0);

        uint256 newMintAmount = 500_000 * 10 ** uint256(decimals);
        uint256 firstBonus = 200_000 * 10 ** uint256(decimals);
        judgeToken.generalMint(owner, newMintAmount);
        judgeToken.approve(address(judgeTreasury), newMintAmount);
        judgeTreasury.addBonusToQuarterReward(firstBonus, 100_000);

        vm.startPrank(user3);
        judgeToken.approve(address(judgeStaking), depositAmount2);
        judgeStaking.deposit(depositAmount2, lockUpPeriod);
        vm.stopPrank();

        vm.roll(poolStartBlock + 648_000);
        console.log("blockcount2", block.number);
        judgeTreasury.fundRewardsManager(2);

        vm.prank(user1);
        judgeStaking.claimRewards(0);
        uint256 user1BalanceBeforeEndOfFirstQuarter = judgeToken.balanceOf(
            user1
        );

        uint256 accJudgePerShare = judgeStaking.accJudgePerShare();
        uint256 accBonusJudgePerShare = judgeStaking.accBonusJudgePerShare();
        console.log("accJudgePerShare", accJudgePerShare);
        console.log("accBonusJudgePerShare", accBonusJudgePerShare);

        vm.prank(user2);
        judgeStaking.claimRewards(0);
        uint256 user2BalanceBeforeEndOfFirstQuarter = judgeToken.balanceOf(
            user2
        );

        vm.prank(user3);
        judgeStaking.claimRewards(0);
        uint256 user3BalanceBeforeEndOfFirstQuarter = judgeToken.balanceOf(
            user3
        );

        uint256 secondBonus = 300_000 * 10 ** uint256(decimals);
        judgeTreasury.addBonusToQuarterReward(secondBonus, 100_000);
        vm.roll(poolStartBlock + 698_000);
        vm.prank(user1);
        judgeStaking.claimRewards(0);
        uint256 user1BalanceinSecondQuarter = judgeToken.balanceOf(user1);
        logRewards(
            user1BalanceinSecondQuarter,
            user1BalanceBeforeEndOfFirstQuarter,
            "user1 second quarter rewards"
        );

        vm.prank(user2);
        judgeStaking.claimRewards(0);
        uint256 user2BalanceinSecondQuarter = judgeToken.balanceOf(user2);
        logRewards(
            user2BalanceinSecondQuarter,
            user2BalanceBeforeEndOfFirstQuarter,
            "user2 second quarter rewards"
        );

        vm.prank(user3);
        judgeStaking.claimRewards(0);
        uint256 user3BalanceinSecondQuarter = judgeToken.balanceOf(user3);
        logRewards(
            user3BalanceinSecondQuarter,
            user3BalanceBeforeEndOfFirstQuarter,
            "user3 second quarter rewards"
        );
    }

    function testWithdraw() public {
        uint256 reward = 1_000_000 * 10 ** uint256(decimals);
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 withdrawalAmount = 30_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount3 = 60_000 * 10 ** uint256(decimals);
        uint256 tooHighAmount = 40_001 * 10 ** uint256(decimals);
        uint256 invalidAmount;
        uint256 bonus = 100_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 10;
        uint32 lockUpPeriod2 = 360;
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, amount);
        judgeToken.generalMint(owner, amount);

        vm.prank(user1);
        judgeToken.approve(address(judgeStaking), amount);

        vm.roll(poolStartBlock);

        judgeTreasury.setNewQuarterlyRewards(reward);
        judgeTreasury.fundRewardsManager(1);

        vm.prank(user1);
        judgeStaking.deposit(depositAmount, lockUpPeriod);

        vm.roll(poolStartBlock + 2000);

        judgeToken.approve(address(judgeTreasury), bonus);
        judgeTreasury.addBonusToQuarterReward(bonus, 200_000);
        vm.prank(user1);
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);
        uint256 balanceOfUser1AfterSecondDeposit = judgeToken.balanceOf(user1);

        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), amount);
        judgeStaking.deposit(depositAmount3, lockUpPeriod2);
        vm.stopPrank();

        vm.roll(poolStartBlock + 80_000);

        vm.expectRevert(InvalidAmount.selector);
        vm.prank(user1);
        judgeStaking.withdraw(invalidAmount, 0);

        vm.expectRevert(InvalidIndex.selector);
        vm.prank(user1);
        judgeStaking.withdraw(withdrawalAmount, 2);

        vm.expectRevert(InsufficientBalance.selector);
        vm.prank(user1);
        judgeStaking.withdraw(tooHighAmount, 0);

        vm.expectRevert(NotYetMatured.selector);
        vm.prank(user2);
        judgeStaking.withdraw(withdrawalAmount, 0);

        vm.prank(user1);
        judgeStaking.withdraw(withdrawalAmount, 0);
        uint256 balanceOfUser1AfterWithdrawal = judgeToken.balanceOf(user1);
        uint256 totalAmountWithdrawn = balanceOfUser1AfterWithdrawal -
            balanceOfUser1AfterSecondDeposit;
        assertApproxEqRel(totalAmountWithdrawn, 34848731500000000000000, 4e14);
        assertApproxEqAbs(totalAmountWithdrawn, 34848731500000000000000, 11e19);

        JudgeStaking.UserStake memory user1Stake = judgeStaking
            .viewUserStakeAtIndex(user1, 0);
        assertEq(user1Stake.amountStaked, 10_000 * 10 ** uint256(decimals));
        assertEq(judgeStaking.totalStaked(), 110_000 * 10 ** uint256(decimals));
        assertApproxEqAbs(
            user1Stake.stakeWeight,
            (user1Stake.amountStaked * 10 * 1e18) / 360 / 1e18,
            10_000
        );
        assertApproxEqAbs(
            judgeStaking.totalStakeWeight(),
            10027778e16,
            10000000000000000
        );
        assertEq(
            user1Stake.rewardDebt,
            (user1Stake.stakeWeight * judgeStaking.accJudgePerShare()) / 1e18
        );
        assertEq(
            user1Stake.bonusRewardDebt,
            (user1Stake.stakeWeight * judgeStaking.accBonusJudgePerShare()) /
                1e18
        );
    }

    function testWithdrawAll() public {
        uint256 reward = 1_000_000 * 10 ** uint256(decimals);
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount3 = 60_000 * 10 ** uint256(decimals);
        uint256 bonus = 100_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 10;
        uint32 lockUpPeriod2 = 360;
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, amount);
        judgeToken.generalMint(owner, amount);

        vm.prank(user1);
        judgeToken.approve(address(judgeStaking), amount);

        vm.roll(poolStartBlock);

        judgeTreasury.setNewQuarterlyRewards(reward);
        judgeTreasury.fundRewardsManager(1);

        vm.prank(user1);
        judgeStaking.deposit(depositAmount, lockUpPeriod);

        vm.roll(poolStartBlock + 2000);

        judgeToken.approve(address(judgeTreasury), bonus);
        judgeTreasury.addBonusToQuarterReward(bonus, 200_000);
        vm.prank(user1);
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);
        uint256 balanceOfUser1AfterSecondDeposit = judgeToken.balanceOf(user1);

        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), amount);
        judgeStaking.deposit(depositAmount3, lockUpPeriod2);
        vm.stopPrank();

        vm.roll(poolStartBlock + 80_000);

        vm.expectRevert(InvalidIndex.selector);
        vm.prank(user1);
        judgeStaking.withdrawAll(2);

        vm.expectRevert(NotYetMatured.selector);
        vm.prank(user2);
        judgeStaking.withdrawAll(0);

        vm.prank(user1);
        judgeStaking.withdrawAll(0);
        uint256 balanceOfUser1AfterWithdrawal = judgeToken.balanceOf(user1);
        uint256 totalAmountWithdrawn = balanceOfUser1AfterWithdrawal -
            balanceOfUser1AfterSecondDeposit;
        assertApproxEqRel(totalAmountWithdrawn, 44848731500000000000000, 4e14);
        assertApproxEqAbs(totalAmountWithdrawn, 44848731500000000000000, 11e19);

        JudgeStaking.UserStake memory user1Stake = judgeStaking
            .viewUserStakeAtIndex(user1, 0);
        assertEq(user1Stake.amountStaked, 0);
        assertEq(judgeStaking.totalStaked(), 100_000 * 10 ** uint256(decimals));
        assertEq(user1Stake.stakeWeight, 0);
        assertEq(judgeStaking.totalStakeWeight(), 1e23);
        assertEq(user1Stake.rewardDebt, 0);
        assertEq(user1Stake.bonusRewardDebt, 0);
    }

    function testEarlyWithdraw() public {
        uint256 reward = 1_000_000 * 10 ** uint256(decimals);
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 bonus = 100_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 10;
        uint32 lockUpPeriod2 = 360;
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, amount);
        judgeToken.generalMint(owner, amount);

        vm.prank(user1);
        judgeToken.approve(address(judgeStaking), amount);

        vm.roll(poolStartBlock);

        judgeTreasury.setNewQuarterlyRewards(reward);
        judgeTreasury.fundRewardsManager(1);

        vm.prank(user1);
        judgeStaking.deposit(40_000 * 10 ** uint256(decimals), lockUpPeriod);
        uint256 user1Stake1StakeWeight = Math.mulDiv(4e22, 10, 360);

        vm.roll(poolStartBlock + 2000);

        judgeToken.approve(address(judgeTreasury), bonus);
        judgeTreasury.addBonusToQuarterReward(bonus, 200_000);

        uint256 accJudgePerShareAFter2000Blocks = Math.mulDiv(
            2000,
            Math.mulDiv(1_000_000 * 10 ** uint256(decimals), 1e18, 648_000),
            user1Stake1StakeWeight
        );
        console.log(
            "accJudgePerShareAfter2000Blocks",
            accJudgePerShareAFter2000Blocks
        );

        vm.roll(poolStartBlock + 3000);
        vm.prank(user1);
        judgeStaking.deposit(40_000 * 10 ** uint256(decimals), lockUpPeriod2);
        uint256 user1Stake2StakeWeight = Math.mulDiv(4e22, 360, 360);

        uint256 accJudgePerShareAFter3000Blocks = (
            Math.mulDiv(
                1_000,
                Math.mulDiv(1_000_000 * 10 ** uint256(decimals), 1e18, 648_000),
                user1Stake1StakeWeight
            )
        ) + accJudgePerShareAFter2000Blocks;
        uint256 accBonusJudgePerShareAfter3000Blocks = Math.mulDiv(
            1_000,
            Math.mulDiv(100_000 * 10 ** uint256(decimals), 1e18, 200_000),
            user1Stake1StakeWeight
        );

        vm.roll(poolStartBlock + 4000);
        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), amount);
        judgeStaking.deposit(60_000 * 10 ** uint256(decimals), lockUpPeriod2);
        vm.stopPrank();

        uint256 accJudgePerShareAFter4000Blocks = (
            Math.mulDiv(
                1_000,
                Math.mulDiv(1_000_000 * 10 ** uint256(decimals), 1e18, 648_000),
                user1Stake1StakeWeight + user1Stake2StakeWeight
            )
        ) + accJudgePerShareAFter3000Blocks;
        uint256 accBonusJudgePerShareAfter4000Blocks = (
            Math.mulDiv(
                1_000,
                Math.mulDiv(100_000 * 10 ** uint256(decimals), 1e18, 200_000),
                user1Stake1StakeWeight + user1Stake2StakeWeight
            )
        ) + accBonusJudgePerShareAfter3000Blocks;
        console.log(
            "accBonusJudgePerShareAfter4000Blocks",
            accBonusJudgePerShareAfter4000Blocks
        );
        uint256 user2StakeWeight = Math.mulDiv(6e22, 360, 360);
        uint256 balanceOfUser2AfterDeposit = judgeToken.balanceOf(user2);

        vm.roll(poolStartBlock + 80_000);

        uint256 totalStakeWeight = user1Stake1StakeWeight +
            user1Stake2StakeWeight +
            user2StakeWeight;
        uint256 accJudgePerShareAFter80000Blocks = Math.mulDiv(
            76_000,
            Math.mulDiv(1_000_000 * 10 ** uint256(decimals), 1e18, 648_000),
            totalStakeWeight
        ) + accJudgePerShareAFter4000Blocks;
        uint256 accBonusJudgePerShareAfter80000Blocks = Math.mulDiv(
            76_000,
            Math.mulDiv(100_000 * 10 ** uint256(decimals), 1e18, 200_000),
            totalStakeWeight
        ) + accBonusJudgePerShareAfter4000Blocks;
        console.log(
            "accBonusJudgePerShareAfter80000Blocks",
            accBonusJudgePerShareAfter80000Blocks
        );
        vm.expectRevert(InvalidAmount.selector);
        vm.prank(user2);
        judgeStaking.earlyWithdraw(0, 0);

        vm.expectRevert(InvalidIndex.selector);
        vm.prank(user2);
        judgeStaking.earlyWithdraw(50_000 * 10 ** uint256(decimals), 2);

        vm.expectRevert(InsufficientBalance.selector);
        vm.prank(user2);
        judgeStaking.earlyWithdraw(60_001 * 10 ** uint256(decimals), 0);

        vm.expectRevert(AlreadyMatured.selector);
        vm.prank(user1);
        judgeStaking.earlyWithdraw(50_000 * 10 ** uint256(decimals), 0);

        vm.prank(user2);
        judgeStaking.earlyWithdraw(50_000 * 10 ** uint256(decimals), 0);

        uint256 balanceOfUser2AfterWithdrawal = judgeToken.balanceOf(user2);
        uint256 totalAmountWithdrawn = balanceOfUser2AfterWithdrawal -
            balanceOfUser2AfterDeposit;
        uint256 user2RewardsExpected = Math.mulDiv(
            user2StakeWeight,
            accJudgePerShareAFter80000Blocks,
            1e18
        ) -
            Math.mulDiv(
                user2StakeWeight,
                accJudgePerShareAFter4000Blocks,
                1e18
            );
        uint256 user2BonusRewardsExpected = Math.mulDiv(
            user2StakeWeight,
            accBonusJudgePerShareAfter80000Blocks,
            1e18
        ) -
            Math.mulDiv(
                user2StakeWeight,
                accBonusJudgePerShareAfter4000Blocks,
                1e18
            );
        console.log("user2RewardsExpected", user2RewardsExpected);
        console.log("user2BonusRewardsExpected", user2BonusRewardsExpected);
        uint256 user2WithdrawnDeposit = 50_000 * 10 ** uint256(decimals);
        uint256 expectedTotalWithdrawnByUser2 = user2RewardsExpected +
            user2BonusRewardsExpected +
            user2WithdrawnDeposit;
        assertEq(totalAmountWithdrawn, expectedTotalWithdrawnByUser2);
        assertEq(totalAmountWithdrawn, expectedTotalWithdrawnByUser2);

        // Checks if penalty was successfully transferred
        assertEq(judgeToken.balanceOf(address(judgeTreasury)), 5e21);
    }

    function testTotalUnclaimedRewards() public {
        uint256 reward = 1_000_000 * 10 ** uint256(decimals);
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 bonus = 100_000 * 10 ** uint256(decimals);
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, amount);

        vm.prank(user1);
        judgeToken.approve(address(judgeStaking), amount);

        vm.roll(poolStartBlock);

        judgeTreasury.setNewQuarterlyRewards(reward);
        judgeTreasury.fundRewardsManager(1);

        vm.prank(user1);
        judgeStaking.deposit(40_000 * 10 ** uint256(decimals), 10);

        vm.roll(poolStartBlock + 2000);

        judgeToken.approve(address(judgeTreasury), bonus);
        judgeTreasury.addBonusToQuarterReward(bonus, 200_000);

        vm.roll(poolStartBlock + 3000);
        vm.prank(user1);
        judgeStaking.deposit(40_000 * 10 ** uint256(decimals), 360);

        vm.roll(poolStartBlock + 4000);
        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), amount);
        judgeStaking.deposit(60_000 * 10 ** uint256(decimals), 360);
        vm.stopPrank();

        vm.roll(poolStartBlock + 80_000);

        uint256 accruedRewards = judgeStaking.rewardsPerBlockForQuarter(1) *
            80_000;
        uint256 accruedBonus = judgeStaking.bonusPerBlockForQuarter(1) * 78_000;
        (, , uint256 total) = judgeStaking.totalUnclaimedRewards();
        assertEq(total, accruedRewards + accruedBonus);
    }

    function testViewMyStakes() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        judgeToken.generalMint(user1, amount);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeStaking), amount);
        uint256 blockNumber = block.number;
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();

        vm.roll(blockNumber + 60);
        uint256 blockNumber2 = block.number;

        vm.startPrank(user1);
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);

        JudgeStaking.UserStake[] memory myStakes = judgeStaking.viewMyStakes();
        assertEq(myStakes.length, 2);
        assertEq(myStakes[0].id, 1);
        assertEq(myStakes[0].amountStaked, depositAmount);
        assertEq(myStakes[0].lockUpPeriod, lockUpPeriod);
        assertEq(myStakes[0].depositBlockNumber, blockNumber);
        assertEq(
            myStakes[0].maturityBlockNumber,
            blockNumber + (lockUpPeriod * 7200)
        );

        assertEq(myStakes[1].id, 2);
        assertEq(myStakes[1].amountStaked, depositAmount2);
        assertEq(myStakes[1].lockUpPeriod, lockUpPeriod2);
        assertEq(myStakes[1].depositBlockNumber, blockNumber2);
        assertEq(
            myStakes[1].maturityBlockNumber,
            blockNumber2 + (lockUpPeriod2 * 7200)
        );
    }

    function testViewMyStakesAtIndex() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        judgeToken.generalMint(user1, amount);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeStaking), amount);
        uint256 blockNumber = block.number;
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        uint256 accJudgePerShare = judgeStaking.accJudgePerShare();

        vm.expectRevert(InvalidIndex.selector);
        judgeStaking.viewMyStakeAtIndex(1);
        assertEq(judgeStaking.viewMyStakeAtIndex(0).id, 1);
        assertEq(
            judgeStaking.viewMyStakeAtIndex(0).amountStaked,
            depositAmount
        );
        assertEq(judgeStaking.viewMyStakeAtIndex(0).lockUpPeriod, lockUpPeriod);
        assertEq(
            judgeStaking.viewMyStakeAtIndex(0).depositBlockNumber,
            blockNumber
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(0).maturityBlockNumber,
            blockNumber + (lockUpPeriod * 7200)
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(0).stakeWeight,
            depositAmount / 2
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(0).lockUpRatio,
            Math.mulDiv(lockUpPeriod, 1e18, 360)
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(0).rewardDebt,
            Math.mulDiv(depositAmount / 2, accJudgePerShare, 1e18)
        );
        vm.roll(blockNumber + 60);

        uint256 blockNumber2 = block.number;
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);
        uint256 accJudgePerShare2 = judgeStaking.accJudgePerShare();
        assertEq(judgeStaking.viewMyStakeAtIndex(1).id, 2);
        assertEq(
            judgeStaking.viewMyStakeAtIndex(1).amountStaked,
            depositAmount2
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(1).lockUpPeriod,
            lockUpPeriod2
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(1).depositBlockNumber,
            blockNumber2
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(1).maturityBlockNumber,
            blockNumber2 + (lockUpPeriod2 * 7200)
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(1).stakeWeight,
            depositAmount2
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(1).lockUpRatio,
            Math.mulDiv(lockUpPeriod2, 1e18, 360)
        );
        assertEq(
            judgeStaking.viewMyStakeAtIndex(1).rewardDebt,
            Math.mulDiv(depositAmount2, accJudgePerShare2, 1e18)
        );
    }

    function testViewUsersList() public {
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 amount2 = 150_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 80_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, amount);
        judgeToken.generalMint(user3, amount2);

        vm.roll(poolStartBlock);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeStaking), depositAmount);
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();

        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), depositAmount);
        judgeStaking.deposit(depositAmount, lockUpPeriod2);
        vm.stopPrank();

        vm.startPrank(user3);
        judgeToken.approve(address(judgeStaking), depositAmount2);
        judgeStaking.deposit(depositAmount2, lockUpPeriod);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user2,
                stakingAdmin
            )
        );
        vm.prank(user2);
        judgeStaking.viewUsersList();

        address[] memory usersArray = judgeStaking.viewUsersList();
        assertEq(usersArray[0], 0x29E3b139f4393aDda86303fcdAa35F60Bb7092bF);
        assertEq(usersArray[1], 0x537C8f3d3E18dF5517a58B3fB9D9143697996802);
        assertEq(usersArray[2], 0xc0A55e2205B289a967823662B841Bd67Aa362Aec);
    }

    function testViewUserStakes() public {
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        judgeToken.generalMint(user1, amount);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeStaking), amount);
        uint256 blockNumber = block.number;
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();

        vm.roll(blockNumber + 60);
        uint256 blockNumber2 = block.number;

        vm.prank(user1);
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user2,
                stakingAdmin
            )
        );
        vm.prank(user2);
        judgeStaking.viewUserStakes(user1);

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.viewUserStakes(zeroAddress);

        JudgeStaking.UserStake[] memory user1Stakes = judgeStaking
            .viewUserStakes(user1);

        assertEq(user1Stakes.length, 2);
        assertEq(user1Stakes[0].id, 1);
        assertEq(user1Stakes[0].amountStaked, depositAmount);
        assertEq(user1Stakes[0].lockUpPeriod, lockUpPeriod);
        assertEq(user1Stakes[0].depositBlockNumber, blockNumber);
        assertEq(
            user1Stakes[0].maturityBlockNumber,
            blockNumber + (lockUpPeriod * 7200)
        );

        assertEq(user1Stakes[1].id, 2);
        assertEq(user1Stakes[1].amountStaked, depositAmount2);
        assertEq(user1Stakes[1].lockUpPeriod, lockUpPeriod2);
        assertEq(user1Stakes[1].depositBlockNumber, blockNumber2);
        assertEq(
            user1Stakes[1].maturityBlockNumber,
            blockNumber2 + (lockUpPeriod2 * 7200)
        );
    }

    function testViewUserStakeAtIndex() public {
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        judgeToken.generalMint(user1, amount);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeStaking), amount);
        uint256 blockNumber = block.number;
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user2,
                stakingAdmin
            )
        );
        vm.prank(user2);
        judgeStaking.viewUserStakeAtIndex(user1, 0);

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.viewUserStakeAtIndex(zeroAddress, 0);

        vm.expectRevert(InvalidIndex.selector);
        judgeStaking.viewUserStakeAtIndex(user1, 1);

        uint256 accJudgePerShare = judgeStaking.accJudgePerShare();
        assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).id, 1);
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).amountStaked,
            depositAmount
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpPeriod,
            lockUpPeriod
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).depositBlockNumber,
            blockNumber
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).maturityBlockNumber,
            blockNumber + (lockUpPeriod * 7200)
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).stakeWeight,
            depositAmount / 2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpRatio,
            Math.mulDiv(lockUpPeriod, 1e18, 360)
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 0).rewardDebt,
            Math.mulDiv(depositAmount / 2, accJudgePerShare, 1e18)
        );

        vm.roll(blockNumber + 60);

        uint256 blockNumber2 = block.number;

        vm.prank(user1);
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);
        uint256 accJudgePerShare2 = judgeStaking.accJudgePerShare();
        assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).id, 2);
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).amountStaked,
            depositAmount2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).lockUpPeriod,
            lockUpPeriod2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).depositBlockNumber,
            blockNumber2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).maturityBlockNumber,
            blockNumber2 + (lockUpPeriod2 * 7200)
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).stakeWeight,
            depositAmount2
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).lockUpRatio,
            Math.mulDiv(lockUpPeriod2, 1e18, 360)
        );
        assertEq(
            judgeStaking.viewUserStakeAtIndex(user1, 1).rewardDebt,
            Math.mulDiv(depositAmount2, accJudgePerShare2, 1e18)
        );
    }

    function testViewMyPendingRewards() public {
        uint256 reward = 1_000_000 * 10 ** uint256(decimals);
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
        judgeToken.generalMint(user1, amount);

        vm.prank(user1);
        judgeToken.approve(address(judgeStaking), amount);
        vm.roll(poolStartBlock);

        judgeTreasury.setNewQuarterlyRewards(reward);
        judgeTreasury.fundRewardsManager(1);

        vm.prank(user1);
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();

        vm.startPrank(user1);
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);

        vm.roll(poolStartBlock + 10000);
        console.log("pending rewards", judgeStaking.viewMyPendingRewards(0));
        assertEq(
            judgeStaking.viewMyPendingRewards(0),
            5611672278338945 * 10 ** uint256(6)
        );
        assertEq(
            judgeStaking.viewMyPendingRewards(1),
            982042648709315375 * 10 ** uint256(4)
        );
    }

    function testCalculateMisplacedJudge() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, depositAmount2);
        uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
        judgeToken.generalMint(user3, misplacedAmount);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeStaking), amount);
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();

        vm.prank(user3);
        judgeToken.transfer(address(judgeStaking), misplacedAmount);

        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), depositAmount2);
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);
        vm.stopPrank();
        assertEq(judgeStaking.calculateMisplacedJudge(), misplacedAmount);
    }

    function testRecoverMisplacedJudge() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
        uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
        uint32 lockUpPeriod = 180;
        uint32 lockUpPeriod2 = 360;
        judgeToken.generalMint(user1, amount);
        judgeToken.generalMint(user2, depositAmount2);

        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        bytes32 tokenRecoveryAdmin = judgeStaking.TOKEN_RECOVERY_ROLE();
        uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
        uint256 invalidAmount;
        uint8 feePercent = 10;
        judgeStaking.grantRole(stakingAdmin, owner);
        judgeStaking.updateFeePercent(feePercent);
        judgeToken.generalMint(user3, misplacedAmount);

        vm.startPrank(user1);
        judgeToken.approve(address(judgeStaking), amount);
        judgeStaking.deposit(depositAmount, lockUpPeriod);
        vm.stopPrank();

        vm.prank(user3);
        judgeToken.transfer(address(judgeStaking), misplacedAmount);

        vm.startPrank(user2);
        judgeToken.approve(address(judgeStaking), depositAmount2);
        judgeStaking.deposit(depositAmount2, lockUpPeriod2);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                tokenRecoveryAdmin
            )
        );

        judgeStaking.recoverMisplacedJudge(user3, misplacedAmount);
        judgeStaking.grantRole(tokenRecoveryAdmin, owner);

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.recoverMisplacedJudge(zeroAddress, misplacedAmount);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        judgeStaking.recoverMisplacedJudge(
            address(judgeStaking),
            misplacedAmount
        );

        vm.expectRevert(InvalidAmount.selector);
        judgeStaking.recoverMisplacedJudge(user3, invalidAmount);

        judgeStaking.recoverMisplacedJudge(user3, misplacedAmount);
        assertEq(judgeToken.balanceOf(user3), (misplacedAmount * 9) / 10);
        assertEq(
            judgeToken.balanceOf(address(judgeTreasury)),
            misplacedAmount / 10
        );
    }

    function testRecoverErc20() public {
        bytes32 tokenRecoveryAdmin = judgeStaking.TOKEN_RECOVERY_ROLE();
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        address strandedTokenAddr = address(sampleErc20);
        uint256 misplacedAmount = 1000 ether;
        uint256 tooHighAmount = 1001 ether;
        uint256 invalidAmount;
        uint8 feePercent = 10;
        judgeStaking.grantRole(stakingAdmin, owner);
        judgeStaking.updateFeePercent(feePercent);
        sampleErc20.mint(user1, misplacedAmount);

        vm.prank(user1);

        sampleErc20.transfer(address(judgeStaking), misplacedAmount);
        assertEq(sampleErc20.balanceOf(address(judgeStaking)), misplacedAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                owner,
                tokenRecoveryAdmin
            )
        );
        judgeStaking.recoverErc20(strandedTokenAddr, user1, misplacedAmount);

        judgeStaking.grantRole(tokenRecoveryAdmin, owner);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        judgeStaking.recoverErc20(
            strandedTokenAddr,
            address(judgeStaking),
            misplacedAmount
        );

        vm.expectRevert(InvalidAmount.selector);
        judgeStaking.recoverErc20(strandedTokenAddr, user1, invalidAmount);

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.recoverErc20(zeroAddress, user1, misplacedAmount);

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.recoverErc20(
            strandedTokenAddr,
            zeroAddress,
            misplacedAmount
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.recoverErc20(zeroAddress, zeroAddress, misplacedAmount);

        vm.expectRevert(InsufficientContractBalance.selector);
        judgeStaking.recoverErc20(strandedTokenAddr, user1, tooHighAmount);

        vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
        judgeStaking.recoverErc20(address(judgeToken), user1, misplacedAmount);

        judgeStaking.recoverErc20(strandedTokenAddr, user1, misplacedAmount);
        assertEq(sampleErc20.balanceOf(user1), (misplacedAmount * 9) / 10);
        assertEq(
            judgeStaking.feeBalanceOfStrandedToken(strandedTokenAddr),
            misplacedAmount / 10
        );
    }

    function testtransferFeesFromOtherTokensOutOfStaking() public {
        bytes32 tokenRecoveryAdmin = judgeStaking.TOKEN_RECOVERY_ROLE();
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        address strandedTokenAddr = address(sampleErc20);
        uint256 misplacedAmount = 1000 ether;
        uint256 invalidAmount;
        uint8 feePercent = 10;
        judgeStaking.grantRole(stakingAdmin, owner);
        judgeStaking.updateFeePercent(feePercent);
        sampleErc20.mint(user1, misplacedAmount);

        vm.prank(user1);
        sampleErc20.transfer(address(judgeStaking), misplacedAmount);

        judgeStaking.grantRole(tokenRecoveryAdmin, owner);
        judgeStaking.recoverErc20(strandedTokenAddr, user1, misplacedAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                tokenRecoveryAdmin
            )
        );
        vm.prank(user1);
        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            strandedTokenAddr,
            user2,
            misplacedAmount / 10
        );

        vm.expectRevert(CannotInputThisContractAddress.selector);
        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            strandedTokenAddr,
            address(judgeStaking),
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAmount.selector);
        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            strandedTokenAddr,
            user2,
            invalidAmount
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            zeroAddress,
            user2,
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            strandedTokenAddr,
            zeroAddress,
            misplacedAmount / 10
        );

        vm.expectRevert(InvalidAddress.selector);
        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            zeroAddress,
            zeroAddress,
            misplacedAmount / 10
        );

        vm.expectRevert(InsufficientBalance.selector);
        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            strandedTokenAddr,
            user2,
            (misplacedAmount * 2) / 10
        );

        vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            address(judgeToken),
            user2,
            misplacedAmount / 10
        );

        judgeStaking.transferFeesFromOtherTokensOutOfStaking(
            strandedTokenAddr,
            user2,
            misplacedAmount / 10
        );
        assertEq(sampleErc20.balanceOf(user2), misplacedAmount / 10);
        assertEq(judgeStaking.feeBalanceOfStrandedToken(strandedTokenAddr), 0);
    }
}
