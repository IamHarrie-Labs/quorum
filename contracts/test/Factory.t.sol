// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {QuorumFactory} from "../src/QuorumFactory.sol";
import {PersonRegistry} from "../src/PersonRegistry.sol";
import {SeatLedger} from "../src/SeatLedger.sol";
import {QuorumAsset} from "../src/QuorumAsset.sol";

/// @notice The factory's claim is that an issuer needs nobody's permission and nobody can act on
///         their register but them. Both halves are asserted here.
contract FactoryTest is Test {
    QuorumFactory factory;

    address issuer = address(0xA1);
    address otherIssuer = address(0xB2);
    address stranger = address(0xC3);
    address apass = address(0xAAA5);

    function setUp() public {
        factory = new QuorumFactory();
    }

    function _deployAs(address who) internal returns (address a, address r, address l) {
        vm.prank(who);
        return factory.deploy("Note", "NOTE", 5, 0, 10_000, apass);
    }

    /// An issuer deploys their own register and the factory records them as its owner.
    function test_deployIsSelfServe() public {
        (address a, address r, address l) = _deployAs(issuer);

        (address asset,,, address owner) = factory.registerOf(a);
        assertEq(asset, a);
        assertEq(owner, issuer, "the deploying wallet owns the register");

        // Wired: the asset can move seats, the issuer can bind people directly.
        assertTrue(SeatLedger(l).isOperator(a), "asset is a seat operator");
        assertTrue(PersonRegistry(r).isRegistrar(issuer), "issuer can bind without the factory");
        assertEq(factory.registerCount(), 1);
    }

    /// The issuer can mint through the factory, because QuorumAsset's issuer is the factory.
    function test_ownerCanIssueThroughFactory() public {
        (address a, address r,) = _deployAs(issuer);

        vm.prank(issuer);
        PersonRegistry(r).bind(stranger, keccak256("person-1"));

        vm.prank(issuer);
        factory.issue(a, stranger, 100e18);
        assertEq(QuorumAsset(a).balanceOf(stranger), 100e18);
    }

    /// Nobody else can, including another issuer who has their own register on the same factory.
    function test_strangersCannotTouchAnotherRegister() public {
        (address a, address r,) = _deployAs(issuer);
        _deployAs(otherIssuer);

        vm.prank(issuer);
        PersonRegistry(r).bind(stranger, keccak256("person-1"));

        vm.prank(stranger);
        vm.expectRevert(QuorumFactory.NotRegisterOwner.selector);
        factory.issue(a, stranger, 100e18);

        vm.prank(otherIssuer);
        vm.expectRevert(QuorumFactory.NotRegisterOwner.selector);
        factory.issue(a, stranger, 100e18);

        vm.prank(otherIssuer);
        vm.expectRevert(QuorumFactory.NotRegisterOwner.selector);
        factory.setConcentrationCeiling(a, 3000);
    }

    /// The factory itself has no authority: it cannot mint on a register it deployed.
    function test_factoryCannotActOnItsOwn() public {
        (address a, address r,) = _deployAs(issuer);

        vm.prank(issuer);
        PersonRegistry(r).bind(stranger, keccak256("person-1"));

        // Calling from the factory's own address still fails the owner check.
        vm.prank(address(factory));
        vm.expectRevert(QuorumFactory.NotRegisterOwner.selector);
        factory.issue(a, stranger, 100e18);

        // And the asset refuses anyone who is not the issuer of record.
        vm.prank(stranger);
        vm.expectRevert(QuorumAsset.NotIssuer.selector);
        QuorumAsset(a).issue(stranger, 100e18);
    }

    /// Two registers on one factory stay independent — different caps, separate seat counts.
    function test_registersAreIsolated() public {
        vm.prank(issuer);
        (address a1,, address l1) = factory.deploy("A", "A", 1, 0, 10_000, apass);
        vm.prank(otherIssuer);
        (address a2, address r2, address l2) = factory.deploy("B", "B", 5, 0, 10_000, apass);

        assertEq(SeatLedger(l1).maxPersons(), 1);
        assertEq(SeatLedger(l2).maxPersons(), 5);

        vm.prank(otherIssuer);
        PersonRegistry(r2).bind(stranger, keccak256("p"));
        vm.prank(otherIssuer);
        factory.issue(a2, stranger, 1e18);

        assertEq(SeatLedger(l2).activeSeats(), 1, "B seated one person");
        assertEq(SeatLedger(l1).activeSeats(), 0, "A is untouched");
        assertEq(QuorumAsset(a1).totalSupply(), 0);
    }

    /// An unknown asset address is rejected rather than silently doing nothing.
    function test_unknownRegisterReverts() public {
        vm.prank(issuer);
        vm.expectRevert(QuorumFactory.UnknownRegister.selector);
        factory.issue(address(0xDEAD), stranger, 1e18);
    }
}
