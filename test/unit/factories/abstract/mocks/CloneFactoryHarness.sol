// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "src/factories/abstract/CloneFactory.sol";

contract CloneFactoryHarness is CloneFactory {
    constructor(address implementation) CloneFactory(implementation) {}

    function contractName() external pure returns (string memory name_) {
        return "CloneFactoryHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {}
}
