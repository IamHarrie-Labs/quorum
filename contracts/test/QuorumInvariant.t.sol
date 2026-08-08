// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PersonRegistry} from "../src/PersonRegistry.sol";
import {SeatLedger} from "../src/SeatLedger.sol";
import {QuorumAsset} from "../src/QuorumAsset.sol";

/// @notice Drives the system with arbitrary sequences of issues, transfers and exits.
/// @dev Deliberately hostile: it hammers the wallet-splitting path, because that is where a naive
///      implementation leaks seats. Six people, ten wallets — person 1 holds three of them.
contract Handler is Test {
    QuorumAsset public asset;
    SeatLedger public ledger;
    PersonRegistry public registry;

    address[10] public wallets;
    uint256 public ghostIssued;

    constructor(QuorumAsset _asset, SeatLedger _ledger, PersonRegistry _registry, address[10] memory _wallets) {
        asset = _asset;
        ledger = _ledger;
        registry = _registry;
        wallets = _wallets;
    }

    function issue(uint256 who, uint96 amount) public {
        address to = wallets[bound(who, 0, 9)];
        amount = uint96(bound(amount, 1, 1_000e18));
        vm.prank(asset.issuer());
        try asset.issue(to, amount) {
            ghostIssued += amount;
        } catch {}
    }

    function move(uint256 fromIdx, uint256 toIdx, uint96 amount) public {
        address from = wallets[bound(fromIdx, 0, 9)];
        address to = wallets[bound(toIdx, 0, 9)];
        uint256 bal = asset.balanceOf(from);
        if (bal == 0) return;
        amount = uint96(bound(amount, 1, bal));
        vm.prank(from);
        try asset.transfer(to, amount) {} catch {}
    }

    function exit(uint256 who, uint96 amount) public {
        address from = wallets[bound(who, 0, 9)];
        uint256 bal = asset.balanceOf(from);
        if (bal == 0) return;
        amount = uint96(bound(amount, 1, bal));
        vm.prank(from);
        try asset.redeem(amount) {} catch {}
    }

    function passTime(uint32 daysAhead) public {
        vm.warp(block.timestamp + bound(daysAhead, 1, 400) * 1 days);
    }

    function reap(uint256 personId) public {
        ledger.reap(bound(personId, 1, 6));
    }
}

/// @dev Two legal models, and the invariant suite found the difference between them the hard way.
///
///   STANDING CAP (windowDays = 0). Every current holder occupies a seat for as long as they
///   hold. The cap limits the size of the holder base. This is what Reg D 506(b)'s 35-purchaser
///   count and Exchange Act s.12(g)'s holders-of-record threshold are actually measuring, and it
///   is what the demo runs — "the room is full" only means something if seats do not quietly
///   free themselves.
///
///   ROLLING WINDOW (windowDays = 365). Seats age out. Singapore SFA s.272A caps offers made to
///   50 persons *within any 12-month period*, so an offering can legitimately accumulate more
///   than 50 lifetime holders by admitting 50 in each of two years. Under this pack a holder can
///   correctly hold with no live seat, and `holder => seat` is NOT an invariant.
///
/// Getting this wrong in either direction is a real compliance failure, so both are tested.
abstract contract QuorumBase is Test {
    PersonRegistry registry;
    SeatLedger ledger;
    QuorumAsset asset;
    Handler handler;

    uint32 constant MAX_PERSONS = 5;

    address[10] wallets;

    function _deploy(uint32 windowDays) internal {
        registry = new PersonRegistry(address(0xA11CE));
        ledger = new SeatLedger(MAX_PERSONS, windowDays);
        asset = new QuorumAsset("Quorum Note", "QNOTE", registry, ledger, 10_000);
        ledger.setOperator(address(asset), true);

        // Six people across ten wallets. Person 1 gets three wallets and person 2 gets two — the
        // splitting case has to be in the fuzz surface, not just in a hand-written test.
        uint8[10] memory owner = [1, 1, 1, 2, 2, 3, 4, 5, 6, 6];
        for (uint256 i = 0; i < 10; i++) {
            wallets[i] = address(uint160(0x1000 + i));
            registry.bind(wallets[i], keccak256(abi.encodePacked("person", owner[i])));
        }

        handler = new Handler(asset, ledger, registry, wallets);
        targetContract(address(handler));
    }

    /// @notice The claim. An offering cannot admit more persons than its exemption allows.
    /// @dev If this ever fails, Quorum is a normal token with extra steps.
    function invariant_seatsNeverExceedCap() public view {
        assertLe(ledger.activeSeats(), MAX_PERSONS, "headcount cap breached");
    }

    /// @notice Wallets are not persons. Ten addresses can never produce more than six seats.
    function invariant_seatsNeverExceedDistinctPersons() public view {
        assertLe(ledger.activeSeats(), 6, "seats exceeded the number of real humans");
    }

    /// @notice Per-person balances must reconcile with per-wallet balances.
    /// @dev Guards the concentration ceiling: if this drifts, a person could split across wallets
    ///      and slip under the ceiling while actually holding more.
    function invariant_personBalancesReconcile() public view {
        uint256[7] memory fromWallets;
        for (uint256 i = 0; i < 10; i++) {
            uint256 pid = registry.personOf(wallets[i]);
            fromWallets[pid] += asset.balanceOf(wallets[i]);
        }
        for (uint256 pid = 1; pid <= 6; pid++) {
            assertEq(asset.personBalance(pid), fromWallets[pid], "person balance drifted from wallets");
        }
    }

    function _assertHoldersAreSeated() internal view {
        for (uint256 pid = 1; pid <= 6; pid++) {
            if (asset.personBalance(pid) > 0) {
                assertTrue(ledger.holdsSeat(pid), "holder without a seat");
            }
        }
    }
}

/// @notice Standing-cap pack — the configuration the demo runs.
contract QuorumStandingCapTest is QuorumBase {
    function setUp() public {
        _deploy(0);
    }

    /// @notice Under a standing cap, nobody holds the security without occupying a seat.
    /// @dev This is the one that failed on the first run with a 365-day window, which is how the
    ///      two legal models got separated. Worth stating plainly in the docs page: an expiring
    ///      seat and a standing seat answer different questions, and the rule pack picks.
    function invariant_holdersAlwaysSeated() public view {
        _assertHoldersAreSeated();
    }
}

/// @notice Rolling-window pack — Singapore SFA s.272A semantics.
contract QuorumRollingWindowTest is QuorumBase {
    function setUp() public {
        _deploy(365);
    }

    /// @notice Seats age out, so a long-standing holder may hold with no live seat. What must
    ///         never happen is a seat still counting as live past its window.
    /// @dev Asserted through holdsSeat() rather than raw storage. Expiry is lazy — an expired
    ///      seat stays in storage until reaped — so the stored flag legitimately lags the logical
    ///      state. holdsSeat() is what every caller reads and what the cap check consults.
    function invariant_noLiveSeatOutlivesItsWindow() public view {
        for (uint256 pid = 1; pid <= 6; pid++) {
            if (ledger.holdsSeat(pid)) {
                (uint64 takenAt,) = ledger.seats(pid);
                assertLe(block.timestamp, uint256(takenAt) + 365 days, "live seat outlived its window");
            }
        }
    }

    /// @notice activeSeats may over-count while expired seats await reaping, but must never
    ///         under-count.
    /// @dev The safety-critical direction. Over-counting fails closed: the register refuses a
    ///      transfer when capacity has actually freed up, which is a conservative error a keeper
    ///      call fixes. Under-counting would let the cap be breached, which is the thing this
    ///      whole project exists to prevent.
    function invariant_activeSeatsNeverUndercounts() public view {
        uint32 live;
        for (uint256 pid = 1; pid <= 6; pid++) {
            if (ledger.holdsSeat(pid)) live++;
        }
        assertGe(ledger.activeSeats(), live, "activeSeats under-counted live seats");
    }
}
