// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title TestBase
/// @notice Minimal, dependency-free replacement for forge-std's Test, calling the
///         standard cheatcode contract directly. The project vendors everything so
///         `forge build` never needs network access.
abstract contract TestBase {
    address constant VM_ADDRESS = address(uint160(uint256(uint160(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D))));

    event Log(string message);
    event LogUint(string message, uint256 value);
    event LogAddress(string message, address value);

    function vmWarp(uint256 ts) internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("warp(uint256)", ts));
        require(ok, "warp failed");
    }

    function vmRoll(uint256 blockNumber) internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("roll(uint256)", blockNumber));
        require(ok, "roll failed");
    }

    function vmPrank(address caller) internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("prank(address)", caller));
        require(ok, "prank failed");
    }

    function vmStartPrank(address caller) internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("startPrank(address)", caller));
        require(ok, "startPrank failed");
    }

    function vmStopPrank() internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("stopPrank()"));
        require(ok, "stopPrank failed");
    }

    function vmExpectRevert(bytes4 revertData) internal {
        vmExpectRevertData(abi.encodePacked(revertData));
    }

    function vmExpectRevertData(bytes memory revertData) internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("expectRevert(bytes)", revertData));
        require(ok, "expectRevert failed");
    }

    function vmExpectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) internal {
        (bool ok, ) = VM_ADDRESS.call(
            abi.encodeWithSignature("expectEmit(bool,bool,bool,bool)", checkTopic1, checkTopic2, checkTopic3, checkData)
        );
        require(ok, "expectEmit failed");
    }

    function vmExpectRevert() internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("expectRevert()"));
        require(ok, "expectRevert failed");
    }

    function vmLabel(address account, string memory label) internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("label(address,string)", account, label));
        require(ok, "label failed");
    }

    function vmAddr(uint256 n) internal returns (address) {
        (bool ok, bytes memory data) =
            VM_ADDRESS.call(abi.encodeWithSignature("addr(uint256)", n));
        require(ok, "addr failed");
        return abi.decode(data, (address));
    }

    function vmMakeAddr(string memory label) internal returns (address) {
        // Deterministic per label, same scheme as forge-std
        uint256 privateKey = uint256(keccak256(abi.encodePacked(label)));
        return vmAddr(privateKey);
    }

    function vmDeal(address account, uint256 amount) internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("deal(address,uint256)", account, amount));
        require(ok, "deal failed");
    }

    function assertTrue(bool condition, string memory message) internal {
        if (!condition) revert AssertError(message);
    }

    function assertFalse(bool condition, string memory message) internal {
        assertTrue(!condition, message);
    }

    function assertEq(uint256 a, uint256 b, string memory message) internal {
        assertTrue(a == b, message);
    }

    function assertEq(address a, address b, string memory message) internal {
        assertTrue(a == b, message);
    }

    function assertEq(string memory a, string memory b, string memory message) internal {
        assertTrue(keccak256(bytes(a)) == keccak256(bytes(b)), message);
    }

    function assertGt(uint256 a, uint256 b, string memory message) internal {
        assertTrue(a > b, message);
    }

    function assertGe(uint256 a, uint256 b, string memory message) internal {
        assertTrue(a >= b, message);
    }

    function assertLt(uint256 a, uint256 b, string memory message) internal {
        assertTrue(a < b, message);
    }

    function assertLe(uint256 a, uint256 b, string memory message) internal {
        assertTrue(a <= b, message);
    }

    error AssertError(string message);
}
