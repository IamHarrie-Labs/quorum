// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PersonRegistry} from "./PersonRegistry.sol";
import {SeatLedger} from "./SeatLedger.sol";
import {QuorumAsset} from "./QuorumAsset.sol";

/// @title QuorumFactory
/// @notice Self-serve deployment of a Quorum register. One transaction, no permission required.
/// @dev The adoption problem this exists to solve: if issuing through Quorum means asking us to
///      deploy your contracts, Quorum is a consultancy, not infrastructure. An issuer connects a
///      wallet, calls deploy(), and owns the result. We never hold a key and are never in the loop.
///
///      A note on control, because the routing below looks odd until you know why it is there.
///      PersonRegistry and SeatLedger fix `admin` at construction, and QuorumAsset's `issuer` is
///      immutable. Whoever runs `new` holds those powers permanently, and here that is necessarily
///      this contract. So the factory records the deploying wallet and routes the owner-only calls
///      back to it. The factory has no authority of its own: every function below is gated on the
///      wallet that deployed that specific register, and there is no path — no owner, no admin, no
///      upgrade hook — by which this contract can act on a register unilaterally.
///
///      The high-frequency operation, binding wallets to persons, is deliberately not routed:
///      deploy() grants the issuer registrar rights directly on their PersonRegistry, so their
///      resolver talks to their own contract with no factory hop.
contract QuorumFactory {
    error NotRegisterOwner();
    error UnknownRegister();

    event RegisterDeployed(
        address indexed owner,
        address indexed asset,
        address registry,
        address ledger,
        uint32 maxPersons,
        uint32 windowDays,
        uint16 concentrationCeilingBps
    );

    struct Register {
        address asset;
        address registry;
        address ledger;
        address owner;
    }

    /// @notice Every register this factory has deployed, keyed by its asset address.
    mapping(address => Register) public registerOf;
    address[] public allAssets;

    modifier onlyRegisterOwner(address asset) {
        Register storage r = registerOf[asset];
        if (r.asset == address(0)) revert UnknownRegister();
        if (msg.sender != r.owner) revert NotRegisterOwner();
        _;
    }

    /// @notice Deploy a complete register: person resolution, seat ledger, and the asset that
    ///         enforces against them. The caller owns all three.
    /// @param maxPersons Headcount cap. 50 for Singapore SFA s.272A, 35 for US Reg D 506(b).
    /// @param windowDays 0 for a standing cap; 365 for a rolling 12-month window.
    /// @param concentrationCeilingBps Per-person ceiling in basis points. 10000 disables it.
    /// @param apass The Cleanverse A-Pass contract for this chain.
    function deploy(
        string calldata name_,
        string calldata symbol_,
        uint32 maxPersons,
        uint32 windowDays,
        uint16 concentrationCeilingBps,
        address apass
    ) external returns (address asset, address registry, address ledger) {
        PersonRegistry reg = new PersonRegistry(apass);
        SeatLedger led = new SeatLedger(maxPersons, windowDays);
        QuorumAsset ast = new QuorumAsset(name_, symbol_, reg, led, concentrationCeilingBps);

        // The asset must be able to take and release seats.
        led.setOperator(address(ast), true);
        // The issuer binds people directly, without coming back through here.
        reg.setRegistrar(msg.sender, true);

        registerOf[address(ast)] =
            Register({asset: address(ast), registry: address(reg), ledger: address(led), owner: msg.sender});
        allAssets.push(address(ast));

        emit RegisterDeployed(
            msg.sender, address(ast), address(reg), address(led), maxPersons, windowDays, concentrationCeilingBps
        );
        return (address(ast), address(reg), address(led));
    }

    // --- owner actions, routed ------------------------------------------------

    function issue(address asset, address to, uint256 amount) external onlyRegisterOwner(asset) {
        QuorumAsset(asset).issue(to, amount);
    }

    function setConcentrationCeiling(address asset, uint16 bps) external onlyRegisterOwner(asset) {
        QuorumAsset(asset).setConcentrationCeiling(bps);
    }

    function setRegistrar(address asset, address who, bool allowed) external onlyRegisterOwner(asset) {
        PersonRegistry(registerOf[asset].registry).setRegistrar(who, allowed);
    }

    function setRequireAPass(address asset, bool on) external onlyRegisterOwner(asset) {
        PersonRegistry(registerOf[asset].registry).setRequireAPass(on);
    }

    function setOperator(address asset, address who, bool allowed) external onlyRegisterOwner(asset) {
        SeatLedger(registerOf[asset].ledger).setOperator(who, allowed);
    }

    function registerCount() external view returns (uint256) {
        return allAssets.length;
    }
}
