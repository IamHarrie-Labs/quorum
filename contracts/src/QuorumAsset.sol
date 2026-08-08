// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {PersonRegistry} from "./PersonRegistry.sol";
import {SeatLedger} from "./SeatLedger.sol";

/// @title QuorumAsset
/// @notice A security whose offering cannot breach its own legal exemption.
/// @dev We deploy this and then register it as a Cleanverse A-Token via
///      POST /atoken/register_atoken. The alternative, POST /atoken/launch, has Cleanverse deploy
///      the contract — which leaves nowhere to put this hook, and the seat logic would end up
///      sitting beside the asset rather than inside it.
///
///      The distinction that makes this project: every rule in the Cleanverse engine is a
///      per-wallet attribute check (tier, subTier, group, subGroup, country). None of them can
///      express an aggregate. So Cleanverse asks "is this recipient allowed?" and Quorum asks
///      "will the whole holder base still satisfy the law once this settles?"
contract QuorumAsset is ERC20 {
    error NotIssuer();
    error RecipientNotRegistered(address wallet);
    error ExemptionCapacityExhausted(uint32 activeSeats, uint32 maxPersons);
    error ConcentrationExceeded(uint256 personId, uint256 wouldHoldBps, uint16 ceilingBps);

    event TransferApproved(
        address indexed from, address indexed to, uint256 indexed personId, uint256 value, bool seatConsumed
    );
    event TransferRefused(address indexed from, address indexed to, uint256 indexed personId, bytes32 reason);

    PersonRegistry public immutable registry;
    SeatLedger public immutable seatLedger;
    address public immutable issuer;

    /// @notice Ceiling on any one person's holding, in basis points of supply.
    /// @dev The second rule that needs person-resolution. Someone accumulating through four
    ///      wallets looks like four modest investors to every other system; here it is one person
    ///      at 11%. Set to 10000 to disable.
    uint16 public concentrationCeilingBps;

    /// @dev Balance per person, not per wallet. Kept in step with _update so concentration is a
    ///      counter lookup rather than a walk over an address set.
    mapping(uint256 => uint256) public personBalance;

    modifier onlyIssuer() {
        if (msg.sender != issuer) revert NotIssuer();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        PersonRegistry _registry,
        SeatLedger _seatLedger,
        uint16 _concentrationCeilingBps
    ) ERC20(name_, symbol_) {
        registry = _registry;
        seatLedger = _seatLedger;
        issuer = msg.sender;
        concentrationCeilingBps = _concentrationCeilingBps;
    }

    function issue(address to, uint256 amount) external onlyIssuer {
        _mint(to, amount);
    }

    /// @notice Exit the register. Burns the holding and frees the seat once the person is empty.
    /// @dev Without this there is no way out. A transfer-restricted security whose only exit is a
    ///      transfer to another eligible holder can trap someone when the register is full, and
    ///      "we froze your position indefinitely" is not an answer an issuer can give. Exits are
    ///      never blocked — leaving cannot breach a headcount cap.
    function redeem(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function setConcentrationCeiling(uint16 bps) external onlyIssuer {
        concentrationCeilingBps = bps;
    }

    /// @notice Read-only preflight: would this transfer be allowed right now, and why not?
    /// @dev Same evaluation the hook runs, against live state, without submitting anything. This
    ///      is what turns Quorum from a blocker into something an issuer's counsel opens in the
    ///      morning to ask "if I admit this investor, what breaks?"
    function preflight(address from, address to, uint256 value)
        external
        view
        returns (bool allowed, bytes32 reason, uint32 seatsAfter)
    {
        uint256 personId = registry.personOf(to);
        if (personId == 0) return (false, "RECIPIENT_NOT_REGISTERED", seatLedger.activeSeats());

        bool needsSeat = !seatLedger.holdsSeat(personId);
        // canTake already reports the count *after* a successful take, so it must not be
        // incremented again here — doing so put a number on the dashboard that the hook would
        // never produce, which is the one thing a preflight panel may not do.
        (bool seatOk, uint32 seatsAfter) = seatLedger.canTake(personId);
        if (needsSeat && !seatOk) {
            return (false, "EXEMPTION_CAPACITY_EXHAUSTED", seatsAfter);
        }

        uint256 wouldHold = personBalance[personId] + value;
        if (from != address(0) && _exceedsCeiling(wouldHold, totalSupply())) {
            return (false, "CONCENTRATION_EXCEEDED", seatsAfter);
        }
        return (true, bytes32(0), seatsAfter);
    }

    /// @dev Every mint and every transfer lands here. Burns are unrestricted — exiting the
    ///      register can never breach a cap, and blocking an exit would trap a holder.
    function _update(address from, address to, uint256 value) internal override {
        if (to == address(0)) {
            super._update(from, to, value);
            _settleSender(from, value);
            return;
        }

        uint256 personId = registry.personOf(to);
        if (personId == 0) {
            emit TransferRefused(from, to, 0, "RECIPIENT_NOT_REGISTERED");
            revert RecipientNotRegistered(to);
        }

        // A seat is held by anyone with a live seat, so a person acquiring through an additional
        // wallet consumes nothing new. Keyed on the seat rather than on balance so that under a
        // rolling-window pack, a holder whose seat has aged out and who then acquires again is
        // treated as a fresh admission in the new window — which is what the law is counting.
        bool needsSeat = !seatLedger.holdsSeat(personId);
        bool seatConsumed = false;
        if (needsSeat) {
            try seatLedger.take(personId) returns (bool consumed) {
                seatConsumed = consumed;
            } catch {
                emit TransferRefused(from, to, personId, "EXEMPTION_CAPACITY_EXHAUSTED");
                revert ExemptionCapacityExhausted(seatLedger.activeSeats(), seatLedger.maxPersons());
            }
        }

        uint256 wouldHold = personBalance[personId] + value;
        // Primary issuance is exempt: the issuer is allocating a book it already knows, and the
        // first allocation is transiently 100% of supply no matter how the book ends up. The
        // ceiling exists to stop silent accumulation on the secondary market, which is a transfer.
        if (from != address(0) && _exceedsCeiling(wouldHold, totalSupply())) {
            emit TransferRefused(from, to, personId, "CONCENTRATION_EXCEEDED");
            revert ConcentrationExceeded(personId, (wouldHold * 10_000) / totalSupply(), concentrationCeilingBps);
        }

        super._update(from, to, value);

        personBalance[personId] = wouldHold;
        _settleSender(from, value);

        emit TransferApproved(from, to, personId, value, seatConsumed);
    }

    function _settleSender(address from, uint256 value) internal {
        if (from == address(0)) return;
        uint256 senderPerson = registry.personOf(from);
        if (senderPerson == 0) return;

        personBalance[senderPerson] -= value;
        if (personBalance[senderPerson] == 0 && seatLedger.holdsSeat(senderPerson)) {
            seatLedger.release(senderPerson);
        }
    }

    function _exceedsCeiling(uint256 wouldHold, uint256 supplyAfter) internal view returns (bool) {
        if (concentrationCeilingBps >= 10_000 || supplyAfter == 0) return false;
        return wouldHold * 10_000 > supplyAfter * concentrationCeilingBps;
    }
}
