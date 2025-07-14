// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {JudgeTreasury} from "./JudgeTreasury.sol";

contract RewardsManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;

    JudgeToken public judgeToken;
    JudgeTreasury public judgeTreasury;
    uint256 public totalRewardsPaid;
    bytes32 public constant REWARD_DISTRIBUTOR_ROLE = keccak256("REWARD_DISTRIBUTOR_ROLE");

    event RewardDistributorWasSet(address indexed setBy, address indexed newRewardDistributor);
    event AdminWithdrawed(address indexed admin, address indexed receiver, uint256 amount);
    event EmergencyWithdrawal(address indexed admin, address indexed receiver, uint256 amount);

    error InvalidAmount();
    error InvalidAddress();
    error InputedThisContractAddress();
    error FordbidDefaultAdminAddress();
    error EOANotAllowed();
    error RecoveryOfJudgeNA();
    error ContractBalanceNotEnough();

    constructor(address _judgeTokenAddress, address _judgeTreasuryAddress) {
        judgeToken = JudgeToken(_judgeTokenAddress);
        judgeTreasury = JudgeTreasury(_judgeTreasuryAddress);
    }

    function setRewardDistributor(address _judgeStakingAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_judgeStakingAddress != address(0), InvalidAddress());
        require(_judgeStakingAddress != address(this), InputedThisContractAddress());
        require(_judgeStakingAddress != msg.sender, FordbidDefaultAdminAddress());
        require(_judgeStakingAddress.code.length > 0, EOANotAllowed());
        _grantRole(REWARD_DISTRIBUTOR_ROLE, _judgeStakingAddress);

        emit RewardDistributorWasSet(msg.sender, _judgeStakingAddress);
    }

    function sendRewards(address _addr, uint256 _amount) external onlyRole(REWARD_DISTRIBUTOR_ROLE) nonReentrant {
        require(_amount <= address(this).balance, ContractBalanceNotEnough());
        judgeToken.safeTransfer(_addr, _amount);
        totalRewardsPaid += _amount;
    }

    function adminWithdrawal(address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_to != address(0), InvalidAddress());
        require(_to != address(this), InputedThisContractAddress());
        require(_amount > 0, InvalidAmount());
        judgeToken.safeTransfer(_to, _amount);

        emit AdminWithdrawed(msg.sender, _to, _amount);
    }

    function emergencyWithdrawal(address _to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_to != address(0), InvalidAddress());
        require(_to != address(this), InputedThisContractAddress());
        require(address(this).balance > 0, ContractBalanceNotEnough());
        judgeToken.safeTransfer(_to, address(this).balance);

        emit EmergencyWithdrawal(msg.sender, _to, address(this).balance);
    }

    function calculateMisplacedJudge() external view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        uint256 contractBalance = address(this).balance;
        uint256 fundsFromTreasury = judgeTreasury.stakingRewardsFundsFromTreasury();
        uint256 misplacedJudge = contractBalance + totalRewardsPaid - fundsFromTreasury;
        return misplacedJudge;
    }

    function recoverERC20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_strandedTokenAddr != address(judgeToken), RecoveryOfJudgeNA());
        IERC20(_strandedTokenAddr).transfer(_addr, _amount);
    }
}
