// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/JudgeToken.sol";

contract JudgeTokenTest is Test{
    JudgeToken public judgeToken;
    address public owner;
    address public zeroAddress;
    address public user1;
    address public user2;
    address public user3;
    uint8 decimals = 18;

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    function setUp() public{
owner = address(this);
zeroAddress = address(0);
user1 = makeAddr("user1");
user2 = makeAddr("user2");
user3 = makeAddr("user3");

uint256 initialSupply = 1_000_000 * 10 ** uint256(decimals);
judgeToken = new JudgeToken(initialSupply);
    }

function testName()public{

}

function testSymbol()public{

}

function testDecimals()public{

}

function testTotalSupply()public{

}

    function testDeployerIsOwner()public{
              bytes32 minterRole = judgeToken.MINTER_ROLE();
              bytes32 defaultAdmin = judgeToken.DEFAULT_ADMIN_ROLE();
              assertTrue(judgeToken.hasRole(defaultAdmin, owner));
              assertTrue(judgeToken.hasRole(minterRole, owner));
    }

    function testMint()public{
        uint256 mintAmount = 10_000 * 10 ** uint256(decimals);
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        judgeToken.mint(user1, mintAmount);
        assertEq(judgeToken.balanceOf(user1), mintAmount);
        assertEq(judgeToken.totalSupply(), judgeToken.balanceOf(user1)+ judgeToken.balanceOf(owner));

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                minterRole
            )
        );
        judgeToken.mint(user1, mintAmount);
    }

function testBurn()public{
    uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
    uint256 burnAmount = 10_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintAmount);
        vm.prank(user1);
        judgeToken.burn(burnAmount);
        assertEq(mintAmount - burnAmount, judgeToken.balanceOf(user1));
}

function testBurnFrom()public{

}

function testBalanceOf()public{

}

function testTransfer()public{

}

function testAllowance()public{

}

function testApprove()public{

}

function testTransferFrom()public{
    
}

function testHasRole()public{

}

function testGetRoleAdmin()public{

}

function testGrantRole()public{

}

function testRevokeRole()public{

}

function testRenounceRole()public{

}

function testSupportsInteface()public{

}

function testCap()public{

}

function testNumCheckpoints()public{

}

function testCheckPoints()public{

}

function testPermit()public{

}
}