// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {JudgeTreasury} from "./JudgeTreasury.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
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

    uint256 public stakingPoolStartTime;
    uint64 private newStakeId;
    uint256 public accJudgePerShare;
    uint256 public rewardsPerBlock;
    uint256 public lastRewardBlock;
    uint256 public totalCalculatedStakeForReward;
    uint256 public totalStaked;
    uint64 private constant SCALE = 1e18;
    address[] internal users;
    uint16 private constant maxLockUpPeriod = 360;
    uint8 public earlyWithdrawPenaltyPercent;
    uint256 public totalPenalties;
    bool public emergencyFuncCalled;
    uint8 public constant maxPenaltyPercent = 20;
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
    mapping(uint256 => uint256) public quarterRewardsPaid;

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
    error OverPaidRewards();

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
        stakingPoolStartTime = block.timestamp;
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

    function setKeyParameters(address _rewardsManagerAddress, address _judgeTreasuryAddress) external onlyRole(STAKING_ADMIN_ROLE) {
        require(_rewardsManagerAddress != address(0) && _judgeTreasuryAddress != address(0), InvalidAddress());
        require(_rewardsManagerAddress != address(this) && _judgeTreasuryAddress != address(this), CannotInputThisContractAddress());
        require(_rewardsManagerAddress.code.length > 0 && _judgeTreasuryAddress.code.length > 0, EOANotAllowed());

        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        judgeTreasury = JudgeTreasury(_judgeTreasuryAddress);
        emit KeyParametersUpdated(msg.sender, _rewardsManagerAddress);
    }

    function updateEarlyWithdrawPenaltyPercent(uint8 _earlyWithdrawPenaltyPercent)
        external validAmount(_earlyWithdrawPenaltyPercent)
        onlyRole(STAKING_ADMIN_ROLE)
    {
        require(_earlyWithdrawPenaltyPercent <= maxPenaltyPercent, ValueTooHigh());
        earlyWithdrawPenaltyPercent = _earlyWithdrawPenaltyPercent;
        emit EarlyWithdrawPenaltyPercentUpdated(_earlyWithdrawPenaltyPercent);
    }

    function getCurrentQuarterIndex()public view returns(uint256){
        return (block.timestamp - stakingPoolStartTime) / 90 days + 1;
    }

    function calculateCurrentRewardsPerBlock()public returns(uint256){

       uint256 currentQuarterIndex = getCurrentQuarterIndex();
        uint256 totalRewards = judgeTreasury.quarterlyRewards(currentQuarterIndex) + judgeTreasury.additionalQuarterRewards(currentQuarterIndex);
        uint256 totalRewardsPaidinCurrentQuarter = quarterRewardsPaid[currentQuarterIndex];
        require (totalRewards >= totalRewardsPaidinCurrentQuarter, OverPaidRewards());
        uint256 remainingRewards = totalRewards - totalRewardsPaidinCurrentQuarter;

        uint256 quarterStart = stakingPoolStartTime + (currentQuarterIndex-1) * 90 days;
        uint256 quarterEnd = quarterStart + 90 days;

        if(block.timestamp > quarterEnd){
            return 0;
        }

        uint256 remainingTime = quarterEnd - block.timestamp;
        uint8 sepoliaBlockTime = 12 seconds;
        uint256 numberOfBlocksLeft = remainingTime / sepoliaBlockTime;
        if(numberOfBlocksLeft== 0){
            return 0;
        }
      rewardsPerBlock = remainingRewards / uint256(numberOfBlocksLeft);
      return rewardsPerBlock;
    }

    function getCurrentAPR() public returns(uint256){
        rewardsPerBlock = calculateCurrentRewardsPerBlock();
        uint256 blocksPerYear = 365 days / 12 seconds;
        // APR is scaled by 1e18, divide by same factor and multiply by 100 to get exact value
        return Math.mulDiv(Math.mulDiv(rewardsPerBlock, blocksPerYear, 1), 1e18, totalStaked);
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
            return;
        }
        uint256 blocksPassed = block.number - lastRewardBlock;
        uint256 totalReward = blocksPassed * calculateCurrentRewardsPerBlock();
        accJudgePerShare += Math.mulDiv(totalReward, SCALE, totalCalculatedStakeForReward);
        lastRewardBlock = block.number;
    }

    function accumulatedStakeRewards(uint16 _index) internal view returns(uint256){
         userStake storage stake = userStakes[msg.sender][_index];
        uint256 accRewards = Math.mulDiv(stake.calculatedStakeForReward, accJudgePerShare, SCALE);
        return accRewards;
    }

    function deposit(uint256 _amount, uint32 _lockUpPeriodInDays) external validAmount(_amount) validAmount(_lockUpPeriodInDays) {
        require(_lockUpPeriodInDays <= maxLockUpPeriod, InvalidLockUpPeriod());
        if (!isUser[msg.sender]) {
            users.push(msg.sender);
            isUser[msg.sender] = true;
        }

        uint256 amountStaked = _amount;
        uint32 lockUpPeriod = _lockUpPeriodInDays;
        uint256 lockUpRatio = Math.mulDiv(lockUpPeriod, SCALE, maxLockUpPeriod);
        uint256 depositTimestamp = block.timestamp;
        uint256 maturityTimestamp = depositTimestamp + lockUpPeriod;
        uint256 calculatedStakeForReward = Math.mulDiv(amountStaked, lockUpRatio, SCALE);
        totalCalculatedStakeForReward += calculatedStakeForReward;
        lastRewardBlock = block.number;
        totalStaked += _amount;

        updatePool();
        uint256 rewardDebt = Math.mulDiv(calculatedStakeForReward, accJudgePerShare, SCALE);
        
       

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

        newStakeId++;
        emit Deposited(msg.sender, _amount);
    }

    function claimRewards(uint16 _index) external validIndex(_index) nonReentrant{
        uint256 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(stake.amountStaked > 0, ZeroStakeBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending
;        }
        stake.rewardDebt = accumulatedStakeRewards(_index);
        emit ClaimedReward(msg.sender, pending);
    }

    function withdraw(uint256 _amount, uint16 _index) external validAmount(_amount) validIndex(_index) nonReentrant {
        uint256 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp >= stake.maturityTimestamp, NotYetMatured());
        require(_amount <= stake.amountStaked, InsufficientBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending;
        }
        totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
        stake.amountStaked -= _amount;
        stake.calculatedStakeForReward = Math.mulDiv(stake.amountStaked, stake.lockUpRatio, SCALE);
        totalCalculatedStakeForReward += stake.calculatedStakeForReward;
        stake.rewardDebt = accumulatedStakeRewards(_index);
        totalStaked -= _amount;
        judgeToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function withdrawAll(uint16 _index) external validIndex(_index) nonReentrant {
        uint256 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp >= stake.maturityTimestamp, NotYetMatured());
        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending;
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
        uint256 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.timestamp < stake.maturityTimestamp, AlreadyMatured());
        require(_amount <= stake.amountStaked, InsufficientBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending;
        }

        totalCalculatedStakeForReward -= stake.calculatedStakeForReward;
        uint256 penalty = Math.mulDiv(_amount, earlyWithdrawPenaltyPercent, 100);
        uint256 deduction = _amount + penalty;
        require(deduction <= stake.amountStaked, InsufficientBalance());
        if (deduction == stake.amountStaked) {
            stake.amountStaked = 0;
            stake.calculatedStakeForReward = 0;
            stake.rewardDebt = 0;
        } else {
            stake.amountStaked -= deduction;
            stake.calculatedStakeForReward = Math.mulDiv(stake.amountStaked, stake.lockUpRatio, SCALE);
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

    function emergencyWithdraw() external nonReentrant onlyRole(STAKING_ADMIN_ROLE) nonReentrant{
        require(!emergencyFuncCalled, AlreadyTriggered());
        emergencyFuncCalled = true;
        uint256 currentQuarterIndex = getCurrentQuarterIndex();
        for (uint32 i; i < users.length; i++) {
            address userAddr = users[i];
            for (uint16 j; j < userStakes[users[i]].length; j++) {
                userStake storage stake = userStakes[users[i]][j];

                updatePool();
                if (stake.amountStaked > 0) {
                    uint256 pending = Math.mulDiv(stake.amountStaked, accJudgePerShare, SCALE) - stake.rewardDebt;

                    rewardsManager.sendRewards(msg.sender, pending);
                    quarterRewardsPaid[currentQuarterIndex] += pending;

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

    function viewUsersList() external view onlyRole(STAKING_ADMIN_ROLE) returns (address[] memory) {
        return users;
    }

    function viewUserStakes(address addr) external view validAddress(addr) onlyRole(STAKING_ADMIN_ROLE) returns (userStake[] memory) {
        return userStakes[addr];
    }

    function viewUserStakeAtIndex(address addr, uint16 _index)
        external
        view validAddress(addr)
        onlyRole(STAKING_ADMIN_ROLE)
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
            tempAccJudgePerShare += Math.mulDiv(totalReward, SCALE, totalCalculatedStakeForReward);
        }
        uint256 pendingReward = Math.mulDiv(stake.calculatedStakeForReward, tempAccJudgePerShare, SCALE) - stake.rewardDebt;
        return pendingReward;
    }

    function calculateMisplacedJudge() public view onlyRole(TOKEN_RECOVERY_ROLE) returns (uint256) {
        uint256 contractBalance = judgeToken.balanceOf(address(this));
        uint256 misplacedJudgeAmount = contractBalance - totalStaked;
        return misplacedJudgeAmount;
    }

    function recoverMisplacedJudgeToken(address _to, uint256 _amount)external validAddress(_to) validAmount(_amount) notSelf(_to)  onlyRole(TOKEN_RECOVERY_ROLE) nonReentrant{
        uint256 misplacedJudgeAmount = calculateMisplacedJudge();
        require(_amount <= misplacedJudgeAmount, InvalidAmount());
        require(_amount >= judgeRecoveryMinimumThreshold, NotUpToThreshold());
        uint256 refund = Math.mulDiv(_amount, (100-uint256(feePercent)), 100);
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
        
        uint256 refund = Math.mulDiv(_amount, (100-uint256(feePercent)), 100);
        uint256 fee = _amount - refund;
        feeBalanceOfStrandedToken[_strandedTokenAddr] += fee;
        IERC20(_strandedTokenAddr).safeTransfer(_addr, refund);
        emit Erc20Recovered(_strandedTokenAddr, _addr, refund, fee);
    }

    function transferFeesFromOtherTokensOutOfStaking(address _strandedTokenAddr, address _to, uint256 _amount)external notSelf(_to) validAmount(_amount) onlyRole(TOKEN_RECOVERY_ROLE) nonReentrant{
        require(_strandedTokenAddr != address(0) && _to != address(0), InvalidAddress());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        require(_amount <= feeBalanceOfStrandedToken[_strandedTokenAddr], InsufficientBalance());
        feeBalanceOfStrandedToken[_strandedTokenAddr] -= _amount;
        IERC20(_strandedTokenAddr).safeTransfer(_to, _amount);
        emit FeesFromOtherTokensTransferred(_strandedTokenAddr, _to, _amount, feeBalanceOfStrandedToken[_strandedTokenAddr]);
    }
}