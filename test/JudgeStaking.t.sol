// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeStaking.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeTreasury.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../src/SampleERC20.sol";

contract JudgeStakingTest is Test{
    JudgeToken public judgeToken;
    JudgeStaking public judgeStaking;
    RewardsManager public rewardsManager;
    JudgeTreasury public judgeTreasury;
    SampleERC20 public sampleERC20;

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
    error ValueHigherThanThreshold();
    error OverPaidRewards();
    error InvalidLockUpPeriod();
    error InvalidIndex();

      struct userStake {
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

function setUp()public{
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
    judgeStaking = new JudgeStaking(address(judgeToken), earlyWithdrawalPercent);
    rewardsManager = new RewardsManager(address(judgeToken));
    judgeTreasury = new JudgeTreasury(address(judgeToken), address(rewardsManager), address(judgeStaking));
    sampleERC20 = new SampleERC20();
    
    bytes32 minterRole = judgeToken.MINTER_ROLE();
    bytes32 rewardsManagerPreciseBalanceUpdater = rewardsManager.REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
    bytes32 rewardsDistributor = rewardsManager.REWARDS_DISTRIBUTOR_ROLE();
    bytes32 treasuryPreciseBalanceUpdater = judgeTreasury.TREASURY_PRECISE_BALANCE_UPDATER();
    bytes32 rewardsManagerAdmin = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
    bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
    bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
    bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
    bytes32 tokenRecoveryRole = judgeStaking.TOKEN_RECOVERY_ROLE();
    bytes32 rewardsPerBlockCalculator = judgeStaking.REWARDS_PER_BLOCK_CALCULATOR();
    judgeStaking.grantRole(stakingAdmin, owner);
    judgeStaking.grantRole(rewardsPerBlockCalculator, address(judgeTreasury));
    rewardsManager.grantRole(rewardsManagerAdmin, owner);
    judgeTreasury.grantRole(treasuryAdmin, owner);
    judgeTreasury.grantRole(fundManager, owner);
    judgeStaking.setKeyParameters(address(rewardsManager), address(judgeTreasury));
    rewardsManager.setKeyParameter(address(judgeTreasury));

    rewardsManager.grantRole(rewardsManagerPreciseBalanceUpdater, address(judgeTreasury));
    rewardsManager.grantRole(rewardsDistributor, address(judgeStaking));
     judgeTreasury.grantRole(treasuryPreciseBalanceUpdater, address(judgeStaking));
     judgeToken.grantRole(minterRole, address(judgeTreasury)); 
     judgeToken.grantRole(minterRole, owner);

     console.log("JudgeTokenAddress", address(judgeToken));
     console.log("JudgeTreasuryAddress", address(judgeTreasury));
     console.log("RewardsmanagerAddress", address(rewardsManager));
     console.log("JudgeStakingAddress", address(judgeStaking));
     console.log("MinterRole is:");
     console.logBytes32(minterRole);
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

function testDeployerIsOwner()public{
bytes32 defaultAdmin = judgeStaking.DEFAULT_ADMIN_ROLE();
    assertTrue(judgeStaking.hasRole(defaultAdmin, owner));
} 

function testSetKeyParameters()public{
bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
vm.expectRevert(
    abi.encodeWithSelector(
        AccessControlUnauthorizedAccount.selector,
        user1,
        stakingAdmin
    )
);
vm.prank(user1);
judgeStaking.setKeyParameters(address(judgeToken), address(judgeToken));

vm.expectRevert(InvalidAddress.selector);
judgeStaking.setKeyParameters(address(0), address(judgeToken));

vm.expectRevert(InvalidAddress.selector);
judgeStaking.setKeyParameters(address(judgeToken), address(0));

vm.expectRevert(InvalidAddress.selector);
judgeStaking.setKeyParameters(address(0), address(0));

vm.expectRevert(CannotInputThisContractAddress.selector);
judgeStaking.setKeyParameters(address(judgeStaking), address(judgeToken));

vm.expectRevert(CannotInputThisContractAddress.selector);
judgeStaking.setKeyParameters(address(judgeToken), address(judgeStaking));

vm.expectRevert(CannotInputThisContractAddress.selector);
judgeStaking.setKeyParameters(address(judgeStaking), address(judgeStaking));

vm.expectRevert(EOANotAllowed.selector);
judgeStaking.setKeyParameters(user1, address(judgeToken));

vm.expectRevert(EOANotAllowed.selector);
judgeStaking.setKeyParameters(address(judgeToken), user1);

vm.expectRevert(EOANotAllowed.selector);
judgeStaking.setKeyParameters(user1, user1);

// For testing purpose we are using judgeToken address as placeholder for new treasury contract
judgeStaking.setKeyParameters(address(judgeToken), address(judgeToken));
assertEq(address(judgeStaking.rewardsManager()), address(judgeToken));
assertEq(address(judgeStaking.judgeTreasury()), address(judgeToken));
}

function testUpdateEarlyWithdrawalPercent()public{
assertEq(judgeStaking.earlyWithdrawPenaltyPercent(), 10);
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
judgeStaking.updateEarlyWithdrawPenaltyPercent(newEarlyWithdrawalPercent);

vm.expectRevert(InvalidAmount.selector);
judgeStaking.updateEarlyWithdrawPenaltyPercent(invalidAmount);

vm.expectRevert(ValueTooHigh.selector);
judgeStaking.updateEarlyWithdrawPenaltyPercent(earlyWithdrawalPercentHigherThanMax);

judgeStaking.updateEarlyWithdrawPenaltyPercent(newEarlyWithdrawalPercent);
assertEq(judgeStaking.earlyWithdrawPenaltyPercent(), 5);
}

function testGetCurrentQuarterIndex()public{
uint256 startBlock = judgeStaking.stakingPoolStartBlock();
assertEq(judgeStaking.getCurrentQuarterIndex(), 1);

vm.roll(startBlock + 648_000);
assertEq(judgeStaking.getCurrentQuarterIndex(), 2);

vm.roll(startBlock + 1_296_000);
assertEq(judgeStaking.getCurrentQuarterIndex(), 3);
}

function testCalculateCurrentRewardsPerBlock()public{
bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
bytes32 rewardsPerBlockAdmin = judgeStaking.REWARDS_PER_BLOCK_CALCULATOR();
uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
uint256 firstQuarterRewards = 1_000_000 * 10 ** uint256(decimals);

judgeToken.approve(address(judgeTreasury), 40_000 * 10 ** uint256(decimals));
judgeTreasury.grantRole(treasuryAdmin, owner);
judgeTreasury.grantRole(fundManager, owner);
judgeStaking.grantRole(rewardsPerBlockAdmin, address(judgeTreasury));

vm.roll(poolStartBlock);
judgeTreasury.setNewQuarterlyRewards(firstQuarterRewards);
judgeTreasury.fundRewardsManager(1);
uint256 totalRewards = firstQuarterRewards;

uint256 remainingRewards = totalRewards - judgeStaking.quarterAccruedRewardsForStakes(1);
uint256 lastRewardBlock = judgeStaking.lastRewardBlock();
uint256 quarterEnd = poolStartBlock + 648_000;
uint256 numberOfBlocksLeft = quarterEnd - lastRewardBlock;
uint256 rewardPerBlock = remainingRewards / numberOfBlocksLeft;
vm.prank(address(judgeTreasury));
assertEq(judgeStaking.rewardsPerBlock(), rewardPerBlock);

vm.roll(poolStartBlock + 655_200);
vm.prank(address(judgeTreasury));
assertEq(judgeStaking.calculateCurrentRewardsPerBlock(), 0);
}

function testGetCurrentAPR()public{
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
uint256 rewardsPerBlock = judgeStaking.rewardsPerBlock();
vm.store(address(judgeStaking), bytes32(uint256(12)), bytes32(assumedTotalStakeWeight));
uint256 blocksPerYear = 365 days / 12;
uint256 apr1 = (rewardsPerBlock * blocksPerYear * 1e18) / judgeStaking.totalStakeWeight();

assertEq(judgeStaking.getCurrentAPR(), apr1);

vm.roll(poolStartBlock + 255_000);
judgeToken.approve(address(judgeTreasury), 40_000 * 10 ** uint256(decimals));
judgeTreasury.addBonusToQuarterReward(additionalRewards, 100_000);
uint256 bonusRewardsPerBlock = judgeStaking.bonusPerBlock();
uint256 apr2 = (bonusRewardsPerBlock * blocksPerYear * 1e18) / judgeStaking.totalStakeWeight();
assertEq(judgeStaking.getCurrentAPR(), apr1 + apr2);
}

function testUpdateFeePercent()public{
    assertEq(judgeStaking.feePercent(), 0);
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

vm.expectRevert(ValueHigherThanThreshold.selector);
judgeStaking.updateFeePercent(feePercentHigherThanThreshold);

judgeStaking.updateFeePercent(newFeePercent);
assertEq(judgeStaking.feePercent(), newFeePercent);
}

function testUpdateJudgeRecoveryMinimumThreshold()public{
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
judgeStaking.updateJudgeRecoveryMinimumThreshold(newJudgeRecoveryMinimumThreshold);

judgeStaking.updateJudgeRecoveryMinimumThreshold(newJudgeRecoveryMinimumThreshold);
assertEq(judgeStaking.judgeRecoveryMinimumThreshold(), newJudgeRecoveryMinimumThreshold);
}

function testDeposit()public{
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
uint256 invalidDepositAmount;
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
uint32 zeroLockUpPeriod;
uint32 higherThanMaxLockUpPeriod = 361;
judgeToken.mint(user1, amount);

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
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).amountStaked, depositAmount);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpPeriod, lockUpPeriod);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).depositBlockNumber, blockNumber);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).maturityBlockNumber, blockNumber + (lockUpPeriod*7200));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).stakeWeight, depositAmount/2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpRatio, Math.mulDiv(lockUpPeriod, 1e18, 360));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).rewardDebt, Math.mulDiv(depositAmount/2 , accJudgePerShare, 1e18));
assertEq(judgeStaking.totalStaked(), depositAmount);
assertEq(judgeToken.balanceOf(user1), amount - depositAmount);

vm.startPrank(user1);
judgeToken.approve(address(judgeStaking), depositAmount2);
uint256 blockNumber2 = block.number;
judgeStaking.deposit(depositAmount2, lockUpPeriod2);

vm.stopPrank();
uint256 accJudgePerShare2 = judgeStaking.accJudgePerShare();
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).id, 2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).amountStaked, depositAmount2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).lockUpPeriod, lockUpPeriod2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).depositBlockNumber, blockNumber2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).maturityBlockNumber, blockNumber2 + (lockUpPeriod2 * 7200));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).stakeWeight, depositAmount2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).lockUpRatio, Math.mulDiv(lockUpPeriod2, 1e18, 360));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).rewardDebt, Math.mulDiv(depositAmount2 , accJudgePerShare2, 1e18));
assertEq(judgeStaking.totalStaked(), depositAmount + depositAmount2);
assertEq(judgeToken.balanceOf(user1), amount - depositAmount - depositAmount2);
}

function logRewards(address user, uint256 balanceAfter, uint256 balanceBefore, string memory label) internal pure returns(uint256){
    console.log(label, balanceAfter - balanceBefore);
    return balanceAfter - balanceBefore;
}

function testClaimRewards()public{
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 amount2 = 150_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 80_000 * 10 ** uint256(decimals);
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
judgeToken.mint(user1, amount);
judgeToken.mint(user2, amount);
judgeToken.mint(user3, amount2);

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

judgeTreasury.setNewQuarterlyRewards(1_000_000 * 10 ** uint256(decimals));
judgeTreasury.fundRewardsManager(1);
uint256 rewardsPerBlock = judgeStaking.rewardsPerBlock();
console.log("rewardsPerblock", rewardsPerBlock);

vm.roll(poolStartBlock + 100_000);
console.log("blockcount1", block.number);

vm.prank(user1);
judgeStaking.claimRewards(0);

uint256 accJudgePerShareAfter100kBlocks = judgeStaking.accJudgePerShare();
console.log("AccJudgePerShareAfter100kBlocks", accJudgePerShareAfter100kBlocks);
uint256 user1BalanceAfterFirstClaim = judgeToken.balanceOf(user1);
logRewards(user1, user1BalanceAfterFirstClaim, user1BalanceAfterDeposit, "user1 first rewards");

vm.prank(user2);
judgeStaking.claimRewards(0);

uint256 user2BalanceAfterFirstClaim = judgeToken.balanceOf(user2);
logRewards(user2, user2BalanceAfterFirstClaim, user2BalanceAfterDeposit, "user2 first rewards");

vm.prank(user3);
judgeStaking.claimRewards(0);

uint256 user3BalanceAfterFirstClaim = judgeToken.balanceOf(user3);
logRewards(user3, user3BalanceAfterFirstClaim, user3BalanceAfterDeposit, "user3 first Rewards");


assertEq(user3BalanceAfterFirstClaim - user3BalanceAfterDeposit, user2BalanceAfterFirstClaim - user2BalanceAfterDeposit);

uint256 rewardsManagerBal = judgeToken.balanceOf(address(rewardsManager));
console.log("rewardsManager balance", rewardsManagerBal);

vm.roll(poolStartBlock + 150_000);
console.log("blockcount2", block.number);

uint256 rewardPerBlock = judgeStaking.rewardsPerBlock();
console.log("rewardsPerBlock", rewardPerBlock);

uint256 accumuJudgePershareBeforeSecondClaim = judgeStaking.accJudgePerShare();
console.log("AccumuJudgePerShareBeforeSecondClaim", accumuJudgePershareBeforeSecondClaim);

vm.prank(user1);
judgeStaking.claimRewards(0);

uint256 accumuJudgePershareAfterSecondClaim = judgeStaking.accJudgePerShare();
console.log("AccumuJudgePerShareAfterSecondClaim", accumuJudgePershareAfterSecondClaim);

uint256 user1BalanceAfterSecondClaim = judgeToken.balanceOf(user1);
logRewards(user1, user1BalanceAfterSecondClaim, user1BalanceAfterFirstClaim, "user1 second rewards");

vm.prank(user2);
judgeStaking.claimRewards(0);

uint256 user2BalanceAfterSecondClaim = judgeToken.balanceOf(user2);
logRewards(user2, user2BalanceAfterSecondClaim, user2BalanceAfterFirstClaim, "user2 second rewards");

}

function testClaimRewardsAfterAddingBonus()public{
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 amount2 = 150_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 80_000 * 10 ** uint256(decimals);
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
judgeToken.mint(user1, amount);
judgeToken.mint(user2, amount);
judgeToken.mint(user3, amount2);

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

judgeTreasury.setNewQuarterlyRewards(1_000_000 * 10 ** uint256(decimals));
judgeTreasury.fundRewardsManager(1);
uint256 rewardsPerBlock = judgeStaking.rewardsPerBlock();
console.log("rewardsPerblock", rewardsPerBlock);

vm.roll(poolStartBlock + 100_000);
console.log("blockcount1", block.number);

vm.prank(user1);
judgeStaking.claimRewards(0);

uint256 accJudgePerShareAfter100kBlocks = judgeStaking.accJudgePerShare();
console.log("AccJudgePerShareAfter100kBlocks", accJudgePerShareAfter100kBlocks);
uint256 user1BalanceAfterFirstClaim = judgeToken.balanceOf(user1);
logRewards(user1, user1BalanceAfterFirstClaim, user1BalanceAfterDeposit, "user1 first rewards");

vm.prank(user2);
judgeStaking.claimRewards(0);

uint256 user2BalanceAfterFirstClaim = judgeToken.balanceOf(user2);
logRewards(user2, user2BalanceAfterFirstClaim, user2BalanceAfterDeposit, "user2 first rewards");

uint newMintAmount = 500_000 * 10 ** uint256(decimals);
judgeToken.mint(owner, newMintAmount);
judgeToken.approve(address(judgeTreasury), newMintAmount);
judgeTreasury.addBonusToQuarterReward(newMintAmount, 100_000);

vm.startPrank(user3);
judgeToken.approve(address(judgeStaking), depositAmount2);
judgeStaking.deposit(depositAmount2, lockUpPeriod);
uint256 user3BalanceAfterDeposit = judgeToken.balanceOf(user3);
vm.stopPrank();

vm.roll(poolStartBlock + 200_000);
console.log("blockcount2", block.number);

uint256 newRewardsPerBlock = judgeStaking.rewardsPerBlock();
console.log("newRewardsPerBlock", newRewardsPerBlock);

uint256 accumuJudgePershare = judgeStaking.accJudgePerShare();
console.log("AccumuJudgePerBeforeThirdClaim", accumuJudgePershare);

uint256 bonusRewardPerBlock = judgeStaking.bonusPerBlock();
console.log("BonusRewardPerBlock", bonusRewardPerBlock);

uint256 accBonusJudgePerShare = judgeStaking.accBonusJudgePerShare();
console.log("AccBonusJudgePerShareBeforeSecondClaim", accBonusJudgePerShare);

vm.prank(user1);
judgeStaking.claimRewards(0);

uint256 accumuJudgePershareAfterClaim = judgeStaking.accJudgePerShare();
console.log("AccumuJudgePerShareAfterSecondClaim", accumuJudgePershareAfterClaim);

uint256 accBonusJudgePerShareAfterClaim = judgeStaking.accBonusJudgePerShare();
console.log("AccBonusJudgePerShareAfterSecondClaim", accBonusJudgePerShareAfterClaim);

uint256 user1BalanceAfterSecondClaim = judgeToken.balanceOf(user1);
logRewards(user1, user1BalanceAfterSecondClaim, user1BalanceAfterFirstClaim, "user1 second rewards");

vm.prank(user2);
judgeStaking.claimRewards(0);

uint256 user2BalanceAfterSecondClaim = judgeToken.balanceOf(user2);
logRewards(user2, user2BalanceAfterSecondClaim, user2BalanceAfterFirstClaim, "user2 second rewards");

vm.prank(user3);
judgeStaking.claimRewards(0);
uint256 user3BalanceAfterFirstClaim = judgeToken.balanceOf(user3);
logRewards(user3, user3BalanceAfterFirstClaim, user3BalanceAfterDeposit, "user3 first rewards");
}

function testClaimRewardsInSecondQuarter()public{
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 amount2 = 150_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 80_000 * 10 ** uint256(decimals);
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
judgeToken.mint(user1, amount);
judgeToken.mint(user2, amount);
judgeToken.mint(user3, amount2);

vm.startPrank(user1);

vm.roll(poolStartBlock);
judgeToken.approve(address(judgeStaking), depositAmount);
judgeStaking.deposit(depositAmount, lockUpPeriod);
vm.stopPrank();

vm.startPrank(user2);
judgeToken.approve(address(judgeStaking), depositAmount);
judgeStaking.deposit(depositAmount, lockUpPeriod2);
vm.stopPrank();

judgeTreasury.setNewQuarterlyRewards(1_000_000 * 10 ** uint256(decimals));
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
judgeToken.mint(owner, newMintAmount);
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
uint256 user1BalanceBeforeEndOfFirstQuarter = judgeToken.balanceOf(user1);

uint256 accJudgePerShare = judgeStaking.accJudgePerShare();
uint256 accBonusJudgePerShare = judgeStaking.accBonusJudgePerShare();
console.log("accJudgePerShare", accJudgePerShare);
console.log("accBonusJudgePerShare", accBonusJudgePerShare);

vm.prank(user2);
judgeStaking.claimRewards(0);
uint256 user2BalanceBeforeEndOfFirstQuarter = judgeToken.balanceOf(user2);

vm.prank(user3);
judgeStaking.claimRewards(0);
uint256 user3BalanceBeforeEndOfFirstQuarter = judgeToken.balanceOf(user3);

uint256 secondBonus = 300_000 * 10 ** uint256(decimals);
judgeTreasury.addBonusToQuarterReward(secondBonus, 100_000);
vm.roll(poolStartBlock + 698_000);
vm.prank(user1);
judgeStaking.claimRewards(0);
uint256 user1BalanceinSecondQuarter = judgeToken.balanceOf(user1);
logRewards(user1, user1BalanceinSecondQuarter, user1BalanceBeforeEndOfFirstQuarter, "user1 second quarter rewards");

vm.prank(user2);
judgeStaking.claimRewards(0);
uint256 user2BalanceinSecondQuarter = judgeToken.balanceOf(user2);
logRewards(user2, user2BalanceinSecondQuarter, user2BalanceBeforeEndOfFirstQuarter, "user2 second quarter rewards");

vm.prank(user3);
judgeStaking.claimRewards(0);
uint256 user3BalanceinSecondQuarter = judgeToken.balanceOf(user3);
logRewards(user3, user3BalanceinSecondQuarter, user3BalanceBeforeEndOfFirstQuarter, "user3 second quarter rewards");
}

function testWithdraw()public{

}

function testWithdrawAll()public{

}

function testEarlyWithdraw()public{

}

function testEmergencyWithdraw()public{

}

function testViewMyStakes()public{
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
judgeToken.mint(user1, amount);

vm.startPrank(user1);
judgeToken.approve(address(judgeStaking), amount);
uint256 blockNumber = block.number;
judgeStaking.deposit(depositAmount, lockUpPeriod);
vm.stopPrank();

vm.roll(blockNumber + 60);
uint256 blockNumber2 = block.number;

vm.startPrank(user1);
judgeStaking.deposit(depositAmount2, lockUpPeriod2);

JudgeStaking.userStake[] memory myStakes = judgeStaking.viewMyStakes();
assertEq(myStakes.length, 2);
assertEq(myStakes[0].id, 1);
assertEq(myStakes[0].amountStaked, depositAmount);
assertEq(myStakes[0].lockUpPeriod, lockUpPeriod);
assertEq(myStakes[0].depositBlockNumber, blockNumber);
assertEq(myStakes[0].maturityBlockNumber, blockNumber + (lockUpPeriod * 7200));

assertEq(myStakes[1].id, 2);
assertEq(myStakes[1].amountStaked, depositAmount2);
assertEq(myStakes[1].lockUpPeriod, lockUpPeriod2);
assertEq(myStakes[1].depositBlockNumber, blockNumber2);
assertEq(myStakes[1].maturityBlockNumber, blockNumber2 + (lockUpPeriod2 * 7200));
}

function testViewMyStakesAtIndex()public{
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
judgeToken.mint(user1, amount);

vm.startPrank(user1);
judgeToken.approve(address(judgeStaking), amount);
uint256 blockNumber = block.number;
judgeStaking.deposit(depositAmount, lockUpPeriod);
uint256 accJudgePerShare = judgeStaking.accJudgePerShare();

vm.expectRevert(InvalidIndex.selector);
judgeStaking.viewMyStakeAtIndex(1);
assertEq(judgeStaking.viewMyStakeAtIndex(0).id, 1);
assertEq(judgeStaking.viewMyStakeAtIndex( 0).amountStaked, depositAmount);
assertEq(judgeStaking.viewMyStakeAtIndex( 0).lockUpPeriod, lockUpPeriod);
assertEq(judgeStaking.viewMyStakeAtIndex( 0).depositBlockNumber, blockNumber);
assertEq(judgeStaking.viewMyStakeAtIndex( 0).maturityBlockNumber, blockNumber + (lockUpPeriod * 7200));
assertEq(judgeStaking.viewMyStakeAtIndex( 0).stakeWeight, depositAmount/2);
assertEq(judgeStaking.viewMyStakeAtIndex( 0).lockUpRatio, Math.mulDiv(lockUpPeriod, 1e18, 360));
assertEq(judgeStaking.viewMyStakeAtIndex( 0).rewardDebt, Math.mulDiv(depositAmount/2 , accJudgePerShare, 1e18));
vm.roll(blockNumber + 60);

uint256 blockNumber2 = block.number;
judgeStaking.deposit(depositAmount2, lockUpPeriod2);
uint256 accJudgePerShare2 = judgeStaking.accJudgePerShare();
assertEq(judgeStaking.viewMyStakeAtIndex(1).id, 2);
assertEq(judgeStaking.viewMyStakeAtIndex( 1).amountStaked, depositAmount2);
assertEq(judgeStaking.viewMyStakeAtIndex( 1).lockUpPeriod, lockUpPeriod2);
assertEq(judgeStaking.viewMyStakeAtIndex( 1).depositBlockNumber, blockNumber2);
assertEq(judgeStaking.viewMyStakeAtIndex( 1).maturityBlockNumber, blockNumber2 + (lockUpPeriod2 * 7200));
assertEq(judgeStaking.viewMyStakeAtIndex( 1).stakeWeight, depositAmount2);
assertEq(judgeStaking.viewMyStakeAtIndex( 1).lockUpRatio, Math.mulDiv(lockUpPeriod2, 1e18, 360));
assertEq(judgeStaking.viewMyStakeAtIndex( 1).rewardDebt, Math.mulDiv(depositAmount2, accJudgePerShare2, 1e18));
}

function testViewUsersList()public{
bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 amount2 = 150_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 80_000 * 10 ** uint256(decimals);
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
uint256 poolStartBlock = judgeStaking.stakingPoolStartBlock();
judgeToken.mint(user1, amount);
judgeToken.mint(user2, amount);
judgeToken.mint(user3, amount2);

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
));
vm.prank(user2);
judgeStaking.viewUsersList();

address[] memory usersArray = judgeStaking.viewUsersList();
assertEq(usersArray[0], 0x29E3b139f4393aDda86303fcdAa35F60Bb7092bF);
assertEq(usersArray[1], 0x537C8f3d3E18dF5517a58B3fB9D9143697996802);
assertEq(usersArray[2], 0xc0A55e2205B289a967823662B841Bd67Aa362Aec);
}

function testViewUserStakes()public{
bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
judgeToken.mint(user1, amount);

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
));
vm.prank(user2);
judgeStaking.viewUserStakes(user1);

vm.expectRevert(InvalidAddress.selector);
judgeStaking.viewUserStakes(zeroAddress);

JudgeStaking.userStake[] memory user1Stakes = judgeStaking.viewUserStakes(user1);

assertEq(user1Stakes.length, 2);
assertEq(user1Stakes[0].id, 1);
assertEq(user1Stakes[0].amountStaked, depositAmount);
assertEq(user1Stakes[0].lockUpPeriod, lockUpPeriod);
assertEq(user1Stakes[0].depositBlockNumber, blockNumber);
assertEq(user1Stakes[0].maturityBlockNumber, blockNumber + (lockUpPeriod * 7200));

assertEq(user1Stakes[1].id, 2);
assertEq(user1Stakes[1].amountStaked, depositAmount2);
assertEq(user1Stakes[1].lockUpPeriod, lockUpPeriod2);
assertEq(user1Stakes[1].depositBlockNumber, blockNumber2);
assertEq(user1Stakes[1].maturityBlockNumber, blockNumber2 + (lockUpPeriod2 * 7200));
}

function testViewUserStakeAtIndex()public{
bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
uint256 amount = 100_000 * 10 ** uint256(decimals);
uint256 depositAmount = 40_000 * 10 ** uint256(decimals);
uint256 depositAmount2 = 35_000 * 10 ** uint256(decimals);
uint32 lockUpPeriod = 180;
uint32 lockUpPeriod2 = 360;
judgeToken.mint(user1, amount);

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
));
vm.prank(user2);
judgeStaking.viewUserStakeAtIndex(user1, 0);

vm.expectRevert(InvalidAddress.selector);
judgeStaking.viewUserStakeAtIndex(zeroAddress, 0);

vm.expectRevert(InvalidIndex.selector);
judgeStaking.viewUserStakeAtIndex(user1, 1);

uint256 accJudgePerShare = judgeStaking.accJudgePerShare();
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).id, 1);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).amountStaked, depositAmount);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpPeriod, lockUpPeriod);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).depositBlockNumber, blockNumber);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).maturityBlockNumber, blockNumber + (lockUpPeriod * 7200));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).stakeWeight, depositAmount/2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpRatio, Math.mulDiv(lockUpPeriod, 1e18, 360));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).rewardDebt, Math.mulDiv(depositAmount/2 , accJudgePerShare, 1e18));

vm.roll(blockNumber + 60);

uint256 blockNumber2 = block.number;

vm.prank(user1);
judgeStaking.deposit(depositAmount2, lockUpPeriod2);
uint256 accJudgePerShare2 = judgeStaking.accJudgePerShare();
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).id, 2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).amountStaked, depositAmount2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).lockUpPeriod, lockUpPeriod2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).depositBlockNumber, blockNumber2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).maturityBlockNumber, blockNumber2 + (lockUpPeriod2 * 7200));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).stakeWeight, depositAmount2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).lockUpRatio, Math.mulDiv(lockUpPeriod2, 1e18, 360));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 1).rewardDebt, Math.mulDiv(depositAmount2, accJudgePerShare2, 1e18));
}

function testViewMyPendingRewards()public{

}

function testCalculateMisplacedJudge()public{

}

function testRecoverMisplacedJudge()public{

}

function testRecoverErc20()public{

}

function testtransferFeesFromOtherTokensOutOfStaking()public{

}    
}
