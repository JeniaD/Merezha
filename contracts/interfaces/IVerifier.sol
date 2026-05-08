// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVerifier {
    /// @notice Verifies that `result` is a valid answer for a task
    ///         whose verification parameters are `params`.
    function verify(bytes calldata params, bytes calldata result) external view returns (bool);
}
