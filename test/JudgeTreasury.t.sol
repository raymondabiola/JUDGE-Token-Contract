// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/RewardsManager.sol";

contract JudgeTreasuryTest is Test{
JudgeToken public judgeToken;
JudgeTreasury public judgeTreasury;
RewardsManager public rewardsManager;
address public owner;
address public user1;
address public user2;
address public user3;
uint8 private decimals = 18;
uint256 public initialSupply = 100_000 * 10 ** decimals;

function setUp() public {
owner = address(this);
user1 = makeAddr("user1");
user2 = makeAddr("user2");
user3 = makeAddr("user3");

judgeToken = new JudgeToken(initialSupply);
rewardsManager = new RewardsManager(address(judgeToken));
judgeTreasury = new JudgeTreasury(address(judgeToken), address(rewardsManager));
}

function testQuarterlyReward() public{
    uint256 expectedQuarterlyReward = 1_250_000 * 10 ** uint256(decimals);
assertEq(judgeTreasury.quarterlyReward(), expectedQuarterlyReward);
}

function testDecimals() public{
assertEq(judgeTreasury.decimals(), decimals);
}

function testDeployerIsOwner() public{
bytes32 defaultAdmin = judgeTreasury.DEFAULT_ADMIN_ROLE();
assertTrue(judgeTreasury.hasRole(defaultAdmin, owner));
}

function testUpdateKeyParameter() public{

}

function testFundRewardsManager() public{

}

function testMintToTreasuryReserve() public{

}

function testTeamFunding() public{

}

function testTransferFromTreasury() public{

}

function testCalculateMisplacedJudge() public{

}

function testRecoverMisplacedJudge() public{

}

function testRecoverERC20() public{

}
}