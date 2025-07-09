// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {JudgeToken} from "./JudgeToken.sol";

contract JudgeStaking is AccessControl, ReentrancyGuard {
    using SafeERC20 for JudgeToken;
    JudgeToken public judgeToken;
    uint256 public accJudgePerShare;
    uint256 private constant SCALE = 1e18;
    mapping(address => uint256) public amountStaked;
    mapping(address => uint256) public rewardDebt;
    bytes32 DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");

    event RewardsFunded(uint amount);

    error InvalidAmount();

    constructor(address _judgeTokenAddress) {
        judgeToken = JudgeToken(_judgeTokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function fundReward(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, InvalidAmount());
        judgeToken.safeTransferFrom(msg.sender, address(this), amount);
    }
}
