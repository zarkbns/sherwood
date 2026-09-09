// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {ERC721} from "../src/ERC721.sol";
import {MockERC721Receiver, MockWrongReceiver} from "./Mocks.sol";

contract TestableNote is ERC721 {
    constructor() ERC721("Sherwood Protection Note", "SPN") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract ERC721Test is TestBase {
    TestableNote internal note;
    uint256 internal tokenId = 1;

    function setUp() public {
        note = new TestableNote();
        note.mint(vmMakeAddr("alice"), tokenId);
    }

    function test_Mint_SetsOwnerAndBalance() public {
        address alice = vmMakeAddr("alice");
        assertEq(note.ownerOf(tokenId), alice, "alice should own token");
        assertEq(note.balanceOf(alice), 1, "balance should be 1");
    }

    function test_OwnerOf_RevertsOnNonexistent() public {
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721NonexistentToken.selector, uint256(999)));
        note.ownerOf(999);
    }

    function test_BalanceOf_RevertsOnZeroAddress() public {
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721InvalidOwner.selector, address(0)));
        note.balanceOf(address(0));
    }

    function test_TransferFrom_ByOwner() public {
        address alice = vmMakeAddr("alice");
        address bob = vmMakeAddr("bob");
        vmPrank(alice);
        note.transferFrom(alice, bob, tokenId);
        assertEq(note.ownerOf(tokenId), bob, "ownership not moved");
        assertEq(note.balanceOf(alice), 0, "sender balance should drop");
        assertEq(note.balanceOf(bob), 1, "receiver balance should rise");
    }

    function test_TransferFrom_ByApproved() public {
        address alice = vmMakeAddr("alice");
        address bob = vmMakeAddr("bob");
        vmPrank(alice);
        note.approve(bob, tokenId);
        vmPrank(bob);
        note.transferFrom(alice, bob, tokenId);
        assertEq(note.ownerOf(tokenId), bob, "approved should be able to move");
    }

    function test_TransferFrom_ByOperator() public {
        address alice = vmMakeAddr("alice");
        address operator = vmMakeAddr("operator");
        vmPrank(alice);
        note.setApprovalForAll(operator, true);
        vmPrank(operator);
        note.transferFrom(alice, operator, tokenId);
        assertEq(note.ownerOf(tokenId), operator, "operator should be able to move");
    }

    function test_TransferFrom_ClearsApproval() public {
        address alice = vmMakeAddr("alice");
        address bob = vmMakeAddr("bob");
        vmPrank(alice);
        note.approve(bob, tokenId);
        vmPrank(alice);
        note.transferFrom(alice, bob, tokenId);
        assertEq(note.getApproved(tokenId), address(0), "approval should clear on transfer");
    }

    function test_TransferFrom_RevertsWhenNotAuthorized() public {
        address alice = vmMakeAddr("alice");
        address attacker = vmMakeAddr("attacker");
        vmPrank(attacker);
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721Unauthorized.selector, attacker, tokenId));
        note.transferFrom(alice, attacker, tokenId);
    }

    function test_TransferFrom_RevertsOnZeroReceiver() public {
        address alice = vmMakeAddr("alice");
        vmPrank(alice);
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721InvalidReceiver.selector, address(0)));
        note.transferFrom(alice, address(0), tokenId);
    }

    function test_TransferFrom_RevertsOnWrongFrom() public {
        address alice = vmMakeAddr("alice");
        vmPrank(alice);
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721Unauthorized.selector, alice, tokenId));
        note.transferFrom(vmMakeAddr("someone else"), alice, tokenId);
    }

    function test_Approve_SetsSpender() public {
        address alice = vmMakeAddr("alice");
        address bob = vmMakeAddr("bob");
        vmPrank(alice);
        note.approve(bob, tokenId);
        assertEq(note.getApproved(tokenId), bob, "approval not set");
    }

    function test_Approve_RevertsWhenNotOwner() public {
        address attacker = vmMakeAddr("attacker");
        vmPrank(attacker);
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721Unauthorized.selector, attacker, tokenId));
        note.approve(attacker, tokenId);
    }

    function test_SetApprovalForAll_RoundTrip() public {
        address alice = vmMakeAddr("alice");
        address operator = vmMakeAddr("operator");
        vmPrank(alice);
        note.setApprovalForAll(operator, true);
        assertTrue(note.isApprovedForAll(alice, operator), "operator should be approved");
        vmPrank(alice);
        note.setApprovalForAll(operator, false);
        assertFalse(note.isApprovedForAll(alice, operator), "operator approval should clear");
    }

    function test_SafeTransferFrom_ToReceiver_Accepts() public {
        address alice = vmMakeAddr("alice");
        MockERC721Receiver receiver = new MockERC721Receiver();
        vmPrank(alice);
        note.safeTransferFrom(alice, address(receiver), tokenId);
        assertEq(note.ownerOf(tokenId), address(receiver), "receiver should own token");
    }

    function test_SafeTransferFrom_ToWrongReceiver_Reverts() public {
        address alice = vmMakeAddr("alice");
        MockWrongReceiver receiver = new MockWrongReceiver();
        vmPrank(alice);
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721InvalidReceiver.selector, address(receiver)));
        note.safeTransferFrom(alice, address(receiver), tokenId);
        assertEq(note.ownerOf(tokenId), alice, "token should stay with sender on failed safe transfer");
    }

    function test_SafeTransferFrom_ToEOA_SkipsHook() public {
        address alice = vmMakeAddr("alice");
        address bob = vmMakeAddr("bob");
        vmPrank(alice);
        note.safeTransferFrom(alice, bob, tokenId);
        assertEq(note.ownerOf(tokenId), bob, "EOA transfer should succeed without hook");
    }

    function test_Mint_RevertsOnZeroAddress() public {
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721InvalidReceiver.selector, address(0)));
        note.mint(address(0), 2);
    }

    function test_Mint_RevertsOnDuplicateId() public {
        address alice = vmMakeAddr("alice");
        vmExpectRevertData(abi.encodeWithSelector(ERC721.ERC721InvalidReceiver.selector, alice));
        note.mint(alice, tokenId);
    }
}
