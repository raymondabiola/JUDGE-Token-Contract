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
    using SafeERC20 for IERC20;

    JudgeToken public judgeToken;
    JudgeTreasury public judgeTreasury;
    IRewardsManager public rewardsManager;

    // == ROLES ==
    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 public constant TOKEN_RECOVERY_ROLE = keccak256("TOKEN_RECOVERY_ROLE");
    bytes32 public constant REWARDS_PER_BLOCK_CALCULATOR = keccak256("REWARDS_PER_BLOCK_CALCULATOR"); //Assign to judgeTreasury at deployment

    // == CONSTANTS ==
    uint256 public constant SCALE = 1e18; // 18 decimals
    uint256 public constant QUARTER_BLOCKS = 648_000; // ~90 days at 12s/block
    uint32 public constant BLOCKS_PER_YEAR = 2_628_000;  // 12 sec blocktime
    uint8 public constant MAX_UPDATE_QUARTERS = 4;
    uint16 public constant MAX_LOCK_UP_PERIOD_DAYS = 360; // 1 year max lock
    uint8 public constant MAX_PENALTY_PERCENT = 20;
    uint8 public constant FEE_PERCENT_MAX_THRESHOLD = 30;

    uint256 public stakingPoolStartBlock;
    uint64 private newStakeId;
    uint256 public accJudgePerShare; 
    uint256 public accBonusJudgePerShare;
    uint256 public lastRewardBlock;
    uint256 public totalStakeWeight;
    uint256 public totalStaked;

    struct Settings{
       uint8 earlyWithdrawPenaltyPercentForMaxLockupPeriod;//This is the penalty percent that is charged on a user stake if they
       //lockup for 360 days MAX_LOCK_UP_PERIOD_DAYS and withdraw early, for lower lockUpPeriods, the penalty is scaled down based on duration/MAX_LOCK_UP_PERIOD_DAYS
       uint8 feePercent; //Fee charged to recover misplaced JudgeTokens sent to the contract
       uint32 lastFullyUpdatedQuarter;
    }
    Settings public settings;

    uint256 public totalPenalties; 
    uint256 public judgeRecoveryMinimumThreshold; //Feasible minimum amount of JudgeTokens that's worth recovering
    uint256 public totalClaimedBaseRewards; 
    uint256 public totalClaimedBonusRewards;
    uint256 public totalAccruedBaseRewards; 
    uint256 public totalAccruedBonusRewards; 

    address[] internal users;
    mapping(address => UserStake[]) internal userStakes; 
    mapping(address => bool) internal isUser; 
    struct UserStake {
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

    mapping(uint32 => uint256) public rewardsPerBlockForQuarter;
    mapping(uint32 => uint256) public bonusPerBlockForQuarter;
    mapping(address => uint256) public feeBalanceOfStrandedToken;

    // == EVENTS ==
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 rewardsPaid);
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

    // == ERRORS ==
    error InvalidAmount();
    error InvalidAddress();
    error InvalidIndex();
    error InsufficientBalance();
    error NotYetMatured();
    error InvalidLockUpPeriod();
    error AlreadyMatured();
    error ValueTooHigh();
    error ZeroStakeBalance();
    error JudgeTokenRecoveryNotAllowed();
    error InsufficientContractBalance();
    error CannotInputThisContractAddress();
    error EOANotAllowed();
    error NotUpToThreshold();
    error RewardsManagerNotSet();
    error PoolNotUpToDate();

    constructor(address _judgeTokenAddress, uint8 _earlyWithdrawPenaltyPercentForMaxLockupPeriod)
    {   
        if(_judgeTokenAddress.code.length == 0) revert EOANotAllowed();
        if(_earlyWithdrawPenaltyPercentForMaxLockupPeriod > MAX_PENALTY_PERCENT) revert ValueTooHigh();
        judgeToken = JudgeToken(_judgeTokenAddress);
        newStakeId = 1;
        settings.earlyWithdrawPenaltyPercentForMaxLockupPeriod = _earlyWithdrawPenaltyPercentForMaxLockupPeriod;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        stakingPoolStartBlock = block.number;
        emit JudgeTokenAddressWasSet(_judgeTokenAddress);
        emit EarlyWithdrawPenaltyPercentForMaxLockupPeriodInitialized(_earlyWithdrawPenaltyPercentForMaxLockupPeriod);
    }

    // == MODIFIERS ==
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

    modifier notEoa(address _addr) {
        require(_addr.code.length > 0, EOANotAllowed());
        _;
    }

    // == ADMIN FUNCTIONS ==
    function setRewardsManagerAddress(address _rewardsManagerAddress)
        external
        onlyRole(STAKING_ADMIN_ROLE)
        validAddress(_rewardsManagerAddress)
        notSelf(_rewardsManagerAddress)
        notEoa(_rewardsManagerAddress)
    {
        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit RewardsManagerAddressUpdated(_rewardsManagerAddress);
    }

    function setJudgeTreasuryAddress(address _judgeTreasuryAddress)
        external
        onlyRole(STAKING_ADMIN_ROLE)
        validAddress(_judgeTreasuryAddress)
        notSelf(_judgeTreasuryAddress)
        notEoa(_judgeTreasuryAddress)
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
        require(_earlyWithdrawPenaltyPercentForMaxLockupPeriod <= MAX_PENALTY_PERCENT, ValueTooHigh());
        settings.earlyWithdrawPenaltyPercentForMaxLockupPeriod = _earlyWithdrawPenaltyPercentForMaxLockupPeriod;
        emit EarlyWithdrawPenaltyPercentForMaxLockupPeriodUpdated(_earlyWithdrawPenaltyPercentForMaxLockupPeriod);
    }

    function updateFeePercent(uint8 _newFeePercent) external onlyRole(STAKING_ADMIN_ROLE) {
        if(_newFeePercent > FEE_PERCENT_MAX_THRESHOLD) revert ValueTooHigh();
        uint8 oldFeePercent = settings.feePercent;
        settings.feePercent = _newFeePercent;
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

    // == POOL CORE FUNCTIONS ==
    function getCurrentQuarterIndex() public view returns (uint32) {
        return uint32((block.number - stakingPoolStartBlock) / QUARTER_BLOCKS + 1);
    }

    function getQuarterIndexFromBlock(uint256 blockNumber) public view returns(uint32){
        return uint32(blockNumber > stakingPoolStartBlock ? ((blockNumber - stakingPoolStartBlock) / QUARTER_BLOCKS) +1 : 1);
    }

    function getCurrentApr() public view returns (uint256) {
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        uint256 localTotalStakeWeight = totalStakeWeight;
        if (localTotalStakeWeight == 0) {
            return 0;
        }
        // APR is scaled by 1e18, divide by same factor and multiply by 100 to get exact value
        uint256 apr1 = Math.mulDiv(Math.mulDiv(rewardsPerBlockForQuarter[currentQuarterIndex], BLOCKS_PER_YEAR, 1), SCALE, localTotalStakeWeight);
        uint256 apr2 = Math.mulDiv(Math.mulDiv(bonusPerBlockForQuarter[currentQuarterIndex], BLOCKS_PER_YEAR, 1), SCALE, localTotalStakeWeight);

        return apr1 + apr2;
    }

    function syncQuarterBonusRewardsPerBlock(uint32 quarterIndex, uint256 _bonus, uint256 _durationInBlocks) external onlyRole(REWARDS_PER_BLOCK_CALCULATOR){
        bonusPerBlockForQuarter[quarterIndex] = Math.mulDiv(_bonus, SCALE, _durationInBlocks);
    }

    function syncQuarterRewardsPerBlock(uint32 quarterIndex) external onlyRole(REWARDS_PER_BLOCK_CALCULATOR) {
        JudgeTreasury.QuarterInfo memory q = judgeTreasury.quarters(quarterIndex);
        uint256 quarterRewards = q.baseReward;
        uint256 rpb = 0;

        if(quarterRewards > 0){
            rpb = quarterRewards / QUARTER_BLOCKS;
        }

        rewardsPerBlockForQuarter[quarterIndex] = rpb;
    }

    function updatePool() public {
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        uint256 blockNum = block.number;
        
        if (blockNum <= lastRewardBlock) return;
        uint256 localTotalStakeWeight = totalStakeWeight;
        if (localTotalStakeWeight == 0) {
            lastRewardBlock = blockNum;
            return;
        }

        uint32 startQuarter = getQuarterIndexFromBlock(lastRewardBlock);
        uint32 processed = 0;
        while(startQuarter <= currentQuarterIndex && processed < MAX_UPDATE_QUARTERS){
        JudgeTreasury.QuarterInfo memory q = judgeTreasury.quarters(startQuarter);
        uint256 quarterStart = stakingPoolStartBlock + (uint256(startQuarter) - 1) * QUARTER_BLOCKS;
        uint256 quarterEnd = quarterStart + QUARTER_BLOCKS;
        uint256 startQuarterBonusEnd = q.bonusEndBlock;

        uint256 rpb = rewardsPerBlockForQuarter[startQuarter];
        uint256 bpb = bonusPerBlockForQuarter[startQuarter];

        if(rpb == 0 && bpb == 0){
            unchecked{
                startQuarter++;
                processed++;
            continue;
            }
        }

        uint256 endBlock = (startQuarter == currentQuarterIndex) ? blockNum : quarterEnd;

        if(endBlock > lastRewardBlock){
           uint256 blocksPassed = endBlock - lastRewardBlock;
            uint256 reward = blocksPassed * rpb;
        accJudgePerShare += Math.mulDiv(reward, SCALE, localTotalStakeWeight);

        uint256 bonusBlocks = 0;
        if(startQuarterBonusEnd > lastRewardBlock){
            bonusBlocks = Math.min(blocksPassed, startQuarterBonusEnd - lastRewardBlock);
        }
         uint256 bonusReward = Math.mulDiv(bonusBlocks, bpb, SCALE);
         accBonusJudgePerShare += Math.mulDiv(bonusReward, SCALE, localTotalStakeWeight);

         totalAccruedBaseRewards += reward;
         totalAccruedBonusRewards += bonusReward;

         lastRewardBlock = endBlock;
         settings.lastFullyUpdatedQuarter = startQuarter;
        }
       
        unchecked{
        startQuarter++;
        processed++;
        }
        }
    }

    function isPoolUpToDate()public view returns(bool){
        return !(settings.lastFullyUpdatedQuarter < getCurrentQuarterIndex()-1);
    }

    // == USER WRITE FUNCTIONS ==
    function deposit(uint256 _amount, uint32 _lockUpPeriodInDays)
        external
        validAmount(_amount)
        validAmount(_lockUpPeriodInDays)
    {
        if(_lockUpPeriodInDays > MAX_LOCK_UP_PERIOD_DAYS) revert InvalidLockUpPeriod();
        updatePool();
        if(!isPoolUpToDate()) revert PoolNotUpToDate();

        uint256 amountStaked = _amount;
        uint32 lockUpPeriod = _lockUpPeriodInDays;
        uint256 lockUpRatio = (uint256(lockUpPeriod) * SCALE) / uint256(MAX_LOCK_UP_PERIOD_DAYS);
        uint256 depositBlockNumber = block.number;
        uint256 maturityBlockNumber = depositBlockNumber + (lockUpPeriod * 7200);
        uint256 stakeWeight = Math.mulDiv(amountStaked, lockUpRatio, SCALE);
        totalStakeWeight += stakeWeight;
        totalStaked += _amount;

        uint256 rewardDebt = Math.mulDiv(stakeWeight, accJudgePerShare, SCALE);
        uint256 bonusRewardDebt = Math.mulDiv(stakeWeight, accBonusJudgePerShare, SCALE);

        UserStake memory newStake = UserStake({
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

        judgeToken.transferFrom(msg.sender, address(this), _amount);
        userStakes[msg.sender].push(newStake);

        if (!isUser[msg.sender]) {
            users.push(msg.sender);
            isUser[msg.sender] = true;
        }

        newStakeId++;
        emit Deposited(msg.sender, _amount);
    }

    function claimRewards(uint16 _index) external validIndex(_index) nonReentrant {
        if(address(rewardsManager) == address(0)) revert RewardsManagerNotSet();
        UserStake storage stake = userStakes[msg.sender][_index];
        if(stake.amountStaked == 0) revert ZeroStakeBalance();
        updatePool();
        if(!isPoolUpToDate()) revert PoolNotUpToDate();

        uint256 stakeWeight = stake.stakeWeight;
        uint256 newAcc = Math.mulDiv(stakeWeight, accJudgePerShare, SCALE);
        uint256 newAccBonus = Math.mulDiv(stakeWeight, accBonusJudgePerShare, SCALE);

        uint256 stakeRewardDebt = stake.rewardDebt;
        uint256 stakeBonusRewardDebt = stake.bonusRewardDebt;

        uint256 pending = newAcc > stakeRewardDebt ? newAcc - stakeRewardDebt : 0;
        uint256 pendingBonus = newAccBonus > stakeBonusRewardDebt ? newAccBonus - stakeBonusRewardDebt : 0;

        if (pending > 0) {
            totalClaimedBaseRewards += pending;
            stake.rewardDebt = newAcc;
            rewardsManager.sendRewards(msg.sender, pending);
        }

        if (pendingBonus > 0) {
            totalClaimedBonusRewards += pendingBonus;
            stake.bonusRewardDebt = newAccBonus;
            rewardsManager.sendBonus(msg.sender, pendingBonus);
        }

        emit ClaimedReward(msg.sender, pending + pendingBonus);
    }

    function withdraw(uint256 _amount, uint16 _index) external validAmount(_amount) validIndex(_index) nonReentrant {
        if(address(rewardsManager) == address(0)) revert RewardsManagerNotSet();
        UserStake storage stake = userStakes[msg.sender][_index];
        if(block.number < stake.maturityBlockNumber) revert NotYetMatured();
        if(_amount > stake.amountStaked) revert InsufficientBalance();

        updatePool();
        if(!isPoolUpToDate()) revert PoolNotUpToDate();

        uint256 oldStakeWeight = stake.stakeWeight;
        uint256 newAcc = Math.mulDiv(oldStakeWeight, accJudgePerShare, SCALE);
        uint256 newAccBonus = Math.mulDiv(oldStakeWeight, accBonusJudgePerShare, SCALE);

        uint256 stakeRewardDebt = stake.rewardDebt;
        uint256 stakeBonusRewardDebt = stake.bonusRewardDebt;

        uint256 pending = newAcc > stakeRewardDebt ? newAcc - stakeRewardDebt : 0;
        uint256 pendingBonus = newAccBonus > stakeBonusRewardDebt ? newAccBonus - stakeBonusRewardDebt : 0;

        stake.amountStaked -= _amount;

        if(stake.amountStaked == 0){
            totalStakeWeight -= oldStakeWeight;
            stake.stakeWeight = 0;
            stake.rewardDebt = 0;
            stake.bonusRewardDebt = 0;
        } else{
        stake.stakeWeight = Math.mulDiv(stake.amountStaked, stake.lockUpRatio, SCALE);
        uint256 newStakeWeight = stake.stakeWeight;
        totalStakeWeight = totalStakeWeight - oldStakeWeight + newStakeWeight;
        stake.rewardDebt = Math.mulDiv(newStakeWeight, accJudgePerShare, SCALE);
        stake.bonusRewardDebt = Math.mulDiv(newStakeWeight, accBonusJudgePerShare, SCALE);
        }
        totalStaked -= _amount;

        if (pending > 0) {
            totalClaimedBaseRewards += pending;
            rewardsManager.sendRewards(msg.sender, pending);
        }

        if (pendingBonus > 0) {
            totalClaimedBonusRewards += pendingBonus;
            rewardsManager.sendBonus(msg.sender, pendingBonus);
        }

        judgeToken.transfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount, pending + pendingBonus);
    }

    function withdrawAll(uint16 _index) external validIndex(_index) nonReentrant {
        if(address(rewardsManager) == address(0)) revert RewardsManagerNotSet();
        UserStake storage stake = userStakes[msg.sender][_index];
        if(block.number < stake.maturityBlockNumber) revert NotYetMatured();

        updatePool();
        if(!isPoolUpToDate()) revert PoolNotUpToDate();

        uint256 stakeWeight = stake.stakeWeight;
        uint256 newAcc = Math.mulDiv(stakeWeight, accJudgePerShare, SCALE);
        uint256 newAccBonus = Math.mulDiv(stakeWeight, accBonusJudgePerShare, SCALE);

        uint256 stakeRewardDebt = stake.rewardDebt;
        uint256 stakeBonusRewardDebt = stake.bonusRewardDebt;

        uint256 pending = newAcc > stakeRewardDebt ? newAcc - stakeRewardDebt : 0;
        uint256 pendingBonus = newAccBonus > stakeBonusRewardDebt ? newAccBonus - stakeBonusRewardDebt : 0;

        uint256 amountWithdrawn = stake.amountStaked;

        totalStakeWeight -= stakeWeight;
        stake.amountStaked = 0;
        stake.stakeWeight = 0;
        totalStaked -= amountWithdrawn;
        stake.rewardDebt = 0;
        stake.bonusRewardDebt = 0;

        if (pending > 0) {
            totalClaimedBaseRewards += pending;
            rewardsManager.sendRewards(msg.sender, pending);
        }

        if (pendingBonus > 0) {
            totalClaimedBonusRewards += pendingBonus;
            rewardsManager.sendBonus(msg.sender, pendingBonus);
        }
        judgeToken.transfer(msg.sender, amountWithdrawn);
        emit Withdrawn(msg.sender, amountWithdrawn, pending + pendingBonus);
    }

    function earlyWithdraw(uint256 _amount, uint16 _index)
        external
        validAmount(_amount)
        validIndex(_index)
        nonReentrant
    {
        if(address(rewardsManager) == address(0)) revert RewardsManagerNotSet();
        UserStake storage stake = userStakes[msg.sender][_index];
        if(block.number > stake.maturityBlockNumber) revert AlreadyMatured();
        if(_amount > stake.amountStaked) revert InsufficientBalance();

        updatePool();
        if(!isPoolUpToDate()) revert PoolNotUpToDate();

        uint256 oldStakeWeight = stake.stakeWeight;
        uint256 newAcc = Math.mulDiv(oldStakeWeight, accJudgePerShare, SCALE);
        uint256 newAccBonus = Math.mulDiv(oldStakeWeight, accBonusJudgePerShare, SCALE);

        uint256 stakeRewardDebt = stake.rewardDebt;
        uint256 stakeBonusRewardDebt = stake.bonusRewardDebt;

        uint256 pending = newAcc > stakeRewardDebt ? newAcc - stakeRewardDebt : 0;
        uint256 pendingBonus = newAccBonus > stakeBonusRewardDebt ? newAccBonus - stakeBonusRewardDebt : 0;

        uint256 penalty = Math.mulDiv(
            _amount, Math.mulDiv(settings.earlyWithdrawPenaltyPercentForMaxLockupPeriod, stake.lockUpRatio, SCALE), 100
        );

        uint256 netAmount = _amount - penalty;

        totalPenalties += penalty;
        judgeTreasury.increaseTreasuryPreciseBalance(penalty);
        judgeToken.transfer(address(judgeTreasury), penalty);

        stake.amountStaked -= _amount;

        if (stake.amountStaked == 0) {
            totalStakeWeight -= oldStakeWeight;
            stake.stakeWeight = 0;
            stake.rewardDebt = 0;
            stake.bonusRewardDebt = 0;
        } else {
            stake.stakeWeight = Math.mulDiv(stake.amountStaked, stake.lockUpRatio, SCALE);
            uint256 newStakeWeight = stake.stakeWeight;
            stake.rewardDebt = Math.mulDiv(newStakeWeight, accJudgePerShare, SCALE);
            stake.bonusRewardDebt = Math.mulDiv(newStakeWeight, accBonusJudgePerShare, SCALE);
            totalStakeWeight = totalStakeWeight - oldStakeWeight + newStakeWeight;
        }

        totalStaked -= _amount;

        if (pending > 0) {
            totalClaimedBaseRewards += pending;
            rewardsManager.sendRewards(msg.sender, pending);
        }

        if (pendingBonus > 0) {
            totalClaimedBonusRewards += pendingBonus;
            rewardsManager.sendBonus(msg.sender, pendingBonus);
        }
        judgeToken.transfer(msg.sender, netAmount);
        emit Withdrawn(msg.sender, netAmount, pending + pendingBonus);
        emit EarlyWithdrawalPenalized(msg.sender, block.number, penalty);
    }

    function totalUnclaimedRewards() external view returns (uint256 base, uint256 bonus, uint256 total) {
        base = totalAccruedBaseRewards > totalClaimedBaseRewards ? totalAccruedBaseRewards - totalClaimedBaseRewards : 0;
        bonus = totalAccruedBonusRewards > totalClaimedBonusRewards ? totalAccruedBonusRewards - totalClaimedBonusRewards : 0;
        total = base + bonus;
        return (base, bonus, total);
    }

    // == USER VIEW FUNCTIONS ==
    function viewMyStakes() external view returns (UserStake[] memory) {
        return userStakes[msg.sender];
    }

    function viewMyStakeAtIndex(uint16 _index) external view validIndex(_index) returns (UserStake memory) {
        return userStakes[msg.sender][_index];
    }

    function viewMyPendingRewards(uint16 _index) external view validIndex(_index) returns (uint256) {
        UserStake memory stake = userStakes[msg.sender][_index];
        uint256 tempAccJudgePerShare = accJudgePerShare;
        uint256 tempAccBonusJudgePerShare = accBonusJudgePerShare;
        uint256 blockNum = block.number;
        uint256 localTotalStakeWeight = totalStakeWeight;
        uint256 localLastRewardBlock = lastRewardBlock;

        if (blockNum > localLastRewardBlock && localTotalStakeWeight > 0) {
            uint32 startQuarter = getQuarterIndexFromBlock(localLastRewardBlock);
            uint32 currentQuarter = getCurrentQuarterIndex();

            uint8 processed = 0;
            uint8 maxSimulatedQuarters = 12; //12 quarters safe for simulation since it's a view function
            while(startQuarter <= currentQuarter && processed < maxSimulatedQuarters) {
                JudgeTreasury.QuarterInfo memory q = judgeTreasury.quarters(startQuarter);
                uint256 quarterStart = stakingPoolStartBlock + (uint256(startQuarter) - 1) * QUARTER_BLOCKS;
                uint256 quarterEnd = quarterStart + QUARTER_BLOCKS;

                uint256 rpb = rewardsPerBlockForQuarter[startQuarter];
                uint bpb = bonusPerBlockForQuarter[startQuarter]; 

                if(rpb == 0 && bpb == 0){
                   unchecked{
                    startQuarter++;
                    processed++;
                   continue;
                   }
                }

                uint256 endBlock = (startQuarter == currentQuarter) ? blockNum : quarterEnd;
                if(endBlock > localLastRewardBlock){
                    uint256 blocksPassed = endBlock - localLastRewardBlock;
                    uint256 reward = blocksPassed * rpb;
                    tempAccJudgePerShare += Math.mulDiv(reward, SCALE, localTotalStakeWeight);

                    uint256 bonusEnd = q.bonusEndBlock;
                    uint256 bonusBlocks = 0;
                    if(bonusEnd > localLastRewardBlock){
                        bonusBlocks = Math.min(blocksPassed, bonusEnd - localLastRewardBlock);
                    }

                    uint256 bonusReward = Math.mulDiv(bonusBlocks, bpb, SCALE);
                    tempAccBonusJudgePerShare += Math.mulDiv(bonusReward, SCALE, localTotalStakeWeight);
                    localLastRewardBlock = endBlock;
                }
                unchecked{
                    startQuarter ++;
                    processed++;
                }
            }
        }
        
        uint256 localStakeWeight = stake.stakeWeight;
        uint256 newLocalAcc = Math.mulDiv(localStakeWeight, tempAccJudgePerShare, SCALE);
        uint256 newLocalAccBonus = Math.mulDiv(localStakeWeight, tempAccBonusJudgePerShare, SCALE);
        
        uint256 stakeRewardDebt = stake.rewardDebt;
        uint256 stakeBonusRewardDebt = stake.bonusRewardDebt;
        
        uint256 pendingReward = newLocalAcc > stakeRewardDebt ? newLocalAcc - stakeRewardDebt : 0;
        uint256 pendingBonus = newLocalAccBonus > stakeBonusRewardDebt ? newLocalAccBonus - stakeBonusRewardDebt : 0;

        return pendingReward + pendingBonus;
    }

    // == ADMIN VIEW FUNCTIONS ==
    function viewUsersList() external view onlyRole(STAKING_ADMIN_ROLE) returns (address[] memory) {
        return users;
    }

    function viewUserStakes(address addr)
        external
        view
        validAddress(addr)
        onlyRole(STAKING_ADMIN_ROLE)
        returns (UserStake[] memory)
    {
        return userStakes[addr];
    }

    function viewUserStakeAtIndex(address addr, uint16 _index)
        external
        view
        validAddress(addr)
        onlyRole(STAKING_ADMIN_ROLE)
        returns (UserStake memory)
    {
        if(_index > userStakes[addr].length) revert InvalidIndex();
        return userStakes[addr][_index];
    }

    // == TOKEN RECOVERY FUNCTIONS ==
    function calculateMisplacedJudge() public view returns (uint256) {
        uint256 contractBalance = judgeToken.balanceOf(address(this));
        uint256 misplacedJudgeAmount = 0;
        if(contractBalance > totalStaked){
        misplacedJudgeAmount = contractBalance - totalStaked;
        }
        return misplacedJudgeAmount;
    }

    function recoverMisplacedJudge(address _to, uint256 _amount)
        external
        validAddress(_to)
        validAmount(_amount)
        notSelf(_to)
        onlyRole(TOKEN_RECOVERY_ROLE)
        nonReentrant
    {
        uint256 misplacedJudgeAmount = calculateMisplacedJudge();
        if(misplacedJudgeAmount == 0 || _amount > misplacedJudgeAmount) revert InvalidAmount();
        if(_amount < judgeRecoveryMinimumThreshold) revert NotUpToThreshold();
        uint256 refund = (_amount * (100 - uint256(settings.feePercent))) / 100;
        uint256 fee = _amount - refund;

        if(fee > 0){
        judgeToken.transfer(address(judgeTreasury), fee);
        judgeTreasury.increaseTreasuryPreciseBalance(fee);
        }

        judgeToken.transfer(_to, refund);

        emit JudgeTokenRecovered(_to, refund, fee);
    }

    function recoverErc20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        notSelf(_addr)
        validAmount(_amount)
        onlyRole(TOKEN_RECOVERY_ROLE)
        nonReentrant
    {
        if(_strandedTokenAddr == address(0) || _addr == address(0)) revert InvalidAddress();
        if(_strandedTokenAddr == address(judgeToken)) revert JudgeTokenRecoveryNotAllowed();
        if(_amount > IERC20(_strandedTokenAddr).balanceOf(address(this))) revert InsufficientContractBalance();

        uint256 refund = (_amount * (100 - uint256(settings.feePercent))) / 100;
        uint256 fee = _amount - refund;

        if(fee > 0){
        feeBalanceOfStrandedToken[_strandedTokenAddr] += fee;
        }

        IERC20(_strandedTokenAddr).safeTransfer(_addr, refund);
        emit Erc20Recovered(_strandedTokenAddr, _addr, refund, fee);
    }

    function transferFeesFromOtherTokensOutOfStaking(address _strandedTokenAddr, address _to, uint256 _amount)
        external
        notSelf(_to)
        validAmount(_amount)
        onlyRole(TOKEN_RECOVERY_ROLE)
        nonReentrant
    {
        if(_strandedTokenAddr == address(0) || _to == address(0)) revert InvalidAddress();
        if(_strandedTokenAddr == address(judgeToken)) revert JudgeTokenRecoveryNotAllowed();
        if(_amount > feeBalanceOfStrandedToken[_strandedTokenAddr]) revert InsufficientBalance();

        feeBalanceOfStrandedToken[_strandedTokenAddr] -= _amount;
        IERC20(_strandedTokenAddr).safeTransfer(_to, _amount);
        emit FeesFromOtherTokensTransferred(
            _strandedTokenAddr, _to, _amount, feeBalanceOfStrandedToken[_strandedTokenAddr]
        );
    }
}