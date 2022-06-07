// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

interface ITerm {
    /// @notice sums inputs to create new PTs and YTs from the deposit amount
    /// @param internalAmount how much of each asset to burn
    /// @param internalAssets an array of token IDs
    /// @param expiration the expiration timestamp
    /// @return a tuple of the number of PTs and YTs created
    function lock(
        uint256[] memory internalAmount,
        uint256[] memory internalAssets,
        uint256 underlyingAmount,
        address ytDestination,
        address ptDestination,
        uint256 ytBeginDate,
        uint256 expiration
    ) external returns (uint256, uint256);

    /// @notice creates a YT spanning from current date to the end of the term
    /// @param destination the address to send the tokens to
    /// @param tokenID the ID of the YT to convert
    /// @param amount the amount of YT to convert
    function convertYT(
        address destination,
        uint256 tokenID,
        uint256 amount
    ) external;

    /// @notice removes all PTs and YTS input
    /// @param destination the address to send unlocked tokens to
    /// @param tokenIDs the IDs of the tokens to unlock
    /// @param amount the amount to unlock
    /// @return the total value of the tokens that have been unlocked
    function unlock(
        address destination,
        uint256[] memory tokenIDs,
        uint256[] memory amount
    ) external returns (uint256);
}
