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
    function sendBonus(address _addr, uint256 _amount) external;
}

contract JudgeStaking is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;
    using SafeERC20 for IERC20;

    JudgeToken public judgeToken;
    JudgeTreasury public judgeTreasury;
    IRewardsManager public rewardsManager;

    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 public constant TOKEN_RECOVERY_ROLE = keccak256("TOKEN_RECOVERY_ROLE");
    bytes32 public constant REWARDS_PER_BLOCK_CALCULATOR = keccak256("REWARDS_PER_BLOCK_CALCULATOR"); //Assign to judgeTreasury at deployment

    uint256 public stakingPoolStartBlock;
    uint256 public constant QUARTER_BLOCKS = 648_000;
    uint8 public constant MAX_UPDATE_QUARTERS = 4;
    uint64 private newStakeId;
    uint256 public accJudgePerShare; //cummulated JUDGE base rewards that a single JUDGE token stake weight is expected to receive
    uint256 public accBonusJudgePerShare; //cummulated JUDGE bonus rewards that a single JUDGE token stake weight is expected to receive
    uint256 public lastRewardBlock;
    uint256 public totalStakeWeight; //The total calculated stake weights of all stakers based on the stake amount and chosen lockup period.
    uint256 public totalStaked;
    uint64 private constant SCALE = 1e18;
    uint32 private constant BLOCKS_PER_YEAR = 2_628_000;
    address[] internal users;
    uint16 private constant maxLockUpPeriod = 360;
    uint8 public earlyWithdrawPenaltyPercentForMaxLockupPeriod; //This is the penalty percent that is charged on a user stake if they
    //lockup for 360 days maxLockUpPeriod and withdraw early, for lower lockUpPeriods, the penalty is scaled down based on duration/maxLockUpPeriod
    uint256 public totalPenalties; //total penalty fees recieved for all users who did unripe withdrawals
    bool public emergencyFuncCalled; //Boolean prevents the emergency function from being called more than once
    uint8 public constant maxPenaltyPercent = 20;
    uint8 public feePercent; //Fee charged to recover misplaced JudgeTokens sent to the contract
    uint8 public constant FEE_PERCENT_MAX_THRESHOLD = 30;
    uint256 public judgeRecoveryMinimumThreshold; //Feasible minimum amount of JudgeTokens that's worth recovering

    struct userStake {
        uint64 id;
        uint256 amountStaked;
        uint32 lockUpPeriod;
        uint256 lockUpRatio;
        uint256 stakeWeight;
        uint256 depositBlockNumber;
        uint256 rewardDebt;
        uint256 bonusRewardDebt;
        uint256 maturityBlockNumber;
    }

    mapping(address => userStake[]) internal userStakes; //Mapping that maps every userStakes as a struct array to their address
    mapping(address => bool) internal isUser; //Mapping checks if a user address has staked before, preventing duplicate address in userlist
    mapping(uint32 => uint256) public rewardsPerBlockForQuarter;
    mapping(uint32 => uint256) public bonusPerBlockForQuarter;
    mapping(uint256 => uint256) public quarterRewardsPaid; //Maps total base rewards claimed in each quarter
    mapping(uint256 => uint256) public quarterBonusRewardsPaid; //Maps total bonus rewards claimed in each quarter
    mapping(uint256 => uint256) public quarterAccruedRewardsForStakes; //Maps total base rewards accrued (both claimed and pending) in each quarter
    mapping(uint256 => uint256) public quarterAccruedBonusRewardsForStakes; //Maps total bonus rewards accrued (both claimed and pending) in each quarter
    mapping(address => uint256) public feeBalanceOfStrandedToken; //mapping of accumulated fee of recovered misplaced tokens

    event RewardsFunded(uint256 amount);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 rewardsPaid);
    event EmergencyWithdrawal(
        address indexed admin, address indexed user, uint256 stakeID, uint256 stakeWithdrawn, uint256 rewardsPaid
    );
    event JudgeTokenAddressWasSet(address indexed judgeTokenAddress);
    event RewardsManagerAddressUpdated(address indexed newRewardsManagerAddress);
    event JudgeTreasuryAddressUpdated(address indexed newJudgeTreasuryAddress);
    event JudgeRecoveryMinimumThresholdUpdated(uint256 oldValue, uint256 newValue);
    event EarlyWithdrawPenaltyPercentForMaxLockupPeriodInitialized(uint256 newValue);
    event EarlyWithdrawPenaltyPercentForMaxLockupPeriodUpdated(uint256 newValue);
    event FeePercentUpdated(uint8 oldValue, uint8 newValue);
    event EarlyWithdrawalPenalized(address indexed user, uint256 block, uint256 penalty);
    event ClaimedReward(address indexed user, uint256 rewards);
    event JudgeTokenRecovered(address indexed to, uint256 refund, uint256 fee);
    event Erc20Recovered(address indexed tokenAddress, address indexed to, uint256 refund, uint256 fee);
    event FeesFromOtherTokensTransferred(
        address indexed tokenAddress, address indexed to, uint256 feeTransferred, uint256 feeBalanceOfStrandedToken
    );

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
    error QuarterNotStarted();
    error RewardsManagerNotSet()

    constructor(address _judgeTokenAddress, uint8 _earlyWithdrawPenaltyPercentForMaxLockupPeriod)
        validAddress(_judgeTokenAddress)
    {
        require(_judgeTokenAddress.code.length > 0, EOANotAllowed());
        require(_earlyWithdrawPenaltyPercentForMaxLockupPeriod <= maxPenaltyPercent, ValueTooHigh());
        judgeToken = JudgeToken(_judgeTokenAddress);
        newStakeId = 1;
        earlyWithdrawPenaltyPercentForMaxLockupPeriod = _earlyWithdrawPenaltyPercentForMaxLockupPeriod;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        stakingPoolStartBlock = block.number;
        emit JudgeTokenAddressWasSet(_judgeTokenAddress);
        emit EarlyWithdrawPenaltyPercentForMaxLockupPeriodInitialized(_earlyWithdrawPenaltyPercentForMaxLockupPeriod);
    }

    modifier validAmount(uint256 _amount) {
        require(_amount > 0, InvalidAmount());
        _;
    }

    modifier validAddress(address addr) {
        require(addr != address(0), InvalidAddress());
        _;
    }

    modifier validIndex(uint16 _index) {
        require(_index < userStakes[msg.sender].length, InvalidIndex());
        _;
    }

    modifier notSelf(address _to) {
        require(_to != address(this), CannotInputThisContractAddress());
        _;
    }

    modifier notEOA(address _addr) {
        require(_addr.code.length > 0, EOANotAllowed());
        _;
    }

    function setRewardsManagerAddress(address _rewardsManagerAddress)
        external
        onlyRole(STAKING_ADMIN_ROLE)
        validAddress(_rewardsManagerAddress)
        notSelf(_rewardsManagerAddress)
        notEOA(_rewardsManagerAddress)
    {
        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit RewardsManagerAddressUpdated(_rewardsManagerAddress);
    }

    function setJudgeTreasuryAddress(address _judgeTreasuryAddress)
        external
        onlyRole(STAKING_ADMIN_ROLE)
        validAddress(_judgeTreasuryAddress)
        notSelf(_judgeTreasuryAddress)
        notEOA(_judgeTreasuryAddress)
    {
        judgeTreasury = JudgeTreasury(_judgeTreasuryAddress);
        _grantRole(REWARDS_PER_BLOCK_CALCULATOR, _judgeTreasuryAddress);
        emit JudgeTreasuryAddressUpdated(_judgeTreasuryAddress);
    }

    function updateEarlyWithdrawPenaltyPercentForMaxLockupPeriod(uint8 _earlyWithdrawPenaltyPercentForMaxLockupPeriod)
        external
        validAmount(_earlyWithdrawPenaltyPercentForMaxLockupPeriod)
        onlyRole(STAKING_ADMIN_ROLE)
    {
        require(_earlyWithdrawPenaltyPercentForMaxLockupPeriod <= maxPenaltyPercent, ValueTooHigh());
        earlyWithdrawPenaltyPercentForMaxLockupPeriod = _earlyWithdrawPenaltyPercentForMaxLockupPeriod;
        emit EarlyWithdrawPenaltyPercentForMaxLockupPeriodUpdated(_earlyWithdrawPenaltyPercentForMaxLockupPeriod);
    }

    function updateFeePercent(uint8 _newFeePercent) external onlyRole(STAKING_ADMIN_ROLE) {
        require(_newFeePercent <= FEE_PERCENT_MAX_THRESHOLD, ValueHigherThanThreshold());
        uint8 oldFeePercent = feePercent;
        feePercent = _newFeePercent;
        emit FeePercentUpdated(oldFeePercent, _newFeePercent);
    }

    function updateJudgeRecoveryMinimumThreshold(uint256 newJudgeRecoveryMinimumThreshold)
        external
        onlyRole(STAKING_ADMIN_ROLE)
    {
        uint256 oldJudgeRecoveryMinimumThreshold = judgeRecoveryMinimumThreshold;
        judgeRecoveryMinimumThreshold = newJudgeRecoveryMinimumThreshold;
        emit JudgeRecoveryMinimumThresholdUpdated(oldJudgeRecoveryMinimumThreshold, newJudgeRecoveryMinimumThreshold);
    }

    function getCurrentQuarterIndex() public view returns (uint32) {
        return uint32((block.number - stakingPoolStartBlock) / QUARTER_BLOCKS + 1);
    }

    function getQuarterIndexFromBlock(uint256 blockNumber) internal view returns(uint32){
        return uint32(blockNumber > stakingPoolStartBlock ? ((blockNumber - stakingPoolStartBlock) / QUARTER_BLOCKS) +1 : 1);
    }

    function syncQuarterBonusRewardsPerBlock(uint32 quarterIndex, uint256 _bonus, uint256 _durationInBlocks) external onlyRole(REWARDS_PER_BLOCK_CALCULATOR){
        bonusPerBlockForQuarter[quarterIndex] = _bonus / _durationInBlocks;
    }

    function syncQuarterRewardsPerBlock(uint32 quarterIndex) external onlyRole(REWARDS_PER_BLOCK_CALCULATOR) {
        uint256 totalQuarterRewards = judgeTreasury.quarterlyRewards(quarterIndex);
        uint256 rpb = 0;

        if(totalQuarterRewards > 0){
            rpb = totalQuarterRewards / QUARTER_BLOCKS;
        }

        rewardsPerBlockForQuarter[quarterIndex] = rpb;
    }

    function getCurrentAPR() public view returns (uint256) {
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        if (totalStakeWeight == 0) {
            return 0;
        }
        // APR is scaled by 1e18, divide by same factor and multiply by 100 to get exact value
        uint256 apr1 = Math.mulDiv(Math.mulDiv(rewardsPerBlockForQuarter[currentQuarterIndex], BLOCKS_PER_YEAR, 1), 1e18, totalStakeWeight);
        uint256 apr2 = Math.mulDiv(Math.mulDiv(bonusPerBlockForQuarter[currentQuarterIndex], BLOCKS_PER_YEAR, 1), 1e18, totalStakeWeight);

        return apr1 + apr2;
    }

    function updatePool() public {
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        
        if (block.number <= lastRewardBlock) return;
        if (totalStakeWeight == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint32 startQuarter = getQuarterIndexFromBlock(lastRewardBlock);
        uint32 processed = 0;
        while(startQuarter <= currentQuarterIndex && processed < MAX_UPDATE_QUARTERS){
        uint256 quarterStart = stakingPoolStartBlock + (uint256(startQuarter) - 1) * 648_000;
        uint256 quarterEnd = quarterStart + 648_000;
        uint256 startQuarterBonusEnd = judgeTreasury.bonusEndBlock(startQuarter);

        uint256 rpb = rewardsPerBlockForQuarter[startQuarter];
        uint256 bpb = bonusPerBlockForQuarter[startQuarter];

        if(rpb == 0 && bpb == 0){
            unchecked{
                startQuarter++;
                processed++;
            }
            continue;
        }

        uint256 endBlock = (startQuarter == currentQuarterIndex) ? block.number : quarterEnd;

        uint256 reward = 0;
        uint256 bonusReward = 0;
        if(endBlock > lastRewardBlock){
           uint256 blocksPassed = endBlock - lastRewardBlock;
            reward = blocksPassed * rpb;
        accJudgePerShare += Math.mulDiv(reward, SCALE, totalStakeWeight);

        uint256 bonusBlocks = 0;
        if(startQuarterBonusEnd > lastRewardBlock){
            bonusBlocks = Math.min(blocksPassed, startQuarterBonusEnd - lastRewardBlock);
            bonusReward = bonusBlocks * bpb;
        }
         accBonusJudgePerShare += Math.mulDiv(bonusReward, SCALE, totalStakeWeight);
        }

        quarterAccruedRewardsForStakes[startQuarter] += reward;
        quarterAccruedBonusRewardsForStakes[startQuarter] += bonusReward;

        lastRewardBlock = endBlock;
        unchecked{
        startQuarter++;
        processed++;
        }
        }
    }


    function deposit(uint256 _amount, uint32 _lockUpPeriodInDays)
        external
        validAmount(_amount)
        validAmount(_lockUpPeriodInDays)
    {
        require(_lockUpPeriodInDays <= maxLockUpPeriod, InvalidLockUpPeriod());

        updatePool(); /**Becomes a bug when there are many missed quarters and a user calls deposit function. Fix it */

        uint256 amountStaked = _amount;
        uint32 lockUpPeriod = _lockUpPeriodInDays;
        uint256 lockUpRatio = Math.mulDiv(lockUpPeriod, SCALE, maxLockUpPeriod);
        uint256 depositBlockNumber = block.number;
        uint256 maturityBlockNumber = depositBlockNumber + (lockUpPeriod * 7200);
        uint256 stakeWeight = Math.mulDiv(amountStaked, lockUpRatio, SCALE);
        totalStakeWeight += stakeWeight;
        totalStaked += _amount;

        uint256 rewardDebt = Math.mulDiv(stakeWeight, accJudgePerShare, SCALE);
        uint256 bonusRewardDebt = Math.mulDiv(stakeWeight, accBonusJudgePerShare, SCALE);

        userStake memory newStake = userStake({
            id: newStakeId,
            amountStaked: amountStaked,
            lockUpPeriod: lockUpPeriod,
            lockUpRatio: lockUpRatio,
            stakeWeight: stakeWeight,
            depositBlockNumber: depositBlockNumber,
            rewardDebt: rewardDebt,
            bonusRewardDebt: bonusRewardDebt,
            maturityBlockNumber: maturityBlockNumber
        });

        judgeToken.safeTransferFrom(msg.sender, address(this), _amount);
        userStakes[msg.sender].push(newStake);

        if (!isUser[msg.sender]) {
            users.push(msg.sender);
            isUser[msg.sender] = true;
        }

        newStakeId++;
        emit Deposited(msg.sender, _amount);
    }

    function accumulatedStakeRewards(uint16 _index) internal view returns (uint256) {
        userStake storage stake = userStakes[msg.sender][_index];
        uint256 accRewards = Math.mulDiv(stake.stakeWeight, accJudgePerShare, SCALE);
        return accRewards;
    }

    function accumulatedStakeBonusRewards(uint16 _index) internal view returns (uint256) {
        userStake storage stake = userStakes[msg.sender][_index];
        uint256 accBonusRewards = Math.mulDiv(stake.stakeWeight, accBonusJudgePerShare, SCALE);
        return accBonusRewards;
    }

    function claimRewards(uint16 _index) external validIndex(_index) nonReentrant {
           require(address(rewardsManager) != address(0), RewardsManagerNotSet());
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(stake.amountStaked > 0, ZeroStakeBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        uint256 pendingBonus = accumulatedStakeBonusRewards(_index) - stake.bonusRewardDebt;

        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending;
            stake.rewardDebt = accumulatedStakeRewards(_index);
        }

        if (pendingBonus > 0) {
            rewardsManager.sendBonus(msg.sender, pendingBonus);
            quarterBonusRewardsPaid[currentQuarterIndex] += pendingBonus;
            stake.bonusRewardDebt = accumulatedStakeBonusRewards(_index);
        }

        emit ClaimedReward(msg.sender, pending);
    }

    function withdraw(uint256 _amount, uint16 _index) external validAmount(_amount) validIndex(_index) nonReentrant {
        require(address(rewardsManager) != address(0), RewardsManagerNotSet());
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.number >= stake.maturityBlockNumber, NotYetMatured());
        require(_amount <= stake.amountStaked, InsufficientBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        uint256 pendingBonus = accumulatedStakeBonusRewards(_index) - stake.bonusRewardDebt;

        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending;
            // Check if it's legit that rewards paid doesnt come from misssed quarters and get added to quarter rewards paid
        }

        if (pendingBonus > 0) {
            rewardsManager.sendBonus(msg.sender, pendingBonus);
            quarterBonusRewardsPaid[currentQuarterIndex] += pendingBonus;
            // Same here
        }

        judgeToken.safeTransfer(msg.sender, _amount);

        uint256 oldStakeWeight = stake.stakeWeight;
        stake.amountStaked -= _amount;
        stake.stakeWeight = Math.mulDiv(stake.amountStaked, stake.lockUpRatio, SCALE);
        totalStakeWeight =totalStakeWeight - oldStakeWeight + stake.stakeWeight;
        stake.rewardDebt = accumulatedStakeRewards(_index);
        stake.bonusRewardDebt = accumulatedStakeBonusRewards(_index);
        totalStaked -= _amount;
        emit Withdrawn(msg.sender, _amount, pending + pendingBonus);
    }

    function withdrawAll(uint16 _index) external validIndex(_index) nonReentrant {
        require(address(rewardsManager) != address(0), RewardsManagerNotSet());
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.number >= stake.maturityBlockNumber, NotYetMatured());
        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        uint256 pendingBonus = accumulatedStakeBonusRewards(_index) - stake.bonusRewardDebt;

        uint256 amountWithdrawn = stake.amountStaked;

        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending;

            // Same here
        }

        if (pendingBonus > 0) {
            rewardsManager.sendBonus(msg.sender, pendingBonus);
            quarterBonusRewardsPaid[currentQuarterIndex] += pendingBonus;
            // Same here
        }
        judgeToken.safeTransfer(msg.sender, amountWithdrawn);

        totalStakeWeight -= stake.stakeWeight;
        stake.amountStaked = 0;
        stake.stakeWeight = 0;
        totalStaked -= amountWithdrawn;
        stake.rewardDebt = 0;
        stake.bonusRewardDebt = 0;
        emit Withdrawn(msg.sender, amountWithdrawn, pending + pendingBonus);
    }

    function earlyWithdraw(uint256 _amount, uint16 _index)
        external
        validAmount(_amount)
        validIndex(_index)
        nonReentrant
    {
        require(address(rewardsManager) != address(0), RewardsManagerNotSet());
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.number < stake.maturityBlockNumber, AlreadyMatured());
        require(_amount <= stake.amountStaked, InsufficientBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        uint256 pendingBonus = accumulatedStakeBonusRewards(_index) - stake.bonusRewardDebt;

        uint256 oldStakeWeight = stake.stakeWeight;
        uint256 penalty = Math.mulDiv(
            _amount, Math.mulDiv(earlyWithdrawPenaltyPercentForMaxLockupPeriod, stake.lockUpRatio, SCALE), 100
        );
        uint256 netAmount = _amount - penalty;

        judgeToken.safeTransfer(address(judgeTreasury), penalty);
        totalPenalties += penalty;
        judgeTreasury.increaseTreasuryPreciseBalance(penalty);

        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending;

            // Same here
        }

        if (pendingBonus > 0) {
            rewardsManager.sendBonus(msg.sender, pendingBonus);
            quarterBonusRewardsPaid[currentQuarterIndex] += pendingBonus;

            // Same here
        }

        judgeToken.safeTransfer(msg.sender, netAmount);
        stake.amountStaked -= _amount;

        if (stake.amountStaked == 0) {
            stake.stakeWeight = 0;
            stake.rewardDebt = 0;
            stake.bonusRewardDebt = 0;
        } else {
            stake.stakeWeight = Math.mulDiv(stake.amountStaked, stake.lockUpRatio, SCALE);
            stake.rewardDebt = accumulatedStakeRewards(_index);
            stake.bonusRewardDebt = accumulatedStakeBonusRewards(_index);
        }

        totalStakeWeight = totalStakeWeight - oldStakeWeight + stake.stakeWeight;
        totalStaked -= _amount;
        emit Withdrawn(msg.sender, _netAmount, pending + pendingBonus);
        emit EarlyWithdrawalPenalized(msg.sender, block.number, penalty);
    }

    /* NOTE: Treat the emergencyWithdraw function with caution, It is an exit route and when called withdraws all user stakes 
    to their wallets. Only use when there is a serious issue with the staking pool.*/
    function emergencyWithdraw() external onlyRole(STAKING_ADMIN_ROLE) nonReentrant {
        // consider batch withdrawals for this function to prevent out of gas issues
        require(address(rewardsManager) != address(0), RewardsManagerNotSet());
        require(!emergencyFuncCalled, AlreadyTriggered());
        emergencyFuncCalled = true;
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        updatePool();
        for (uint32 i; i < users.length; i++) {
            address userAddr = users[i];
            for (uint16 j; j < userStakes[users[i]].length; j++) {
                userStake storage stake = userStakes[users[i]][j];

                if (stake.amountStaked > 0) {
                    uint256 pending = Math.mulDiv(stake.stakeWeight, accJudgePerShare, SCALE) - stake.rewardDebt;
                    uint256 pendingBonus =
                        Math.mulDiv(stake.stakeWeight, accBonusJudgePerShare, SCALE) - stake.bonusRewardDebt;

                    uint256 amount = stake.amountStaked;

                    rewardsManager.sendRewards(userAddr, pending);
                    quarterRewardsPaid[currentQuarterIndex] += pending;
                    rewardsManager.sendBonus(userAddr, pendingBonus);
                    quarterBonusRewardsPaid[currentQuarterIndex] += pendingBonus;
                    judgeToken.safeTransfer(userAddr, amount);

                    totalStakeWeight -= stake.stakeWeight;
                    stake.amountStaked = 0;
                    stake.stakeWeight = 0;
                    totalStaked -= amount;
                    stake.rewardDebt = 0;
                    stake.bonusRewardDebt = 0;
                    emit EmergencyWithdrawal(msg.sender, userAddr, stake.id, amount, pending + pendingBonus);
                }
            }
        }
    }

    function calculateQuarterUnclaimedRewards(uint32 index) external view returns (uint256) {
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        require(index <= currentQuarterIndex, QuarterNotStarted());

        uint256 tempQuarterAccruedRewards = quarterAccruedRewardsForStakes[index];
        uint256 tempQuarterAccruedBonusRewards = quarterAccruedBonusRewardsForStakes[index];

        if(index == currentQuarterIndex){
        uint256 blocksPassed = 0;
        if(block.number > lastRewardBlock){
        blocksPassed = block.number - lastRewardBlock;
        }
        uint256 bonusEnd = judgeTreasury.bonusEndBlock(index);
        uint256 bonusBlocksPassed = 0;
        if(bonusEnd > lastRewardBlock){
        bonusBlocksPassed = Math.min(blocksPassed, bonusEnd - lastRewardBlock);
        }

        uint256 totalRewardSinceLastRewardBlock = blocksPassed * rewardsPerBlockForQuarter[currentQuarterIndex];
        uint256 totalBonusRewardSinceLastRewardBlock = bonusBlocksPassed * bonusPerBlockForQuarter[currentQuarterIndex];

        tempQuarterAccruedRewards += totalRewardSinceLastRewardBlock;
        tempQuarterAccruedBonusRewards += totalBonusRewardSinceLastRewardBlock;
        }

        uint256 unClaimedBaseRewards = tempQuarterAccruedRewards > quarterRewardsPaid[index] ? tempQuarterAccruedRewards - quarterRewardsPaid[index] : 0;
        uint256 unClaimedBonusRewards = tempQuarterAccruedBonusRewards > quarterBonusRewardsPaid[index] ? tempQuarterAccruedBonusRewards - quarterBonusRewardsPaid[index] : 0;
        return unClaimedBaseRewards + unClaimedBonusRewards;
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

    function viewUserStakes(address addr)
        external
        view
        validAddress(addr)
        onlyRole(STAKING_ADMIN_ROLE)
        returns (userStake[] memory)
    {
        return userStakes[addr];
    }

    function viewUserStakeAtIndex(address addr, uint16 _index)
        external
        view
        validAddress(addr)
        onlyRole(STAKING_ADMIN_ROLE)
        returns (userStake memory)
    {
        require(_index < userStakes[addr].length, InvalidIndex());
        return userStakes[addr][_index];
    }

    function viewMyPendingRewards(uint16 _index) external view validIndex(_index) returns (uint256) {
        userStake memory stake = userStakes[msg.sender][_index];
        uint256 tempAccJudgePerShare = accJudgePerShare;
        uint256 tempAccBonusJudgePerShare = accBonusJudgePerShare;

        if (block.number > lastRewardBlock && totalStakeWeight > 0) {
            uint32 startQuarter = getQuarterIndexFromBlock(lastRewardBlock);
            uint32 currentQuarter = getCurrentQuarterIndex();
            uint256 tempLastRewardBlock = lastRewardBlock;

            uint8 processed = 0;
            uint8 maxSimulatedQuarters = 12;
            while(startQuarter <= currentQuarter && processed < MAX_UPDATE_QUARTERS) {
                uint256 quarterStart = stakingPoolStartBlock + (uint256(startQuarter) - 1) * QUARTER_BLOCKS;
                uint256 quarterEnd = quarterStart + QUARTER_BLOCKS;

                uint256 rpb = rewardsPerBlockForQuarter[startQuarter];
                uint bpb = bonusPerBlockForQuarter[startQuarter]; 

                if(rpb == 0 && bpb == 0){
                   unchecked{
                    startQuarter++;
                       processed++;
                   }
                   continue;
                }

                uint256 endBlock = (startQuarter == currentQuarter) ? block.number : quarterEnd;
                uint256 reward = 0;
                uint256 bonusReward = 0;
                if(endBlock > tempLastRewardBlock){
                    uint256 blocksPassed = endBlock - tempLastRewardBlock;
                    reward = blocksPassed * rpb;
                    tempAccJudgePerShare += Math.mulDiv(reward, SCALE, totalStakeWeight);

                    uint256 bonusEnd = judgeTreasury.bonusEndBlock(startQuarter);
                    uint256 bonusBlocks = 0;
                    if(bonusEnd > tempLastRewardBlock){
                        bonusBlocks = Math.min(blocksPassed, bonusEnd - tempLastRewardBlock);
                    }

                    bonusReward = bonusBlocks * bpb;
                    tempAccBonusJudgePerShare += Math.mulDiv(bonusReward, SCALE, totalStakeWeight);
                    tempLastRewardBlock = endBlock;
                }
                unchecked{
                    startQuarter ++;
                    processed++;
                }
            }
        }

        uint256 pendingReward = 0;
        uint256 calcReward = Math.mulDiv(stake.stakeWeight, tempAccJudgePerShare, SCALE);
        if (calcReward > stake.rewardDebt){
            pendingReward = calcReward - stake.rewardDebt;
        }

        uint256 pendingBonus = 0;
        uint256 calcBonus = Math.mulDiv(stake.stakeWeight, tempAccBonusJudgePerShare, SCALE);
        if(calcBonus > stake.bonusRewardDebt){
            pendingBonus = calcBonus - stake.bonusRewardDebt;
        }
        return pendingReward + pendingBonus;
    }

    function calculateMisplacedJudge() public view returns (uint256) {
        uint256 contractBalance = judgeToken.balanceOf(address(this));
        uint256 misplacedJudgeAmount = 0;
        if(contractBalance > totalStaked){
        misplacedJudgeAmount = contractBalance - totalStaked;
        }
        return misplacedJudgeAmount;
    }

    function recoverMisplacedJudgeToken(address _to, uint256 _amount)
        external
        validAddress(_to)
        validAmount(_amount)
        notSelf(_to)
        onlyRole(TOKEN_RECOVERY_ROLE)
        nonReentrant
    {
        uint256 misplacedJudgeAmount = calculateMisplacedJudge();
        require(misplacedJudgeAmount > 0, InvalidAmount());
        require(_amount <= misplacedJudgeAmount, InvalidAmount());
        require(_amount >= judgeRecoveryMinimumThreshold, NotUpToThreshold());
        uint256 refund = Math.mulDiv(_amount, (100 - uint256(feePercent)), 100);
        uint256 fee = _amount - refund;

        judgeToken.safeTransfer(_to, refund);

        if(fee > 0){
        judgeToken.safeTransfer(address(judgeTreasury), fee);
        judgeTreasury.increaseTreasuryPreciseBalance(fee);
        }

        emit JudgeTokenRecovered(_to, refund, fee);
    }

    function recoverErc20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        notSelf(_addr)
        validAmount(_amount)
        onlyRole(TOKEN_RECOVERY_ROLE)
        nonReentrant
    {
        require(_strandedTokenAddr != address(0) && _addr != address(0), InvalidAddress());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        require(_amount <= IERC20(_strandedTokenAddr).balanceOf(address(this)), InsufficientContractBalance());

        uint256 refund = Math.mulDiv(_amount, (100 - uint256(feePercent)), 100);
        uint256 fee = _amount - refund;
        IERC20(_strandedTokenAddr).safeTransfer(_addr, refund);

        if(fee > 0){
        feeBalanceOfStrandedToken[_strandedTokenAddr] += fee;
        }
        emit Erc20Recovered(_strandedTokenAddr, _addr, refund, fee);
    }

    function transferFeesFromOtherTokensOutOfStaking(address _strandedTokenAddr, address _to, uint256 _amount)
        external
        notSelf(_to)
        validAmount(_amount)
        onlyRole(TOKEN_RECOVERY_ROLE)
        nonReentrant
    {
        require(_strandedTokenAddr != address(0) && _to != address(0), InvalidAddress());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        require(_amount <= feeBalanceOfStrandedToken[_strandedTokenAddr], InsufficientBalance());
        IERC20(_strandedTokenAddr).safeTransfer(_to, _amount);
        feeBalanceOfStrandedToken[_strandedTokenAddr] -= _amount;
        emit FeesFromOtherTokensTransferred(
            _strandedTokenAddr, _to, _amount, feeBalanceOfStrandedToken[_strandedTokenAddr]
        );
    }
}