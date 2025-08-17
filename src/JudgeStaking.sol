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
    uint64 private newStakeId;
    uint256 public accJudgePerShare; //cummulated JUDGE base rewards that a single JUDGE token stake weight is expected to receive
    uint256 public accBonusJudgePerShare; //cummulated JUDGE bonus rewards that a single JUDGE token stake weight is expected to receive
    uint256 public rewardsPerBlock;
    uint256 public bonusPerBlock;
    uint256 public lastRewardBlock;
    uint256 public totalStakeWeight; //The total calculated stake weights of all stakers based on the stake amount and chosen lockup period.
    uint256 public totalStaked;
    uint64 private constant SCALE = 1e18;
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
    error OverPaidRewards();

    constructor(address _judgeTokenAddress, uint8 _earlyWithdrawPenaltyPercentForMaxLockupPeriod)
        validAddress(_judgeTokenAddress)
    {
        require(_judgeTokenAddress.code.length > 0, EOANotAllowed());
        require(earlyWithdrawPenaltyPercentForMaxLockupPeriod <= maxPenaltyPercent, ValueTooHigh());
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
        require(_newFeePercent < FEE_PERCENT_MAX_THRESHOLD, ValueHigherThanThreshold());
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
        return uint32((block.number - stakingPoolStartBlock) / 648_000 + 1);
    }

    function calculateBonusRewardsPerBlock(uint256 _bonus, uint256 _durationInBlocks) public returns (uint256) {
        bonusPerBlock = _bonus / _durationInBlocks;
        return bonusPerBlock;
    }

    function calculateCurrentRewardsPerBlock() external onlyRole(REWARDS_PER_BLOCK_CALCULATOR) returns (uint256) {
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        uint256 totalRewards = judgeTreasury.quarterlyRewards(currentQuarterIndex);
        uint256 totalRewardsAccruedinCurrentQuarter = quarterAccruedRewardsForStakes[currentQuarterIndex];
        require(totalRewards >= totalRewardsAccruedinCurrentQuarter, OverPaidRewards());
        uint256 remainingRewards = totalRewards - totalRewardsAccruedinCurrentQuarter;

        uint256 quarterStart = stakingPoolStartBlock + (currentQuarterIndex - 1) * 648_000;
        uint256 quarterEnd = quarterStart + 648_000;

        if (lastRewardBlock > quarterEnd) {
            return 0;
        }

        if (remainingRewards == 0) {
            return 0;
        }

        uint256 remainingBlocks = quarterEnd - lastRewardBlock;
        if (remainingBlocks == 0) {
            return 0;
        }
        rewardsPerBlock = remainingRewards / remainingBlocks;
        return rewardsPerBlock;
    }

    function getCurrentAPR() public view returns (uint256) {
        uint256 blocksPerYear = 2_628_000;
        if (totalStakeWeight == 0) {
            return 0;
        }
        // APR is scaled by 1e18, divide by same factor and multiply by 100 to get exact value
        uint256 apr1 = Math.mulDiv(Math.mulDiv(rewardsPerBlock, 2_628_000, 1), 1e18, totalStakeWeight);
        uint256 apr2 = Math.mulDiv(Math.mulDiv(bonusPerBlock, 2_628_000, 1), 1e18, totalStakeWeight);

        return apr1 + apr2;
    }

    function updatePool() public {
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        uint256 quarterStart = stakingPoolStartBlock + (currentQuarterIndex - 1) * 648_000;
        if (block.number <= lastRewardBlock) {
            return;
        }
        if (totalStakeWeight == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 blocksPassed = block.number - lastRewardBlock;
        uint256 totalReward = blocksPassed * rewardsPerBlock;
        accJudgePerShare += Math.mulDiv(totalReward, SCALE, totalStakeWeight);
        uint256 bonusBlocksPassed = judgeTreasury.bonusEndBlock() > lastRewardBlock
            ? Math.min(blocksPassed, judgeTreasury.bonusEndBlock() - lastRewardBlock)
            : 0;
        uint256 totalBonusReward = bonusBlocksPassed * bonusPerBlock;
        accBonusJudgePerShare += Math.mulDiv(totalBonusReward, SCALE, totalStakeWeight);
        lastRewardBlock = block.number;

        uint256 blocksPassedSinceQuarterStart = block.number - quarterStart;
        quarterAccruedRewardsForStakes[currentQuarterIndex] = blocksPassedSinceQuarterStart * rewardsPerBlock;
        quarterAccruedBonusRewardsForStakes[currentQuarterIndex] += totalBonusReward;
    }

    function deposit(uint256 _amount, uint32 _lockUpPeriodInDays)
        external
        validAmount(_amount)
        validAmount(_lockUpPeriodInDays)
    {
        require(_lockUpPeriodInDays <= maxLockUpPeriod, InvalidLockUpPeriod());
        if (!isUser[msg.sender]) {
            users.push(msg.sender);
            isUser[msg.sender] = true;
        }

        updatePool();

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
        }

        if (pendingBonus > 0) {
            rewardsManager.sendBonus(msg.sender, pendingBonus);
            quarterBonusRewardsPaid[currentQuarterIndex] += pendingBonus;
        }

        judgeToken.safeTransfer(msg.sender, _amount);

        totalStakeWeight -= stake.stakeWeight;
        stake.amountStaked -= _amount;
        stake.stakeWeight = Math.mulDiv(stake.amountStaked, stake.lockUpRatio, SCALE);
        totalStakeWeight += stake.stakeWeight;
        stake.rewardDebt = accumulatedStakeRewards(_index);
        stake.bonusRewardDebt = accumulatedStakeBonusRewards(_index);
        totalStaked -= _amount;
        emit Withdrawn(msg.sender, _amount, pending + pendingBonus);
    }

    function withdrawAll(uint16 _index) external validIndex(_index) nonReentrant {
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
        }

        if (pendingBonus > 0) {
            rewardsManager.sendBonus(msg.sender, pendingBonus);
            quarterBonusRewardsPaid[currentQuarterIndex] += pendingBonus;
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
        uint32 currentQuarterIndex = getCurrentQuarterIndex();
        userStake storage stake = userStakes[msg.sender][_index];
        require(block.number < stake.maturityBlockNumber, AlreadyMatured());
        require(_amount <= stake.amountStaked, InsufficientBalance());

        updatePool();
        uint256 pending = accumulatedStakeRewards(_index) - stake.rewardDebt;
        uint256 pendingBonus = accumulatedStakeBonusRewards(_index) - stake.bonusRewardDebt;

        totalStakeWeight -= stake.stakeWeight;
        uint256 penalty = Math.mulDiv(
            _amount, Math.mulDiv(earlyWithdrawPenaltyPercentForMaxLockupPeriod, stake.lockUpRatio, SCALE), 100
        );
        uint256 deduction = _amount + penalty;
        require(deduction <= stake.amountStaked, InsufficientBalance());

        judgeToken.safeTransfer(address(judgeTreasury), penalty);
        totalPenalties += penalty;
        judgeTreasury.increaseTreasuryPreciseBalance(penalty);

        if (pending > 0) {
            rewardsManager.sendRewards(msg.sender, pending);
            quarterRewardsPaid[currentQuarterIndex] += pending;
        }

        if (pendingBonus > 0) {
            rewardsManager.sendBonus(msg.sender, pendingBonus);
            quarterBonusRewardsPaid[currentQuarterIndex] += pendingBonus;
        }

        judgeToken.safeTransfer(msg.sender, _amount);

        if (deduction == stake.amountStaked) {
            stake.amountStaked = 0;
            stake.stakeWeight = 0;
            stake.rewardDebt = 0;
            stake.bonusRewardDebt = 0;
        } else {
            stake.amountStaked -= deduction;
            stake.stakeWeight = Math.mulDiv(stake.amountStaked, stake.lockUpRatio, SCALE);
            totalStakeWeight += stake.stakeWeight;
            stake.rewardDebt = accumulatedStakeRewards(_index);
            stake.bonusRewardDebt = accumulatedStakeBonusRewards(_index);
        }
        totalStaked -= deduction;
        emit Withdrawn(msg.sender, _amount, pending + pendingBonus);
        emit EarlyWithdrawalPenalized(msg.sender, block.number, penalty);
    }

    /* NOTE: Treat the emergencyWithdraw function with caution, It is an exit route and when called withdraws all user stakes 
    to their wallets. Only use when there is a serious issue with the staking pool.*/
    function emergencyWithdraw() external onlyRole(STAKING_ADMIN_ROLE) nonReentrant {
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

    function calculateTotalUnclaimedRewards() external view returns (uint256) {
        uint32 currentQuarterIndex = getCurrentQuarterIndex();

        uint256 tempQuarterAccruedRewards = quarterAccruedRewardsForStakes[currentQuarterIndex];
        uint256 tempQuarterAccruedBonusRewards = quarterAccruedBonusRewardsForStakes[currentQuarterIndex];

        uint256 quarterStart = stakingPoolStartBlock + (currentQuarterIndex - 1) * 648_000;
        uint256 blocksPassed = block.number - lastRewardBlock;
        uint256 bonusBlocksPassed = judgeTreasury.bonusEndBlock() > lastRewardBlock
            ? Math.min(blocksPassed, judgeTreasury.bonusEndBlock() - lastRewardBlock)
            : 0;
        uint256 totalBonusReward = bonusBlocksPassed * bonusPerBlock;

        uint256 blocksPassedSinceQuarterStart = block.number - quarterStart;
        tempQuarterAccruedRewards = blocksPassedSinceQuarterStart * rewardsPerBlock;
        tempQuarterAccruedBonusRewards += totalBonusReward;

        uint256 unClaimedBaseRewards = tempQuarterAccruedRewards - quarterRewardsPaid[currentQuarterIndex];
        uint256 unClaimedBonusRewards = tempQuarterAccruedBonusRewards - quarterBonusRewardsPaid[currentQuarterIndex];
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
            uint256 blocksPassed = block.number - lastRewardBlock;
            uint256 totalReward = blocksPassed * rewardsPerBlock;
            tempAccJudgePerShare += Math.mulDiv(totalReward, SCALE, totalStakeWeight);

            uint256 bonusBlocksPassed = judgeTreasury.bonusEndBlock() > lastRewardBlock
                ? Math.min(blocksPassed, judgeTreasury.bonusEndBlock() - lastRewardBlock)
                : 0;
            uint256 totalBonusReward = bonusBlocksPassed * bonusPerBlock;
            tempAccBonusJudgePerShare += Math.mulDiv(totalBonusReward, SCALE, totalStakeWeight);
        }

        uint256 pendingReward = Math.mulDiv(stake.stakeWeight, tempAccJudgePerShare, SCALE) - stake.rewardDebt;
        uint256 pendingBonus = Math.mulDiv(stake.stakeWeight, tempAccBonusJudgePerShare, SCALE) - stake.rewardDebt;

        return pendingReward + pendingBonus;
    }

    function calculateMisplacedJudge() public view onlyRole(TOKEN_RECOVERY_ROLE) returns (uint256) {
        uint256 contractBalance = judgeToken.balanceOf(address(this));
        uint256 misplacedJudgeAmount = contractBalance - totalStaked;
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
        require(_amount <= misplacedJudgeAmount, InvalidAmount());
        require(_amount >= judgeRecoveryMinimumThreshold, NotUpToThreshold());
        uint256 refund = Math.mulDiv(_amount, (100 - uint256(feePercent)), 100);
        uint256 fee = _amount - refund;
        judgeToken.safeTransfer(address(judgeTreasury), fee);
        judgeTreasury.increaseTreasuryPreciseBalance(fee);
        judgeToken.safeTransfer(_to, refund);
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
        feeBalanceOfStrandedToken[_strandedTokenAddr] += fee;
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
