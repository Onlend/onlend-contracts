// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Exposes only the ERC-4626 subset read by the VAULT_SHARE_PRICE node. `rate` is the amount of asset base units
///      one whole share converts to, and `convertToAssets` rounds down like a real vault. Share decimals are set
///      independently of the asset's, so a decimals offset is modelled by setting them higher.
contract MockERC4626Vault {
    bool public shouldRevertOnDecimals;
    bool public shouldRevertOnAsset;
    bool public shouldRevertOnConvertToAssets;

    address private _asset;
    uint8 private _decimals;
    uint256 private _rate;

    error DecimalsReverted();
    error AssetReverted();
    error ConvertToAssetsReverted();

    constructor(address asset_, uint8 decimals_, uint256 rate) {
        _asset = asset_;
        _decimals = decimals_;
        _rate = rate;
    }

    function setAsset(address asset_) external {
        _asset = asset_;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setRate(uint256 rate) external {
        _rate = rate;
    }

    function setShouldRevertOnDecimals(bool value) external {
        shouldRevertOnDecimals = value;
    }

    function setShouldRevertOnAsset(bool value) external {
        shouldRevertOnAsset = value;
    }

    function setShouldRevertOnConvertToAssets(bool value) external {
        shouldRevertOnConvertToAssets = value;
    }

    function decimals() external view returns (uint8) {
        if (shouldRevertOnDecimals) revert DecimalsReverted();
        return _decimals;
    }

    function asset() external view returns (address) {
        if (shouldRevertOnAsset) revert AssetReverted();
        return _asset;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (shouldRevertOnConvertToAssets) revert ConvertToAssetsReverted();
        return Math.mulDiv(shares, _rate, 10 ** _decimals);
    }
}
