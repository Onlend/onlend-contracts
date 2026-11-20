// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Authorisable} from "src/authorisation/abstract/Authorisable.sol";
import {IAuthorisable} from "src/authorisation/interfaces/IAuthorisable.sol";
import {AuthorisableHarness} from "./mocks/AuthorisableHarness.sol";

contract AuthorisableFuzzTest is Test {
    string internal constant AUTHORISATION_TYPE_DEFINITION =
        "Authorisation(address authoriser,address authorised,bool isAuthorised,uint256 nonce,uint256 deadline)";
    uint256 internal constant MAX_SUBMISSIONS = 16;

    uint256 internal authoriserKey;
    address internal authoriser;
    address internal authorised;
    address internal relayer;
    AuthorisableHarness internal authorisable;

    function setUp() public {
        (authoriser, authoriserKey) = makeAddrAndKey("authoriser");
        authorised = makeAddr("authorised");
        relayer = makeAddr("relayer");

        AuthorisableHarness implementation = new AuthorisableHarness();
        authorisable = AuthorisableHarness(Clones.clone(address(implementation)));
        authorisable.initialize("AuthorisableHarness", "1");
    }

    // setAuthorisation()

    function testFuzz_setAuthorisation_AuthorisesAccount(address authoriser_, address authorised_) public {
        vm.prank(authoriser_);
        authorisable.setAuthorisation(authorised_, true);

        assertTrue(authorisable.isAuthorised(authoriser_, authorised_));
    }

    function testFuzz_setAuthorisation_RevokesAuthorisation(address authoriser_, address authorised_) public {
        vm.prank(authoriser_);
        authorisable.setAuthorisation(authorised_, true);

        vm.prank(authoriser_);
        authorisable.setAuthorisation(authorised_, false);

        assertFalse(authorisable.isAuthorised(authoriser_, authorised_));
    }

    // setAuthorisationWithSig()

    function testFuzz_setAuthorisationWithSig_AuthorisesAccount(
        uint256 authoriserKey_,
        address authorised_,
        address relayer_
    ) public {
        authoriserKey_ = bound(authoriserKey_, 1, SECP256K1_ORDER - 1);
        address authoriser_ = vm.addr(authoriserKey_);
        IAuthorisable.Authorisation memory authorisation =
            _authorisation(authoriser_, authorised_, true, 0, block.timestamp);
        IAuthorisable.Signature memory signature = _sign(authoriserKey_, authorisation);

        vm.prank(relayer_);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        assertTrue(authorisable.isAuthorised(authoriser_, authorised_));
    }

    function testFuzz_setAuthorisationWithSig_AcceptsSignatureUntilDeadline(uint256 deadline, uint256 timestamp)
        public
    {
        timestamp = bound(timestamp, 0, deadline);
        IAuthorisable.Authorisation memory authorisation = _authorisation(authoriser, authorised, true, 0, deadline);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
        vm.warp(timestamp);

        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);

        assertTrue(authorisable.isAuthorised(authoriser, authorised));
    }

    function testFuzz_setAuthorisationWithSig_RevertsWhenDeadlineHasPassed(uint256 deadline, uint256 timestamp) public {
        deadline = bound(deadline, 0, type(uint256).max - 1);
        timestamp = bound(timestamp, deadline + 1, type(uint256).max);
        IAuthorisable.Authorisation memory authorisation = _authorisation(authoriser, authorised, true, 0, deadline);
        IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(Authorisable.SignatureExpired.selector, deadline));
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function testFuzz_setAuthorisationWithSig_RevertsWhenSignerIsNotAuthoriser(
        uint256 signerKey,
        uint256 authoriserKey_
    ) public {
        authoriserKey_ = bound(authoriserKey_, 1, SECP256K1_ORDER - 1);
        signerKey = bound(signerKey, 1, SECP256K1_ORDER - 1);
        vm.assume(signerKey != authoriserKey_);
        address authoriser_ = vm.addr(authoriserKey_);
        IAuthorisable.Authorisation memory authorisation =
            _authorisation(authoriser_, authorised, true, 0, block.timestamp);
        IAuthorisable.Signature memory signature = _sign(signerKey, authorisation);

        vm.expectRevert(abi.encodeWithSelector(Authorisable.InvalidSigner.selector, vm.addr(signerKey), authoriser_));
        vm.prank(relayer);
        authorisable.setAuthorisationWithSig(authorisation, signature);
    }

    function testFuzz_setAuthorisationWithSig_ConsumesNoncesSequentially(uint256 submissions) public {
        submissions = bound(submissions, 1, MAX_SUBMISSIONS);
        for (uint256 i; i < submissions; ++i) {
            IAuthorisable.Authorisation memory authorisation =
                _authorisation(authoriser, authorised, true, i, block.timestamp);
            IAuthorisable.Signature memory signature = _sign(authoriserKey, authorisation);
            vm.prank(relayer);
            authorisable.setAuthorisationWithSig(authorisation, signature);
        }

        assertEq(authorisable.nonces(authoriser), submissions);
    }

    // _isSenderAuthorised()

    function testFuzz_isSenderAuthorised_ReturnsTrueForSelf(address account) public {
        vm.prank(account);
        bool senderAuthorised = authorisable.isSenderAuthorised(account);

        assertTrue(senderAuthorised);
    }

    function testFuzz_isSenderAuthorised_ReturnsFalseWhenNotAuthorised(address caller, address onBehalfOf) public {
        vm.assume(caller != onBehalfOf);

        vm.prank(caller);
        bool senderAuthorised = authorisable.isSenderAuthorised(onBehalfOf);

        assertFalse(senderAuthorised);
    }

    function _authorisation(
        address authoriser_,
        address authorised_,
        bool isAuthorised,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (IAuthorisable.Authorisation memory) {
        return IAuthorisable.Authorisation({
            authoriser: authoriser_,
            authorised: authorised_,
            isAuthorised: isAuthorised,
            nonce: nonce,
            deadline: deadline
        });
    }

    /// @dev Hashes the struct with Foundry's EIP-712 encoder rather than `AUTHORISATION_TYPEHASH`, so a wrong typehash
    ///      in the contract fails verification instead of producing a matching wrong digest.
    function _sign(uint256 privateKey, IAuthorisable.Authorisation memory authorisation)
        internal
        view
        returns (IAuthorisable.Signature memory)
    {
        bytes32 structHash = vm.eip712HashStruct(AUTHORISATION_TYPE_DEFINITION, abi.encode(authorisation));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", authorisable.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return IAuthorisable.Signature({v: v, r: r, s: s});
    }
}
