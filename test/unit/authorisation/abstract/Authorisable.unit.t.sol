// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {Authorisable} from "src/authorisation/abstract/Authorisable.sol";
import {IAuthorisable} from "src/authorisation/interfaces/IAuthorisable.sol";
import {AuthorisableHarness} from "./mocks/AuthorisableHarness.sol";

contract AuthorisableUnitTest is Test {
    string internal constant NAME = "AuthorisableHarness";
    string internal constant VERSION = "1";
    string internal constant AUTHORISATION_TYPE_DEFINITION =
        "Authorisation(address authoriser,address authorised,bool isAuthorised,uint256 nonce,uint256 deadline)";

    uint256 internal authoriserKey;
    address internal authoriser;
    address internal authorised;
    address internal relayer;
    uint256 internal deadline;
    AuthorisableHarness internal implementation;
    AuthorisableHarness internal authorisable;

    function setUp() public {
        (authoriser, authoriserKey) = makeAddrAndKey("authoriser");
        authorised = makeAddr("authorised");
        relayer = makeAddr("relayer");
        deadline = block.timestamp + 1 hours;

        implementation = new AuthorisableHarness();
        authorisable = AuthorisableHarness(Clones.clone(address(implementation)));
        authorisable.initialize(NAME, VERSION);
    }

    // initialize()

    function test_initialize_SetsEip712Domain() public view {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            authorisable.eip712Domain();

        assertEq(name, NAME);
        assertEq(version, VERSION);
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(authorisable));
    }

    // setAuthorisation()

    function test_setAuthorisation_AuthorisesAccount() public {
        vm.expectEmit();
        emit Authorisable.AuthorisationSet(authoriser, authoriser, authorised, true);

        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);

        assertTrue(authorisable.isAuthorised(authoriser, authorised));
    }

    function test_setAuthorisation_RevokesAuthorisation() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);

        vm.expectEmit();
        emit Authorisable.AuthorisationSet(authoriser, authoriser, authorised, false);

        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, false);

        assertFalse(authorisable.isAuthorised(authoriser, authorised));
    }

    function test_setAuthorisation_DoesNotAuthoriseInReverse() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);

        assertFalse(authorisable.isAuthorised(authorised, authoriser));
    }

    function test_setAuthorisation_DoesNotConsumeNonce() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);

        assertEq(authorisable.nonces(authoriser), 0);
    }

    function test_setAuthorisation_DoesNotInvalidatePendingSignature() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, false);

        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        assertTrue(authorisable.isAuthorised(authoriser, authorised));
    }

    function test_setAuthorisation_RevertsWhenAlreadyAuthorised() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);

        vm.expectRevert(abi.encodeWithSelector(Authorisable.AuthorisationAlreadySet.selector, authoriser, authorised));
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);
    }

    function test_setAuthorisation_RevertsWhenAlreadyUnauthorised() public {
        vm.expectRevert(abi.encodeWithSelector(Authorisable.AuthorisationAlreadySet.selector, authoriser, authorised));
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, false);
    }

    // setAuthorisationWithSig()

    function test_setAuthorisationWithSig_AuthorisesAccount() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);

        vm.expectEmit();
        emit Authorisable.AuthorisationSet(relayer, authoriser, authorised, true);

        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        assertTrue(authorisable.isAuthorised(authoriser, authorised));
    }

    function test_setAuthorisationWithSig_RevokesAuthorisation() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);
        IAuthorisable.Authorisation memory authorisation = _authorisation(false, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);

        vm.expectEmit();
        emit Authorisable.AuthorisationSet(relayer, authoriser, authorised, false);

        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        assertFalse(authorisable.isAuthorised(authoriser, authorised));
    }

    function test_setAuthorisationWithSig_ConsumesNonce() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);

        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        assertEq(authorisable.nonces(authoriser), 1);
    }

    function test_setAuthorisationWithSig_ConsumesNonceWhenAlreadySet() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(false, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);

        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        assertFalse(authorisable.isAuthorised(authoriser, authorised));
        assertEq(authorisable.nonces(authoriser), 1);
    }

    function test_setAuthorisationWithSig_AcceptsSignatureAtDeadline() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
        vm.warp(deadline);

        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        assertTrue(authorisable.isAuthorised(authoriser, authorised));
    }

    function test_setAuthorisationWithSig_RevertsWhenDeadlineHasPassed() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(Authorisable.SignatureExpired.selector, deadline));
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function test_setAuthorisationWithSig_RevertsWhenNonceIsReused() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        vm.expectRevert(abi.encodeWithSelector(NoncesUpgradeable.InvalidAccountNonce.selector, authoriser, 1));
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function test_setAuthorisationWithSig_RevertsWhenNonceIsAhead() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 1);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);

        vm.expectRevert(abi.encodeWithSelector(NoncesUpgradeable.InvalidAccountNonce.selector, authoriser, 0));
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function test_setAuthorisationWithSig_RevertsWhenSignerIsNotAuthoriser() public {
        (address signer, uint256 signerKey) = makeAddrAndKey("signer");
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(signerKey, authorisation);

        vm.expectRevert(abi.encodeWithSelector(Authorisable.InvalidSigner.selector, signer, authoriser));
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function test_setAuthorisationWithSig_RevertsWhenAuthorisationIsTampered() public {
        IAuthorisable.Signature memory signature = _sign(authoriserKey, _authorisation(true, 0));
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        authorisation.authorised = relayer;

        vm.expectPartialRevert(Authorisable.InvalidSigner.selector);
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function test_setAuthorisationWithSig_RevertsWhenSignedForAnotherContract() public {
        AuthorisableHarness otherAuthorisable = AuthorisableHarness(Clones.clone(address(implementation)));
        otherAuthorisable.initialize(NAME, VERSION);
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(otherAuthorisable, authoriserKey, authorisation);

        vm.expectPartialRevert(Authorisable.InvalidSigner.selector);
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function test_setAuthorisationWithSig_RevertsWhenSignedForAnotherChain() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
        vm.chainId(block.chainid + 1);

        vm.expectPartialRevert(Authorisable.InvalidSigner.selector);
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function test_setAuthorisationWithSig_RevertsWhenSignatureIsMalleable() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
        bytes32 highS = bytes32(SECP256K1_ORDER - uint256(signature.s));
        signature = IAuthorisable.Signature({v: signature.v == 27 ? 28 : 27, r: signature.r, s: highS});

        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, highS));
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function test_setAuthorisationWithSig_RevertsWhenSignatureIsInvalid() public {
        IAuthorisable.Authorisation memory authorisation = _authorisation(true, 0);
        IAuthorisable.Signature memory signature = IAuthorisable.Signature({v: 27, r: bytes32(0), s: bytes32(0)});

        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    // isAuthorised()

    function test_isAuthorised_ReturnsFalseByDefault() public view {
        assertFalse(authorisable.isAuthorised(authoriser, authorised));
    }

    function test_isAuthorised_ReturnsFalseForSelf() public view {
        assertFalse(authorisable.isAuthorised(authoriser, authoriser));
    }

    // supportsInterface()

    function test_supportsInterface_ReturnsTrueForAuthorisable() public view {
        assertTrue(authorisable.supportsInterface(type(IAuthorisable).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForERC165() public view {
        assertTrue(authorisable.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnknownInterface() public view {
        assertFalse(authorisable.supportsInterface(bytes4(0xffffffff)));
    }

    // _isSenderAuthorised()

    function test_isSenderAuthorised_ReturnsTrueForSelf() public {
        vm.prank(authoriser);
        bool senderAuthorised = authorisable.isSenderAuthorised(authoriser);

        assertTrue(senderAuthorised);
    }

    function test_isSenderAuthorised_ReturnsTrueWhenAuthorised() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);

        vm.prank(authorised);
        bool senderAuthorised = authorisable.isSenderAuthorised(authoriser);

        assertTrue(senderAuthorised);
    }

    function test_isSenderAuthorised_ReturnsFalseWhenNotAuthorised() public {
        vm.prank(authorised);
        bool senderAuthorised = authorisable.isSenderAuthorised(authoriser);

        assertFalse(senderAuthorised);
    }

    function test_isSenderAuthorised_ReturnsFalseWhenAuthorisedInReverse() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);

        vm.prank(authoriser);
        bool senderAuthorised = authorisable.isSenderAuthorised(authorised);

        assertFalse(senderAuthorised);
    }

    // _requireSenderAuthorised()

    function test_requireSenderAuthorised_DoesNotRevertWhenAuthorised() public {
        vm.prank(authoriser);
        authorisable.setAuthorisation(authorised, true);

        vm.prank(authorised);
        authorisable.requireSenderAuthorised(authoriser);
    }

    function test_requireSenderAuthorised_RevertsWhenNotAuthorised() public {
        vm.expectRevert(abi.encodeWithSelector(Authorisable.Unauthorised.selector, authoriser, authorised));
        vm.prank(authorised);
        authorisable.requireSenderAuthorised(authoriser);
    }

    function _authorisation(bool isAuthorised, uint256 nonce)
        internal
        view
        returns (IAuthorisable.Authorisation memory)
    {
        return IAuthorisable.Authorisation({
            authoriser: authoriser, authorised: authorised, isAuthorised: isAuthorised, nonce: nonce, deadline: deadline
        });
    }

    function _sign(uint256 privateKey, IAuthorisable.Authorisation memory authorisation)
        internal
        view
        returns (IAuthorisable.Signature memory)
    {
        return _sign(authorisable, privateKey, authorisation);
    }

    /// @dev Hashes the struct with Foundry's EIP-712 encoder rather than `AUTHORISATION_TYPEHASH`, so a wrong typehash
    ///      in the contract fails verification instead of producing a matching wrong digest.
    function _sign(AuthorisableHarness target, uint256 privateKey, IAuthorisable.Authorisation memory authorisation)
        internal
        view
        returns (IAuthorisable.Signature memory)
    {
        bytes32 structHash = vm.eip712HashStruct(AUTHORISATION_TYPE_DEFINITION, abi.encode(authorisation));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", target.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return IAuthorisable.Signature({v: v, r: r, s: s});
    }
}
