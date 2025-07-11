// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";

contract JudgeStaking is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;
    JudgeToken public judgeToken;
    uint256 public accJudgePerShare;
    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    uint256 public totalStaked;
    uint256 private constant SCALE = 1e18;
    struct userStake {
        uint256 amountStaked;
        uint256 rewardDebt;
    }
    mapping(address => userStake) usersInfo;
    bytes32 DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");

    event RewardsFunded(uint256 amount);
    event Deposited(address indexed addr, uint256 amount);
    event Withdrawn(address indexed addr, uint256 amount);

    error InvalidAmount();
    error InsufficientBal();

    constructor(address _judgeTokenAddress) {
        judgeToken = JudgeToken(_judgeTokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function fundReward(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, InvalidAmount());
        judgeToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsFunded(amount);
    }

    function updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
        }
        uint256 blocksPassed = block.number - lastRewardBlock;
        uint256 totalReward = blocksPassed * rewardPerBlock;
        accJudgePerShare += (totalReward * SCALE) / totalStaked;
        lastRewardBlock = block.number;
    }

    function deposit(uint256 _amount) external {
        require(_amount > 0, InvalidAmount());
        userStake storage user = usersInfo[msg.sender];
        updatePool();

        if (user.amountStaked > 0) {
            uint256 pending = (user.amountStaked * accJudgePerShare) /
                SCALE -
                user.rewardDebt;
            if (pending > 0) {
                judgeToken.safeTransfer(msg.sender, pending);
            }
        }
        judgeToken.safeTransferFrom(msg.sender, address(this), _amount);
        totalStaked += _amount;
        user.amountStaked += _amount;
        user.rewardDebt = (user.amountStaked * accJudgePerShare) / SCALE;
        emit Deposited(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, InvalidAmount());
        userStake storage user = usersInfo[msg.sender];
        require(_amount <= user.amountStaked, InsufficientBal());

        updatePool();
        uint256 pending = (user.amountStaked * accJudgePerShare) /
            SCALE -
            user.rewardDebt;
        if (pending > 0) {
            judgeToken.safeTransfer(msg.sender, pending);
        }
        user.amountStaked -= _amount;
        totalStaked -= _amount;
        user.rewardDebt = (user.amountStaked * accJudgePerShare) / SCALE;
        judgeToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function withdrawAll() external nonReentrant {
        userStake storage user = usersInfo[msg.sender];
        updatePool();
        uint256 pending = (user.amountStaked * accJudgePerShare) /
            SCALE -
            user.rewardDebt;
        if (pending > 0) {
            judgeToken.safeTransfer(msg.sender, pending);

            uint256 amountWithdrawn = user.amountStaked;
            user.amountStaked = 0;
            totalStaked -= amountWithdrawn;
            user.rewardDebt = 0;
            judgeToken.safeTransfer(msg.sender, amountWithdrawn);
            emit Withdrawn(msg.sender, amountWithdrawn);
        }
    }
}
