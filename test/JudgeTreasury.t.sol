// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeTreasury.sol";
import "../src/RewardsManager.sol";

contract JudgeTreasuryTest is Test{
JudgeToken public judgeToken;
JudgeTreasury public judgeTreasury;
RewardsManager public rewardsManager;
address public owner;
address public user1;
address public user2;
address public user3;
address public zeroAddress;
uint8 private decimals = 18;
uint256 public initialSupply = 100_000 * 10 ** decimals;

error EOANotAllowed();
error InvalidAddress();
error CannotInputThisContractAddress();
error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
error TotalStakingRewardAllocationExceeded();
error ExceedsRemainingAllocation();
error AmountExceedsMintable();

function setUp() public {
owner = address(this);
user1 = makeAddr("user1");
user2 = makeAddr("user2");
user3 = makeAddr("user3");
zeroAddress = address(0);

judgeToken = new JudgeToken(initialSupply);
rewardsManager = new RewardsManager(address(judgeToken));
judgeTreasury = new JudgeTreasury(address(judgeToken), address(rewardsManager));
bytes32 minterRole = judgeToken.MINTER_ROLE();
judgeToken.grantRole(minterRole, address(judgeTreasury));
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
    bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
    judgeTreasury.grantRole(treasuryAdmin, owner);
    vm.expectRevert(EOANotAllowed.selector);
judgeTreasury.updateKeyParameter(user1);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.updateKeyParameter(zeroAddress);

vm.expectRevert(CannotInputThisContractAddress.selector);
judgeTreasury.updateKeyParameter(address(judgeTreasury));

vm.expectRevert(
    abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector,
    user1,
    treasuryAdmin)
);
vm.prank(user1);
judgeTreasury.updateKeyParameter(user2);

// using judgeToken contract as example for input. Test purposes only
judgeTreasury.updateKeyParameter(address(judgeToken));
assertEq(address(judgeTreasury.rewardsManager()), address(judgeToken));
}

function testFundRewardsManager() public{
    uint256 MAX_ALLOCATION = judgeToken.MAX_STAKING_REWARD_ALLOCATION();
    uint256 newStakingRewardsFundFromTreasury = 49_000_000 * 10 ** uint256(decimals);
    bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
vm.expectRevert(abi.encodeWithSelector(
    AccessControlUnauthorizedAccount.selector,
    owner,
    fundManager
));
judgeTreasury.fundRewardsManager();

judgeTreasury.grantRole(fundManager, owner);
judgeTreasury.fundRewardsManager();
assertEq(judgeTreasury.stakingRewardsFundsFromTreasury(), judgeTreasury.quarterlyReward());

vm.store(address(judgeTreasury), bytes32(uint256(4)), bytes32(MAX_ALLOCATION));
vm.expectRevert(TotalStakingRewardAllocationExceeded.selector);
judgeTreasury.fundRewardsManager();

vm.store(address(judgeTreasury), bytes32(uint256(4)), bytes32(newStakingRewardsFundFromTreasury));
vm.expectRevert(ExceedsRemainingAllocation.selector);
judgeTreasury.fundRewardsManager();
}

function testMintToTreasuryReserve() public{
 bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
 uint256 amount = 2_000_000 * 10 * 10 ** uint256(decimals);
 uint assumedMintable = 1_000_000 * 10 * 10 ** uint256(decimals);
vm.expectRevert(abi.encodeWithSelector(
    AccessControlUnauthorizedAccount.selector,
    owner,
    fundManager
));
judgeTreasury.mintToTreasuryReserve(amount);

judgeTreasury.grantRole(fundManager, owner);
judgeTreasury.mintToTreasuryReserve(amount);
assertEq(judgeToken.balanceOf(address(judgeTreasury)), amount);

vm.store(address(judgeToken), bytes32(uint256(12)), bytes32(assumedMintable));
vm.expectRevert(AmountExceedsMintable.selector);
judgeTreasury.mintToTreasuryReserve(amount);
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