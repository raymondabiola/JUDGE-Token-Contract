// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IRewardsManager {
    function sendRewards(address _addr, uint256 _amount) external;
}

contract JudgeStaking is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;

    JudgeToken public judgeToken;
    IRewardsManager public rewardsManager;

    uint256 private newStakeId;
    uint256 public accJudgePerShare;
    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    uint256 public totalCalculatedStakeForReward;
    uint256 public totalStaked;
    uint256 private constant SCALE = 1e18;
    address[] internal users;
    uint256 private constant maxLockUpPeriod = 360;
    uint256 public earlyWithdrawPenaltyPercent;
    uint256 public totalPenalties;
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
        address indexed admin, address indexed user, uint256 stakeID, uint256 stakeWithdrawn, uint256 rewardPaid
    );
    event JudgeTokenAddressInitialized(address indexed judgeTokenAddress);
    event KeyParameterInitialized(address indexed by, address indexed RewardsManager);
    event KeyParameterUpdated(address indexed by, address indexed newRewardsManager);
    event RewardsPerBlockInitialized(uint256 value);
    event RewardsPerBlockUpdated(uint256 newValue);
    event EarlyWithdrawPenaltyPercentInitialized(uint256 newValue);
    event EarlyWithdrawPenaltyPercentUpdated(uint256 newValue);
    event EarlyWithdrawalPenalty(address indexed user, uint256 block, uint256 penalty);
    event ClaimedReward(address indexed user, uint256 rewards);

    error InvalidAmount();
    error InvalidAddress();
    error InvalidIndex();
    error InsufficientBal();
    error AlreadyTriggered();
    error NotYetMatured();
    error InvalidLockUpPeriod();
    error AlreadyMatured();
    error TooHigh();
    error ZeroStakeBalance();
    error RecoveryOfJudgeNA();
    error ContractBalanceNotEnough();
    error SetRewardsMangerAsZeroAddr();
    error AlreadyInitialized();
    error InputedThisContractAddress();
    error EOANotAllowed();

    constructor(
        address _judgeTokenAddress,
        address _rewardsManagerAddress,
        uint256 _rewardPerBlock,
        uint256 _earlyWithdrawPenaltyPercent
    ) {
        require(_rewardsManagerAddress == address(0), SetRewardsMangerAsZeroAddr());
        require(_judgeTokenAddress != address(0), InvalidAddress());
        require(_judgeTokenAddress != address(this), InputedThisContractAddress());
        require(_judgeTokenAddress.code.length > 0, EOANotAllowed());
        require(earlyWithdrawPenaltyPercent <= 10, TooHigh());

        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        judgeToken = JudgeToken(_judgeTokenAddress);
        newStakeId = 1;
        rewardPerBlock = _rewardPerBlock;
        earlyWithdrawPenaltyPercent = _earlyWithdrawPenaltyPercent;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        emit JudgeTokenAddressInitialized(_judgeTokenAddress);
        emit RewardsPerBlockInitialized(_rewardPerBlock);
        emit EarlyWithdrawPenaltyPercentInitialized(_earlyWithdrawPenaltyPercent);
    }

    function initializeKeyParameter(address _rewardsManagerAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(rewardsManager) == address(0), AlreadyInitialized());
        require(_rewardsManagerAddress != address(0), InvalidAddress());
        require(_rewardsManagerAddress != address(this), InputedThisContractAddress());
        require(_rewardsManagerAddress.code.length > 0, EOANotAllowed());

        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit KeyParameterInitialized(msg.sender, _rewardsManagerAddress);
    }

    function updateKeyParameter(address _rewardsManagerAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_rewardsManagerAddress != address(0), InvalidAddress());
        require(_rewardsManagerAddress != address(this), InputedThisContractAddress());
        require(_rewardsManagerAddress.code.length > 0, EOANotAllowed());

        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit KeyParameterUpdated(msg.sender, _rewardsManagerAddress);
    }

    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardPerBlock = _rewardPerBlock;
        emit RewardsPerBlockUpdated(_rewardPerBlock);
    }

    function updateEarlyWithdrawPenaltyPercent(uint256 _earlyWithdrawPenaltyPercent)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_earlyWithdrawPenaltyPercent > 0, InvalidAmount());
        require(_earlyWithdrawPenaltyPercent <= 10, TooHigh());
        earlyWithdrawPenaltyPercent = _earlyWithdrawPenaltyPercent;
        emit EarlyWithdrawPenaltyPercentUpdated(_earlyWithdrawPenaltyPercent);
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
        accJudgePerShare += (totalReward * SCALE) / totalCalculatedStakeForReward;
        lastRewardBlock = block.number;
    }

    function deposit(uint256 _amount, uint256 _lockUpPeriodInDays) external {
        require(_amount > 0, InvalidAmount());
        require(_lockUpPeriodInDays > 0, InvalidAmount());
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
        uint256 rewardDebt = (calculatedStakeForReward * accJudgePerShare) / SCALE;
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

    function claimRewards(uint256 _index) external {
        require(_index < userStakes[msg.sender].length, InvalidIndex());
        userStake storage stake = userStakes[msg.sender][_index];
        require(stake.amountStaked > 0, ZeroStakeBalance());

        updatePool();
        uint256 pending = (stake.calculatedStakeForReward * accJudgePerShare) / SCALE - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
        }
        stake.rewardDebt = (stake.calculatedStakeForReward * accJudgePerShare) / SCALE;
        emit ClaimedReward(msg.sender, pending);
    }

    function withdraw(uint256 _amount, uint256 _index) external nonReentrant {
        require(_amount > 0, InvalidAmount());
        require(_index < userStakes[msg.sender].length, InvalidIndex());
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp >= stake.maturityTimestamp, NotYetMatured());
        require(_amount <= stake.amountStaked, InsufficientBal());

        updatePool();
        uint256 pending = (stake.calculatedStakeForReward * accJudgePerShare) / SCALE - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
        }
        totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
        stake.amountStaked -= _amount;
        stake.calculatedStakeForReward = (stake.amountStaked * stake.lockUpRatio) / SCALE;
        totalCalculatedStakeForReward += stake.calculatedStakeForReward;
        stake.rewardDebt = (stake.calculatedStakeForReward * accJudgePerShare) / SCALE;
        totalStaked -= _amount;
        judgeToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function withdrawAll(uint256 _index) external nonReentrant {
        require(_index < userStakes[msg.sender].length, InvalidIndex());
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp >= stake.maturityTimestamp, NotYetMatured());
        updatePool();
        uint256 pending = (stake.calculatedStakeForReward * accJudgePerShare) / SCALE - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
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

    function earlyWithdraw(uint256 _index, uint256 _amount) external {
        require(_amount > 0, InvalidAmount());
        require(_index < userStakes[msg.sender].length, InvalidIndex());

        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp < stake.maturityTimestamp, AlreadyMatured());
        require(_amount <= stake.amountStaked, InsufficientBal());

        updatePool();
        uint256 pending = (stake.calculatedStakeForReward * accJudgePerShare) / SCALE - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
        }

        totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
        uint256 penalty = (_amount * earlyWithdrawPenaltyPercent) / 100;
        uint256 deduction = _amount + penalty;
        require(deduction <= stake.amountStaked, InsufficientBal());
        if (deduction == stake.amountStaked) {
            stake.amountStaked = 0;
            stake.calculatedStakeForReward = 0;
            stake.rewardDebt = 0;
        } else {
            stake.amountStaked -= deduction;
            stake.calculatedStakeForReward = (stake.amountStaked * stake.lockUpRatio) / SCALE;
            totalCalculatedStakeForReward += stake.calculatedStakeForReward;
            stake.rewardDebt = (stake.calculatedStakeForReward * accJudgePerShare) / SCALE;
        }
        totalStaked -= deduction;
        totalPenalties += penalty;
        judgeToken.safeTransfer(address(rewardsManager), penalty);
        judgeToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
        emit EarlyWithdrawalPenalty(msg.sender, block.number, penalty);
    }

    function emergencyWithdraw() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!emergencyFuncCalled, AlreadyTriggered());
        emergencyFuncCalled = true;
        for (uint256 i; i < users.length; i++) {
            address userAddr = users[i];
            for (uint256 j; j < userStakes[users[i]].length; j++) {
                userStake memory stake = userStakes[users[i]][j];

                updatePool();
                if (stake.amountStaked > 0) {
                    uint256 pending = (stake.amountStaked * accJudgePerShare) / SCALE - stake.rewardDebt;

                    rewardsManager.sendRewards(msg.sender, pending);

                    uint256 amount = stake.amountStaked;
                    totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
                    stake.amountStaked = 0;
                    stake.calculatedStakeForReward = 0;
                    totalStaked -= amount;
                    stake.rewardDebt = 0;
                    judgeToken.safeTransfer(userAddr, amount);
                    emit EmergencyWithdrawal(msg.sender, userAddr, stake.id, amount, pending);
                }
            }
        }
    }

    function viewMyStakes() external view returns (userStake[] memory) {
        return userStakes[msg.sender];
    }

    function viewMyStakeAtIndex(uint256 _index) external view returns (userStake memory) {
        require(_index < userStakes[msg.sender].length, InvalidIndex());
        return userStakes[msg.sender][_index];
    }

    function viewUsersList() external view onlyRole(DEFAULT_ADMIN_ROLE) returns (address[] memory) {
        return users;
    }

    function viewUserStakes(address addr) external view onlyRole(DEFAULT_ADMIN_ROLE) returns (userStake[] memory) {
        require(addr != address(0), InvalidAddress());
        return userStakes[addr];
    }

    function viewUserStakeAtIndex(address addr, uint256 _index)
        external
        view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (userStake memory)
    {
        require(addr != address(0), InvalidAddress());
        require(_index < userStakes[addr].length, InvalidIndex());
        return userStakes[addr][_index];
    }

    function viewMyPendingRewards(uint256 _index) external view returns (uint256) {
        require(_index < userStakes[msg.sender].length, InvalidIndex());
        userStake memory stake = userStakes[msg.sender][_index];
        uint256 tempAccJudgePerShare = accJudgePerShare;

        if (block.number > lastRewardBlock && totalCalculatedStakeForReward > 0) {
            uint256 blocksPassed = block.number - lastRewardBlock;
            uint256 totalReward = blocksPassed * rewardPerBlock;
            tempAccJudgePerShare += (totalReward * SCALE) / totalCalculatedStakeForReward;
        }
        uint256 pendingReward = (stake.calculatedStakeForReward * tempAccJudgePerShare) / SCALE - stake.rewardDebt;
        return pendingReward;
    }

    function recoverERC20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_strandedTokenAddr != address(0) && _addr != address(0), InvalidAddress());
        require(_amount > 0, InvalidAmount());
        require(_amount <= IERC20(_strandedTokenAddr).balanceOf(address(this)), ContractBalanceNotEnough());
        require(_strandedTokenAddr != address(judgeToken), RecoveryOfJudgeNA());
        IERC20(_strandedTokenAddr).transfer(_addr, _amount);
    }
}
