// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {JudgeTreasury} from "./JudgeTreasury.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IRewardsManager {
    function sendRewards(address _addr, uint256 _amount) external;
}

contract JudgeStaking is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;
    using SafeERC20 for IERC20;

    JudgeToken public judgeToken;
    JudgeTreasury public judgeTreasury;
    IRewardsManager public rewardsManager;

    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 public constant TOKEN_RECOVERY_ROLE = keccak256("TOKEN_RECOVERY_ROLE");

    uint64 private newStakeId;
    uint256 public accJudgePerShare;
    uint256 internal rewardsPerQuarter;
    uint256 internal rewardsPerBlock;
    uint256 public lastRewardBlock;
    uint256 public totalCalculatedStakeForReward;
    uint256 public totalStaked;
    uint64 private constant SCALE = 1e18;
    address[] internal users;
    uint16 private constant maxLockUpPeriod = 360;
    uint8 public earlyWithdrawPenaltyPercent;
    uint256 public totalPenalties;
    bool public emergencyFuncCalled;
    uint8 public constant maxPenaltyPercent = 10;
    uint8 public feePercent;
    uint8 public constant FEE_PERCENT_MAX_THRESHOLD = 30; 
    uint256 public judgeRecoveryMinimumThreshold;

    mapping(address => uint256) public feeBalanceOfStrandedToken;

    struct userStake {
        uint64 id;
        uint256 amountStaked;
        uint32 lockUpPeriod;
        uint256 lockUpRatio;
        uint256 calculatedStakeForReward;
        uint256 depositTimestamp;
        uint256 rewardDebt;
        uint256 maturityTimestamp;
    }

    mapping(address => userStake[]) internal userStakes;
    mapping(address => bool) internal isUser;

    event RewardsFunded(uint256 amount);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event EmergencyWithdrawal(
        address indexed admin, address indexed user, uint256 stakeID, uint256 stakeWithdrawn, uint256 rewardPaid
    );
    event JudgeTokenAddressWasSet(address indexed judgeTokenAddress);
    event KeyParametersUpdated(address indexed by, address indexed newRewardsManager);
    event JudgeRecoveryMinimumThresholdUpdated(uint256 oldValue, uint256 newValue);
    event EarlyWithdrawPenaltyPercentInitialized(uint256 newValue);
    event EarlyWithdrawPenaltyPercentUpdated(uint256 newValue);
    event FeePercentUpdated(uint8 oldValue, uint8 newValue);
    event EarlyWithdrawalPenalized(address indexed user, uint256 block, uint256 penalty);
    event ClaimedReward(address indexed user, uint256 rewards);
    event JudgeTokenRecovered(address indexed to, uint256 refund, uint256 fee);
    event Erc20Recovered(address indexed tokenAddress, address indexed to, uint256 refund, uint256 fee);
     event FeesFromOtherTokensTransferred (address indexed tokenAddress, address indexed to, uint256 feeTransferred, uint256 feeBalanceOfStrandedToken);

    error InvalidAmount();
    error InvalidAddress();
    error InvalidIndex();
    error InsufficientBalance();
    error AlreadyTriggered();
    error NotYetMatured();
    error InvalidLockUpPeriod();
    error AlreadyMatured();
    error ValueTooHigh();
    error ZeroStakeBalance();
    error JudgeTokenRecoveryNotAllowed();
    error InsufficientContractBalance();
    error CannotInputThisContractAddress();
    error EOANotAllowed();
    error ValueHigherThanThreshold();
    error NotUpToThreshold();

    constructor(
        address _judgeTokenAddress,
        uint8 _earlyWithdrawPenaltyPercent
    ) validAddress(_judgeTokenAddress) {
        require(_judgeTokenAddress.code.length > 0, EOANotAllowed());
        require(earlyWithdrawPenaltyPercent <= maxPenaltyPercent, ValueTooHigh());
        judgeToken = JudgeToken(_judgeTokenAddress);
        newStakeId = 1;
        earlyWithdrawPenaltyPercent = _earlyWithdrawPenaltyPercent;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        emit JudgeTokenAddressWasSet(_judgeTokenAddress);
        emit EarlyWithdrawPenaltyPercentInitialized(_earlyWithdrawPenaltyPercent);
    }

    modifier validAmount(uint256 _amount){
         require(_amount > 0, InvalidAmount());
         _;
    }

    modifier validAddress(address addr){
              require(addr != address(0), InvalidAddress());
              _;
    }

    modifier validIndex(uint16 _index){
        require(_index < userStakes[msg.sender].length, InvalidIndex());
        _;
    }

    modifier notSelf(address _to){
        require(_to != address(this), CannotInputThisContractAddress());
        _;
    }

    function setKeyParameters(address _rewardsManagerAddress, address _judgeTreasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_rewardsManagerAddress != address(0) && _judgeTreasuryAddress != address(0), InvalidAddress());
        require(_rewardsManagerAddress != address(this) && _judgeTreasuryAddress != address(this), CannotInputThisContractAddress());
        require(_rewardsManagerAddress.code.length > 0 && _judgeTreasuryAddress.code.length > 0, EOANotAllowed());

        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        judgeTreasury = JudgeTreasury(_judgeTreasuryAddress);
        emit KeyParametersUpdated(msg.sender, _rewardsManagerAddress);
    }

    function updateEarlyWithdrawPenaltyPercent(uint8 _earlyWithdrawPenaltyPercent)
        external validAmount(_earlyWithdrawPenaltyPercent)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_earlyWithdrawPenaltyPercent <= maxPenaltyPercent, ValueTooHigh());
        earlyWithdrawPenaltyPercent = _earlyWithdrawPenaltyPercent;
        emit EarlyWithdrawPenaltyPercentUpdated(_earlyWithdrawPenaltyPercent);
    }

    function updateRewardsPerBlock()public onlyRole(DEFAULT_ADMIN_ROLE)returns(uint256){
        uint32 numberOfDaysPerQuarter = 90 days;
        uint8 sepoliaBlockTime = 12 seconds;
        uint32 numberOfBlocksPerQuarter = numberOfDaysPerQuarter / sepoliaBlockTime;
        rewardsPerQuarter = judgeTreasury.quarterlyReward();
        rewardsPerBlock = rewardsPerQuarter / numberOfBlocksPerQuarter;
        return rewardsPerBlock;
    }

     function updateFeePercent(uint8 _newFeePercent) external onlyRole(STAKING_ADMIN_ROLE){
        require(_newFeePercent < FEE_PERCENT_MAX_THRESHOLD, ValueHigherThanThreshold());
        uint8 oldFeePercent = feePercent;
        feePercent = _newFeePercent;
        emit FeePercentUpdated(oldFeePercent, _newFeePercent);
    }

    function updateJudgeRecoveryMinimumThreshold(uint256 newJudgeRecoveryMinimumThreshold) external onlyRole(STAKING_ADMIN_ROLE){
        uint256 oldJudgeRecoveryMinimumThreshold = judgeRecoveryMinimumThreshold;
        judgeRecoveryMinimumThreshold = newJudgeRecoveryMinimumThreshold;
        emit JudgeRecoveryMinimumThresholdUpdated(oldJudgeRecoveryMinimumThreshold, newJudgeRecoveryMinimumThreshold);
    }

    function updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }
        if (totalCalculatedStakeForReward == 0) {
            lastRewardBlock = block.number;
        }
        uint256 blocksPassed = block.number - lastRewardBlock;
        uint256 totalReward = blocksPassed * updateRewardsPerBlock();
        accJudgePerShare += (totalReward * SCALE) / totalCalculatedStakeForReward;
        lastRewardBlock = block.number;
    }

    function accumulatedStakeRewards(uint16 _index) internal view returns(uint256){
         userStake storage stake = userStakes[msg.sender][_index];
        uint256 accRewards = (stake.calculatedStakeForReward * accJudgePerShare) / SCALE;
        return accRewards;
    }

    function deposit(uint256 _amount, uint32 _lockUpPeriodInDays) external validAmount(_amount) validAmount(_lockUpPeriodInDays) {
        require(_lockUpPeriodInDays <= maxLockUpPeriod, InvalidLockUpPeriod());
        if (!isUser[msg.sender]) {
            users.push(msg.sender);
            isUser[msg.sender] = true;
        }

        updatePool();
        uint256 amountStaked = _amount;
        uint32 lockUpPeriod = _lockUpPeriodInDays;
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

    function claimRewards(uint16 _index) external validIndex(_index) nonReentrant{
        userStake storage stake = userStakes[msg.sender][_index];
        require(stake.amountStaked > 0, ZeroStakeBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
        }
        stake.rewardDebt = accumulatedStakeRewards(_index);
        emit ClaimedReward(msg.sender, pending);
    }

    function withdraw(uint256 _amount, uint16 _index) external validAmount(_amount) validIndex(_index) nonReentrant {
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp >= stake.maturityTimestamp, NotYetMatured());
        require(_amount <= stake.amountStaked, InsufficientBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
        }
        totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
        stake.amountStaked -= _amount;
        stake.calculatedStakeForReward = (stake.amountStaked * stake.lockUpRatio) / SCALE;
        totalCalculatedStakeForReward += stake.calculatedStakeForReward;
        stake.rewardDebt = accumulatedStakeRewards(_index);
        totalStaked -= _amount;
        judgeToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function withdrawAll(uint16 _index) external validIndex(_index) nonReentrant {
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp >= stake.maturityTimestamp, NotYetMatured());
        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
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

    function earlyWithdraw(uint16 _index, uint256 _amount) external validAmount(_amount) validIndex(_index) nonReentrant{

        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp < stake.maturityTimestamp, AlreadyMatured());
        require(_amount <= stake.amountStaked, InsufficientBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
        }

        totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
        uint256 penalty = (_amount * earlyWithdrawPenaltyPercent) / 100;
        uint256 deduction = _amount + penalty;
        require(deduction <= stake.amountStaked, InsufficientBalance());
        if (deduction == stake.amountStaked) {
            stake.amountStaked = 0;
            stake.calculatedStakeForReward = 0;
            stake.rewardDebt = 0;
        } else {
            stake.amountStaked -= deduction;
            stake.calculatedStakeForReward = (stake.amountStaked * stake.lockUpRatio) / SCALE;
            totalCalculatedStakeForReward += stake.calculatedStakeForReward;
            stake.rewardDebt = accumulatedStakeRewards(_index);
        }
        totalStaked -= deduction;
        totalPenalties += penalty;
        judgeToken.safeTransfer(address(judgeTreasury), penalty);
        judgeTreasury.increaseTreasuryPreciseBalance(penalty);
        judgeToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
        emit EarlyWithdrawalPenalized(msg.sender, block.number, penalty);
    }

    function emergencyWithdraw() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant{
        require(!emergencyFuncCalled, AlreadyTriggered());
        emergencyFuncCalled = true;
        for (uint32 i; i < users.length; i++) {
            address userAddr = users[i];
            for (uint16 j; j < userStakes[users[i]].length; j++) {
                userStake storage stake = userStakes[users[i]][j];

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

    function viewMyStakeAtIndex(uint16 _index) external view validIndex(_index) returns (userStake memory) {
        return userStakes[msg.sender][_index];
    }

    function viewUsersList() external view onlyRole(DEFAULT_ADMIN_ROLE) returns (address[] memory) {
        return users;
    }

    function viewUserStakes(address addr) external view validAddress(addr) onlyRole(DEFAULT_ADMIN_ROLE) returns (userStake[] memory) {
        return userStakes[addr];
    }

    function viewUserStakeAtIndex(address addr, uint16 _index)
        external
        view validAddress(addr)
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (userStake memory)
    {
        require(_index < userStakes[addr].length, InvalidIndex());
        return userStakes[addr][_index];
    }

    function viewMyPendingRewards(uint16 _index) external view validIndex(_index) returns (uint256) {
        userStake memory stake = userStakes[msg.sender][_index];
        uint256 tempAccJudgePerShare = accJudgePerShare;

        if (block.number > lastRewardBlock && totalCalculatedStakeForReward > 0) {
            uint256 blocksPassed = block.number - lastRewardBlock;
            uint256 totalReward = blocksPassed * rewardsPerBlock;
            tempAccJudgePerShare += (totalReward * SCALE) / totalCalculatedStakeForReward;
        }
        uint256 pendingReward = (stake.calculatedStakeForReward * tempAccJudgePerShare) / SCALE - stake.rewardDebt;
        return pendingReward;
    }

    function calculateMisplacedJudge() public view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        uint256 contractBalance = judgeToken.balanceOf(address(this));
        uint256 misplacedJudgeAmount = contractBalance - totalStaked;
        return misplacedJudgeAmount;
    }

    function recoverMisplacedJudgeToken(address _to, uint256 _amount)external validAddress(_to) validAmount(_amount) notSelf(_to)  onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant{
        uint256 misplacedJudgeAmount = calculateMisplacedJudge();
        require(_amount <= misplacedJudgeAmount, InvalidAmount());
        require(_amount >= judgeRecoveryMinimumThreshold, NotUpToThreshold());
        uint256 refund = (_amount * (100-uint256(feePercent)))/100;
        uint256 fee = _amount - refund;
        judgeToken.safeTransfer(address(judgeTreasury), fee);
        judgeTreasury.increaseTreasuryPreciseBalance(fee);
        judgeToken.safeTransfer(_to, refund);
        emit JudgeTokenRecovered(_to, refund, fee);
    }

    function recoverErc20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        notSelf(_addr) validAmount(_amount) onlyRole(TOKEN_RECOVERY_ROLE) 
    nonReentrant{
        require(_strandedTokenAddr != address(0) && _addr != address(0), InvalidAddress());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        require(_amount <= IERC20(_strandedTokenAddr).balanceOf(address(this)), InsufficientContractBalance());
        
        uint256 refund = (_amount * (100-uint256(feePercent)))/100;
        uint256 fee = _amount - refund;
        feeBalanceOfStrandedToken[_strandedTokenAddr] += fee;
        IERC20(_strandedTokenAddr).safeTransfer(_addr, refund);
        emit Erc20Recovered(_strandedTokenAddr, _addr, refund, fee);
    }

    function transferFeesFromOtherTokensOutOfStaking(address _strandedTokenAddr, address _to, uint256 _amount)external notSelf(_to) validAmount(_amount) onlyRole(STAKING_ADMIN_ROLE) nonReentrant{
        require(_strandedTokenAddr != address(0) && _to != address(0), InvalidAddress());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        require(_amount <= feeBalanceOfStrandedToken[_strandedTokenAddr], InsufficientBalance());
        feeBalanceOfStrandedToken[_strandedTokenAddr] -= _amount;
        IERC20(_strandedTokenAddr).safeTransfer(_to, _amount);
        emit FeesFromOtherTokensTransferred(_strandedTokenAddr, _to, _amount, feeBalanceOfStrandedToken[_strandedTokenAddr]);
    }
}
