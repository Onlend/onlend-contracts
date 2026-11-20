// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {OracleConsumer} from "src/oracle-consumer/abstract/OracleConsumer.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

contract OracleConsumerHarness is OracleConsumer {
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address oracleUpdater, address initialOracle) external initializer {
        __AccessControlEnumerable_init();
        _initializeOracleConsumer(oracleUpdater, initialOracle);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function oracleValue(IPool pool, uint256 amount, Math.Rounding rounding) external view returns (uint256) {
        return _oracleValue(pool, amount, rounding);
    }
}
