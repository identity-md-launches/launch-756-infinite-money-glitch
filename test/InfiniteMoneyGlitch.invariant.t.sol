// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {InfiniteMoneyGlitch} from "../src/InfiniteMoneyGlitch.sol";

/// @dev All minted tokens remain among these four actors, allowing a complete balance sum.
contract TokenHandler is Test {
    InfiniteMoneyGlitch public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA11), address(0xD00D)];

    constructor(InfiniteMoneyGlitch token_) {
        token = token_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        amount = bound(amount, 0, beforeFrom);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? beforeFrom : beforeFrom - amount);
        assertEq(token.balanceOf(to), from == to ? beforeTo : beforeTo + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeOwner = token.balanceOf(owner);
        uint256 beforeTo = token.balanceOf(to);
        uint256 approved = token.allowance(owner, spender);
        uint256 limit = beforeOwner < approved ? beforeOwner : approved;
        amount = bound(amount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.balanceOf(owner), owner == to ? beforeOwner : beforeOwner - amount);
        assertEq(token.balanceOf(to), owner == to ? beforeTo : beforeTo + amount);
        assertEq(token.allowance(owner, spender), approved == type(uint256).max ? approved : approved - amount);
    }
}

contract InfiniteMoneyGlitchInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    InfiniteMoneyGlitch private token;
    TokenHandler private handler;

    function setUp() public {
        token = new InfiniteMoneyGlitch();
        handler = new TokenHandler(token);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), SUPPLY / 4);
        }
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
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
}
