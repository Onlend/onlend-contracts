// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IAuthorisable} from "../interfaces/IAuthorisable.sol";

/// @title Authorisable
/// @notice Abstract contract that lets accounts authorise others to act on their behalf. See {IAuthorisable}.
/// @dev Inheriting contracts decide which operations are gated on `_requireSenderAuthorised` or `_isSenderAuthorised`.
///      Authorisations and signatures are scoped to each inheriting contract, since the EIP-712 domain binds
///      `address(this)`. Provides an internal initializer for EIP-1167-compatible inheriting contracts.
abstract contract Authorisable is IAuthorisable, ERC165Upgradeable, EIP712Upgradeable, NoncesUpgradeable {
    /// @notice EIP-712 typehash of `Authorisation`.
    bytes32 public constant AUTHORISATION_TYPEHASH = keccak256(
        "Authorisation(address authoriser,address authorised,bool isAuthorised,uint256 nonce,uint256 deadline)"
    );

    mapping(address authoriser => mapping(address authorised => bool)) private _isAuthorised;

    /// @notice Emitted when an authorisation is set.
    /// @param caller The account that submitted the authorisation.
    /// @param authoriser The account granting or revoking the authorisation.
    /// @param authorised The account whose authorisation is updated.
    /// @param newIsAuthorised New authorisation status.
    event AuthorisationSet(
        address indexed caller, address indexed authoriser, address indexed authorised, bool newIsAuthorised
    );

    /// @notice Reverts when the caller acts on behalf of an account that has not authorised it.
    /// @param onBehalfOf The account the caller acted on behalf of.
    /// @param caller The unauthorised caller.
    error Unauthorised(address onBehalfOf, address caller);
    /// @notice Reverts when setting an authorisation to its current status.
    /// @param authoriser The account granting or revoking the authorisation.
    /// @param authorised The account whose authorisation is already set.
    error AuthorisationAlreadySet(address authoriser, address authorised);
    /// @notice Reverts when a signed authorisation is submitted after its deadline.
    /// @param deadline The authorisation's deadline.
    error SignatureExpired(uint256 deadline);
    /// @notice Reverts when a signed authorisation was not signed by its authoriser.
    /// @param signer The account that signed the authorisation.
    /// @param authoriser The authorisation's authoriser.
    error InvalidSigner(address signer, address authoriser);

    /// @notice Initializes Authorisable state for an inheriting contract.
    /// @dev Must be called from the inheriting contract's initializer.
    /// @param name EIP-712 domain name.
    /// @param version EIP-712 domain version; changing it invalidates outstanding signatures.
    function _initializeAuthorisable(string memory name, string memory version) internal onlyInitializing {
        __EIP712_init(name, version);
    }

    /// @inheritdoc IAuthorisable
    function setAuthorisation(address authorised, bool newIsAuthorised) external {
        if (newIsAuthorised == _isAuthorised[msg.sender][authorised]) {
            revert AuthorisationAlreadySet(msg.sender, authorised);
        }

        _isAuthorised[msg.sender][authorised] = newIsAuthorised;
        emit AuthorisationSet(msg.sender, msg.sender, authorised, newIsAuthorised);
    }

    /// @inheritdoc IAuthorisable
    /// @dev Deliberately does not revert when the authorisation is already set, since the revert would roll back the
    ///      nonce consumption, which is a desired side effect:
    ///      - It is how an authoriser cancels a pending signature: signing and submitting a no-op for the same nonce
    ///        invalidates it, as there is no separate nonce-cancelling function.
    ///      - It keeps every signature single-use. `setAuthorisation` does not consume nonces, so without this a
    ///        signature submitted after its value was set directly would stay live, and could be replayed later to undo
    ///        a subsequent direct change at a time the authoriser did not choose.
    ///      - It spares relayers, who do not control submission timing, from reverting on a harmless no-op.
    function setAuthorisationWithSig(Authorisation calldata authorisation, Signature calldata signature) external {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > authorisation.deadline) revert SignatureExpired(authorisation.deadline);
        _useCheckedNonce(authorisation.authoriser, authorisation.nonce);

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(AUTHORISATION_TYPEHASH, authorisation)));
        address signer = ECDSA.recover(digest, signature.v, signature.r, signature.s);
        if (signer != authorisation.authoriser) revert InvalidSigner(signer, authorisation.authoriser);

        _isAuthorised[authorisation.authoriser][authorisation.authorised] = authorisation.isAuthorised;
        emit AuthorisationSet(
            msg.sender, authorisation.authoriser, authorisation.authorised, authorisation.isAuthorised
        );
    }

    /// @inheritdoc IAuthorisable
    function isAuthorised(address authoriser, address authorised) external view returns (bool) {
        return _isAuthorised[authoriser][authorised];
    }

    /// @inheritdoc IAuthorisable
    // forge-lint: disable-next-line(mixed-case-function)
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IAuthorisable
    function nonces(address authoriser) public view override(IAuthorisable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(authoriser);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAuthorisable).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Whether the caller is `onBehalfOf` or authorised by it.
    function _isSenderAuthorised(address onBehalfOf) internal view returns (bool) {
        return msg.sender == onBehalfOf || _isAuthorised[onBehalfOf][msg.sender];
    }

    /// @dev Reverts unless the caller is `onBehalfOf` or authorised by it.
    function _requireSenderAuthorised(address onBehalfOf) internal view {
        if (!_isSenderAuthorised(onBehalfOf)) revert Unauthorised(onBehalfOf, msg.sender);
    }
}
