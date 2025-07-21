// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/JudgeTreasury.sol";
import "../src/RewardsManager.sol";
import "../src/SampleERC20.sol";

contract JudgeTreasuryTest is Test{
JudgeToken public judgeToken;
JudgeTreasury public judgeTreasury;
RewardsManager public rewardsManager;
SampleERC20 public sampleERC20;
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
error NotUpToThreshold();
error JudgeTokenRecoveryNotAllowed();
error InsufficientContractBalance();
error ValueHigherThanThreshold();

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

sampleERC20 = new SampleERC20();
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
bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
uint8 newFeePercent = 15;
uint8 incorrectFeePercent = 32;
vm.expectRevert(
    abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector,
    user3,
    treasuryAdmin
));
vm.prank(user3);
judgeTreasury.updateFeePercent(newFeePercent);

vm.expectRevert(ValueHigherThanThreshold.selector);
judgeTreasury.updateFeePercent(incorrectFeePercent);

judgeTreasury.updateFeePercent(newFeePercent);
assertEq(judgeTreasury.feePercent(), newFeePercent);
}

function testUpdateJudgeRecoveryMinimumThreshold() public {
bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
uint256 newJudgeRecoveryMinimumThreshold = 1000 * 10 ** uint256(decimals); 
vm.expectRevert(
    abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector,
    user2,
    treasuryAdmin
));
vm.prank(user2);
judgeTreasury.updateJudgeRecoveryMinimumThreshold(newJudgeRecoveryMinimumThreshold);

judgeTreasury.updateJudgeRecoveryMinimumThreshold(newJudgeRecoveryMinimumThreshold);
assertEq(judgeTreasury.judgeRecoveryMinimumThreshold(), newJudgeRecoveryMinimumThreshold);
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
uint256 invalidAmount = 300_000 * 10 ** uint256(decimals);
uint256 amountLessThanThreshold = 20 * 10 * uint256(decimals);

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

vm.expectRevert(InvalidAmount.selector);
judgeTreasury.recoverMisplacedJudgeToken(user2, 0);

vm.expectRevert(InvalidAmount.selector);
judgeTreasury.recoverMisplacedJudgeToken(user2, invalidAmount);

vm.expectRevert(NotUpToThreshold.selector);
judgeTreasury.recoverMisplacedJudgeToken(user2, amountLessThanThreshold);

vm.expectRevert(CannotInputThisContractAddress.selector);
judgeTreasury.recoverMisplacedJudgeToken(address(judgeTreasury), misplacedAmount);

uint256 oldBalanceOfUser2 = judgeToken.balanceOf(user2);
judgeTreasury.recoverMisplacedJudgeToken(user2, misplacedAmount);
uint256 newBalanceOfUser2 = judgeToken.balanceOf(user2);
assertEq(newBalanceOfUser2 - oldBalanceOfUser2, misplacedAmount * 90 / 100);
assertEq(judgeTreasury.treasuryPreciseBalance(), amount - amountToTransfer + (misplacedAmount * 10 / 100));
}

function testRecoverErc20() public{
bytes32 tokenRecoveryAdmin = judgeTreasury.TOKEN_RECOVERY_ROLE();
address strandedTokenAddr = address(sampleERC20);
uint256 misplacedAmount = 1000 ether;
uint256 tooHighAmount = 1001 ether;
uint256 invalidAmount;
 sampleERC20.mint(user1, misplacedAmount);

 vm.prank(user1);

 sampleERC20.transfer(address(judgeTreasury), misplacedAmount);
 assertEq(sampleERC20.balanceOf(address(judgeTreasury)), misplacedAmount);

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
judgeTreasury.recoverErc20(strandedTokenAddr, address(judgeTreasury), misplacedAmount);

vm.expectRevert(InvalidAmount.selector);
judgeTreasury.recoverErc20(strandedTokenAddr, user1, invalidAmount);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.recoverErc20(zeroAddress, user1, misplacedAmount);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.recoverErc20(strandedTokenAddr, zeroAddress, misplacedAmount);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.recoverErc20(zeroAddress, zeroAddress, misplacedAmount);

vm.expectRevert(InsufficientContractBalance.selector);
judgeTreasury.recoverErc20(strandedTokenAddr, user1, tooHighAmount);

vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
judgeTreasury.recoverErc20(address(judgeToken), user1, misplacedAmount);

 judgeTreasury.recoverErc20(strandedTokenAddr, user1, misplacedAmount);
 assertEq(sampleERC20.balanceOf(user1), misplacedAmount * 9/10);
 assertEq(judgeTreasury.feeBalanceOfStrandedToken(strandedTokenAddr), misplacedAmount * 1/10 );
}

function testTransferFeesFromOtherTokensOutOfTreasury()public{
bytes32 tokenRecoveryAdmin = judgeTreasury.TOKEN_RECOVERY_ROLE();
bytes32 fundManagerRole = judgeTreasury.FUND_MANAGER_ROLE();
address strandedTokenAddr = address(sampleERC20);
uint256 misplacedAmount = 1000 ether;
uint256 tooHighAmount = 1001 ether;
uint256 invalidAmount;
sampleERC20.mint(user1, misplacedAmount);

vm.prank(user1);
sampleERC20.transfer(address(judgeTreasury), misplacedAmount);

judgeTreasury.grantRole(tokenRecoveryAdmin, owner);
judgeTreasury.recoverErc20(strandedTokenAddr, user1, misplacedAmount);


vm.expectRevert(
    abi.encodeWithSelector(
    AccessControlUnauthorizedAccount.selector,
    owner,
    fundManagerRole)
);
judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(strandedTokenAddr, user2, misplacedAmount/10);

judgeTreasury.grantRole(fundManagerRole, owner);

vm.expectRevert(CannotInputThisContractAddress.selector);
judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(strandedTokenAddr, address(judgeTreasury), misplacedAmount/10);

vm.expectRevert(InvalidAmount.selector);
judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(strandedTokenAddr, user2, invalidAmount);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(zeroAddress, user2, misplacedAmount/10);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(strandedTokenAddr, zeroAddress, misplacedAmount/10);

vm.expectRevert(InvalidAddress.selector);
judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(zeroAddress, zeroAddress, misplacedAmount/10);

vm.expectRevert(InsufficientBalance.selector);
judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(strandedTokenAddr, user2, misplacedAmount*2/10);

vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(address(judgeToken), user2, misplacedAmount/10);

judgeTreasury.transferFeesFromOtherTokensOutOfTreasury(strandedTokenAddr, user2, misplacedAmount/10);
assertEq(sampleERC20.balanceOf(user2), misplacedAmount/10);
assertEq(judgeTreasury.feeBalanceOfStrandedToken(strandedTokenAddr), 0);
}
}