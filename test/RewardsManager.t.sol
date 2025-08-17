// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeTreasury.sol";
import "../src/JudgeStaking.sol";
import "../src/SampleERC20.sol";

contract RewardsManagerTest is Test {
    JudgeToken public judgeToken;
    RewardsManager public rewardsManager;
    JudgeTreasury public judgeTreasury;
    JudgeStaking public judgeStaking;
    SampleERC20 public sampleERC20;

    address public owner;
    address public zeroAddress;
    address public user1;
    address public user2;
    address public user3;
    uint8 private decimals = 18;
    uint256 public initialSupply = 100_000 * 10 ** uint256(decimals);
    uint8 public earlyWithdrawalPercent = 10;

    error InvalidAddress();
    error EOANotAllowed();
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error CannotInputThisContractAddress();
    error ValueHigherThanThreshold();
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientContractBalance();
    error JudgeTokenRecoveryNotAllowed();

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        zeroAddress = address(0);

        judgeToken = new JudgeToken(initialSupply);
        rewardsManager = new RewardsManager(address(judgeToken));
        judgeStaking = new JudgeStaking(address(judgeToken), earlyWithdrawalPercent);
        judgeTreasury = new JudgeTreasury(address(judgeToken), address(rewardsManager), address(judgeStaking));
        bytes32 rewardsManagerAdmin = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        rewardsManager.setJudgeTreasuryAddress(address(judgeTreasury));
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        bytes32 rewardsManagerPrecisebalanceUpdater = rewardsManager.REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
        bytes32 treasuryAdmin = judgeTreasury.TREASURY_ADMIN_ROLE();
        bytes32 rewardsPerBlockAdmin = judgeStaking.REWARDS_PER_BLOCK_CALCULATOR();
        bytes32 stakingAdmin = judgeStaking.STAKING_ADMIN_ROLE();
        rewardsManager.grantRole(rewardsManagerPrecisebalanceUpdater, address(judgeTreasury));
        judgeToken.grantRole(minterRole, address(judgeTreasury));
        judgeTreasury.grantRole(treasuryAdmin, owner);
        judgeStaking.grantRole(stakingAdmin, owner);
        judgeStaking.grantRole(rewardsPerBlockAdmin, address(judgeTreasury));
        judgeStaking.setRewardsManagerAddress(address(rewardsManager));
        judgeStaking.setJudgeTreasuryAddress(address(judgeTreasury));

        sampleERC20 = new SampleERC20();
    }

    function testDeployerIsOwner() public {
        bytes32 defaultAdmin = rewardsManager.DEFAULT_ADMIN_ROLE();
        assertTrue(rewardsManager.hasRole(defaultAdmin, owner));
    }

    function testSetKeyParameter() public {
        bytes32 rewardsManagerAdminRole = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, rewardsManagerAdminRole)
        );
        vm.prank(user1);
        rewardsManager.setJudgeTreasuryAddress(address(judgeTreasury));

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.setJudgeTreasuryAddress(zeroAddress);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.setJudgeTreasuryAddress(address(rewardsManager));

        vm.expectRevert(EOANotAllowed.selector);
        rewardsManager.setJudgeTreasuryAddress(user1);

        // For testing purpose we are using judgeToken address as placeholder for new treasury contract
        rewardsManager.setJudgeTreasuryAddress(address(judgeToken));
        assertEq(address(rewardsManager.judgeTreasury()), address(judgeToken));
    }

    function testUpdateFeePercent() public {
        bytes32 rewardsManagerAdminRole = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
        uint8 newFeePercent = 20;
        uint8 feePercentHigherThanThreshold = 31;
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, rewardsManagerAdminRole)
        );
        vm.prank(user1);
        rewardsManager.updateFeePercent(newFeePercent);

        vm.expectRevert(ValueHigherThanThreshold.selector);
        rewardsManager.updateFeePercent(feePercentHigherThanThreshold);

        rewardsManager.updateFeePercent(newFeePercent);
        assertEq(rewardsManager.feePercent(), newFeePercent);
    }

    function testUpdateJudgeRecoveryMinimumThreshold() public {
        bytes32 rewardsManagerAdminRole = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
        uint256 newJudgeRecoveryMinimumThreshold = 10_000 * 10 ** uint256(decimals);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, rewardsManagerAdminRole)
        );
        vm.prank(user1);
        rewardsManager.updateJudgeRecoveryMinimumThreshold(newJudgeRecoveryMinimumThreshold);

        rewardsManager.updateJudgeRecoveryMinimumThreshold(newJudgeRecoveryMinimumThreshold);
        assertEq(rewardsManager.judgeRecoveryMinimumThreshold(), newJudgeRecoveryMinimumThreshold);
    }

    function testAdminWithdrawal() public {
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 fundManagerAdminRewardsManager = rewardsManager.FUND_MANAGER_ROLE();
        uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
        judgeToken.mint(user3, misplacedAmount);
        uint256 amount = 250_000 * 10 ** uint256(decimals);
        uint256 amountHigherThanBalance = 1_250_001 * 10 ** uint256(decimals);
        uint256 invalidAmount;
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint32 index = 1;
        judgeTreasury.setNewQuarterlyRewards(rewards);
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(index);

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, owner, fundManagerAdminRewardsManager)
        );
        rewardsManager.adminWithdrawal(user2, amount);
        rewardsManager.grantRole(fundManagerAdminRewardsManager, owner);

        vm.expectRevert(InvalidAmount.selector);
        rewardsManager.adminWithdrawal(user2, invalidAmount);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.adminWithdrawal(zeroAddress, amount);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.adminWithdrawal(address(rewardsManager), amount);

        judgeToken.transfer(address(rewardsManager), misplacedAmount);
        vm.expectRevert(InsufficientBalance.selector);
        rewardsManager.adminWithdrawal(user2, amountHigherThanBalance);
        rewardsManager.adminWithdrawal(user2, amount);
        assertEq(judgeToken.balanceOf(user2), amount);
        assertEq(judgeToken.balanceOf(address(rewardsManager)), 850_000 * 10 ** uint256(decimals));
    }

    function testEmergencyWithdrawal() public {
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint32 index = 1;
        judgeTreasury.setNewQuarterlyRewards(rewards);
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 fundManagerAdminRewardsManager = rewardsManager.FUND_MANAGER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user2, fundManagerAdminRewardsManager)
        );
        vm.prank(user2);
        rewardsManager.emergencyWithdrawal(user1);
        rewardsManager.grantRole(fundManagerAdminRewardsManager, owner);

        vm.expectRevert(InsufficientContractBalance.selector);
        rewardsManager.emergencyWithdrawal(user1);

        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(index);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.emergencyWithdrawal(zeroAddress);
        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.emergencyWithdrawal(address(rewardsManager));
        rewardsManager.emergencyWithdrawal(user1);
        assertEq(judgeToken.balanceOf(user1), 1_000_000 * 10 ** uint256(decimals));
    }

    function testCalculateMisplacedJudge() public {
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 tokenRecoveryAdmin = rewardsManager.TOKEN_RECOVERY_ROLE();
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint32 index = 1;
        judgeTreasury.setNewQuarterlyRewards(rewards);
        uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
        judgeToken.mint(user3, misplacedAmount);
        vm.prank(user3);
        judgeToken.transfer(address(rewardsManager), misplacedAmount);
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(index);

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, owner, tokenRecoveryAdmin));
        rewardsManager.calculateMisplacedJudge();
        rewardsManager.grantRole(tokenRecoveryAdmin, owner);
        assertEq(rewardsManager.calculateMisplacedJudge(), misplacedAmount);
    }

    function testRecoverMisplacedJudgeToken() public {
        bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
        bytes32 rewardsManagerAdmin = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
        bytes32 tokenRecoveryAdmin = rewardsManager.TOKEN_RECOVERY_ROLE();
        bytes32 treasuryPreciseBalanceUpdater = judgeTreasury.TREASURY_PRECISE_BALANCE_UPDATER();
        judgeTreasury.grantRole(treasuryPreciseBalanceUpdater, address(rewardsManager));
        uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
        uint256 invalidAmount;
        uint8 feePercent = 10;
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        rewardsManager.updateFeePercent(feePercent);
        judgeToken.mint(user3, misplacedAmount);
        vm.prank(user3);
        judgeToken.transfer(address(rewardsManager), misplacedAmount);
        uint256 rewards = 1_000_000 * 10 ** uint256(decimals);
        uint32 index = 1;
        judgeTreasury.setNewQuarterlyRewards(rewards);
        judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
        judgeTreasury.fundRewardsManager(index);

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, owner, tokenRecoveryAdmin));
        rewardsManager.recoverMisplacedJudge(user3, misplacedAmount);
        rewardsManager.grantRole(tokenRecoveryAdmin, owner);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.recoverMisplacedJudge(zeroAddress, misplacedAmount);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.recoverMisplacedJudge(address(rewardsManager), misplacedAmount);

        vm.expectRevert(InvalidAmount.selector);
        rewardsManager.recoverMisplacedJudge(user3, invalidAmount);

        rewardsManager.recoverMisplacedJudge(user3, misplacedAmount);
        assertEq(judgeToken.balanceOf(user3), misplacedAmount * 9 / 10);
        assertEq(judgeToken.balanceOf(address(judgeTreasury)), misplacedAmount / 10);
    }

    function testRecoverErc20() public {
        bytes32 tokenRecoveryAdmin = rewardsManager.TOKEN_RECOVERY_ROLE();
        bytes32 rewardsManagerAdmin = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
        address strandedTokenAddr = address(sampleERC20);
        uint256 misplacedAmount = 1000 ether;
        uint256 tooHighAmount = 1001 ether;
        uint256 invalidAmount;
        uint8 feePercent = 10;
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        rewardsManager.updateFeePercent(feePercent);
        sampleERC20.mint(user1, misplacedAmount);

        vm.prank(user1);

        sampleERC20.transfer(address(rewardsManager), misplacedAmount);
        assertEq(sampleERC20.balanceOf(address(rewardsManager)), misplacedAmount);

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, owner, tokenRecoveryAdmin));
        rewardsManager.recoverErc20(strandedTokenAddr, user1, misplacedAmount);

        rewardsManager.grantRole(tokenRecoveryAdmin, owner);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.recoverErc20(strandedTokenAddr, address(rewardsManager), misplacedAmount);

        vm.expectRevert(InvalidAmount.selector);
        rewardsManager.recoverErc20(strandedTokenAddr, user1, invalidAmount);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.recoverErc20(zeroAddress, user1, misplacedAmount);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.recoverErc20(strandedTokenAddr, zeroAddress, misplacedAmount);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.recoverErc20(zeroAddress, zeroAddress, misplacedAmount);

        vm.expectRevert(InsufficientContractBalance.selector);
        rewardsManager.recoverErc20(strandedTokenAddr, user1, tooHighAmount);

        vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
        rewardsManager.recoverErc20(address(judgeToken), user1, misplacedAmount);

        rewardsManager.recoverErc20(strandedTokenAddr, user1, misplacedAmount);
        assertEq(sampleERC20.balanceOf(user1), misplacedAmount * 9 / 10);
        assertEq(rewardsManager.feeBalanceOfStrandedToken(strandedTokenAddr), misplacedAmount / 10);
    }

    function testTransferFeesFromOtherTokensOutOfRewardsManager() public {
        bytes32 tokenRecoveryAdmin = rewardsManager.TOKEN_RECOVERY_ROLE();
        bytes32 rewardsManagerAdmin = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
        bytes32 fundManagerRole = rewardsManager.FUND_MANAGER_ROLE();
        address strandedTokenAddr = address(sampleERC20);
        uint256 misplacedAmount = 1000 ether;
        uint256 invalidAmount;
        uint8 feePercent = 10;
        rewardsManager.grantRole(rewardsManagerAdmin, owner);
        rewardsManager.updateFeePercent(feePercent);
        sampleERC20.mint(user1, misplacedAmount);

        vm.prank(user1);
        sampleERC20.transfer(address(rewardsManager), misplacedAmount);

        rewardsManager.grantRole(tokenRecoveryAdmin, owner);
        rewardsManager.recoverErc20(strandedTokenAddr, user1, misplacedAmount);

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, owner, fundManagerRole));
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(strandedTokenAddr, user2, misplacedAmount / 10);

        rewardsManager.grantRole(fundManagerRole, owner);

        vm.expectRevert(CannotInputThisContractAddress.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr, address(rewardsManager), misplacedAmount / 10
        );

        vm.expectRevert(InvalidAmount.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(strandedTokenAddr, user2, invalidAmount);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(zeroAddress, user2, misplacedAmount / 10);

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr, zeroAddress, misplacedAmount / 10
        );

        vm.expectRevert(InvalidAddress.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(zeroAddress, zeroAddress, misplacedAmount / 10);

        vm.expectRevert(InsufficientBalance.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(
            strandedTokenAddr, user2, misplacedAmount * 2 / 10
        );

        vm.expectRevert(JudgeTokenRecoveryNotAllowed.selector);
        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(address(judgeToken), user2, misplacedAmount / 10);

        rewardsManager.transferFeesFromOtherTokensOutOfRewardsManager(strandedTokenAddr, user2, misplacedAmount / 10);
        assertEq(sampleERC20.balanceOf(user2), misplacedAmount / 10);
        assertEq(rewardsManager.feeBalanceOfStrandedToken(strandedTokenAddr), 0);
    }

    function testSendRewards() public {}
}
