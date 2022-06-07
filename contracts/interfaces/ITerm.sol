// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import "./IMultiToken.sol";

interface ITerm is IMultiToken {
    /// @notice sums inputs to create new PTs and YTs from the deposit amount
    /// @param internalAssets an array of token IDs
    /// @param internalAmounts how much of each asset to burn
    /// @param underlyingAmount The amount of underlying in addition to the internal assets to lock
    /// @param ytDestination The address which gets YT
    /// @param ptDestination The address which gets PT
    /// @param ytBeginDate The start date of the YT created
    /// @param expiration the expiration timestamp
    /// @return a tuple of the number of PTs and YTs created
    function lock(
        uint256[] calldata internalAssets,
        uint256[] calldata internalAmounts,
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
    /// @param destination The address which receives the token released
    /// @param tokenIDs the IDs of the tokens to unlock
    /// @param amount The amount each token to unlock
    /// @return the total value of the tokens that have been unlocked
    function unlock(
        address destination,
        uint256[] calldata tokenIDs,
        uint256[] calldata amount
    ) external returns (uint256);

    function unlockedSharePrice() external returns (uint256);
}
