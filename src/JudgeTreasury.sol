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
    error InvalidAddr();
    error RecoveryOfJudgeNA();

    constructor(address _judgeTokenAddress, address _rewardsManagerAddress) {
        judgeToken = JudgeToken(_judgeTokenAddress);
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
        judgeToken.mint(address(this), _amount);
    }

    function transferFromTreasury(address _addr, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_addr != address(0), InvalidAddr());
        require(_amount <= address(this).balance, InsufficientBal());
        require(_amount > 0, InvalidAmount());
        judgeToken.safeTransfer(_addr, _amount);

        if (_addr == address(rewardsManager)) {
            stakingRewardsFundsFromTreasury += _amount;
        }
    }

    function recoverERC20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_strandedTokenAddr != address(judgeToken), RecoveryOfJudgeNA());
        IERC20(_strandedTokenAddr).transfer(_addr, _amount);
    }
}
