// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {FactoryRegistry} from "src/factories/abstract/FactoryRegistry.sol";

contract FactoryRegistryHarness is FactoryRegistry {
    constructor(address owner_) FactoryRegistry(owner_) {}

    function exposedClone(address cloneFactory_, bytes32 salt, bytes calldata data) external returns (address) {
        return _clone(cloneFactory_, salt, data);
    }

    function contractName() external pure returns (string memory name_) {
        return "FactoryRegistryHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }
}
