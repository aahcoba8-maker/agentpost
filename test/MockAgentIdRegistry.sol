// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Test double for the Agent ID registry: an address "holds an Agent ID"
///         iff it was registered with `addHolder`. Mirrors the real registry's
///         balanceOf / handleOf surface used by AgentPost.
contract MockAgentIdRegistry {
    mapping(address => string) private _handles;

    function addHolder(address account, string calldata handle) external {
        _handles[account] = handle;
    }

    function removeHolder(address account) external {
        delete _handles[account];
    }

    function balanceOf(address owner) external view returns (uint256) {
        return bytes(_handles[owner]).length > 0 ? 1 : 0;
    }

    function handleOf(address owner) external view returns (string memory) {
        return _handles[owner];
    }
}
