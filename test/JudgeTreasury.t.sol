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
uint256 public initialSupply = 100_000 * 10 ** uint256(decimals);

error EOANotAllowed();
error InvalidAddress();
error InvalidAmount();
error InsufficientBalance();
error CannotInputThisContractAddress();
error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
error TotalStakingRewardAllocationExceeded();
error ExceedsRemainingAllocation();
error AmountExceedsMintable();
error TeamDevelopmentAllocationExceeded();

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
bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
judgeToken.grantRole(minterRole, address(judgeTreasury));
judgeTreasury.grantRole(treasuryAdmin, owner);
judgeTreasury.updateFeePercent(10);
judgeTreasury.updateJudgeRecoveryMinimumThreshold(200 * 10 ** uint256(decimals));
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

function testUpdateFeePercent()public{

}

function testUpdateJudgeRecoveryMinimumThreshold() public {

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
 uint256 invalidAmount;
 uint assumedMintable = 1_000_000 * 10 * 10 ** uint256(decimals);
vm.expectRevert(abi.encodeWithSelector(
    AccessControlUnauthorizedAccount.selector,
    owner,
    fundManager
));
judgeTreasury.mintToTreasuryReserve(amount);

judgeTreasury.grantRole(fundManager, owner);

vm.expectRevert(InvalidAmount.selector);
judgeTreasury.mintToTreasuryReserve(invalidAmount);

judgeTreasury.mintToTreasuryReserve(amount);
assertEq(judgeToken.balanceOf(address(judgeTreasury)), amount);

vm.store(address(judgeToken), bytes32(uint256(12)), bytes32(assumedMintable));
vm.expectRevert(AmountExceedsMintable.selector);
judgeTreasury.mintToTreasuryReserve(amount);
}

function testFundTeamDevelopment() public{
bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
uint256 amount = 2_000_000 * 10 ** uint256(decimals);
uint256 invalidAmount;
uint256 MAX_ALLOCATION = judgeToken.MAX_TEAM_ALLOCATION();
uint256 assumedTeamFundReceived = 49_000_000 * 10 ** uint256(decimals);


vm.expectRevert(abi.encodeWithSelector(
    AccessControlUnauthorizedAccount.selector,
    owner,
    fundManager
));
judgeTreasury.fundTeamDevelopment(owner, amount);

judgeTreasury.grantRole(fundManager, owner);
vm.expectRevert(InvalidAmount.selector);
judgeTreasury.fundTeamDevelopment(owner, invalidAmount);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.fundTeamDevelopment(zeroAddress, amount);

judgeTreasury.fundTeamDevelopment(owner, amount);
assertEq(judgeToken.balanceOf(owner), amount + initialSupply);

vm.store(address(judgeTreasury), bytes32(uint256(5)), bytes32(MAX_ALLOCATION));
vm.expectRevert(TeamDevelopmentAllocationExceeded.selector);
judgeTreasury.fundTeamDevelopment(owner, amount);

vm.store(address(judgeTreasury), bytes32(uint256(5)), bytes32(assumedTeamFundReceived));
vm.expectRevert(ExceedsRemainingAllocation.selector);
judgeTreasury.fundTeamDevelopment(owner, amount);
}

function testTransferFromTreasury() public{
bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
uint256 amount = 2_000_000 * 10 ** uint256(decimals);
uint256 amountToTransfer = 1_000_000 * 10 ** uint256(decimals);
uint256 amountHigherThanTreasuryBalance = 2_000_001 * 10 ** uint256(decimals);
uint256 invalidAmount;

judgeTreasury.grantRole(fundManager, owner);
judgeTreasury.mintToTreasuryReserve(amount);
vm.expectRevert(abi.encodeWithSelector(
    AccessControlUnauthorizedAccount.selector,
    user1,
    fundManager
));
vm.prank(user1);
judgeTreasury.transferFromTreasury(owner, amountToTransfer);

vm.expectRevert(InvalidAmount.selector);
judgeTreasury.transferFromTreasury(user1, invalidAmount);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.transferFromTreasury(zeroAddress, amountToTransfer);

vm.expectRevert(CannotInputThisContractAddress.selector);
judgeTreasury.transferFromTreasury(address(judgeTreasury), amountToTransfer);

vm.expectRevert(InsufficientBalance.selector);
judgeTreasury.transferFromTreasury(user1, amountHigherThanTreasuryBalance);

judgeTreasury.transferFromTreasury(user1, amountToTransfer);
assertEq(judgeToken.balanceOf(user1), amountToTransfer);
assertEq(judgeTreasury.treasuryPreciseBalance(), amount - amountToTransfer);
}

function testCalculateMisplacedJudge() public{
bytes32 tokenRecoveryAdmin = judgeTreasury.TOKEN_RECOVERY_ROLE();
bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
uint256 amount = 2_000_000 * 10 ** uint256(decimals);
uint256 amountToTransfer = 500_000 * 10 ** uint256(decimals);
uint256 misplacedAmount = 200_000 * 10 ** uint256(decimals);

judgeTreasury.grantRole(fundManager, owner);
judgeTreasury.mintToTreasuryReserve(amount);
judgeTreasury.transferFromTreasury(user2, amountToTransfer);

vm.prank(user2);
judgeToken.transfer(address(judgeTreasury), misplacedAmount);
judgeTreasury.grantRole(tokenRecoveryAdmin, owner);
assertEq(judgeTreasury.calculateMisplacedJudge(), misplacedAmount);

vm.expectRevert(abi.encodeWithSelector(
    AccessControlUnauthorizedAccount.selector,
    user2,
    tokenRecoveryAdmin
));
vm.prank(user2);
judgeTreasury.calculateMisplacedJudge();
}

function testRecoverMisplacedJudge() public{
bytes32 tokenRecoveryAdmin = judgeTreasury.TOKEN_RECOVERY_ROLE();
bytes32 fundManager = judgeTreasury.FUND_MANAGER_ROLE();
uint256 amount = 2_000_000 * 10 ** uint256(decimals);
uint256 amountToTransfer = 500_000 * 10 ** uint256(decimals);
uint256 misplacedAmount = 200_000 * 10 ** uint256(decimals);

judgeTreasury.grantRole(fundManager, owner);
judgeTreasury.mintToTreasuryReserve(amount);
judgeTreasury.transferFromTreasury(user2, amountToTransfer);

vm.prank(user2);
judgeToken.transfer(address(judgeTreasury), misplacedAmount);
vm.expectRevert(
    abi.encodeWithSelector(
        AccessControlUnauthorizedAccount.selector,
        owner,
        tokenRecoveryAdmin
    )
);
judgeTreasury.recoverMisplacedJudgeToken(zeroAddress, misplacedAmount);
judgeTreasury.grantRole(tokenRecoveryAdmin, owner);
uint256 oldBalanceOfUser2 = judgeToken.balanceOf(user2);
judgeTreasury.recoverMisplacedJudgeToken(user2, misplacedAmount);
uint256 newBalanceOfUser2 = judgeToken.balanceOf(user2);
assertEq(newBalanceOfUser2 - oldBalanceOfUser2, misplacedAmount * 90 / 100);
}

function testRecoverErc20() public{

}

function testTransferFeesFromOtherTokensOutOfTreasury()public{

}

}