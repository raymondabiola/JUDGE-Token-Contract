// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {RewardsManager} from "./RewardsManager.sol";

contract JudgeTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;

    JudgeToken public judgeToken;
    RewardsManager public rewardsManager;

    bytes32 public constant TREASURY_ADMIN_ROLE = keccak256("TREASURY_ADMIN_ROLE");
    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");
    bytes32 public constant TOKEN_RECOVERY_ROLE = keccak256("TOKEN_RECOVERY_ROLE");

    uint256 public stakingRewardsFundsFromTreasury;
    uint256 public teamFundingReceived;
    uint256 public treasuryPreciseBalance;
    uint8 public feePercent;     //Fee to recover mistakenly sent funds from contract
    uint8 public constant FEE_PERCENT_THRESHOLD = 30; 
    uint256 public judgeRecoveryMinimumThreshold;

    uint8 public decimals;
    uint256 public quarterlyReward; 

    mapping(address => uint256) public treasuryFeeBalanceOfStrandedToken;

    event JudgeTokenAddressWasSet(address indexed judgeTokenAddress);
    event RewardsManagerAddressInitialized(address indexed rewardsManagerAddress);
    event KeyParameterUpdated(address indexed rewardsManagerAddress);
    event RewardsManagerFunded(uint256 amount);
    event MintedToTreasury(uint256 amount);
    event TransferredFromTreasury(address indexed to, uint256 amount);

    error InvalidAmount();
    error InsufficientBalance();
    error InvalidAddress();
    error JudgeTokenRecoveryNotAllowed();
    error CannotInputThisContractAddress();
    error InsufficientContractBalance();
    error EOANotAllowed();
    error TotalStakingRewardAllocationExceeded();
    error TeamDevelopmentAllocationExceeded();
    error ExceedsRemainingAllocation();
    error NotEnough();
    error ValueHigherThanThreshold();

    constructor(address _judgeTokenAddress, address _rewardsManagerAddress) {
        require(_judgeTokenAddress != address(0) && _rewardsManagerAddress != address(0), InvalidAddress());
        require(_judgeTokenAddress.code.length > 0 && _rewardsManagerAddress.code.length > 0, EOANotAllowed());
        judgeToken = JudgeToken(_judgeTokenAddress);
        rewardsManager = RewardsManager(_rewardsManagerAddress);

        decimals = judgeToken.decimals();
        quarterlyReward = 1_250_000 * 10 ** decimals;

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

    function updateKeyParameter(address _rewardsManagerAddress) external validAddress(_rewardsManagerAddress) onlyRole(TREASURY_ADMIN_ROLE) {
        require(_rewardsManagerAddress != address(this), CannotInputThisContractAddress());
        require(_rewardsManagerAddress.code.length > 0, EOANotAllowed());
        rewardsManager = RewardsManager(_rewardsManagerAddress);

        emit KeyParameterUpdated(_rewardsManagerAddress);
    }

    function updateFeePercent(uint8 _newFeePercent) external onlyRole(TREASURY_ADMIN_ROLE){
        require(_newFeePercent < FEE_PERCENT_THRESHOLD, ValueHigherThanThreshold());
        feePercent = _newFeePercent;
    }

    function updateJudgeRecoveryThreshold(uint256 newJudgeRecoveryThreshold) external onlyRole(TREASURY_ADMIN_ROLE){
        judgeRecoveryMinimumThreshold = newJudgeRecoveryThreshold;
    }

    function fundRewardsManager() external onlyRole(FUND_MANAGER_ROLE) {
        require(stakingRewardsFundsFromTreasury < judgeToken.MAX_STAKING_REWARD_ALLOCATION(), TotalStakingRewardAllocationExceeded());
        require(quarterlyReward <= judgeToken.MAX_STAKING_REWARD_ALLOCATION() - stakingRewardsFundsFromTreasury, ExceedsRemainingAllocation());
        judgeToken.mintFromAllocation(address(rewardsManager), quarterlyReward);
        stakingRewardsFundsFromTreasury += quarterlyReward;

        emit RewardsManagerFunded(quarterlyReward);
    }

    function mintToTreasuryReserve(uint256 _amount) external validAmount(_amount) onlyRole(FUND_MANAGER_ROLE){
        judgeToken.mint(address(this), _amount);
        treasuryPreciseBalance += _amount;

        emit MintedToTreasury(_amount);
    }

    function fundTeam(address _addr, uint256 _amount) external validAddress(_addr) validAmount(_amount) onlyRole(FUND_MANAGER_ROLE) nonReentrant{
       require(teamFundingReceived < judgeToken.MAX_TEAM_ALLOCATION(), TeamDevelopmentAllocationExceeded());
        require(_amount <= judgeToken.MAX_TEAM_ALLOCATION() - teamFundingReceived, ExceedsRemainingAllocation());
        judgeToken.mintFromAllocation(msg.sender, _amount);
        teamFundingReceived += _amount;
    }

    function transferFromTreasury(address _addr, uint256 _amount) external onlyRole(FUND_MANAGER_ROLE) validAddress(_addr) validAmount(_amount) nonReentrant{
        
        require(_addr != address(this), CannotInputThisContractAddress());
        require(_amount <= treasuryPreciseBalance, InsufficientBalance());
        judgeToken.safeTransfer(_addr, _amount);

        treasuryPreciseBalance -= _amount;

            emit TransferredFromTreasury(_addr, _amount);
    }

    function calculateMisplacedJudge() public view onlyRole(TOKEN_RECOVERY_ROLE) returns (uint256) {
        uint256 misplacedJudgeAmount = judgeToken.balanceOf(address(this)) - treasuryPreciseBalance;
        return misplacedJudgeAmount;
    }

    function recoverMisplacedJudgeToken(address _to, uint256 _amount) external onlyRole(TOKEN_RECOVERY_ROLE) validAmount(_amount) validAddress(_to) nonReentrant{
        uint256 misplacedJudgeAmount = calculateMisplacedJudge();
        require(_amount <= misplacedJudgeAmount, InvalidAmount());
        require(_amount >= judgeRecoveryMinimumThreshold, NotEnough());
        require(_to != address(this), CannotInputThisContractAddress());
        uint256 refund = (_amount * uint256(100-feePercent))/100;
        uint256 fee = _amount - refund;
        treasuryPreciseBalance += fee;
        judgeToken.safeTransfer(_to, refund);
    }

    function recoverERC20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        onlyRole(TOKEN_RECOVERY_ROLE) validAmount(_amount)
    nonReentrant{
        require(_strandedTokenAddr != address(0) && _addr != address(0), InvalidAddress());
        require(_amount <= IERC20(_strandedTokenAddr).balanceOf(address(this)), InsufficientContractBalance());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        require(_addr != address(this), CannotInputThisContractAddress());
        uint256 refund = (_amount * uint256(100-feePercent))/100;
        uint256 fee = _amount - refund;
        treasuryFeeBalanceOfStrandedToken[_strandedTokenAddr] += fee;
        IERC20(_strandedTokenAddr).transfer(_addr, refund);
    }

    function transferFeesFromOtherTokensOutOfTreasury(address _strandedTokenAddr, address _to, uint256 _amount)external onlyRole(TREASURY_ADMIN_ROLE) validAmount(_amount) nonReentrant{
        require(_strandedTokenAddr != address(0) && _to != address(0), InvalidAddress());
        require(_to != address(this), CannotInputThisContractAddress());
        require(treasuryFeeBalanceOfStrandedToken[_strandedTokenAddr] > 0, InsufficientBalance());
        treasuryFeeBalanceOfStrandedToken[_strandedTokenAddr] -= _amount;
        IERC20(_strandedTokenAddr).transfer(_to, _amount);
    }
}
