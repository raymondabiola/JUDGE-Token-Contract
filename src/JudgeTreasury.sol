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

    uint256 decimals = 18;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public stakingRewardsFundsFromTreasury;
    uint256 internal treasuryPreciseBalance;

    event JudgeTokenAddressInitialized(address indexed judgeTokenAddress);
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
    error AlreadyInitialized();
    error SetRewardsMangerAsZeroAddr();
    error EOANotAllowed();

    constructor(address _judgeTokenAddress, address _rewardsManagerAddress) {
        require(_rewardsManagerAddress == address(0), SetRewardsMangerAsZeroAddr());
        require(_judgeTokenAddress != address(0), InvalidAddress());
        require(_judgeTokenAddress != address(this), InputedThisContractAddress());
        require(_judgeTokenAddress.code.length > 0, EOANotAllowed());
        judgeToken = JudgeToken(_judgeTokenAddress);
        rewardsManager = RewardsManager(_rewardsManagerAddress);

        emit JudgeTokenAddressInitialized(_judgeTokenAddress);
    }

    function initializeKeyParameter(address _rewardsManagerAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(rewardsManager) == address(0), AlreadyInitialized());
        require(_rewardsManagerAddress != address(0), InvalidAddress());
        require(_rewardsManagerAddress != address(this), InputedThisContractAddress());
        require(_rewardsManagerAddress.code.length > 0, EOANotAllowed());
        rewardsManager = RewardsManager(_rewardsManagerAddress);

        emit RewardsManagerAddressInitialized(_rewardsManagerAddress);
    }

    function updateKeyParameter(address _rewardsManagerAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_rewardsManagerAddress != address(0), InvalidAddress());
        require(_rewardsManagerAddress != address(this), InputedThisContractAddress());
        require(_rewardsManagerAddress.code.length > 0, EOANotAllowed());
        rewardsManager = RewardsManager(_rewardsManagerAddress);

        emit KeyParameterUpdated(_rewardsManagerAddress);
    }

    function fundRewardsManager(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            416_667 * 10 ** uint256(decimals) <= _amount && _amount <= 1_250_000 * 10 ** uint256(decimals),
            InvalidAmount()
        );
        judgeToken.mint(address(rewardsManager), _amount);
        stakingRewardsFundsFromTreasury += _amount;

        emit RewardsManagerFunded(_amount);
    }

    function mintToTreasury(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount > 0, InvalidAmount());
        judgeToken.mint(address(this), _amount);
        treasuryPreciseBalance += _amount;

        emit MintedToTreasury(_amount);
    }

    function transferFromTreasury(address _addr, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_addr != address(0), InvalidAddress());
        require(_addr != address(this), InputedThisContractAddress());
        require(_amount > 0, InvalidAmount());
        require(_amount <= judgeToken.balanceOf(address(this)), InsufficientBal());
        judgeToken.safeTransfer(_addr, _amount);

        treasuryPreciseBalance -= _amount;

        if (_addr == address(rewardsManager)) {
            stakingRewardsFundsFromTreasury += _amount;

            emit TransferredFromTreasury(_addr, _amount);
        }
    }

    function calculateMisplacedJudge() public view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        uint256 misplacedJudge = judgeToken.balanceOf(address(this)) - treasuryPreciseBalance;
        return misplacedJudge;
    }

    function recoverMisplacedJudgeToken(address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 misplacedJudge = calculateMisplacedJudge();
        require(_to != address(0), InvalidAddress());
        require(_to != address(this), InputedThisContractAddress());
        require(_amount > 0, InvalidAmount());
        require(_amount <= misplacedJudge, InvalidAmount());
        require(judgeToken.balanceOf(address(this)) > 0, ContractBalanceNotEnough());
        judgeToken.safeTransfer(_to, _amount);
    }

    function recoverERC20(address _strandedTokenAddr, address _addr, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_strandedTokenAddr != address(0) && _addr != address(0), InvalidAddress());
        require(_amount > 0, InvalidAmount());
        require(_amount <= IERC20(_strandedTokenAddr).balanceOf(address(this)), ContractBalanceNotEnough());
        require(_strandedTokenAddr != address(judgeToken), RecoveryOfJudgeNA());
        IERC20(_strandedTokenAddr).transfer(_addr, _amount);
    }
}
