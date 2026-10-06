// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {InfiniteMoneyGlitch} from "../src/InfiniteMoneyGlitch.sol";

/// @dev All minted tokens remain among these four actors, allowing a complete balance sum.
contract TokenHandler is Test {
    InfiniteMoneyGlitch public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA11), address(0xD00D)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(InfiniteMoneyGlitch token_) {
        token = token_;
        // Derived from the specified supply and setup distribution, never from token getters.
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = 1_000_000_000 ether / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
        assertEq(token.balanceOf(from), from == to ? beforeFrom : beforeFrom - amount);
        assertEq(token.balanceOf(to), from == to ? beforeTo : beforeTo + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    /// @dev Explicitly reach revocation, dust, full-supply and both uint256 allowance boundaries.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint8 mode) external {
        uint256[5] memory amounts = [uint256(0), 1, 1_000_000_000 ether, type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amounts[mode % 5]);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeOwner = token.balanceOf(owner);
        uint256 beforeTo = token.balanceOf(to);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 held = expectedBalance[owner];
        uint256 limit = held < approved ? held : approved;
        amount = bound(amount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordTransfer(owner, to, amount);
        if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        assertEq(token.balanceOf(owner), owner == to ? beforeOwner : beforeOwner - amount);
        assertEq(token.balanceOf(to), owner == to ? beforeTo : beforeTo + amount);
        assertEq(token.allowance(owner, spender), approved == type(uint256).max ? approved : approved - amount);
    }

    function rejectOverdraw(uint256 ownerSeed, uint256 toSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[owner];
        amount = bound(amount, held + 1, type(uint256).max);
        address spender = actors[(ownerSeed % actors.length + 1) % actors.length];
        if (delegated) _approve(owner, spender, amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, to, amount);
        else token.transfer(to, amount);
        // The independent ledger remains unchanged on rejection, including the approval above.
    }

    function rejectOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 approval) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 held = expectedBalance[owner];
        approval = bound(approval, 0, held == 0 ? 0 : held - 1);
        _approve(owner, spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, approval + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, approval + 1);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        if (delegated) _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    /// @dev Every holder can send its whole balance and get it back, even after rejected operations.
    function roundTripFullBalance(uint256 fromSeed) external {
        uint256 index = fromSeed % actors.length;
        address from = actors[index];
        address to = actors[(index + 1) % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
        // Net-zero movement: no ghost update. Allowances must also remain unchanged.
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract InfiniteMoneyGlitchInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    InfiniteMoneyGlitch private token;
    TokenHandler private handler;

    function setUp() public {
        token = new InfiniteMoneyGlitch();
        handler = new TokenHandler(token);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.actors(i), SUPPLY / 4));
            // Make nonzero delegated spending reachable from the first random call.
            handler.approve(i, (i + 1) % 4, SUPPLY / 4);
        }
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.approveBoundary.selector;
        selectors[4] = TokenHandler.rejectOverdraw.selector;
        selectors[5] = TokenHandler.rejectOverspend.selector;
        selectors[6] = TokenHandler.rejectZeroRecipient.selector;
        selectors[7] = TokenHandler.rejectZeroSpender.selector;
        selectors[8] = TokenHandler.roundTripFullBalance.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndAllBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// @dev Check each account and each permission, including uninvolved actors after a call.
    /// Conservation alone would miss theft between actors or corruption of somebody else's approval.
    function invariant_balancesAndAllowancesMatchAuthorizedCalls() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "unauthorized balance change");
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            assertEq(token.allowance(owner, address(this)), 0, "deployer gained spending authority");
            assertEq(token.allowance(owner, address(handler)), 0, "handler gained spending authority");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "incorrect allowance"
                );
            }
        }
    }

    /// @dev After every campaign, every remaining token must still be transferable by its holder.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            handler.transfer(i, 0, handler.expectedBalance(handler.actors(i)));
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariant_supplyAndAllBalancesAreConserved();
        invariant_balancesAndAllowancesMatchAuthorizedCalls();
    }
}
