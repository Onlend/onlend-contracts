// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Authorisable} from "src/authorisation/abstract/Authorisable.sol";

contract AuthorisableHarness is Authorisable {
    constructor() {
        _disableInitializers();
    }

    function initialize(string calldata name, string calldata version) external initializer {
        _initializeAuthorisable(name, version);
    }

    function isSenderAuthorised(address onBehalfOf) external view returns (bool) {
        return _isSenderAuthorised(onBehalfOf);
    }

    function requireSenderAuthorised(address onBehalfOf) external view {
        _requireSenderAuthorised(onBehalfOf);
    }
}
