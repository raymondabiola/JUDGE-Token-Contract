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
    uint256 initialSupply = 1_000_000 * 10 ** uint256(decimals);

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSpender(address spender);
    error ERC20ExceededCap(uint256 increasedSupply, uint256 cap);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error AccessControlBadConfirmation();

    function setUp() public{
        owner = address(this);
        zeroAddress = address(0);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        judgeToken = new JudgeToken(initialSupply);
    }

    function testName()public{
        assertEq("JudgeToken", judgeToken.name());
    }

    function testSymbol()public{
        assertEq("JUDGE", judgeToken.symbol());
    }

    function testDecimals()public{
        assertEq(decimals, judgeToken.decimals());
    }

    function testCap()public{
        uint256 cap = 100_000_000 * 10 ** uint256(decimals);
        uint256 mintAmount = 99_000_001 * 10 ** uint256(decimals);
        uint256 increasedSupply = mintAmount + initialSupply;
        assertEq(cap, judgeToken.cap());
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20ExceededCap.selector,
                increasedSupply,
                judgeToken.cap()
            )
        );
        judgeToken.mint(user1, mintAmount);
    }

    function testTotalSupply()public{
        uint256 mintAmount = 67_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintAmount);
        uint256 expectedTotalSupply = mintAmount + initialSupply;
        assertEq(expectedTotalSupply, judgeToken.totalSupply());
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

        vm.expectRevert(
        abi.encodeWithSelector(
            ERC20InvalidReceiver.selector,
            address(0)
        )
        );
        judgeToken.mint(zeroAddress, mintAmount);
    }

    function testBurn()public{
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 burnAmount = 10_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintAmount);
        vm.prank(user1);
        judgeToken.burn(burnAmount);
        assertEq(mintAmount - burnAmount, judgeToken.balanceOf(user1));

        vm.expectRevert(
                abi.encodeWithSelector(
                    ERC20InvalidSender.selector,
                    address(0)
                )
            );
        vm.prank(zeroAddress);
        judgeToken.burn(burnAmount);
    }

    function testBurnFrom()public{
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 allowance = 30_000 * 10 ** uint256(decimals);
        uint256 burnAmount = 10_000 * 10 ** uint256(decimals);
        uint256 balanceLeft = mintAmount - burnAmount;
        judgeToken.mint(user2, mintAmount);

        vm.prank(user2);
        judgeToken.approve(user1, allowance);

        vm.prank(user1);
        judgeToken.burnFrom(user2, burnAmount);
        
        assertEq(judgeToken.balanceOf(user2), balanceLeft);

    // This will revert with insufficiant allowance before reverting with invalid sender
        vm.expectRevert(
                abi.encodeWithSelector(
                    ERC20InsufficientAllowance.selector,
                    user1,
                    0,
                    burnAmount
                )
            );
        vm.prank(user1);
        judgeToken.burnFrom(zeroAddress, burnAmount);
    }

    function testBalanceOf()public{
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        assertEq(judgeToken.balanceOf(user2), 0);
        judgeToken.mint(user2, mintAmount);
        assertEq(judgeToken.balanceOf(user2), mintAmount);
    }

    function testTransfer()public{
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 amount = 40_000 * 10 ** uint256(decimals);
        uint256 amountGreaterThanBalance = 61000 * 10 ** uint256(decimals); 
        judgeToken.mint(user2, mintAmount);

        vm.prank(user2);
        judgeToken.transfer(user1, amount);
        assertEq(judgeToken.balanceOf(user1), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientBalance.selector,
                user2,
                judgeToken.balanceOf(user2),
                amountGreaterThanBalance
            )
        );
        vm.prank(user2);
        judgeToken.transfer(user1, amountGreaterThanBalance);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InvalidSender.selector,
                address(0)
            )
        );
        vm.prank(zeroAddress);
        judgeToken.transfer(user1, amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InvalidReceiver.selector,
                address(0)
            )
        );
        vm.prank(user2);
        judgeToken.transfer(zeroAddress, amount);
    }

    function testTransferFrom()public{
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 allowance = 30_000 * 10 ** uint256(decimals);
        uint256 valueGreaterThanAllowance = 30_001 * 10 ** uint256(decimals);
        judgeToken.mint(user2, mintAmount);

        vm.prank(user2);
            judgeToken.approve(user1, allowance);

        vm.expectRevert(
                abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector,
                user1,
                allowance,
                valueGreaterThanAllowance
                )
        );
        vm.prank(user1);
        judgeToken.transferFrom(user2, user3, valueGreaterThanAllowance);

        vm.prank(user1);
        judgeToken.transferFrom(user2, user3, allowance);
        assertEq(judgeToken.balanceOf(user3), allowance);
    }

    function testAllowance()public{
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 allowance = 30_000 * 10 ** uint256(decimals);
        judgeToken.mint(user2, mintAmount);

        vm.prank(user2);
        judgeToken.approve(user1, allowance);

        assertEq(judgeToken.allowance(user2, user1), allowance);
    }

    function testApprove()public{
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 allowance = 30_000 * 10 ** uint256(decimals);
            judgeToken.mint(user2, mintAmount);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ERC20InvalidSpender.selector,
                    address(0)
                )
        );
        vm.prank(user2);
        judgeToken.approve(zeroAddress, allowance);
    }

    function testGrantRole()public{
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        bytes32 defaultAdmin = judgeToken.DEFAULT_ADMIN_ROLE();
        assertFalse(judgeToken.hasRole(minterRole, user1));
        judgeToken.grantRole(minterRole, user1);
        assertTrue(judgeToken.hasRole(minterRole, user1));

        vm.expectRevert(
            abi.encodeWithSelector(
        AccessControlUnauthorizedAccount.selector,
        user1,
        defaultAdmin
            )
        );
        vm.prank(user1);
        judgeToken.grantRole(minterRole, user2);
    }

    function testHasRole()public{
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        assertFalse(judgeToken.hasRole(minterRole, user1));
        judgeToken.grantRole(minterRole, user1);
        assertTrue(judgeToken.hasRole(minterRole, user1));
    }

    function testGetRoleAdmin()public{
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        bytes32 defaultAdmin = judgeToken.DEFAULT_ADMIN_ROLE();
        assertEq(judgeToken.getRoleAdmin(minterRole), defaultAdmin);
    }

    function testRevokeRole()public{
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        bytes32 defaultAdmin = judgeToken.DEFAULT_ADMIN_ROLE();
        judgeToken.grantRole(minterRole, user2);
        assertTrue(judgeToken.hasRole(minterRole, user2));

        vm.expectRevert(
        abi.encodeWithSelector(
        AccessControlUnauthorizedAccount.selector,
        user1,
        defaultAdmin
        )
    );
        vm.prank(user1);
        judgeToken.revokeRole(minterRole, user2);
        assertTrue(judgeToken.hasRole(minterRole, user2));

        judgeToken.revokeRole(minterRole, user2);
        assertFalse(judgeToken.hasRole(minterRole, user2));
    }

    function testRenounceRole()public{
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        judgeToken.grantRole(minterRole, user2);
        assertTrue(judgeToken.hasRole(minterRole, user2));

        vm.prank(user2);
        judgeToken.renounceRole(minterRole, user2);
        assertFalse(judgeToken.hasRole(minterRole, user2));

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlBadConfirmation.selector
            )
        );
         vm.prank(user2);
        judgeToken.renounceRole(minterRole, user1);
    }

    function testSetRoleAdmin()public{

    }

    function testNonces()public{

    }

    function testSupportsInteface()public{

    }

    function testDelegate()public{
        
    }

    function testDelegates()public{

    }

    function testGetVotes()public{

    }

    function testGetPastVotes()public{

    }

    function testGetPastTotalSupply()public{

    }

    function testDelegateBySig()public{

    }

    function testNumCheckpoints()public{

    }

    function testCheckPoints()public{

    }

    function testPermit()public{

    }

    function testDOMAIN_SEPERATOR()public{

    }
}