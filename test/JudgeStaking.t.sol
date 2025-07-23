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

function setUp()public{
    owner = address(this);
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
    bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
    bytes32 rewardsManagerPreciseBalanceUpdater = rewardsManager.REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
    bytes32 treasuryPreciseBalanceUpdater = judgeTreasury.TREASURY_PRECISE_BALANCE_UPDATER();
    
    judgeStaking.setKeyParameters(address(rewardsManager), address(judgeTreasury));
    rewardsManager.setKeyParameter(address(judgeTreasury));

    rewardsManager.grantRole(rewardsManagerPreciseBalanceUpdater, address(judgeTreasury));
     judgeTreasury.grantRole(treasuryPreciseBalanceUpdater, address(judgeStaking));
     judgeToken.grantRole(minterRole, address(judgeTreasury));
     judgeStaking.grantRole(stakingAdmin, owner);
}

function testDeployerIsOwner()public{

} 

function testSetKeyParameters()public{

}

function testUpdateEarlyWithdrawalPercent()public{

}

function testCalculateRewardsPerBlock()public{

}

function testUpdateFeePercent()public{

}

function testUpdateJudgeRecoveryMinimumThreshold()public{

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
