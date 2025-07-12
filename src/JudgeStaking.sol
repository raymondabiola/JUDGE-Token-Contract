// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";

contract JudgeStaking is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;
    JudgeToken public judgeToken;
    uint256 private newStakeId;
    uint256 public accJudgePerShare;
    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    uint256 public totalCalculatedStakeForReward;
    uint public totalStaked;
    uint256 private constant SCALE = 1e18;
    address[] internal users;
    uint256 private constant maxLockUpPeriod = 360;
    bool public emergencyFuncCalled;

    struct userStake {
        uint256 id;
        uint256 amountStaked;
        uint256 lockUpPeriod;
        uint256 lockUpRatio;
        uint256 calculatedStakeForReward;
        uint256 depositTimestamp;
        uint256 rewardDebt;
        uint256 maturityTimestamp;
    }

    mapping(address => userStake[]) internal userStakes;
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
    error NotYetMatured();
    error InvalidLockUpPeriod();

    constructor(address _judgeTokenAddress, uint256 _rewardPerBlock) {
        judgeToken = JudgeToken(_judgeTokenAddress);
        newStakeId = 1;
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
        if (totalCalculatedStakeForReward == 0) {
            lastRewardBlock = block.number;
        }
        uint256 blocksPassed = block.number - lastRewardBlock;
        uint256 totalReward = blocksPassed * rewardPerBlock;
        accJudgePerShare +=
            (totalReward * SCALE) /
            totalCalculatedStakeForReward;
        lastRewardBlock = block.number;
    }

    function deposit(uint256 _amount, uint256 _lockUpPeriodInDays) external {
        require(_amount > 0, InvalidAmount());
        require(_lockUpPeriodInDays <= maxLockUpPeriod, InvalidLockUpPeriod());
        if (!isUser[msg.sender]) {
            users.push(msg.sender);
            isUser[msg.sender] = true;
        }

        updatePool();
        uint256 amountStaked = _amount;
        uint256 lockUpPeriod = _lockUpPeriodInDays;
        uint256 lockUpRatio = (lockUpPeriod * SCALE) / maxLockUpPeriod;
        uint256 calculatedStakeForReward = (amountStaked * lockUpRatio) / SCALE;
        uint256 depositTimestamp = block.timestamp;
        uint256 rewardDebt = (calculatedStakeForReward * accJudgePerShare) /
            SCALE;
        uint256 maturityTimestamp = depositTimestamp + lockUpPeriod;

        userStake memory newStake = userStake({
            id: newStakeId,
            amountStaked: amountStaked,
            lockUpPeriod: lockUpPeriod,
            lockUpRatio: lockUpRatio,
            calculatedStakeForReward: calculatedStakeForReward,
            depositTimestamp: depositTimestamp,
            rewardDebt: rewardDebt,
            maturityTimestamp: maturityTimestamp
        });

        judgeToken.safeTransferFrom(msg.sender, address(this), _amount);
        userStakes[msg.sender].push(newStake);

        totalCalculatedStakeForReward += calculatedStakeForReward;
        totalStaked += _amount;

        newStakeId++;
        emit Deposited(msg.sender, _amount);
    }

    function withdraw(uint256 _amount, uint256 _index) external nonReentrant {
        require(_amount > 0, InvalidAmount());
        userStake storage stake = userStakes[msg.sender][_index];
        require(stake.maturityTimestamp <= block.timestamp, NotYetMatured());
        require(_amount <= stake.amountStaked, InsufficientBal());

        updatePool();
        uint256 pending = (stake.calculatedStakeForReward * accJudgePerShare) /
            SCALE -
            stake.rewardDebt;
        if (pending > 0) {
            judgeToken.safeTransfer(msg.sender, pending);
        }
        totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
        stake.amountStaked -= _amount;
        stake.calculatedStakeForReward =
            (stake.amountStaked * stake.lockUpRatio) /
            SCALE;
        totalCalculatedStakeForReward += stake.calculatedStakeForReward;
        stake.rewardDebt =
            (stake.calculatedStakeForReward * accJudgePerShare) /
            SCALE;
        totalStaked -= _amount;
        judgeToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function withdrawAll(uint _index) external nonReentrant {
        userStake storage stake = userStakes[msg.sender][_index];
        updatePool();
        uint256 pending = (stake.calculatedStakeForReward * accJudgePerShare) /
            SCALE -
            stake.rewardDebt;
        if (pending > 0) {
            judgeToken.safeTransfer(msg.sender, pending);
        }

        uint256 amountWithdrawn = stake.amountStaked;
        totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
        stake.amountStaked = 0;
        stake.calculatedStakeForReward = 0;
        totalStaked -= amountWithdrawn;
        stake.rewardDebt = 0;
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
            uint256 amount = userStakes[users[i]].amountStaked;

            updatePool();
            if (userStakes[userAddr].amountStaked > 0) {
                uint256 pending = (userStakes[userAddr].amountStaked *
                    accJudgePerShare) /
                    SCALE -
                    userStakes[userAddr].rewardDebt;

                judgeToken.safeTransfer(userAddr, pending);

                userStakes[userAddr].amountStaked = 0;
                totalStaked -= amount;
                userStakes[userAddr].rewardDebt = 0;
                judgeToken.safeTransfer(userAddr, amount);
                emit EmergencyWithdrawal(msg.sender, userAddr, amount, pending);
            }
        }
    }

    function myStakeDetails() external view returns (userStake memory) {
        return userStakes[msg.sender];
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
        return userStakes[addr];
    }
}
