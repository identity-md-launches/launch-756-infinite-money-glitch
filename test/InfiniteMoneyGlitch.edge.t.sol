// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {InfiniteMoneyGlitch} from "src/InfiniteMoneyGlitch.sol";

/// @dev Complements the original suite with permission isolation, replay and rollback boundaries.
/// forge-config: default.fuzz.runs = 1000
contract InfiniteMoneyGlitchEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    InfiniteMoneyGlitch private token;

    function setUp() public {
        token = new InfiniteMoneyGlitch();
    }

    function test_oneWeiRoundTrip() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxUintTransferCannotOverflowBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplyDelegatedTransferCannotBeReplayedAfterRefill() public {
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);

        // Replenishing a balance must not replenish the permission that has already been spent.
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        uint256 approval = type(uint256).max - 1;
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), approval - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), approval - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceCanBeReplacedByFiniteLimit() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertTrue(token.approve(SPENDER, 1));
        assertEq(token.allowance(address(this), SPENDER), 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_infiniteAllowanceDoesNotBypassBalanceAndSurvivesFailure() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferPreservesExistingFiniteApproval() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 0));
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function test_zeroValueStillRejectsZeroSpenderAndDelegatedRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertTrue(token.approve(SPENDER, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), 7);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroSenderCannotTransferOrApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(0), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedOverdrawPreservesUsableAllowance(uint256 held, uint256 amount, uint256 approval) public {
        held = bound(held, 1, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        approval = bound(approval, amount, type(uint256).max);
        assertTrue(token.transfer(ALICE, held));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approval));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);

        // The same approval must remain usable after the failure.
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, held));
        assertEq(token.allowance(ALICE, SPENDER), approval == type(uint256).max ? approval : approval - held);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), held);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedOverspendPreservesUsableAllowance(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY - 1);
        amount = bound(amount, approval + 1, SUPPLY);
        assertTrue(token.approve(SPENDER, approval));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approval, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, approval));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - approval);
        assertEq(token.balanceOf(ALICE), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalsAreIsolatedByOwnerAndSpender(
        uint256 held,
        uint256 firstApproval,
        uint256 secondApproval,
        uint256 amount
    ) public {
        held = bound(held, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, held));
        assertTrue(token.approve(SPENDER, firstApproval));
        assertTrue(token.approve(BOB, secondApproval));
        vm.startPrank(ALICE);
        assertTrue(token.approve(SPENDER, secondApproval));
        assertTrue(token.approve(BOB, firstApproval));
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), held, "approvals moved tokens");
        assertEq(token.balanceOf(address(this)), SUPPLY - held);

        uint256 limit = SUPPLY - held < firstApproval ? SUPPLY - held : firstApproval;
        amount = bound(amount, 0, limit);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(
            token.allowance(address(this), SPENDER),
            firstApproval == type(uint256).max ? firstApproval : firstApproval - amount
        );
        assertEq(token.allowance(address(this), BOB), secondApproval);
        assertEq(token.allowance(ALICE, SPENDER), secondApproval);
        assertEq(token.allowance(ALICE, BOB), firstApproval);
        assertEq(token.allowance(SPENDER, address(this)), 0);
        assertEq(token.balanceOf(ALICE), held + amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - held - amount);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);

        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(ALICE, SPENDER), secondApproval, "revocation affected another owner");
        assertEq(token.allowance(address(this), BOB), secondApproval, "revocation affected another spender");
        assertEq(token.allowance(ALICE, BOB), firstApproval);
    }
}
