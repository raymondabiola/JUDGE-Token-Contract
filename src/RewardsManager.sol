// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";
import {JudgeTreasury} from "./JudgeTreasury.sol";

contract RewardsManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;
    using SafeERC20 for IERC20;

    JudgeToken public judgeToken;
    JudgeTreasury public judgeTreasury;

    bytes32 public constant REWARDS_DISTRIBUTOR_ROLE = keccak256("REWARDS_DISTRIBUTOR_ROLE"); //Assign to judgeStaking on deployment
    bytes32 public constant REWARDS_MANAGER_ADMIN_ROLE = keccak256("REWARDS_MANAGER_ADMIN_ROLE");
    bytes32 public constant TOKEN_RECOVERY_ROLE = keccak256("TOKEN_RECOVERY_ROLE");
    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");
    bytes32 public constant REWARDS_MANAGER_PRECISE_BALANCE_UPDATER = keccak256("REWARDS_MANAGER_PRECISE_BALANCE_UPDATER"); //Assign Role to judgeTreasury at deployment
    
    uint256 public totalRewardsPaid; //Total rewards (base + bonus) claimed by users in the staking pool
    uint8 public feePercent; //Fee charged to recover misplaced JudgeTokens sent to the contract
    uint8 public constant FEE_PERCENT_MAX_THRESHOLD = 30; 
    uint256 public judgeRecoveryMinimumThreshold; //Feasible minimum amount of JudgeTokens that's worth recovering
    uint256 public rewardsManagerPreciseBalance; //Exact total amount of judgeTokens in rewards Manager contract excluding misplaced judgeTokens
    uint256 public rewardsManagerBonusBalance; //Bonus reward balance of this contract, incremented by recieving bonus from treasury and decrement by paying out bonus

    mapping(address => uint256) public feeBalanceOfStrandedToken; //mapping of accumulated fee of recovered misplaced tokens

    event JudgeTokenAddressWasSet(address indexed judgeTokenAddress);
    event JudgeTreasuryAdressUpdated(address indexed judgeTreasuryAddress);
    event JudgeRecoveryMinimumThresholdUpdated(uint256 oldValue, uint256 newValue);
    event FeePercentUpdated(uint8 oldValue, uint8 newValue);
    event AdminWithdrawed(address indexed admin, address indexed receiver, uint256 amount);
    event EmergencyWithdrawal(address indexed admin, address indexed receiver, uint256 amount);
    event Erc20Recovered(address indexed tokenAddress, address indexed to, uint256 refund, uint256 fee);
    event FeesFromOtherTokensTransferred (address indexed tokenAddress, address indexed to, uint256 feeTransferred, uint256 feeBalanceOfStrandedToken);
    event JudgeTokenRecovered(address indexed to, uint256 refund, uint256 fee);

    error InvalidAmount();
    error InvalidAddress();
    error CannotInputThisContractAddress();
    error EOANotAllowed();
    error JudgeTokenRecoveryNotAllowed();
    error InsufficientContractBalance();
    error InsufficientBalance();
    error ValueHigherThanThreshold();
    error NotUpToThreshold();

    constructor(address _judgeTokenAddress) validAddress(_judgeTokenAddress){
        require(_judgeTokenAddress.code.length > 0, EOANotAllowed());
        judgeToken = JudgeToken(_judgeTokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        emit JudgeTokenAddressWasSet(_judgeTokenAddress);
    }

     modifier validAddress(address _to){
              require(_to != address(0), InvalidAddress());
              _;
    }

    modifier notSelf(address _to){
        require(_to != address(this), CannotInputThisContractAddress());
        _;
    }

       modifier validAmount(uint256 _amount){
         require(_amount > 0, InvalidAmount());
         _;
    }

    function setJudgeTreasuryAddress(address _judgeTreasuryAddress) external validAddress(_judgeTreasuryAddress) notSelf(_judgeTreasuryAddress) onlyRole(REWARDS_MANAGER_ADMIN_ROLE) {
        require(_judgeTreasuryAddress.code.length > 0, EOANotAllowed());
        
        judgeTreasury = JudgeTreasury(_judgeTreasuryAddress);

        emit JudgeTreasuryAdressUpdated(_judgeTreasuryAddress);
    }

    function updateFeePercent(uint8 _newFeePercent) external onlyRole(REWARDS_MANAGER_ADMIN_ROLE){
        require(_newFeePercent < FEE_PERCENT_MAX_THRESHOLD, ValueHigherThanThreshold());
        uint8 oldFeePercent = feePercent;
        feePercent = _newFeePercent;
        emit FeePercentUpdated(oldFeePercent, _newFeePercent);
    }

    function updateJudgeRecoveryMinimumThreshold(uint256 newJudgeRecoveryMinimumThreshold) external onlyRole(REWARDS_MANAGER_ADMIN_ROLE){
        uint256 oldJudgeRecoveryMinimumThreshold = judgeRecoveryMinimumThreshold;
        judgeRecoveryMinimumThreshold = newJudgeRecoveryMinimumThreshold;
        emit JudgeRecoveryMinimumThresholdUpdated(oldJudgeRecoveryMinimumThreshold, newJudgeRecoveryMinimumThreshold);
    }

    // Assign this role to the JudgeTreasury contract from deployment script
    function increaseRewardsManagerPreciseBalance(uint256 _amount)external onlyRole(REWARDS_MANAGER_PRECISE_BALANCE_UPDATER){
        rewardsManagerPreciseBalance += _amount;
    }

    function increaseRewardsManagerBonusBalance(uint256 _amount) external onlyRole(REWARDS_MANAGER_PRECISE_BALANCE_UPDATER){
        rewardsManagerBonusBalance += _amount;
    }

    // Grant the rewards distributor role to the judge staking contract in the deployment script.
    function sendRewards(address _addr, uint256 _amount) external onlyRole(REWARDS_DISTRIBUTOR_ROLE) validAddress(_addr) nonReentrant {
        require(_amount <= rewardsManagerPreciseBalance, InsufficientBalance());
        judgeToken.safeTransfer(_addr, _amount);
        totalRewardsPaid += _amount;
        rewardsManagerPreciseBalance -= _amount;
    }

    function sendBonus(address _addr, uint256 _amount) external onlyRole(REWARDS_DISTRIBUTOR_ROLE) validAddress(_addr) nonReentrant{
        require(_amount <= rewardsManagerBonusBalance, InsufficientBalance());
        judgeToken.safeTransfer(_addr, _amount);
        totalRewardsPaid += _amount;
        rewardsManagerBonusBalance -= _amount;
    }

    function adminWithdrawal(address _to, uint256 _amount) external validAddress(_to) validAmount(_amount) notSelf(_to) onlyRole(FUND_MANAGER_ROLE) nonReentrant{
        require(_amount <= rewardsManagerPreciseBalance, InsufficientBalance());
        judgeToken.safeTransfer(_to, _amount);
        rewardsManagerPreciseBalance -= _amount;

        emit AdminWithdrawed(msg.sender, _to, _amount);
    }

    //Sensitive function to pull out all balances from rewardsManager
    function emergencyWithdrawal(address _to) external validAddress(_to) notSelf(_to) onlyRole(FUND_MANAGER_ROLE) nonReentrant{
        require(judgeToken.balanceOf(address(this)) > 0, InsufficientContractBalance());
        judgeToken.safeTransfer(_to, judgeToken.balanceOf(address(this)) );
        rewardsManagerPreciseBalance = 0;
         rewardsManagerBonusBalance = 0;

        emit EmergencyWithdrawal(msg.sender, _to, judgeToken.balanceOf(address(this)));
    }

    function calculateMisplacedJudge() public view onlyRole(TOKEN_RECOVERY_ROLE) returns (uint256) {
        uint256 contractBalance = judgeToken.balanceOf(address(this));
        uint256 misplacedJudgeAmount = contractBalance - rewardsManagerPreciseBalance - rewardsManagerBonusBalance;
        return misplacedJudgeAmount;
    }

    function recoverMisplacedJudge(address _to, uint256 _amount) external validAddress(_to) validAmount(_amount) notSelf(_to)  onlyRole(TOKEN_RECOVERY_ROLE) nonReentrant{
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

    function transferFeesFromOtherTokensOutOfRewardsManager(address _strandedTokenAddr, address _to, uint256 _amount)external notSelf(_to) validAmount(_amount) onlyRole(FUND_MANAGER_ROLE) nonReentrant{
        require(_strandedTokenAddr != address(0) && _to != address(0), InvalidAddress());
        require(_strandedTokenAddr != address(judgeToken), JudgeTokenRecoveryNotAllowed());
        require(_amount <= feeBalanceOfStrandedToken[_strandedTokenAddr], InsufficientBalance());
        feeBalanceOfStrandedToken[_strandedTokenAddr] -= _amount;
        IERC20(_strandedTokenAddr).safeTransfer(_to, _amount);
        emit FeesFromOtherTokensTransferred(_strandedTokenAddr, _to, _amount, feeBalanceOfStrandedToken[_strandedTokenAddr]);
    }
}