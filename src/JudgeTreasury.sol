// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {RewardsManager} from "./RewardsManager.sol";

contract JudgeTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;

    JudgeToken public judgeToken;
    RewardsManager public rewardsManager;

    uint256 decimals = 18;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public stakingRewardsFundsFromTreasury;

    error InvalidAmount();
    error InsufficientBal();
    error InvalidAddress();
    error RecoveryOfJudgeNA();
    error InputedThisContractAddress();
    error ContractBalanceNotEnough();
    error AlreadyInitialized();
    error SetRewardsMangerAsZeroAddr();

    constructor(address _judgeTokenAddress, address _rewardsManagerAddress) {
        require(_rewardsManagerAddress == address(0), SetRewardsMangerAsZeroAddr());
        judgeToken = JudgeToken(_judgeTokenAddress);
        rewardsManager = RewardsManager(_rewardsManagerAddress);
    }

    function initializeKeyParameters(address _rewardsManagerAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(rewardsManager) == address(0), AlreadyInitialized());
        rewardsManager = RewardsManager(_rewardsManagerAddress);
    }

    function fundRewardsManager(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            416_667 * 10 ** uint256(decimals) <= _amount && _amount <= 1_250_000 * 10 ** uint256(decimals),
            InvalidAmount()
        );
        judgeToken.mint(address(rewardsManager), _amount);
        stakingRewardsFundsFromTreasury += _amount;
    }

    function mintToTreasury(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount > 0, InvalidAmount());
        judgeToken.mint(address(this), _amount);
    }

    function transferFromTreasury(address _addr, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_addr != address(0), InvalidAddress());
        require(_addr != address(this), InputedThisContractAddress());
        require(_amount > 0, InvalidAmount());
        require(_amount <= address(this).balance, InsufficientBal());
        judgeToken.safeTransfer(_addr, _amount);

        if (_addr == address(rewardsManager)) {
            stakingRewardsFundsFromTreasury += _amount;
        }
    }

    function recoverERC20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_strandedTokenAddr != address(0) && _addr != address(0), InvalidAddress());
        require(_amount > 0, InvalidAmount());
        require(_amount < address(this).balance, ContractBalanceNotEnough());
        require(_strandedTokenAddr != address(judgeToken), RecoveryOfJudgeNA());
        IERC20(_strandedTokenAddr).transfer(_addr, _amount);
    }
}
