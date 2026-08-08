// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PersonRegistry} from "../src/PersonRegistry.sol";
import {SeatLedger} from "../src/SeatLedger.sol";
import {QuorumAsset} from "../src/QuorumAsset.sol";

/// @notice The demo, encoded. Every scene in the submission video is asserted here first.
/// @dev Rehearsing on-camera is not a test strategy. If a scene cannot be made to pass in Solidity
///      it will not survive a live recording either.
contract ScenesTest is Test {
    PersonRegistry registry;
    SeatLedger ledger;
    QuorumAsset asset;

    uint32 constant MAX_PERSONS = 5;

    // Five people who take seats, one who arrives too late. P1 holds three wallets.
    address p1a = address(0x11);
    address p1b = address(0x12);
    address p1c = address(0x13);
    address p2 = address(0x20);
    address p3 = address(0x30);
    address p4 = address(0x40);
    address p5 = address(0x50);
    address p6 = address(0x60);

    function setUp() public {
        registry = new PersonRegistry(address(0xA11CE));
        ledger = new SeatLedger(MAX_PERSONS, 0); // standing cap — the demo pack
        asset = new QuorumAsset("Quorum Note", "QNOTE", registry, ledger, 10_000);
        ledger.setOperator(address(asset), true);

        // Three wallets, one human. This is the whole thesis in three lines of setup.
        registry.bind(p1a, keccak256("person-1"));
        registry.bind(p1b, keccak256("person-1"));
        registry.bind(p1c, keccak256("person-1"));
        registry.bind(p2, keccak256("person-2"));
        registry.bind(p3, keccak256("person-3"));
        registry.bind(p4, keccak256("person-4"));
        registry.bind(p5, keccak256("person-5"));
        registry.bind(p6, keccak256("person-6"));
    }

    function _fillToCapacity() internal {
        asset.issue(p1a, 100e18);
        asset.issue(p2, 100e18);
        asset.issue(p3, 100e18);
        asset.issue(p4, 100e18);
        asset.issue(p5, 100e18);
    }

    /// Scene 2 — the last seat fills and the offering reaches capacity.
    function test_scene2_capacityReached() public {
        _fillToCapacity();
        assertEq(ledger.activeSeats(), 5, "five persons seated");
        assertEq(ledger.headroom(), 0, "no seats left");
    }

    /// Scene 3 — the money shot. A recipient who is verified, domiciled and accredited is refused
    /// anyway, because the room is full. Every other system in the field would allow this.
    function test_scene3_eligibleRecipientRefusedOnCapacity() public {
        _fillToCapacity();

        // P6 is perfectly eligible: registered, known, nothing wrong with them.
        assertTrue(registry.isKnown(p6), "P6 is a fully registered person");

        (bool allowed, bytes32 reason,) = asset.preflight(address(0), p6, 10e18);
        assertFalse(allowed, "refused");
        assertEq(reason, bytes32("EXEMPTION_CAPACITY_EXHAUSTED"), "refused on capacity, not on identity");

        vm.expectRevert(
            abi.encodeWithSelector(QuorumAsset.ExemptionCapacityExhausted.selector, uint32(5), uint32(5))
        );
        asset.issue(p6, 10e18);
    }

    /// Scene 4 — wallet splitting fails. A seated person acquiring through a second and third
    /// verified wallet is still one person and consumes no additional seat.
    function test_scene4_walletSplittingConsumesNoNewSeat() public {
        _fillToCapacity();
        assertEq(ledger.activeSeats(), 5);

        // P1 moves value to their own second and third wallets. Ten addresses, still five people.
        vm.prank(p1a);
        asset.transfer(p1b, 30e18);
        vm.prank(p1a);
        asset.transfer(p1c, 20e18);

        assertEq(ledger.activeSeats(), 5, "wallet splitting did not manufacture a seat");
        assertEq(asset.personBalance(registry.personOf(p1a)), 100e18, "person balance unchanged by splitting");
        assertEq(asset.balanceOf(p1b), 30e18);
        assertEq(asset.balanceOf(p1c), 20e18);

        // And the offering is still correctly full for anyone new.
        (bool allowed,,) = asset.preflight(address(0), p6, 1e18);
        assertFalse(allowed, "still at capacity");
    }

    /// A seat is released when a person exits entirely, and only then.
    function test_seatReleasedOnFullExit() public {
        _fillToCapacity();

        vm.prank(p2);
        asset.redeem(40e18);
        assertEq(ledger.activeSeats(), 5, "partial exit keeps the seat");

        vm.prank(p2);
        asset.redeem(60e18);
        assertEq(ledger.activeSeats(), 4, "full exit frees the seat");

        // The freed seat is now available to the person who was refused a moment ago.
        asset.issue(p6, 10e18);
        assertEq(ledger.activeSeats(), 5);
    }

    /// P1 must exit all three wallets before the seat frees — not just the first.
    function test_seatSurvivesUntilEveryWalletIsEmpty() public {
        _fillToCapacity();
        vm.prank(p1a);
        asset.transfer(p1b, 100e18);

        vm.prank(p1b);
        asset.redeem(99e18);
        assertEq(ledger.activeSeats(), 5, "1 wei left across the person's wallets keeps the seat");

        vm.prank(p1b);
        asset.redeem(1e18);
        assertEq(ledger.activeSeats(), 4, "seat freed only when the person holds nothing");
    }

    /// Concentration — one person accumulating through several individually-modest wallets.
    function test_concentrationCeilingCountsThePersonNotTheWallet() public {
        // Primary issuance is exempt; the ceiling bites on the secondary market, which is where
        // silent accumulation actually happens.
        asset.issue(p1a, 100e18);
        asset.issue(p2, 100e18);
        asset.issue(p3, 100e18);
        asset.setConcentrationCeiling(4000); // 40% of a 300e18 supply == 120e18

        // P1 already sits at 100/300 (33%). Buying 50 more from P2 *through a different wallet*
        // would put the person at 150/300 = 50%. Per-wallet accounting sees two modest holders of
        // 100 and 50; person-accounting sees one holder at half the book.
        vm.prank(p2);
        vm.expectRevert();
        asset.transfer(p1b, 50e18);

        assertEq(asset.personBalance(registry.personOf(p1a)), 100e18, "no partial state written");
        assertEq(asset.balanceOf(p1b), 0, "the split wallet received nothing");

        // A purchase that keeps the person under 40% still clears: 100 + 15 = 115/300 = 38%.
        vm.prank(p3);
        asset.transfer(p1b, 15e18);
        assertEq(asset.personBalance(registry.personOf(p1a)), 115e18);
        assertEq(asset.balanceOf(p1b), 15e18);
    }

    /// Unregistered recipients are refused before any state moves.
    function test_unregisteredRecipientRefused() public {
        address stranger = address(0x99);
        vm.expectRevert(abi.encodeWithSelector(QuorumAsset.RecipientNotRegistered.selector, stranger));
        asset.issue(stranger, 1e18);
    }

    /// Preflight must agree with what the hook actually does — the panel cannot lie.
    function test_preflightMatchesExecution() public {
        _fillToCapacity();

        (bool allowed,,) = asset.preflight(address(0), p6, 5e18);
        assertFalse(allowed);
        vm.expectRevert();
        asset.issue(p6, 5e18);

        vm.prank(p2);
        asset.redeem(100e18);

        (bool allowedNow,, uint32 seatsAfter) = asset.preflight(address(0), p6, 5e18);
        assertTrue(allowedNow, "preflight sees the freed seat");
        assertEq(seatsAfter, 5, "and projects the resulting count");
        asset.issue(p6, 5e18);
        assertEq(ledger.activeSeats(), 5);
    }
}
