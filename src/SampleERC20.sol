// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SampleERC20 is ERC20{
    constructor () ERC20("Sample Token", "ST"){
    }

    function mint(address _to,uint256 _amount)public{
        _mint(_to, _amount);
    }
}