// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ScriptBase
/// @notice Cheatcode shims shared by the deploy and demo scripts: no forge-std,
///         the build stays dependency-free.
abstract contract ScriptBase {
    address constant VM_ADDRESS = address(uint160(uint256(uint160(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D))));

    function vmStartBroadcast() internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("startBroadcast()"));
        require(ok, "startBroadcast failed");
    }

    function vmStopBroadcast() internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("stopBroadcast()"));
        require(ok, "stopBroadcast failed");
    }

    /// @notice Script log. This forge build rejects both `log(string)` and
    ///         `emit_log(string)` as cheatcodes, so logs go out as a plain event and show
    ///         up in `forge script -vvvv` as `emit Log(message: "...")`.
    event Log(string message);

    function vmLog(string memory message) internal {
        emit Log(message);
    }

    function vmToString(uint256 value) internal returns (string memory) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("toString(uint256)", value));
        require(ok, "toString failed");
        return abi.decode(data, (string));
    }

    function vmToString(address account) internal returns (string memory) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("toString(address)", account));
        require(ok, "toString failed");
        return abi.decode(data, (string));
    }

    function vmToString(int256 value) internal returns (string memory) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("toString(int256)", value));
        require(ok, "toString failed");
        return abi.decode(data, (string));
    }

    function vmEnvString(string memory key) internal returns (string memory) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("envString(string)", key));
        require(ok, "envString failed");
        return abi.decode(data, (string));
    }

    function vmEnvOr(string memory key, string memory fallbackValue) internal returns (string memory) {
        (bool ok, bytes memory data) =
            VM_ADDRESS.call(abi.encodeWithSignature("envOr(string,string)", key, fallbackValue));
        require(ok, "envOr failed");
        return abi.decode(data, (string));
    }

    function vmEnvUint(string memory key, uint256 fallbackValue) internal returns (uint256) {
        (bool ok, bytes memory data) =
            VM_ADDRESS.call(abi.encodeWithSignature("envOr(string,uint256)", key, fallbackValue));
        require(ok, "envOr failed");
        return abi.decode(data, (uint256));
    }

    /// @notice Required uint env var: reverts when unset instead of silently applying a
    ///         fallback. For knobs where the value chosen IS the thing being demonstrated.
    function vmEnvUintRequired(string memory key) internal returns (uint256) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("envUint(string)", key));
        require(ok, "envUint failed");
        return abi.decode(data, (uint256));
    }

    /// @notice Address `forge script` signs from for this private key.
    function vmAddr(uint256 privateKey) internal returns (address) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("addr(uint256)", privateKey));
        require(ok, "addr failed");
        return abi.decode(data, (address));
    }

    function vmParseAddress(string memory value) internal returns (address) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("parseAddress(string)", value));
        require(ok, "parseAddress failed");
        return abi.decode(data, (address));
    }

    function vmEnvAddress(string memory key) internal returns (address) {
        return vmParseAddress(vmEnvString(key));
    }

    function vmEnvAddressOpt(string memory key) internal returns (address) {
        string memory value = vmEnvOr(key, "");
        if (bytes(value).length == 0) return address(0);
        return vmParseAddress(value);
    }
}
