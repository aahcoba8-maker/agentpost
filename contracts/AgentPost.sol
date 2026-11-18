// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal interface of the Agent ID registry (SPACE ID Agent ID, ERC-721).
///         Deployed on BNB Smart Chain at 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F.
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function handleOf(address owner) external view returns (string memory);
}

/// @title AgentPost
/// @notice On-chain messaging between Agent ID holders on BNB Smart Chain.
///         Only wallets that hold an Agent ID can send or receive messages.
///         Messages are stored on-chain and are PUBLIC — anyone can read any inbox.
/// @dev Permission surface: NONE. This contract has no owner, no admin functions,
///      no fees, no pause, no upgrade path, and it never holds or moves user assets.
///      The Agent ID registry address is immutable and set once at deployment.
contract AgentPost {
    /// @notice The Agent ID registry used for holder checks (immutable).
    IAgentIdRegistry public immutable agentIdRegistry;

    /// @notice Maximum message size, in bytes (UTF-8 bytes of the string).
    uint256 public constant MAX_TEXT_BYTES = 280;

    struct Message {
        address from;
        uint64 timestamp;
        string text;
    }

    /// @dev inbox[recipient] = ordered list of messages received by `recipient`.
    mapping(address => Message[]) private _inboxes;

    event MessageSent(address indexed from, address indexed to, uint256 indexed index, uint64 timestamp);

    error NotAgentIdHolder(address account);
    error EmptyMessage();
    error MessageTooLong(uint256 length, uint256 maxLength);
    error IndexOutOfRange(uint256 index, uint256 count);

    constructor(address registry) {
        require(registry != address(0), "registry is zero address");
        agentIdRegistry = IAgentIdRegistry(registry);
    }

    /// @notice True if `account` currently holds an Agent ID.
    function isAgentIdHolder(address account) public view returns (bool) {
        return agentIdRegistry.balanceOf(account) > 0;
    }

    /// @notice The Agent ID handle (e.g. "tripur") of a holder, straight from the registry.
    function handleOf(address account) external view returns (string memory) {
        return agentIdRegistry.handleOf(account);
    }

    /// @notice Send a short on-chain message to another Agent ID holder.
    /// @param to   Recipient wallet — must hold an Agent ID.
    /// @param text Message text, 1..280 bytes. Stored on-chain; PUBLIC.
    function sendMessage(address to, string calldata text) external {
        if (!isAgentIdHolder(msg.sender)) revert NotAgentIdHolder(msg.sender);
        if (!isAgentIdHolder(to)) revert NotAgentIdHolder(to);
        uint256 len = bytes(text).length;
        if (len == 0) revert EmptyMessage();
        if (len > MAX_TEXT_BYTES) revert MessageTooLong(len, MAX_TEXT_BYTES);

        Message[] storage inbox = _inboxes[to];
        uint256 index = inbox.length;
        inbox.push(Message({from: msg.sender, timestamp: uint64(block.timestamp), text: text}));
        emit MessageSent(msg.sender, to, index, uint64(block.timestamp));
    }

    /// @notice Number of messages in `user`'s inbox.
    function inboxCount(address user) external view returns (uint256) {
        return _inboxes[user].length;
    }

    /// @notice Read a single message from `user`'s inbox by index (0 = oldest).
    function getMessage(address user, uint256 index)
        external
        view
        returns (address from, uint64 timestamp, string memory text)
    {
        Message[] storage inbox = _inboxes[user];
        if (index >= inbox.length) revert IndexOutOfRange(index, inbox.length);
        Message storage m = inbox[index];
        return (m.from, m.timestamp, m.text);
    }

    /// @notice Read a page of `user`'s inbox. Returns up to `limit` messages starting
    ///         at `offset` (0 = oldest). Safe for out-of-range offsets (returns empty).
    function getInbox(address user, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory froms, uint64[] memory timestamps, string[] memory texts)
    {
        Message[] storage inbox = _inboxes[user];
        uint256 count = inbox.length;
        if (offset >= count || limit == 0) {
            return (new address[](0), new uint64[](0), new string[](0));
        }
        uint256 end = offset + limit;
        if (end > count) end = count;
        uint256 n = end - offset;
        froms = new address[](n);
        timestamps = new uint64[](n);
        texts = new string[](n);
        for (uint256 i = 0; i < n; i++) {
            Message storage m = inbox[offset + i];
            froms[i] = m.from;
            timestamps[i] = m.timestamp;
            texts[i] = m.text;
        }
        return (froms, timestamps, texts);
    }
}
