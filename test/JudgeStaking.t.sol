// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeStaking.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeTreasury.sol";
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
    judgeTreasury = new JudgeTreasury(address(judgeToken), address(rewardsManager));
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

function testCalculateRewardsPerBlock()public{

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
