// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {JudgeTreasury} from "./JudgeTreasury.sol";
import {JudgeStaking} from "./JudgeStaking.sol";

contract RewardsManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;

    JudgeToken public judgeToken;
    JudgeTreasury public judgeTreasury;
    JudgeStaking public judgeStaking;

    bytes32 public constant REWARD_DISTRIBUTOR_ROLE = keccak256("REWARD_DISTRIBUTOR_ROLE");
    uint256 public totalRewardsPaid;

    event JudgeTokenAddressWasSet(address indexed judgeTokenAddress);
    event JudgeTreasuryAdressUpdated(address indexed judgeTreasuryAddress);
    event JudgeStakingAddressUpdated(address indexed judgeStakingAddress);
    event RewardDistributorWasSet(address indexed setBy, address indexed newRewardDistributor);
    event AdminWithdrawed(address indexed admin, address indexed receiver, uint256 amount);
    event EmergencyWithdrawal(address indexed admin, address indexed receiver, uint256 amount);

    error InvalidAmount();
    error InvalidAddress();
    error CannotInputThisContractAddress();
    error EOANotAllowed();
    error JudgeTokenRecoveryNotAllowed();
    error InsufficientContractBalance();

    constructor(address _judgeTokenAddress) validAddress(_judgeTokenAddress){
        require(_judgeTokenAddress.code.length > 0, EOANotAllowed());
        judgeToken = JudgeToken(_judgeTokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        emit JudgeTokenAddressWasSet(_judgeTokenAddress);
    }

     modifier validAddress(address _to){
              require(_to != address(0), InvalidAddress());
              _;
    }

    modifier notSelf(address _to){
        require(_to != address(this), CannotInputThisContractAddress());
        _;
    }

       modifier validAmount(uint256 _amount){
         require(_amount > 0, InvalidAmount());
         _;
    }

    function setKeyParameters(address _judgeTreasuryAddress, address _judgeStakingAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_judgeTreasuryAddress != address(0) && _judgeStakingAddress != address(0), InvalidAddress());
        require(_judgeTreasuryAddress != address(this) && _judgeStakingAddress != address(this), CannotInputThisContractAddress());
        require(_judgeTreasuryAddress.code.length > 0 && _judgeStakingAddress.code.length > 0, EOANotAllowed());
        
        judgeTreasury = JudgeTreasury(_judgeTreasuryAddress);
        judgeStaking = JudgeStaking(_judgeStakingAddress);

        _grantRole(REWARD_DISTRIBUTOR_ROLE, _judgeStakingAddress);

        emit JudgeTreasuryAdressUpdated(_judgeTreasuryAddress);
        emit JudgeStakingAddressUpdated(_judgeStakingAddress);
        emit RewardDistributorWasSet(msg.sender, _judgeStakingAddress);
    }

    function sendRewards(address _addr, uint256 _amount) external onlyRole(REWARD_DISTRIBUTOR_ROLE) validAddress(_addr) nonReentrant {
        require(_amount <= judgeToken.balanceOf(address(this)), InsufficientContractBalance());
        judgeToken.safeTransfer(_addr, _amount);
        totalRewardsPaid += _amount;
    }

    function adminWithdrawal(address _to, uint256 _amount) external validAddress(_to) validAmount(_amount) notSelf(_to) onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant{
        judgeToken.safeTransfer(_to, _amount);

        emit AdminWithdrawed(msg.sender, _to, _amount);
    }

    function emergencyWithdrawal(address _to) external validAddress(_to) notSelf(_to) onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant{
        require(judgeToken.balanceOf(address(this)) > 0, InsufficientContractBalance());
        judgeToken.safeTransfer(_to, judgeToken.balanceOf(address(this)) );

        emit EmergencyWithdrawal(msg.sender, _to, judgeToken.balanceOf(address(this)));
    }

    function calculateMisplacedJudge() public view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        uint256 contractBalance = judgeToken.balanceOf(address(this));
        uint256 fundsFromTreasury = judgeTreasury.stakingRewardsFundsFromTreasury();
        uint256 penaltiesFromJudgeStaking = judgeStaking.totalPenalties();
        uint256 misplacedJudge = contractBalance + totalRewardsPaid - fundsFromTreasury - penaltiesFromJudgeStaking;
        return misplacedJudge;
    }

    function recoverMisplacedJudgeToken(address _to, uint256 _amount) external validAddress(_to) validAmount(_amount) notSelf(_to)  onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant{
        uint256 misplacedJudge = calculateMisplacedJudge();
        require(_amount <= misplacedJudge, InvalidAmount());
        require(judgeToken.balanceOf(address(this)) > 0, InsufficientContractBalance());
        judgeToken.safeTransfer(_to, _amount);
    }

    function recoverERC20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validAmount(_amount)
    nonReentrant{
        require(_strandedTokenAddr != address(0) && _addr != address(0), InvalidAddress());
         require(_amount <= IERC20(_strandedTokenAddr).balanceOf(address(this)), InsufficientContractBalance());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        IERC20(_strandedTokenAddr).transfer(_addr, _amount);
    }
}
