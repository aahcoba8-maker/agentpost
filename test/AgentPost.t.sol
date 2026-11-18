// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentPost} from "../contracts/AgentPost.sol";
import {MockAgentIdRegistry} from "./MockAgentIdRegistry.sol";

/// @dev Minimal cheatcode interface (avoids a forge-std dependency).
interface Vm {
    function prank(address msgSender) external;
    function expectRevert() external;
    function expectRevert(bytes4 revertData) external;
    function expectRevert(bytes calldata revertData) external;
}

/// @dev Tiny assertion helper — a failed require fails the forge test.
contract Assert {
    function assertTrue(bool c, string memory m) internal pure {
        require(c, m);
    }

    function assertEq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function assertEq(address a, address b, string memory m) internal pure {
        require(a == b, m);
    }

    function assertEq(string memory a, string memory b, string memory m) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), m);
    }
}

contract AgentPostTest is Assert {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    MockAgentIdRegistry internal registry;
    AgentPost internal post;

    address internal alice = address(0xA11CE); // holder "alice"
    address internal bob = address(0xB0B); // holder "bob"
    address internal carol = address(0xCA401); // NOT a holder

    function setUp() public {
        registry = new MockAgentIdRegistry();
        registry.addHolder(alice, "alice");
        registry.addHolder(bob, "bob");
        post = new AgentPost(address(registry));
    }

    // --- holder checks -------------------------------------------------------

    function testIsAgentIdHolder() public view {
        assertTrue(post.isAgentIdHolder(alice), "alice should be a holder");
        assertTrue(post.isAgentIdHolder(bob), "bob should be a holder");
        assertTrue(!post.isAgentIdHolder(carol), "carol should NOT be a holder");
    }

    function testHandleOfPassthrough() public view {
        assertEq(post.handleOf(alice), "alice", "handle mismatch");
    }

    // --- happy path ----------------------------------------------------------

    function testHolderToHolderSend() public {
        vm.prank(alice);
        post.sendMessage(bob, "hello bob");

        assertEq(post.inboxCount(bob), 1, "bob inbox should have 1 message");
        assertEq(post.inboxCount(alice), 0, "alice inbox should be empty");

        (address from, uint64 ts, string memory text) = post.getMessage(bob, 0);
        assertEq(from, alice, "sender mismatch");
        assertTrue(ts > 0, "timestamp should be set");
        assertEq(text, "hello bob", "text mismatch");
    }

    function testMultipleMessagesKeepOrder() public {
        vm.prank(alice);
        post.sendMessage(bob, "first");
        vm.prank(alice);
        post.sendMessage(bob, "second");

        assertEq(post.inboxCount(bob), 2, "bob should have 2 messages");
        (, , string memory t0) = post.getMessage(bob, 0);
        (, , string memory t1) = post.getMessage(bob, 1);
        assertEq(t0, "first", "order broken at 0");
        assertEq(t1, "second", "order broken at 1");
    }

    function testSendToSelfAllowed() public {
        vm.prank(alice);
        post.sendMessage(alice, "note to self");
        assertEq(post.inboxCount(alice), 1, "self-send should land in own inbox");
    }

    // --- gating --------------------------------------------------------------

    function testNonHolderSenderReverts() public {
        vm.prank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(AgentPost.NotAgentIdHolder.selector, carol)
        );
        post.sendMessage(bob, "hi");
    }

    function testNonHolderRecipientReverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AgentPost.NotAgentIdHolder.selector, carol)
        );
        post.sendMessage(carol, "hi");
    }

    function testHolderLosingIdCanNoLongerSend() public {
        registry.removeHolder(alice);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AgentPost.NotAgentIdHolder.selector, alice)
        );
        post.sendMessage(bob, "hi");
    }

    // --- length cap ----------------------------------------------------------

    function testEmptyMessageReverts() public {
        vm.prank(alice);
        vm.expectRevert(AgentPost.EmptyMessage.selector);
        post.sendMessage(bob, "");
    }

    function testExactlyMaxLengthOk() public {
        string memory maxText = _repeat("a", 280);
        vm.prank(alice);
        post.sendMessage(bob, maxText);
        assertEq(post.inboxCount(bob), 1, "280-byte message should be accepted");
    }

    function testOverMaxLengthReverts() public {
        string memory tooLong = _repeat("a", 281);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AgentPost.MessageTooLong.selector, 281, 280)
        );
        post.sendMessage(bob, tooLong);
    }

    // --- reads / pagination ----------------------------------------------------

    function testGetMessageOutOfRangeReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(AgentPost.IndexOutOfRange.selector, 0, 0)
        );
        post.getMessage(bob, 0);
    }

    function testPagination() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            post.sendMessage(bob, _num(i));
        }

        // First page
        (address[] memory froms, uint64[] memory tss, string[] memory texts) =
            post.getInbox(bob, 0, 2);
        assertEq(froms.length, 2, "page 1 size");
        assertEq(texts[0], "0", "page 1 item 0");
        assertEq(texts[1], "1", "page 1 item 1");
        assertEq(froms[0], alice, "page 1 sender");
        assertTrue(tss[0] > 0, "page 1 timestamp");

        // Middle page
        (, , string[] memory mid) = post.getInbox(bob, 2, 2);
        assertEq(mid.length, 2, "page 2 size");
        assertEq(mid[0], "2", "page 2 item 0");
        assertEq(mid[1], "3", "page 2 item 1");

        // Last partial page
        (, , string[] memory last) = post.getInbox(bob, 4, 2);
        assertEq(last.length, 1, "last page should clamp to 1");
        assertEq(last[0], "4", "last page item");

        // Offset beyond the end returns empty, limit 0 returns empty
        (, , string[] memory beyond) = post.getInbox(bob, 99, 10);
        assertEq(beyond.length, 0, "offset beyond end should be empty");
        (, , string[] memory zeroLimit) = post.getInbox(bob, 0, 0);
        assertEq(zeroLimit.length, 0, "limit 0 should be empty");
    }

    // --- helpers ---------------------------------------------------------------

    function _repeat(string memory s, uint256 n) internal pure returns (string memory) {
        bytes memory out = new bytes(n * bytes(s).length);
        bytes memory sb = bytes(s);
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < sb.length; j++) {
                out[i * sb.length + j] = sb[j];
            }
        }
        return string(out);
    }

    function _num(uint256 i) internal pure returns (string memory) {
        return string(abi.encodePacked(uint8(48 + i))); // "0".."4"
    }
}
