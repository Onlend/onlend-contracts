// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title Authorisable Interface
/// @notice Lets an account authorise others to act on its behalf, either directly or through an EIP-712 signature
///         relayed by anyone.
interface IAuthorisable {
    /// @notice An authorisation signed by `authoriser` for relay through `setAuthorisationWithSig`.
    /// @param authoriser The account granting or revoking the authorisation.
    /// @param authorised The account whose authorisation is updated.
    /// @param isAuthorised New authorisation status.
    /// @param nonce The authoriser's nonce the signature consumes.
    /// @param deadline The last timestamp at which the signature may be submitted.
    struct Authorisation {
        address authoriser;
        address authorised;
        bool isAuthorised;
        uint256 nonce;
        uint256 deadline;
    }

    /// @notice An ECDSA signature.
    /// @param v The recovery byte.
    /// @param r The first 32 bytes of the signature.
    /// @param s The second 32 bytes of the signature.
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Sets whether `authorised` may act on the caller's behalf.
    /// @dev Does not consume the caller's nonce, so a pending signed authorisation stays valid and can still be
    ///      submitted afterwards, overriding this change.
    /// @param authorised The account whose authorisation is updated.
    /// @param newIsAuthorised True to authorise `authorised`, false to revoke it.
    function setAuthorisation(address authorised, bool newIsAuthorised) external;

    /// @notice Sets an authorisation signed by its authoriser. Callable by anyone.
    /// @dev Consumes the authoriser's nonce even where the authorisation is already set, so a pending signature can be
    ///      invalidated by submitting another for the same nonce.
    /// @param authorisation The authorisation to set.
    /// @param signature The authoriser's EIP-712 signature over `authorisation`.
    function setAuthorisationWithSig(Authorisation calldata authorisation, Signature calldata signature) external;

    /// @notice Whether `authorised` may act on behalf of `authoriser`.
    /// @dev An account is always implicitly authorised to act on its own behalf, even where this returns false.
    /// @param authoriser The account granting the authorisation.
    /// @param authorised The account to query.
    /// @return True if `authorised` has been authorised by `authoriser`, false otherwise.
    function isAuthorised(address authoriser, address authorised) external view returns (bool);

    /// @notice The nonce `authoriser`'s next signed authorisation must carry.
    /// @dev Used to prevent replay attacks with EIP-712 signatures.
    /// @param authoriser The account to query.
    /// @return The authoriser's next nonce.
    function nonces(address authoriser) external view returns (uint256);

    /// @notice The EIP-712 domain separator signed authorisations are bound to.
    /// @dev Warning: Every EIP-712 signed message based on this domain separator can be reused on chains sharing the
    /// same chain id and on forks because the domain separator would be the same.
    /// @return The domain separator for the current chain and this contract.
    // forge-lint: disable-next-line(mixed-case-function)
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
