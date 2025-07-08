// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/JudgeToken.sol";
import {Checkpoints} from "../lib/openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC165} from "../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

contract JudgeTokenTest is Test {
    JudgeToken public judgeToken;
    address public owner;
    address public zeroAddress;
    uint256 pKey = 0x450802246;
    uint256 pKey2 = 0xF333BB;
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
    error ERC20InsufficientAllowance(
        address spender,
        uint256 allowance,
        uint256 needed
    );
    error ERC20InsufficientBalance(
        address sender,
        uint256 balance,
        uint256 needed
    );
    error AccessControlBadConfirmation();
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);

    function setUp() public {
        owner = address(this);
        zeroAddress = address(0);
        user1 = vm.addr(pKey);
        user2 = makeAddr("user2");
        user3 = vm.addr(pKey2);
        judgeToken = new JudgeToken(initialSupply);
    }

    function testName() public {
        assertEq("JudgeToken", judgeToken.name());
    }

    function testSymbol() public {
        assertEq("JUDGE", judgeToken.symbol());
    }

    function testDecimals() public {
        assertEq(decimals, judgeToken.decimals());
    }

    function testCap() public {
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

    function testTotalSupply() public {
        uint256 mintAmount = 67_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintAmount);
        uint256 expectedTotalSupply = mintAmount + initialSupply;
        assertEq(expectedTotalSupply, judgeToken.totalSupply());
    }

    function testDeployerIsOwner() public {
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        bytes32 defaultAdmin = judgeToken.DEFAULT_ADMIN_ROLE();
        assertTrue(judgeToken.hasRole(defaultAdmin, owner));
        assertTrue(judgeToken.hasRole(minterRole, owner));
    }

    function testMint() public {
        uint256 mintAmount = 10_000 * 10 ** uint256(decimals);
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        judgeToken.mint(user1, mintAmount);
        assertEq(judgeToken.balanceOf(user1), mintAmount);
        assertEq(
            judgeToken.totalSupply(),
            judgeToken.balanceOf(user1) + judgeToken.balanceOf(owner)
        );

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
            abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0))
        );
        judgeToken.mint(zeroAddress, mintAmount);
    }

    function testBurn() public {
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 burnAmount = 10_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintAmount);
        vm.prank(user1);
        judgeToken.burn(burnAmount);
        assertEq(mintAmount - burnAmount, judgeToken.balanceOf(user1));

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InvalidSender.selector, address(0))
        );
        vm.prank(zeroAddress);
        judgeToken.burn(burnAmount);
    }

    function testBurnFrom() public {
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

    function testBalanceOf() public {
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        assertEq(judgeToken.balanceOf(user2), 0);
        judgeToken.mint(user2, mintAmount);
        assertEq(judgeToken.balanceOf(user2), mintAmount);
    }

    function testTransfer() public {
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
            abi.encodeWithSelector(ERC20InvalidSender.selector, address(0))
        );
        vm.prank(zeroAddress);
        judgeToken.transfer(user1, amount);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(user2);
        judgeToken.transfer(zeroAddress, amount);
    }

    function testTransferFrom() public {
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

    function testAllowance() public {
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 allowance = 30_000 * 10 ** uint256(decimals);
        judgeToken.mint(user2, mintAmount);

        vm.prank(user2);
        judgeToken.approve(user1, allowance);

        assertEq(judgeToken.allowance(user2, user1), allowance);
    }

    function testApprove() public {
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        uint256 allowance = 30_000 * 10 ** uint256(decimals);
        judgeToken.mint(user2, mintAmount);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InvalidSpender.selector, address(0))
        );
        vm.prank(user2);
        judgeToken.approve(zeroAddress, allowance);
    }

    function testGrantRole() public {
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

    function testHasRole() public {
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        assertFalse(judgeToken.hasRole(minterRole, user1));
        judgeToken.grantRole(minterRole, user1);
        assertTrue(judgeToken.hasRole(minterRole, user1));
    }

    function testGetRoleAdmin() public {
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        bytes32 defaultAdmin = judgeToken.DEFAULT_ADMIN_ROLE();
        assertEq(judgeToken.getRoleAdmin(minterRole), defaultAdmin);
    }

    function testRevokeRole() public {
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

    function testRenounceRole() public {
        bytes32 minterRole = judgeToken.MINTER_ROLE();
        judgeToken.grantRole(minterRole, user2);
        assertTrue(judgeToken.hasRole(minterRole, user2));

        vm.prank(user2);
        judgeToken.renounceRole(minterRole, user2);
        assertFalse(judgeToken.hasRole(minterRole, user2));

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlBadConfirmation.selector)
        );
        vm.prank(user2);
        judgeToken.renounceRole(minterRole, user1);
    }

    function testSupportsInterface() public {
        assertTrue(judgeToken.supportsInterface(type(IERC165).interfaceId));
        assertTrue(
            judgeToken.supportsInterface(type(IAccessControl).interfaceId)
        );
    }

    function testDelegate() public {
        judgeToken.delegate(user1);
        assertEq(judgeToken.getVotes(owner), 0);
        assertEq(judgeToken.balanceOf(owner), initialSupply);
        assertEq(judgeToken.getVotes(user1), initialSupply);
    }

    function testDelegates() public {
        judgeToken.delegate(user1);
        assertEq(judgeToken.delegates(owner), user1);
    }

    function testGetVotes() public {
        assertEq(judgeToken.getVotes(owner), 0);
        judgeToken.delegate(user1);
        assertEq(judgeToken.getVotes(owner), 0);
        assertEq(judgeToken.getVotes(user1), initialSupply);
    }

    function testGetPastVotes() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        judgeToken.delegate(owner);
        assertEq(judgeToken.getVotes(owner), initialSupply);
        uint256 timePoint = block.number;

        for (uint i; i < 10; i++) {
            vm.roll(block.number + 1);
        }
        judgeToken.transfer(user1, amount);
        assertEq(judgeToken.getVotes(owner), initialSupply - amount);
        assertEq(judgeToken.getPastVotes(owner, timePoint), initialSupply);
        assertEq(judgeToken.getPastVotes(user1, timePoint), 0);
    }

    function testGetPastTotalSupply() public {
        uint256 timePoint1 = block.number;
        uint256 amount = 100_500 * 10 ** uint256(decimals);
        for (uint i; i < 10; i++) {
            vm.roll(block.number + 1);
        }
        judgeToken.mint(user2, amount);
        assertEq(judgeToken.getPastTotalSupply(timePoint1), initialSupply);
        assertEq(judgeToken.getTotalSupply(), initialSupply + amount);
    }

    function testNumCheckpoints() public {
        uint256 amount = 100_000 * 10 ** uint256(decimals);
        judgeToken.delegate(owner);

        for (uint i; i < 5; i++) {
            vm.roll(block.number + 1);
        }
        judgeToken.transfer(user1, amount);

        for (uint i; i < 10; i++) {
            vm.roll(block.number + 1);
        }
        judgeToken.transfer(user2, amount);

        assertEq(judgeToken.numCheckpoints(owner), 3);
    }

    function testCheckPoints() public {
        uint256 amount = 10_000 * 10 ** uint256(decimals);
        uint256 amount2 = 100_500 * 10 ** uint256(decimals);
        assertEq(judgeToken.numCheckpoints(owner), 0);
        for (uint i; i < 10; i++) {
            vm.roll(block.number + 1);
        }
        judgeToken.delegate(owner);

        for (uint i; i < 10; i++) {
            vm.roll(block.number + 1);
        }
        judgeToken.transfer(user1, amount);

        for (uint i; i < 10; i++) {
            vm.roll(block.number + 1);
        }
        judgeToken.mint(owner, amount2);

        uint32 num = judgeToken.numCheckpoints(owner);

        for (uint32 i = 0; i < num; i++) {
            Checkpoints.Checkpoint208 memory ckpt = judgeToken.checkpoints(
                owner,
                i
            );
            console.log("Checkpoint", i);
            console.log("fromBlock", ckpt._key);
            console.log("Votes", ckpt._value);
        }

        Checkpoints.Checkpoint208 memory ckpt1 = judgeToken.checkpoints(
            owner,
            0
        );
        assertEq(ckpt1._value, initialSupply);
        Checkpoints.Checkpoint208 memory ckpt2 = judgeToken.checkpoints(
            owner,
            1
        );
        assertEq(ckpt2._value, initialSupply - amount);
        Checkpoints.Checkpoint208 memory ckpt3 = judgeToken.checkpoints(
            owner,
            2
        );
        assertEq(ckpt3._value, initialSupply - amount + amount2);
    }

    function getPermitDigest(
        string memory name,
        string memory version,
        address tokenAddress,
        uint256 chainId,
        address signer,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32) {
        bytes32 DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                tokenAddress
            )
        );

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            signer,
                            spender,
                            value,
                            nonce,
                            deadline
                        )
                    )
                )
            );
    }

    function testNonces() public {
        assertEq(judgeToken.nonces(user1), 0);
        uint256 value = 10_000 * 10 ** uint256(decimals);
        uint256 user1Nonce = judgeToken.nonces(user1);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = getPermitDigest(
            "JudgeToken",
            "1",
            address(judgeToken),
            block.chainid,
            user1,
            user2,
            value,
            user1Nonce,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pKey, digest);
        judgeToken.permit(user1, user2, value, deadline, v, r, s);
        assertEq(judgeToken.nonces(user1), 1);
    }

    function testPermit() public {
        uint256 mintValue = 150_000 * 10 ** uint256(decimals);
        uint256 value = 10_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintValue);
        uint256 nonce = judgeToken.nonces(user1);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = getPermitDigest(
            "JudgeToken",
            "1",
            address(judgeToken),
            block.chainid,
            user1,
            user2,
            value,
            nonce,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pKey, digest);
        judgeToken.permit(user1, user2, value, deadline, v, r, s);
        assertEq(judgeToken.allowance(user1, user2), value);

        vm.prank(user2);
        judgeToken.transferFrom(user1, user2, value);
        assertEq(judgeToken.allowance(user1, user2), 0);
        assertEq(judgeToken.balanceOf(user2), value);
        assertEq(judgeToken.balanceOf(user1), mintValue - value);
    }

    function testRevertForExpiredSig() public {
        uint256 mintValue = 150_000 * 10 ** uint256(decimals);
        uint256 value = 10_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintValue);
        uint256 nonce = judgeToken.nonces(user1);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = getPermitDigest(
            "JudgeToken",
            "1",
            address(judgeToken),
            block.chainid,
            user1,
            user2,
            value,
            nonce,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pKey, digest);
        vm.warp(deadline + 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(ERC2612ExpiredSignature.selector, deadline)
        );
        judgeToken.permit(user1, user2, value, deadline, v, r, s);
    }

    function testInvalidSignerForPermit() public {
        uint256 mintValue = 150_000 * 10 ** uint256(decimals);
        uint256 value = 10_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintValue);
        uint256 nonce = judgeToken.nonces(user1);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = getPermitDigest(
            "JudgeToken",
            "1",
            address(judgeToken),
            block.chainid,
            user1,
            user2,
            value,
            nonce,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pKey2, digest);
        vm.expectRevert(
            abi.encodeWithSelector(ERC2612InvalidSigner.selector, user3, user1)
        );
        judgeToken.permit(user1, user2, value, deadline, v, r, s);
    }

    function testDelegateBySig() public {
        address delegatee = user2;
        uint256 nonce = judgeToken.nonces(user1); // should be 0
        uint256 expiry = block.timestamp + 1 hours;
        uint256 mintAmount = 100_000 * 10 ** uint256(decimals);
        judgeToken.mint(user1, mintAmount);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Delegation(address delegatee,uint256 nonce,uint256 expiry)"
                ),
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 domainSeparator = judgeToken.DOMAIN_SEPARATOR();

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pKey, digest);

        vm.prank(user3); // any address, not user1
        judgeToken.delegateBySig(delegatee, nonce, expiry, v, r, s);

        assertEq(judgeToken.delegates(user1), delegatee);
        console.log("The delegatee is ", judgeToken.delegates(user1));
        console.log("user2 is ", user2);
        assertEq(judgeToken.getVotes(user2), mintAmount);
        console.log("user2 votes is ", judgeToken.getVotes(user2));
    }
}
