// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

contract MockERC4626Pool {
    uint256 public totalAssets_;
    uint256 public totalSupply_;

    function setExchangeRate(uint256 totalAssets, uint256 totalSupply) external {
        totalAssets_ = totalAssets;
        totalSupply_ = totalSupply;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (totalSupply_ == 0) return shares;
        return (shares * totalAssets_) / totalSupply_;
    }
}
