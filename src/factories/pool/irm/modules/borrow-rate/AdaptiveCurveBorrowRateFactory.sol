// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../../../../abstract/CloneFactory.sol";
import {IVersioned} from "../../../../../interfaces/IVersioned.sol";
import {AdaptiveCurveBorrowRate} from "../../../../../pool/irm/modules/borrow-rate/AdaptiveCurveBorrowRate.sol";

/// @title  AdaptiveCurveBorrowRateFactory
/// @notice Specific Factory that clones and initializes `AdaptiveCurveBorrowRate`.
contract AdaptiveCurveBorrowRateFactory is CloneFactory {
    /// @param implementation `AdaptiveCurveBorrowRate` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "AdaptiveCurveBorrowRate1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        address borrowRateCaller = abi.decode(data, (address));

        AdaptiveCurveBorrowRate(instance).initialize(borrowRateCaller);
    }
}
