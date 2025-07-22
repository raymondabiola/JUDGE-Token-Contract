// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import "../src/RewardsManager.sol";
import "../src/JudgeTreasury.sol";
import "../src/SampleERC20.sol";

contract RewardsManagerTest is Test{
    JudgeToken public judgeToken;
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

    error InvalidAddress();
    error EOANotAllowed();
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error CannotInputThisContractAddress();
    error ValueHigherThanThreshold();
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientContractBalance();

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
    bytes32 rewardsManagerPrecisebalanceUpdater = rewardsManager.REWARDS_MANAGER_PRECISE_BALANCE_UPDATER();
    rewardsManager.grantRole(rewardsManagerPrecisebalanceUpdater, address(judgeTreasury));
    judgeToken.grantRole(minterRole, address(judgeTreasury));
    }

    function testDeployerIsOwner()public{
    bytes32 defaultAdmin = rewardsManager.DEFAULT_ADMIN_ROLE();
    assertTrue(rewardsManager.hasRole(defaultAdmin, owner));
    }

    function testSetKeyParameters()public{
    bytes32 rewardsManagerAdminRole = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
    vm.expectRevert(
        abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            owner,
            rewardsManagerAdminRole
        )
    );
    rewardsManager.setKeyParameter(address(judgeTreasury));
    rewardsManager.grantRole(rewardsManagerAdminRole, owner);

    vm.expectRevert(InvalidAddress.selector);
    rewardsManager.setKeyParameter(zeroAddress);

    vm.expectRevert(CannotInputThisContractAddress.selector);
    rewardsManager.setKeyParameter(address(rewardsManager));

    vm.expectRevert(EOANotAllowed.selector);
    rewardsManager.setKeyParameter(user1);

    // For testing purpose we are using judgeToken address as placeholder for new treasury contract
    rewardsManager.setKeyParameter(address(judgeToken));
    assertEq(address(rewardsManager.judgeTreasury()), address(judgeToken));
    }

    function testUpdateFeePercent()public{
    bytes32 rewardsManagerAdminRole = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
    uint8 newFeePercent = 20;
    uint8 feePercentHigherThanThreshold = 31;
    vm.expectRevert(
        abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            owner,
            rewardsManagerAdminRole
        )
    );
    rewardsManager.updateFeePercent(newFeePercent);
    rewardsManager.grantRole(rewardsManagerAdminRole, owner);

    vm.expectRevert(ValueHigherThanThreshold.selector);
    rewardsManager.updateFeePercent(feePercentHigherThanThreshold);

    rewardsManager.updateFeePercent(newFeePercent);
    assertEq(rewardsManager.feePercent(), newFeePercent);
    }

    function testUpdateJudgeRecoveryMinimumThreshold()public{
    bytes32 rewardsManagerAdminRole = rewardsManager.REWARDS_MANAGER_ADMIN_ROLE();
    uint256 newJudgeRecoveryMinimumThreshold = 10_000 * 10 ** uint256(decimals);
    vm.expectRevert(
        abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            owner,
            rewardsManagerAdminRole
        )
    );
    rewardsManager.updateJudgeRecoveryMinimumThreshold(newJudgeRecoveryMinimumThreshold);
    rewardsManager.grantRole(rewardsManagerAdminRole, owner);

    rewardsManager.updateJudgeRecoveryMinimumThreshold(newJudgeRecoveryMinimumThreshold);
    assertEq(rewardsManager.judgeRecoveryMinimumThreshold(), newJudgeRecoveryMinimumThreshold);
    }

    function testAdminWithdrawal()public{
    bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
    bytes32 fundManagerAdminRewardsManager = rewardsManager.FUND_MANAGER_ROLE();
    uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
    judgeToken.mint(user3, misplacedAmount);
    uint256 amount = 250_000 * 10 ** uint256(decimals);
    uint256 amountHigherThanBalance = 1_250_001 * 10 ** uint256(decimals);
    uint256 invalidAmount;
    judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
    judgeTreasury.fundRewardsManager();

    vm.expectRevert(
        abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            owner,
            fundManagerAdminRewardsManager
        )
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
    assertEq(judgeToken.balanceOf(address(rewardsManager)), 1_100_000 * 10 ** uint256(decimals));
    }

    function testEmergencyWithdrawal()public{
    bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
    bytes32 fundManagerAdminRewardsManager = rewardsManager.FUND_MANAGER_ROLE();
    vm.expectRevert(
        abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            user2,
            fundManagerAdminRewardsManager
        )
    );
    vm.prank(user2);
    rewardsManager.emergencyWithdrawal(user1);
    rewardsManager.grantRole(fundManagerAdminRewardsManager, owner);
   
    vm.expectRevert(InsufficientContractBalance.selector);
    rewardsManager.emergencyWithdrawal(user1);

    judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
    judgeTreasury.fundRewardsManager();

    vm.expectRevert(InvalidAddress.selector);
    rewardsManager.emergencyWithdrawal(zeroAddress);
    vm.expectRevert(CannotInputThisContractAddress.selector);
    rewardsManager.emergencyWithdrawal(address(rewardsManager));
    rewardsManager.emergencyWithdrawal(user1);
    assertEq(judgeToken.balanceOf(user1), 1_250_000 * 10 ** uint256(decimals));
    }

    function testCalculateMisplacedJudge()public{
    bytes32 fundManagerAdminTreasury = judgeTreasury.FUND_MANAGER_ROLE();
    bytes32 tokenRecoveryAdmin = rewardsManager.TOKEN_RECOVERY_ROLE();
    uint256 misplacedAmount = 100_000 * 10 ** uint256(decimals);
    judgeToken.mint(user3, misplacedAmount);
    vm.prank(user3);
    judgeToken.transfer(address(rewardsManager), misplacedAmount);
    judgeTreasury.grantRole(fundManagerAdminTreasury, owner);
    judgeTreasury.fundRewardsManager();

    vm.expectRevert(
        abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            owner,
            tokenRecoveryAdmin
        )
    );
    rewardsManager.calculateMisplacedJudge();
    rewardsManager.grantRole(tokenRecoveryAdmin, owner);
    assertEq(rewardsManager.calculateMisplacedJudge(), misplacedAmount);
    }

    function testRecoverMisplacedJudge()public{

    }

    function testRecoverErc20()public{

    }

    function testTransferFeesFromOtherTokensOutOfTreasury()public {

    }
}