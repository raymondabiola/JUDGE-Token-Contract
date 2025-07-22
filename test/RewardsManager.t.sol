// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeTreasury.sol";
import "../src/JudgeStaking.sol";

contract RewardsManagerTest is Test{
    JudgeToken public judgeToken;
    RewardsManager public rewardsManager;
    JudgeTreasury public judgeTreasury;
    JudgeStaking public judgeStaking;

    address public owner;
    address public zeroAddress;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {

    }

    function testSetKeyParameters()public{

    }

    function testUpdateFeePercent()public{

    }

    function testUpdateJudgeRecoveryMinimumThreshold()public{
        
    }

    function testSendRewards()public{

    }

    function testAdminWithdrawal()public{

    }

    function testEmergencyWithdrawal()public{

    }

    function testCalculateMisplacedJudge()public{

    }

    function testRecoverMisplacedJudge()public{

    }

    function testRecoverErc20()public{

    }

    function testTransferFeesFromOtherTokensOutOfTreasury()public {

    }
}