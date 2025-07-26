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

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error InvalidAddress();
    error CannotInputThisContractAddress();
    error EOANotAllowed();
    error InvalidAmount();
    error ValueTooHigh();
    error ValueHigherThanThreshold();
    error OverPaidRewards();
    error InvalidLockUpPeriod();

function setUp()public{
    owner = address(this);
    console.log(owner, "owner address");
    zeroAddress = address(0);
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");
    user3 = makeAddr("user3");


    judgeToken = new JudgeToken(initialSupply);
    judgeStaking = new JudgeStaking(address(judgeToken), earlyWithdrawalPercent);
    rewardsManager = new RewardsManager(address(judgeToken));
    judgeTreasury = new JudgeTreasury(address(judgeToken), address(rewardsManager), address(judgeStaking));
    sampleERC20 = new SampleERC20();
    
    bytes32 minterRole = judgeToken.MINTER_ROLE();
    bytes32 rewardsManagerPreciseBalanceUpdater = rewardsManager.REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
    bytes32 treasuryPreciseBalanceUpdater = judgeTreasury.TREASURY_PRECISE_BALANCE_UPDATER();
    bytes32 rewardsManagerAdmin = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
    bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
    judgeStaking.grantRole(stakingAdmin, owner);
    rewardsManager.grantRole(rewardsManagerAdmin, owner);
    judgeStaking.setKeyParameters(address(rewardsManager), address(judgeTreasury));
    rewardsManager.setKeyParameter(address(judgeTreasury));

    rewardsManager.grantRole(rewardsManagerPreciseBalanceUpdater, address(judgeTreasury));
     judgeTreasury.grantRole(treasuryPreciseBalanceUpdater, address(judgeStaking));
     judgeToken.grantRole(minterRole, address(judgeTreasury)); 
     judgeToken.grantRole(minterRole, owner);
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
uint256 startTime = judgeStaking.stakingPoolStartTime();
assertEq(judgeStaking.getCurrentQuarterIndex(), 1);

vm.warp(startTime + 90 days);
assertEq(judgeStaking.getCurrentQuarterIndex(), 2);

vm.warp(startTime + 180 days);
assertEq(judgeStaking.getCurrentQuarterIndex(), 3);
}

function testCalculateCurrentRewardsPerBlock()public{
bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
uint256 poolStartTime = judgeStaking.stakingPoolStartTime();
uint256 firstQuarterRewards = 1_000_000 * 10 ** uint256(decimals);
uint256 additionalRewards = 20_000 * 10 ** uint256(decimals);

judgeToken.approve(address(judgeTreasury), 40_000 * 10 ** uint256(decimals));
judgeTreasury.grantRole(treasuryAdmin, owner);
judgeTreasury.grantRole(fundManager, owner);

vm.warp(poolStartTime);
judgeTreasury.setNewQuarterlyRewards(firstQuarterRewards);
judgeTreasury.fundRewardsManager(1);
judgeTreasury.addToQuarterReward(additionalRewards);
uint256 totalRewards = firstQuarterRewards + additionalRewards;
uint256 assumedTotalCurrentQuarterRewardspaid1 = 1_020_001 * 10 ** uint256(decimals);
uint256 assumedTotalCurrentQuarterRewardspaid2 = 400_000 * 10 ** uint256(decimals);
uint256 baseSlotQuarterlyRewardsPaid = 21;
bytes32 firstQuarterRewardsPaidSlot = keccak256(abi.encode(1, uint256(baseSlotQuarterlyRewardsPaid)));
vm.store(address(judgeStaking), firstQuarterRewardsPaidSlot, bytes32(assumedTotalCurrentQuarterRewardspaid1));

vm.expectRevert(OverPaidRewards.selector);
judgeStaking.calculateCurrentRewardsPerBlock();

vm.warp(poolStartTime + 40 days);
vm.store(address(judgeStaking), firstQuarterRewardsPaidSlot, bytes32(assumedTotalCurrentQuarterRewardspaid2));
uint256 remainingRewards = totalRewards - assumedTotalCurrentQuarterRewardspaid2;
uint256 remainingTime = 50 days;
uint256 numberOfBlocksLeft = remainingTime / 12;
uint256 rewardPerBlock = remainingRewards / numberOfBlocksLeft;
assertEq(judgeStaking.calculateCurrentRewardsPerBlock(), rewardPerBlock);

vm.warp(poolStartTime + 91 days);
assertEq(judgeStaking.calculateCurrentRewardsPerBlock(), 0);
}

function testGetCurrentAPR()public{
bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
uint256 poolStartTime = judgeStaking.stakingPoolStartTime();
uint256 firstQuarterRewards = 1_000_000 * 10 ** uint256(decimals);
uint256 additionalRewards = 20_000 * 10 ** uint256(decimals);

judgeTreasury.grantRole(treasuryAdmin, owner);
judgeTreasury.grantRole(fundManager, owner);
judgeStaking.grantRole(stakingAdmin, owner);

vm.warp(poolStartTime);
judgeTreasury.setNewQuarterlyRewards(firstQuarterRewards);
judgeTreasury.fundRewardsManager(1);

uint256 assumedTotalStaked = 10_000_000 * 10 ** uint256(decimals);
uint256 rewardsPerBlock1 = judgeStaking.calculateCurrentRewardsPerBlock();
vm.store(address(judgeStaking), bytes32(uint256(12)), bytes32(assumedTotalStaked));
uint256 apr1 = (rewardsPerBlock1 * 365 days / 12 * 1e18) / judgeStaking.totalStaked();

assertEq(judgeStaking.getCurrentAPR(), apr1);

uint256 assumedTotalCurrentQuarterRewardspaid1 = 400_000 * 10 ** uint256(decimals);
uint256 baseSlotQuarterlyRewardsPaid = 21;
bytes32 firstQuarterRewardsPaidSlot = keccak256(abi.encode(1, uint256(baseSlotQuarterlyRewardsPaid)));

vm.warp(poolStartTime + 40 days);
judgeToken.approve(address(judgeTreasury), 40_000 * 10 ** uint256(decimals));
judgeTreasury.addToQuarterReward(additionalRewards);
vm.store(address(judgeStaking), firstQuarterRewardsPaidSlot, bytes32(assumedTotalCurrentQuarterRewardspaid1));
uint256 rewardsPerBlock2 = judgeStaking.calculateCurrentRewardsPerBlock();
uint256 apr2 = (rewardsPerBlock2 * 365 days / 12 * 1e18) / judgeStaking.totalStaked();
assertEq(judgeStaking.getCurrentAPR(), apr2);
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
uint256 invalidDepositAmount;
uint32 lockUpPeriod = 180;
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
uint256 timeStamp = block.timestamp;
judgeStaking.deposit(depositAmount, lockUpPeriod);
vm.stopPrank();
uint256 accJudgePerShare = judgeStaking.accJudgePerShare();
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).id, 1);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).amountStaked, depositAmount);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpPeriod, lockUpPeriod);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).depositTimestamp, timeStamp);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).maturityTimestamp, timeStamp + lockUpPeriod);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).calculatedStakeForReward, depositAmount/2);
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).lockUpRatio, Math.mulDiv(lockUpPeriod, 1e18, 360));
assertEq(judgeStaking.viewUserStakeAtIndex(user1, 0).rewardDebt, Math.mulDiv(depositAmount/2 , accJudgePerShare, 1e18));
}

function testClaimRewards()public{

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

}

function testViewStakeAtIndex()public{

}

function testViewUsersList()public{

}

function testViewUserStakes()public{

}

function testViewUsersStakesAtIndex()public{

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
