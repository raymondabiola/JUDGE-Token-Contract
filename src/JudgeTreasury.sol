// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {RewardsManager} from "./RewardsManager.sol";
import {JudgeStaking} from "./JudgeStaking.sol";

contract JudgeTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    JudgeToken public judgeToken;
    RewardsManager public rewardsManager;
    JudgeStaking public judgeStaking;

    bytes32 public immutable TREASURY_ADMIN_ROLE =
        keccak256("TREASURY_ADMIN_ROLE");
    bytes32 public immutable FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");
    bytes32 public immutable TOKEN_RECOVERY_ROLE =
        keccak256("TOKEN_RECOVERY_ROLE");
    bytes32 public immutable TREASURY_PRECISE_BALANCE_UPDATER =
        keccak256("TREASURY_PRECISE_BALANCE_UPDATER"); //Assign to judgeStaking on deployment

    uint256 public totalBaseRewardsFunded; //Total rewards sent to rewardsManager From treasury excluding bonus rewards.
    uint256 public teamFundingReceived;
    uint256 public treasuryPreciseBalance; //Exact total amount of judgeTokens in treasury contract excluding misplaced judgeTokens
    uint8 public constant FEE_PERCENT_MAX_THRESHOLD = 30;
    uint256 public judgeRecoveryMinimumThreshold; //Feasible minimum amount of JudgeTokens that's worth recovering
    uint256 public immutable MIN_QUARTERLY_REWARD_ALLOCATION; //Lower bound of quarterly reward allocation
    uint256 public immutable MAX_QUARTERLY_REWARD_ALLOCATION; //Upper bound of quarterly reward allocation

    struct Settings {
        uint8 feePercent; //Fee charged to recover misplaced JudgeTokens sent to the contract
        uint8 decimals;
    }

    Settings public settings;

    uint32 quarterIndex;

    struct QuarterInfo {
        uint256 baseReward;
        uint256 currentBonus; //If there are bonus rewards, they can be sent for distribution while setting the number of blocks the bonus will run for
        uint256 currentBonusStartBlock;
        uint256 currentBonusEndBlock;
        uint256 totalBonusReceived;
        bool isFunded; // boolean for if baseRewards are funded for that quarter
    }

    mapping(uint32 => QuarterInfo) public quarters; // Mapping of quarter index to their Details

    mapping(address => uint256) public feeBalanceOfStrandedToken; //mapping of accumulated fee of recovered misplaced tokens

    event JudgeTokenAddressWasSet(address indexed judgeTokenAddress);
    event RewardsManagerAddressUpdated(
        address indexed newRewardsManagerAddress
    );
    event JudgeStakingAddressUpdated(address indexed newJudgeStakingAddress);
    event FeePercentUpdated(uint8 oldValue, uint8 newValue);
    event JudgeRecoveryMinimumThresholdUpdated(
        uint256 oldValue,
        uint256 newValue
    );
    event RewardsManagerFunded(uint256 amount);
    event TeamDevelopmentWasFunded(address indexed to, uint256 amount);
    event MintedToTreasury(uint256 amount);
    event TransferredFromTreasury(address indexed to, uint256 amount);
    event Erc20Recovered(
        address indexed tokenAddress,
        address indexed to,
        uint256 refund,
        uint256 fee
    );
    event FeesFromOtherTokensTransferred(
        address indexed tokenAddress,
        address indexed to,
        uint256 feeTransferred,
        uint256 feeBalanceOfStrandedToken
    );
    event JudgeTokenRecovered(address indexed to, uint256 refund, uint256 fee);

    error InvalidAmount();
    error InsufficientBalance();
    error InvalidAddress();
    error BonusTooSmall();
    error JudgeTokenRecoveryNotAllowed();
    error CannotInputThisContractAddress();
    error InsufficientContractBalance();
    error EOANotAllowed();
    error RewardsInputedOutOfDefinedRange();
    error ExceedsRemainingAllocation();
    error lastBonusStillRunning();
    error NotUpToThreshold();
    error ValueHigherThanThreshold();
    error CurrentQuarterAllocationNotYetFunded();
    error BaseRewardsNotSet();
    error QuarterAllocationAlreadyFunded();
    error DurationBeyondQuarterEnd();
    error DurationTooLow();
    error StakingPoolNotUpToDate();

    constructor(
        address _judgeTokenAddress,
        address _rewardsManagerAddress,
        address _judgeStakingAddress
    ) {
        if (
            _judgeTokenAddress.code.length == 0 ||
            _rewardsManagerAddress.code.length == 0 ||
            _judgeStakingAddress.code.length == 0
        ) revert EOANotAllowed();
        judgeToken = JudgeToken(_judgeTokenAddress);
        rewardsManager = RewardsManager(_rewardsManagerAddress);
        judgeStaking = JudgeStaking(_judgeStakingAddress);

        quarterIndex = 1;
        settings.decimals = judgeToken.decimals();
        MIN_QUARTERLY_REWARD_ALLOCATION =
            416_666 *
            10 ** uint256(settings.decimals);
        MAX_QUARTERLY_REWARD_ALLOCATION =
            1_250_000 *
            10 ** uint256(settings.decimals);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit JudgeTokenAddressWasSet(_judgeTokenAddress);
        emit RewardsManagerAddressUpdated(_rewardsManagerAddress);
    }

    modifier validAmount(uint256 _amount) {
        require(_amount > 0, InvalidAmount());
        _;
    }

    modifier validAddress(address _addr) {
        require(
            _addr != address(0) && _addr != address(this),
            InvalidAddress()
        );
        _;
    }

    modifier notSelf(address _addr) {
        require(_addr != address(this), CannotInputThisContractAddress());
        _;
    }

    modifier notEoa(address _addr) {
        require(_addr.code.length > 0, EOANotAllowed());
        _;
    }

    function setRewardsManagerAddress(
        address newRewardsManagerAddress
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validAddress(newRewardsManagerAddress)
        notEoa(newRewardsManagerAddress)
    {
        rewardsManager = RewardsManager(newRewardsManagerAddress);
        emit RewardsManagerAddressUpdated(newRewardsManagerAddress);
    }

    function setJudgeStakingAddress(
        address newJudgeStakingAddress
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validAddress(newJudgeStakingAddress)
        notEoa(newJudgeStakingAddress)
    {
        judgeStaking = JudgeStaking(newJudgeStakingAddress);

        emit JudgeStakingAddressUpdated(newJudgeStakingAddress);
    }

    function updateFeePercent(
        uint8 _newFeePercent
    ) external onlyRole(TREASURY_ADMIN_ROLE) {
        if (_newFeePercent > FEE_PERCENT_MAX_THRESHOLD) {
            revert ValueHigherThanThreshold();
        }
        uint8 oldFeePercent = settings.feePercent;
        settings.feePercent = _newFeePercent;
        emit FeePercentUpdated(oldFeePercent, _newFeePercent);
    }

    function updateJudgeRecoveryMinimumThreshold(
        uint256 newJudgeRecoveryMinimumThreshold
    ) external onlyRole(TREASURY_ADMIN_ROLE) {
        uint256 oldJudgeRecoveryMinimumThreshold = judgeRecoveryMinimumThreshold;
        judgeRecoveryMinimumThreshold = newJudgeRecoveryMinimumThreshold;
        emit JudgeRecoveryMinimumThresholdUpdated(
            oldJudgeRecoveryMinimumThreshold,
            newJudgeRecoveryMinimumThreshold
        );
    }

    function setNewQuarterlyRewards(
        uint256 _reward
    ) public onlyRole(TREASURY_ADMIN_ROLE) {
        if (_reward == 0) revert InvalidAmount();
        if (
            _reward < MIN_QUARTERLY_REWARD_ALLOCATION ||
            _reward > MAX_QUARTERLY_REWARD_ALLOCATION
        ) {
            revert RewardsInputedOutOfDefinedRange();
        }
        quarters[quarterIndex].baseReward = _reward;
        quarterIndex += 1;
    }

    function addBonusToQuarterReward(
        uint256 _bonus,
        uint256 _durationInBlocks
    ) external validAmount(_bonus) validAmount(_durationInBlocks) {
        uint32 currentQuarterIndex = judgeStaking.getCurrentQuarterIndex();
        uint256 stakingStart = judgeStaking.stakingPoolStartBlock();
        uint256 quarterBlocks = judgeStaking.QUARTER_BLOCKS();

        uint256 quarterStart = stakingStart +
            (uint256(currentQuarterIndex) - 1) *
            quarterBlocks;
        uint256 quarterEnd = quarterStart + quarterBlocks;
        uint256 b = block.number;
        if (!quarters[currentQuarterIndex].isFunded) {
            revert CurrentQuarterAllocationNotYetFunded();
        }
        if (!judgeStaking.isPoolUpToDate()) revert StakingPoolNotUpToDate();
        if (_durationInBlocks < 100_000) revert DurationTooLow();
        if (_durationInBlocks > quarterEnd - b) {
            revert DurationBeyondQuarterEnd();
        }
        if (_bonus < _durationInBlocks) revert BonusTooSmall();
        if (b < quarters[currentQuarterIndex].currentBonusEndBlock) {
            revert lastBonusStillRunning();
        }

        quarters[currentQuarterIndex].currentBonus = _bonus;
        quarters[currentQuarterIndex].totalBonusReceived += _bonus;
        quarters[currentQuarterIndex].currentBonusStartBlock = b;
        quarters[currentQuarterIndex].currentBonusEndBlock =
            b +
            _durationInBlocks;

        judgeToken.transferFrom(msg.sender, address(rewardsManager), _bonus);
        rewardsManager.increaseRewardsManagerBonusBalanceAccounting(_bonus);
        judgeStaking.updatePool();
        judgeStaking.syncQuarterBonusRewardsPerBlock(
            currentQuarterIndex,
            _bonus,
            _durationInBlocks
        );
    }

    // Assign the treasury precise balance updater role to JudgeStaking contract and Rewards Manager Contract
    function increaseTreasuryPreciseBalance(
        uint256 _amount
    ) external onlyRole(TREASURY_PRECISE_BALANCE_UPDATER) {
        treasuryPreciseBalance += _amount;
    }

    function fundRewardsManager(
        uint32 _index
    ) external onlyRole(FUND_MANAGER_ROLE) {
        uint256 rewardAmount = quarters[_index].baseReward;
        if (quarters[_index].isFunded) revert QuarterAllocationAlreadyFunded();
        if (
            rewardAmount >
            judgeToken.MAX_STAKING_REWARD_ALLOCATION() - totalBaseRewardsFunded
        ) {
            revert ExceedsRemainingAllocation();
        }
        judgeToken.mintFromAllocation(address(rewardsManager), rewardAmount);
        totalBaseRewardsFunded += rewardAmount;
        rewardsManager.increaseRewardsManagerBaseBalanceAccounting(
            rewardAmount
        );

        quarters[_index].isFunded = true;

        judgeStaking.updatePool();

        judgeStaking.syncQuarterRewardsPerBlock(_index);

        emit RewardsManagerFunded(rewardAmount);
    }

    function mintToTreasuryReserve(
        uint256 _amount
    ) external validAmount(_amount) onlyRole(FUND_MANAGER_ROLE) {
        judgeToken.generalMint(address(this), _amount); //Grant minter role to judgeTreasury to be able to call this function
        treasuryPreciseBalance += _amount;

        emit MintedToTreasury(_amount);
    }

    function fundTeamDevelopment(
        address _addr,
        uint256 _amount
    )
        external
        validAddress(_addr)
        validAmount(_amount)
        onlyRole(FUND_MANAGER_ROLE)
        nonReentrant
    {
        if (_amount > judgeToken.MAX_TEAM_ALLOCATION() - teamFundingReceived) {
            revert ExceedsRemainingAllocation();
        }
        judgeToken.mintFromAllocation(_addr, _amount);
        teamFundingReceived += _amount;
        emit TeamDevelopmentWasFunded(_addr, _amount);
    }

    function transferFromTreasury(
        address _addr,
        uint256 _amount
    )
        external
        onlyRole(FUND_MANAGER_ROLE)
        validAddress(_addr)
        validAmount(_amount)
        nonReentrant
    {
        if (_amount > treasuryPreciseBalance) revert InsufficientBalance();

        treasuryPreciseBalance -= _amount;
        judgeToken.transfer(_addr, _amount);

        emit TransferredFromTreasury(_addr, _amount);
    }

    function remainingStakingAllocation() public view returns (uint256) {
        uint256 maxStakingAllocation = judgeToken
            .MAX_STAKING_REWARD_ALLOCATION();
        return
            maxStakingAllocation > totalBaseRewardsFunded
                ? maxStakingAllocation - totalBaseRewardsFunded
                : 0;
    }

    function remainingTeamAllocation() public view returns (uint256) {
        return
            judgeToken.MAX_TEAM_ALLOCATION() > teamFundingReceived
                ? judgeToken.MAX_TEAM_ALLOCATION() - teamFundingReceived
                : 0;
    }

    function currentFeePercent() public view returns (uint8) {
        return settings.feePercent;
    }

    function getQuarterInfo(
        uint32 index
    ) public view returns (QuarterInfo memory) {
        return quarters[index];
    }

    function calculateMisplacedJudge() public view returns (uint256) {
        return
            judgeToken.balanceOf(address(this)) > treasuryPreciseBalance
                ? judgeToken.balanceOf(address(this)) - treasuryPreciseBalance
                : 0;
    }

    function recoverMisplacedJudge(
        address _to,
        uint256 _amount
    )
        external
        onlyRole(TOKEN_RECOVERY_ROLE)
        validAddress(_to)
        validAmount(_amount)
        nonReentrant
    {
        uint256 misplacedJudgeAmount = calculateMisplacedJudge();
        if (_amount > misplacedJudgeAmount) revert InvalidAmount();
        if (_amount < judgeRecoveryMinimumThreshold) revert NotUpToThreshold();
        uint256 refund = (_amount * (100 - uint256(settings.feePercent))) / 100;
        uint256 fee = _amount - refund;
        if (fee > 0) {
            treasuryPreciseBalance += fee;
        }
        judgeToken.transfer(_to, refund);
        emit JudgeTokenRecovered(_to, refund, fee);
    }

    function recoverErc20(
        address _strandedTokenAddr,
        address _addr,
        uint256 _amount
    ) external validAmount(_amount) onlyRole(TOKEN_RECOVERY_ROLE) nonReentrant {
        if (_addr == address(this)) revert CannotInputThisContractAddress();
        if (_strandedTokenAddr == address(0) || _addr == address(0)) {
            revert InvalidAddress();
        }
        if (_strandedTokenAddr == address(judgeToken)) {
            revert JudgeTokenRecoveryNotAllowed();
        }
        if (_amount > IERC20(_strandedTokenAddr).balanceOf(address(this))) {
            revert InsufficientContractBalance();
        }

        uint256 refund = (_amount * (100 - uint256(settings.feePercent))) / 100;
        uint256 fee = _amount - refund;
        if (fee > 0) {
            feeBalanceOfStrandedToken[_strandedTokenAddr] += fee;
        }
        IERC20(_strandedTokenAddr).safeTransfer(_addr, refund);
        emit Erc20Recovered(_strandedTokenAddr, _addr, refund, fee);
    }

    function transferFeesFromOtherTokensOutOfTreasury(
        address _strandedTokenAddr,
        address _to,
        uint256 _amount
    ) external validAmount(_amount) onlyRole(FUND_MANAGER_ROLE) nonReentrant {
        if (_to == address(this)) revert CannotInputThisContractAddress();
        if (_strandedTokenAddr == address(0) || _to == address(0)) {
            revert InvalidAddress();
        }
        if (_strandedTokenAddr == address(judgeToken)) {
            revert JudgeTokenRecoveryNotAllowed();
        }
        if (_amount > feeBalanceOfStrandedToken[_strandedTokenAddr]) {
            revert InsufficientBalance();
        }
        feeBalanceOfStrandedToken[_strandedTokenAddr] -= _amount;
        IERC20(_strandedTokenAddr).safeTransfer(_to, _amount);
        emit FeesFromOtherTokensTransferred(
            _strandedTokenAddr,
            _to,
            _amount,
            feeBalanceOfStrandedToken[_strandedTokenAddr]
        );
    }
}
