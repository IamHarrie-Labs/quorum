// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SeatLedger
/// @notice Counts persons, not wallets, against a legal headcount cap over a rolling window.
/// @dev Singapore SFA s.272A allows an offer to no more than 50 persons in any 12-month period.
///      US Reg D 506(b) caps non-accredited purchasers at 35. These are cliffs: go one over and
///      the exemption is void retroactively, and every prior sale becomes an unregistered
///      securities sale. Today the number lives in a transfer agent's spreadsheet, reconciled
///      monthly — after the transfers have already settled.
///
///      Design note: the count is an O(1) counter, never a loop over holders. A cap check that
///      iterates the holder set gets more expensive as the offering fills, which is exactly
///      backwards. Expiry is lazy: seats are reaped when touched, and `activeSeats` is only ever
///      incremented while strictly below the cap. So the invariant holds by construction —
///      expiry can only ever reduce the count.
contract SeatLedger {
    error NotOperator();
    error CapacityExhausted(uint32 activeSeats, uint32 maxPersons);
    error NoSeat(uint256 personId);

    event SeatTaken(uint256 indexed personId, uint64 takenAt, uint32 activeSeats);
    event SeatReleased(uint256 indexed personId, uint32 activeSeats);
    event SeatExpired(uint256 indexed personId, uint32 activeSeats);

    struct Seat {
        uint64 takenAt;
        bool held;
    }

    address public immutable admin;
    mapping(address => bool) public isOperator;

    /// @notice Headcount ceiling. 50 for sg_sfa_272a; the demo runs a pack of 5 because you
    ///         cannot obtain fifty bank-verified identities for a hackathon and faking forty-nine
    ///         of them would make the demo a simulation.
    uint32 public maxPersons;
    uint32 public windowDays;
    uint32 public activeSeats;

    mapping(uint256 => Seat) public seats;

    modifier onlyOperator() {
        if (!isOperator[msg.sender]) revert NotOperator();
        _;
    }

    constructor(uint32 _maxPersons, uint32 _windowDays) {
        admin = msg.sender;
        isOperator[msg.sender] = true;
        maxPersons = _maxPersons;
        windowDays = _windowDays;
    }

    function setOperator(address who, bool allowed) external {
        if (msg.sender != admin) revert NotOperator();
        isOperator[who] = allowed;
    }

    function holdsSeat(uint256 personId) public view returns (bool) {
        Seat storage s = seats[personId];
        if (!s.held) return false;
        return !_expired(s.takenAt);
    }

    /// @notice Seats remaining before the exemption is exhausted.
    function headroom() external view returns (uint32) {
        return activeSeats >= maxPersons ? 0 : maxPersons - activeSeats;
    }

    /// @notice Take a seat for `personId`, or confirm they already hold one.
    /// @dev Returns false when no new seat was consumed — the wallet-splitting case. A person
    ///      acquiring through a second verified wallet is still one person and must not burn a
    ///      second seat, or the cap would be enforced against addresses again and the whole
    ///      exercise would be pointless.
    function take(uint256 personId) external onlyOperator returns (bool consumed) {
        _reap(personId);
        if (seats[personId].held) return false;

        if (activeSeats >= maxPersons) revert CapacityExhausted(activeSeats, maxPersons);

        seats[personId] = Seat({takenAt: uint64(block.timestamp), held: true});
        activeSeats += 1;
        emit SeatTaken(personId, uint64(block.timestamp), activeSeats);
        return true;
    }

    /// @notice Give up a seat when a person's holding goes to zero.
    function release(uint256 personId) external onlyOperator {
        if (!seats[personId].held) revert NoSeat(personId);
        delete seats[personId];
        activeSeats -= 1;
        emit SeatReleased(personId, activeSeats);
    }

    /// @notice Would taking a seat for `personId` succeed right now? Read-only preflight.
    /// @dev Backs the "what happens if I admit this investor" panel. It reads live contract state
    ///      via eth_call — a dry run against the real register, not a simulation on fake numbers.
    function canTake(uint256 personId) external view returns (bool ok, uint32 seatsAfter) {
        if (holdsSeat(personId)) return (true, activeSeats);
        uint32 projected = _projectedActive(personId);
        if (projected >= maxPersons) return (false, projected);
        return (true, projected + 1);
    }

    function reap(uint256 personId) external {
        _reap(personId);
    }

    function _reap(uint256 personId) internal {
        Seat storage s = seats[personId];
        if (s.held && _expired(s.takenAt)) {
            delete seats[personId];
            activeSeats -= 1;
            emit SeatExpired(personId, activeSeats);
        }
    }

    function _projectedActive(uint256 personId) internal view returns (uint32) {
        Seat storage s = seats[personId];
        if (s.held && _expired(s.takenAt)) return activeSeats - 1;
        return activeSeats;
    }

    function _expired(uint64 takenAt) internal view returns (bool) {
        if (windowDays == 0) return false;
        return block.timestamp > uint256(takenAt) + uint256(windowDays) * 1 days;
    }
}
