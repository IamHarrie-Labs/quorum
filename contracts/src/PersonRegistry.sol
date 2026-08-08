// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal view of the Cleanverse A-Pass contract on Monad.
/// @dev 0xbA82D189540CaC9DC6FF46B6837CaC1BFdEC58B9 answers balanceOf on-chain. It does NOT expose
///      the KYC hash, tier or country tags — those only come back from POST /query_apass. So the
///      hash arrives off-chain and is bound here by a registrar; possession is what we can check
///      synchronously. Caution: balanceOf returned 1 for 0x…dEaD in probing, so treat it as a
///      weak signal until verified against a known-unverified wallet. Hence `requireAPass`.
interface IAPass {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title PersonRegistry
/// @notice Collapses many wallets into one legal person.
/// @dev This is the whole reason Quorum can exist. Every securities exemption is a headcount rule,
///      and a chain counts wallets, not people — one person opens fifty wallets in an afternoon.
///      Cleanverse's A-Pass is bank-verified and wallet-bound, so `currentKycHash` from
///      /query_apass is the same value for every wallet belonging to one human. We bind that hash
///      to a dense personId and count personIds instead of addresses.
contract PersonRegistry {
    error NotRegistrar();
    error AlreadyBound(address wallet);
    error NoAPass(address wallet);
    error ZeroHash();

    event RegistrarSet(address indexed registrar, bool allowed);
    event PersonCreated(uint256 indexed personId, bytes32 indexed kycHash);
    event WalletBound(uint256 indexed personId, address indexed wallet);

    IAPass public immutable apass;
    address public immutable admin;

    /// @dev Off until A-Pass possession is confirmed to be a real per-wallet signal.
    bool public requireAPass;

    mapping(address => bool) public isRegistrar;
    mapping(bytes32 => uint256) public personOfHash;
    mapping(address => uint256) public personOf;
    mapping(uint256 => uint32) public walletCount;
    mapping(uint256 => bytes32) public hashOfPerson;

    uint256 public personCount;

    modifier onlyRegistrar() {
        if (!isRegistrar[msg.sender]) revert NotRegistrar();
        _;
    }

    constructor(address _apass) {
        apass = IAPass(_apass);
        admin = msg.sender;
        isRegistrar[msg.sender] = true;
        emit RegistrarSet(msg.sender, true);
    }

    function setRegistrar(address who, bool allowed) external {
        if (msg.sender != admin) revert NotRegistrar();
        isRegistrar[who] = allowed;
        emit RegistrarSet(who, allowed);
    }

    function setRequireAPass(bool on) external {
        if (msg.sender != admin) revert NotRegistrar();
        requireAPass = on;
    }

    /// @notice Bind a wallet to the person identified by their Cleanverse KYC hash.
    /// @dev Two wallets with the same hash land on the same personId — that is the point. The
    ///      hash comes from POST /query_apass; the backend is a courier, not an authority, and
    ///      cannot invent a person because a fabricated hash simply creates an unfunded personId.
    function bind(address wallet, bytes32 kycHash) external onlyRegistrar returns (uint256 personId) {
        if (kycHash == bytes32(0)) revert ZeroHash();
        if (personOf[wallet] != 0) revert AlreadyBound(wallet);
        if (requireAPass && apass.balanceOf(wallet) == 0) revert NoAPass(wallet);

        personId = personOfHash[kycHash];
        if (personId == 0) {
            personId = ++personCount;
            personOfHash[kycHash] = personId;
            hashOfPerson[personId] = kycHash;
            emit PersonCreated(personId, kycHash);
        }

        personOf[wallet] = personId;
        walletCount[personId] += 1;
        emit WalletBound(personId, wallet);
    }

    function isKnown(address wallet) external view returns (bool) {
        return personOf[wallet] != 0;
    }
}
