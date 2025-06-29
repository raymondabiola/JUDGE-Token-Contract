// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20Capped} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract JudgeToken is ERC20, ERC20Burnable, ERC20Permit, AccessControl, ERC20Capped, ReentrancyGuard{
bytes32 constant public MINTER_ROLE = keccak256("MINTER_ROLE");
bytes32 constant public SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

constructor (uint256 initialSupply) 
ERC20 ("JudgeToken", "JUDGE")
ERC20Capped(100_000_000*10**decimals())
ERC20Permit("JudgeToken")
{
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MINTER_ROLE, msg.sender);
    _grantRole(SNAPSHOT_ROLE, msg.sender);

    _mint(msg.sender, initialSupply);
}

function mint(address to, uint amount)external onlyRole(MINTER_ROLE){
    _mint(to, amount);
}

function setRoleAdmin(bytes32 role, bytes32 adminRole)external onlyRole(DEFAULT_ADMIN_ROLE){
_setRoleAdmin(role, adminRole);
}

function _update(address from, address to, uint value) internal override (ERC20, ERC20Capped){
    super._update(from, to, value);
}
}