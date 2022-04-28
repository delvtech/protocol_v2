// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

interface ITerm {

    // TODO: had a param for tokenAmountIn but I think that was leftover code that we don't want anymore
    /// @notice sums inputs to create new PTs and YTs from the deposit amount
	/// @param internalAssets an array of token IDs
    /// @param internalAmounts how much of each asset to burn
	/// @param expiration the expiration timestamp
	/// @return a tuple of the number of PTs and YTs created
    function lock(uint256[] internalAmount, uint256[] internalAssets, uint256 expiration) external returns (uint256, uint256);

    /// @notice creates a YT spanning from current date to the end of the term
    /// @param destination the address to send the tokens to
    /// @param tokenID the ID of the YT to convert
    /// @param amount the amount of YT to convert
    function convertYT(address destination, uint256 tokenID, uint256 amount) external;

    /// @notice removes all PTs and YTS input
	/// @param tokenIDs the IDs of the tokens to unlock
	/// @return the total value of the tokens that have been unlocked
	function unlock(address destination, uint256[] tokenIDs, uint256 amount) external returns (uint256);

    /// @notice creates a YT from timestamp 0 to timestamp 0
    function unlockedExposure() external;

    /// @notice initializes a new term and makes the first deposit
    /// @param expiration the expiration timestamp for the term
    /// @param andotherparams placeholder for other parameters we want for this function
    function initializeTerm(uint256 expiration, string andotherparams) external;
}
