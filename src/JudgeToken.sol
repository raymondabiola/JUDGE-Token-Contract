// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20Capped} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Votes} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {JudgeTreasury} from "./JudgeTreasury.sol";
import {Nonces} from "../lib/openzeppelin-contracts/contracts/utils/Nonces.sol";

contract JudgeToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, AccessControl, ERC20Capped {
    JudgeTreasury public judgeTreasury;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public mintableJudgeAmount;

    event Minted(address indexed caller, address indexed to, uint256 amount);
    event JudgeTreasuryAddressUpdated(address indexed by, address indexed JudgeTreasuryAddress);

    error TreasuryPlaceholderAsZeroAddr();
    error AlreadyInitialized();
    error ExceededMaxMintable();
    error InvalidAddress();
    error EOANotAllowed();
    error InputedThisContractAddress();
    error TooHigh();

    constructor(uint256 initialSupply)
        ERC20("JudgeToken", "JUDGE")
        ERC20Capped(500_000_000 * 10 ** decimals())
        ERC20Permit("JudgeToken")
    {
        require(initialSupply <= 100_000 * 10 ** decimals(), TooHigh());
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _mint(msg.sender, initialSupply);
        emit Minted(msg.sender, msg.sender, initialSupply);
    }

    function setJudgeTreasuryAddress(address _judgeTreasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_judgeTreasuryAddress != address(0), InvalidAddress());
         require(_judgeTreasuryAddress.code.length > 0, EOANotAllowed());
         require(_judgeTreasuryAddress != address(this), InputedThisContractAddress());
        judgeTreasury = JudgeTreasury(_judgeTreasuryAddress);
        _grantRole(MINTER_ROLE, _judgeTreasuryAddress);

        mintableJudgeAmount = cap() - judgeTreasury.totalStakingRewardBudget() - judgeTreasury.teamDevelopmentBudget();
        emit JudgeTreasuryAddressUpdated(msg.sender, _judgeTreasuryAddress);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(amount <= mintableJudgeAmount, ExceededMaxMintable());
        _mint(to, amount);
        emit Minted(msg.sender, to, amount);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
