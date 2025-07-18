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

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public stakingRewardsFundsFromTreasury;
    uint256 public teamFundingReceived;
    uint256 internal treasuryPreciseBalance;

    uint256 decimals;
    uint256 public quarterlyReward; 

    event JudgeTokenAddressWasSet(address indexed judgeTokenAddress);
    event RewardsManagerAddressInitialized(address indexed rewardsManagerAddress);
    event KeyParameterUpdated(address indexed rewardsManagerAddress);
    event RewardsManagerFunded(uint256 amount);
    event MintedToTreasury(uint256 amount);
    event TransferredFromTreasury(address indexed to, uint256 amount);

    error InvalidAmount();
    error InsufficientBal();
    error InvalidAddress();
    error RecoveryOfJudgeNA();
    error InputedThisContractAddress();
    error ContractBalanceNotEnough();
    error EOANotAllowed();
    error TotalStakingRewardAllocationUsed();
    error TeamDevelpomentAllocationUsed();
    error RemainingAllocationExceeded();

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

    function updateKeyParameter(address _rewardsManagerAddress) external validAddress(_rewardsManagerAddress) onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_rewardsManagerAddress != address(this), InputedThisContractAddress());
        require(_rewardsManagerAddress.code.length > 0, EOANotAllowed());
        rewardsManager = RewardsManager(_rewardsManagerAddress);

        emit KeyParameterUpdated(_rewardsManagerAddress);
    }

    function fundRewardsManager() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakingRewardsFundsFromTreasury < judgeToken.MAX_STAKING_REWARD_ALLOCATION(), TotalStakingRewardAllocationUsed());
        require(quarterlyReward <= judgeToken.MAX_STAKING_REWARD_ALLOCATION() - stakingRewardsFundsFromTreasury, RemainingAllocationExceeded());
        judgeToken.mint(address(rewardsManager), quarterlyReward);
        stakingRewardsFundsFromTreasury += quarterlyReward;

        emit RewardsManagerFunded(quarterlyReward);
    }

    function mintToTreasuryReserve(uint256 _amount) external validAmount(_amount) onlyRole(DEFAULT_ADMIN_ROLE){
        judgeToken.mint(address(this), _amount);
        treasuryPreciseBalance += _amount;

        emit MintedToTreasury(_amount);
    }

    function teamFunding(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) validAmount(_amount) nonReentrant{
       require(teamFundingReceived < judgeToken.MAX_TEAM_ALLOCATION(), TeamDevelpomentAllocationUsed());
        require(_amount <= judgeToken.MAX_TEAM_ALLOCATION() - teamFundingReceived, RemainingAllocationExceeded());
        judgeToken.mint(msg.sender, _amount);
        teamFundingReceived += _amount;
    }

    function transferFromTreasury(address _addr, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) validAddress(_addr) validAmount(_amount) nonReentrant{
     
        require(_addr != address(this), InputedThisContractAddress());
        require(_amount <= judgeToken.balanceOf(address(this)), InsufficientBal());
        judgeToken.safeTransfer(_addr, _amount);

        treasuryPreciseBalance -= _amount;

            emit TransferredFromTreasury(_addr, _amount);
    }

    function calculateMisplacedJudge() public view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        uint256 misplacedJudge = judgeToken.balanceOf(address(this)) - treasuryPreciseBalance;
        return misplacedJudge;
    }

    function recoverMisplacedJudgeToken(address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) validAmount(_amount) validAddress(_to) nonReentrant{
        uint256 misplacedJudge = calculateMisplacedJudge();
        require(_to != address(this), InputedThisContractAddress());
        require(_amount <= misplacedJudge, InvalidAmount());
        require(judgeToken.balanceOf(address(this)) > 0, ContractBalanceNotEnough());
        judgeToken.safeTransfer(_to, _amount);
    }

    function recoverERC20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) validAmount(_amount)
    nonReentrant{
        require(_strandedTokenAddr != address(0) && _addr != address(0), InvalidAddress());
        require(_amount <= IERC20(_strandedTokenAddr).balanceOf(address(this)), ContractBalanceNotEnough());
        require(_strandedTokenAddr != address(judgeToken), RecoveryOfJudgeNA());
        IERC20(_strandedTokenAddr).transfer(_addr, _amount);
    }
}
