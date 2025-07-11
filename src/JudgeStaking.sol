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
    address[] internal users;
    bool public emergencyFuncCalled;

    struct userStake {
        uint256 amountStaked;
        uint256 rewardDebt;
    }

    mapping(address => userStake) internal usersInfo;
    mapping(address => bool) internal isUser;
    bytes32 DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");

    event RewardsFunded(uint256 amount);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event EmergencyWithdrawal(
        address indexed admin,
        address indexed user,
        uint256 stakeWithdrawn,
        uint256 rewardPaid
    );
    event RewardPerBlockUpdated(uint newValue);

    error InvalidAmount();
    error InsufficientBal();
    error AlreadyTriggered();

    constructor(address _judgeTokenAddress, uint256 _rewardPerBlock) {
        judgeToken = JudgeToken(_judgeTokenAddress);
        rewardPerBlock = _rewardPerBlock;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function fundReward(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, InvalidAmount());
        judgeToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsFunded(amount);
    }

    function setNewRewardPerBlock(
        uint256 newRewardPerBlock
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardPerBlock = newRewardPerBlock;
        emit RewardPerBlockUpdated(newRewardPerBlock);
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
        if (!isUser[msg.sender]) {
            users.push(msg.sender);
            isUser[msg.sender] = true;
        }
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
        }

        uint256 amountWithdrawn = user.amountStaked;
        user.amountStaked = 0;
        totalStaked -= amountWithdrawn;
        user.rewardDebt = 0;
        judgeToken.safeTransfer(msg.sender, amountWithdrawn);
        emit Withdrawn(msg.sender, amountWithdrawn);
    }

    function emergencyWithdraw()
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(!emergencyFuncCalled, AlreadyTriggered());
        emergencyFuncCalled = true;
        for (uint256 i; i < users.length; i++) {
            address userAddr = users[i];
            uint256 amount = usersInfo[users[i]].amountStaked;

            updatePool();
            if (usersInfo[userAddr].amountStaked > 0) {
                uint256 pending = (usersInfo[userAddr].amountStaked *
                    accJudgePerShare) /
                    SCALE -
                    usersInfo[userAddr].rewardDebt;

                judgeToken.safeTransfer(userAddr, pending);

                usersInfo[userAddr].amountStaked = 0;
                totalStaked -= amount;
                usersInfo[userAddr].rewardDebt = 0;
                judgeToken.safeTransfer(userAddr, amount);
                emit EmergencyWithdrawal(msg.sender, userAddr, amount, pending);
            }
        }
    }

    function myStakeDetails() external view returns (userStake memory) {
        return usersInfo[msg.sender];
    }

    function getUserList()
        external
        view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (address[] memory)
    {
        return users;
    }

    function getUserStakeDetails(
        address addr
    ) external view onlyRole(DEFAULT_ADMIN_ROLE) returns (userStake memory) {
        return usersInfo[addr];
    }
}
