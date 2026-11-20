// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @notice ERC-3156 receiver that accepts and repays by default, and can be made to misbehave or to put the loan to
///         use by queueing calls to make from within the callback.
contract MockFlashBorrower is IERC3156FlashBorrower {
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    struct Call {
        address target;
        bytes data;
    }

    bytes32 public callbackReturnValue = CALLBACK_SUCCESS;
    bool public approveRepayment = true;
    uint256 public balanceDuringCallback;

    Call[] private _callbackCalls;

    function setCallbackReturnValue(bytes32 callbackReturnValue_) external {
        callbackReturnValue = callbackReturnValue_;
    }

    function setApproveRepayment(bool approveRepayment_) external {
        approveRepayment = approveRepayment_;
    }

    /// @notice Queues a call the borrower makes from within the callback, standing in for whatever the loan is used for.
    function addCallbackCall(address target, bytes calldata data) external {
        _callbackCalls.push(Call({target: target, data: data}));
    }

    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        balanceDuringCallback = IERC20(token).balanceOf(address(this));

        for (uint256 i; i < _callbackCalls.length; ++i) {
            Address.functionCall(_callbackCalls[i].target, _callbackCalls[i].data);
        }

        if (approveRepayment) IERC20(token).approve(msg.sender, amount + fee);

        return callbackReturnValue;
    }
}
