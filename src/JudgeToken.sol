// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20Capped} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Votes} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "../lib/openzeppelin-contracts/contracts/utils/Nonces.sol";

contract JudgeToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, AccessControl, ERC20Capped {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE"); 
    bytes32 public constant ALLOCATION_MINTER_ROLE = keccak256("ALLOCATION_MINTER_ROLE"); //Grant role to JudgeTreasury contract during deployment
    uint256 public immutable MAX_STAKING_REWARD_ALLOCATION = 50_000_000 * 10 ** 18;
    uint256 public immutable MAX_TEAM_ALLOCATION = 50_000_000 * 10 ** 18;
    uint256 public mintableUnallocatedJudge;
    uint256 public mintableAllocatedJudge;

    event Minted(address indexed caller, address indexed to, uint256 amount);

    error AmountExceedsMintableUnallocatedJudge();
    error AmountExceedsMintableAllocatedJudge();
    error InitialMintExceedsLimit();

    constructor(uint256 initialSupply)
        ERC20("JudgeToken", "JUDGE")
        ERC20Capped(500_000_000 * 10 ** decimals())
        ERC20Permit("JudgeToken")
    {
        if(initialSupply > 100_000 * 10 ** decimals()) revert InitialMintExceedsLimit();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _mint(msg.sender, initialSupply);

        mintableUnallocatedJudge = cap() - MAX_STAKING_REWARD_ALLOCATION - MAX_TEAM_ALLOCATION - initialSupply;
        mintableAllocatedJudge = MAX_STAKING_REWARD_ALLOCATION + MAX_TEAM_ALLOCATION;
        emit Minted(msg.sender, msg.sender, initialSupply);
    }

    function decreaseMintableUnallocatedJudge(uint256 amount) internal {
        if(amount > mintableUnallocatedJudge) revert AmountExceedsMintableUnallocatedJudge();
        unchecked{mintableUnallocatedJudge -= amount;}
    }

    function decreaseMintableAllocatedJudge(uint256 amount) internal {
        if(amount > mintableAllocatedJudge) revert AmountExceedsMintableAllocatedJudge();
        unchecked{mintableAllocatedJudge -= amount;}
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        decreaseMintableUnallocatedJudge(amount);
        _mint(to, amount);
        emit Minted(msg.sender, to, amount);
    }

    // Default admin should grant the allocation_minter role only to judgeTreasury
    function mintFromAllocation(address to, uint256 amount) external onlyRole(ALLOCATION_MINTER_ROLE) {
        decreaseMintableAllocatedJudge(amount);
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