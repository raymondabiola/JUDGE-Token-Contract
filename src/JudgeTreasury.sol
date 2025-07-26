// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {RewardsManager} from "./RewardsManager.sol";
import {JudgeStaking} from "./JudgeStaking.sol";

contract JudgeTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;
    using SafeERC20 for IERC20;

    JudgeToken public judgeToken;
    RewardsManager public rewardsManager;
    JudgeStaking public judgeStaking;

    bytes32 public constant TREASURY_ADMIN_ROLE = keccak256("TREASURY_ADMIN_ROLE");
    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");
    bytes32 public constant TOKEN_RECOVERY_ROLE = keccak256("TOKEN_RECOVERY_ROLE");
    bytes32 public constant TREASURY_PRECISE_BALANCE_UPDATER = keccak256("TREASURY_PRECISE_BALANCE_UPDATER");

    uint256 public stakingRewardsFundsFromTreasury;
    uint256 public teamFundingReceived;
    uint256 public treasuryPreciseBalance;
    uint8 public feePercent;     //Fee to recover mistakenly sent funds from contract
    uint8 public constant FEE_PERCENT_MAX_THRESHOLD = 30; 
    uint256 public judgeRecoveryMinimumThreshold;
    uint256 public immutable MIN_QUARTERLY_REWARD_ALLOCATION;
    uint256 public immutable MAX_QUARTERLY_REWARD_ALLOCATION;

    uint8 public decimals;
    uint256 quarterIndex;
    
    mapping(uint256 => bool) public setQuarterlyRewardsAtIndexWasPaidToRewardsManager;
    mapping(uint256 => uint256)public quarterlyRewards; //mapping of base quarterly rewards;
    mapping(uint256 => uint256) public additionalQuarterRewards; //mapping of additional rewards
    mapping(address => uint256) public feeBalanceOfStrandedToken;

    event JudgeTokenAddressWasSet(address indexed judgeTokenAddress);
    event RewardsManagerAddressInitialized(address indexed rewardsManagerAddress);
    event KeyParametersUpdated( address indexed newRewardsManagerAddress, address indexed newJudgeStakingAddress);
    event FeePercentUpdated(uint8 oldValue, uint8 newValue);
    event JudgeRecoveryMinimumThresholdUpdated(uint256 oldValue, uint256 newValue);
    event RewardsManagerFunded(uint256 amount);
    event TeamDevelopmentWasFunded(address indexed to, uint256 amount);
    event MintedToTreasury(uint256 amount);
    event TransferredFromTreasury(address indexed to, uint256 amount);
    event Erc20Recovered(address indexed tokenAddress, address indexed to, uint256 refund, uint256 fee);
    event FeesFromOtherTokensTransferred (address indexed tokenAddress, address indexed to, uint256 feeTransferred, uint256 feeBalanceOfStrandedToken);
    event JudgeTokenRecovered(address indexed to, uint256 refund, uint256 fee);

    error InvalidAmount();
    error InsufficientBalance();
    error InvalidAddress();
    error JudgeTokenRecoveryNotAllowed();
    error CannotInputThisContractAddress();
    error InsufficientContractBalance();
    error EOANotAllowed();
    error RewardsInputedOutOfDefinedRange();
    error TotalStakingRewardAllocationExceeded();
    error TeamDevelopmentAllocationExceeded();
    error ExceedsRemainingAllocation();
    error NotUpToThreshold();
    error ValueHigherThanThreshold();
    error CurrentQuarterAllocationNotYetFunded();
    error QuarterAllocationAlreadyFunded();

    constructor(address _judgeTokenAddress, address _rewardsManagerAddress, address _judgeStakingAddress) {
        require(_judgeTokenAddress != address(0) && _rewardsManagerAddress != address(0) && _judgeStakingAddress != address(0), InvalidAddress());
        require(_judgeTokenAddress.code.length > 0 && _rewardsManagerAddress.code.length > 0 && _judgeStakingAddress.code.length > 0, EOANotAllowed());
        judgeToken = JudgeToken(_judgeTokenAddress);
        rewardsManager = RewardsManager(_rewardsManagerAddress);
        judgeStaking = JudgeStaking(_judgeStakingAddress);
        
        quarterIndex = 1;
        decimals = judgeToken.decimals();
        MIN_QUARTERLY_REWARD_ALLOCATION = 416_666 * 10 ** uint256(decimals);
        MAX_QUARTERLY_REWARD_ALLOCATION = 1_250_000 * 10 ** uint256(decimals);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit JudgeTokenAddressWasSet(_judgeTokenAddress);
        emit RewardsManagerAddressInitialized(_rewardsManagerAddress);
    }

    modifier validAmount(uint256 _amount){
         require(_amount > 0, InvalidAmount());
         _;
    }

     modifier validAddress(address _addr){
              require(_addr != address(0), InvalidAddress());
              _;
    }

    modifier notSelf(address _addr){
        require(_addr != address(this), CannotInputThisContractAddress());
        _;
    }

    function updateKeyParameters(address newRewardsManagerAddress, address newJudgeStakingAddress) external onlyRole(TREASURY_ADMIN_ROLE) {
        require(newRewardsManagerAddress != address(0) && newJudgeStakingAddress != address(0), InvalidAddress());
        require(newRewardsManagerAddress != address(this) && newJudgeStakingAddress != address(this), CannotInputThisContractAddress());
        require(newRewardsManagerAddress.code.length > 0 && newJudgeStakingAddress.code.length > 0, EOANotAllowed());
        rewardsManager = RewardsManager(newRewardsManagerAddress);
        judgeStaking = JudgeStaking(newJudgeStakingAddress);

        emit KeyParametersUpdated(newRewardsManagerAddress, newJudgeStakingAddress);
    }

    function setNewQuarterlyRewards(uint256 _reward)public onlyRole(TREASURY_ADMIN_ROLE){
        require(_reward != 0, InvalidAmount());
        require(_reward >= MIN_QUARTERLY_REWARD_ALLOCATION && _reward <= MAX_QUARTERLY_REWARD_ALLOCATION, RewardsInputedOutOfDefinedRange());
    quarterlyRewards[quarterIndex] = _reward;
    quarterIndex += 1;
    }

    function addToQuarterReward(uint256 _reward)external{
        require(_reward != 0, InvalidAmount());
        uint256 currentQuarterIndex = judgeStaking.getCurrentQuarterIndex();
    require(setQuarterlyRewardsAtIndexWasPaidToRewardsManager[currentQuarterIndex], CurrentQuarterAllocationNotYetFunded());
        additionalQuarterRewards[currentQuarterIndex] += _reward;
        judgeToken.safeTransferFrom(msg.sender, address(rewardsManager), _reward);
        rewardsManager.increaseRewardsManagerPreciseBalance(_reward);
    }
    
    function updateFeePercent(uint8 _newFeePercent) external onlyRole(TREASURY_ADMIN_ROLE){
        require(_newFeePercent < FEE_PERCENT_MAX_THRESHOLD, ValueHigherThanThreshold());
        uint8 oldFeePercent = feePercent;
        feePercent = _newFeePercent;
        emit FeePercentUpdated(oldFeePercent, _newFeePercent);
    }

    function updateJudgeRecoveryMinimumThreshold(uint256 newJudgeRecoveryMinimumThreshold) external onlyRole(TREASURY_ADMIN_ROLE){
        uint256 oldJudgeRecoveryMinimumThreshold = judgeRecoveryMinimumThreshold;
        judgeRecoveryMinimumThreshold = newJudgeRecoveryMinimumThreshold;
        emit JudgeRecoveryMinimumThresholdUpdated(oldJudgeRecoveryMinimumThreshold, newJudgeRecoveryMinimumThreshold);
    }

    // Assign the trasury precise balance updater to JudgeStaking contract and Rewards Manager Contract
    function increaseTreasuryPreciseBalance(uint256 _amount)external onlyRole(TREASURY_PRECISE_BALANCE_UPDATER){
        treasuryPreciseBalance += _amount;
    }

    function fundRewardsManager(uint256 _index) external onlyRole(FUND_MANAGER_ROLE) {
        require(!setQuarterlyRewardsAtIndexWasPaidToRewardsManager[_index], QuarterAllocationAlreadyFunded());
        require(stakingRewardsFundsFromTreasury < judgeToken.MAX_STAKING_REWARD_ALLOCATION(), TotalStakingRewardAllocationExceeded());
        require(quarterlyRewards[_index] <= judgeToken.MAX_STAKING_REWARD_ALLOCATION() - stakingRewardsFundsFromTreasury, ExceedsRemainingAllocation());
        judgeToken.mintFromAllocation(address(rewardsManager), quarterlyRewards[_index]);
        stakingRewardsFundsFromTreasury += quarterlyRewards[_index];
        rewardsManager.increaseRewardsManagerPreciseBalance(quarterlyRewards[_index]);
        setQuarterlyRewardsAtIndexWasPaidToRewardsManager[_index] = true;

        emit RewardsManagerFunded(quarterlyRewards[_index]);
    }

    function mintToTreasuryReserve(uint256 _amount) external validAmount(_amount) onlyRole(FUND_MANAGER_ROLE){
        judgeToken.mint(address(this), _amount);
        treasuryPreciseBalance += _amount;

        emit MintedToTreasury(_amount);
    }

    function fundTeamDevelopment(address _addr, uint256 _amount) external validAddress(_addr) validAmount(_amount) onlyRole(FUND_MANAGER_ROLE) nonReentrant{
       require(teamFundingReceived < judgeToken.MAX_TEAM_ALLOCATION(), TeamDevelopmentAllocationExceeded());
        require(_amount <= judgeToken.MAX_TEAM_ALLOCATION() - teamFundingReceived, ExceedsRemainingAllocation());
        judgeToken.mintFromAllocation(msg.sender, _amount);
        teamFundingReceived += _amount;
        emit TeamDevelopmentWasFunded(_addr, _amount);
    }

    function transferFromTreasury(address _addr, uint256 _amount) external onlyRole(FUND_MANAGER_ROLE) validAddress(_addr) notSelf(_addr) validAmount(_amount) nonReentrant{
        require(_amount <= treasuryPreciseBalance, InsufficientBalance());
        judgeToken.safeTransfer(_addr, _amount);

        treasuryPreciseBalance -= _amount;

            emit TransferredFromTreasury(_addr, _amount);
    }

    function calculateMisplacedJudge() public view onlyRole(TOKEN_RECOVERY_ROLE) returns (uint256) {
        uint256 misplacedJudgeAmount = judgeToken.balanceOf(address(this)) - treasuryPreciseBalance;
        return misplacedJudgeAmount;
    }

    function recoverMisplacedJudge(address _to, uint256 _amount) external onlyRole(TOKEN_RECOVERY_ROLE) validAddress(_to) notSelf(_to) validAmount(_amount) nonReentrant{
        uint256 misplacedJudgeAmount = calculateMisplacedJudge();
        require(_amount <= misplacedJudgeAmount, InvalidAmount());
        require(_amount >= judgeRecoveryMinimumThreshold, NotUpToThreshold());
        uint256 refund = Math.mulDiv(_amount, (100-uint256(feePercent)), 100);
        uint256 fee = _amount - refund;
        treasuryPreciseBalance += fee;
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

    function transferFeesFromOtherTokensOutOfTreasury(address _strandedTokenAddr, address _to, uint256 _amount)external notSelf(_to) validAmount(_amount) onlyRole(FUND_MANAGER_ROLE) nonReentrant{
        require(_strandedTokenAddr != address(0) && _to != address(0), InvalidAddress());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        require(_amount <= feeBalanceOfStrandedToken[_strandedTokenAddr], InsufficientBalance());
        feeBalanceOfStrandedToken[_strandedTokenAddr] -= _amount;
        IERC20(_strandedTokenAddr).safeTransfer(_to, _amount);
        emit FeesFromOtherTokensTransferred(_strandedTokenAddr, _to, _amount, feeBalanceOfStrandedToken[_strandedTokenAddr]);
    }
}