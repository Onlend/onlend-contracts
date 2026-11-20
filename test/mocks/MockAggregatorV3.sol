// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAggregatorV3} from "src/oracle/node-manager/interfaces/external/IAggregatorV3.sol";

contract MockAggregatorV3 is IAggregatorV3 {
    bool public shouldRevertOnDecimals;
    bool public shouldRevertOnLatestRoundData;

    uint8 private _decimals;
    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    error DecimalsReverted();
    error LatestRoundDataReverted();

    /// @dev Seeds round 1 as complete, started and answered in the same round.
    constructor(uint8 decimals_, int256 answer, uint256 updatedAt) {
        _decimals = decimals_;
        _roundId = 1;
        _answer = answer;
        _startedAt = updatedAt;
        _updatedAt = updatedAt;
        _answeredInRound = 1;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setAnswer(int256 answer, uint256 updatedAt) external {
        _answer = answer;
        _updatedAt = updatedAt;
    }

    function setRoundData(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
        external
    {
        _roundId = roundId;
        _answer = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function setShouldRevertOnDecimals(bool value) external {
        shouldRevertOnDecimals = value;
    }

    function setShouldRevertOnLatestRoundData(bool value) external {
        shouldRevertOnLatestRoundData = value;
    }

    function decimals() external view returns (uint8) {
        if (shouldRevertOnDecimals) revert DecimalsReverted();
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (shouldRevertOnLatestRoundData) revert LatestRoundDataReverted();
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
}
