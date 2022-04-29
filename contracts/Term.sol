// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

contract Term is MultiToken {

    // a mapping of unlock timestamps to number of shares
    mapping(uint256 => uint256) public timestampShares;

	/// @dev sums inputs to create new PTs and YTs from the deposit amount
	/// @param internalAssets an array of token IDs
    /// @param internalAmounts how much of each asset to burn
	/// @param expiration the expiration timestamp
	/// @return a tuple of the number of PT's and YT's created
	function lock(uint256[] internalAssets, uint256[] internalAmount, uint256 underlyingamoutn, uint256 ytBeginDate, uint256 expiration) external returns (uint256, uint256) {
		uint256 totalValue = 0;
        // do special case for index 0 -- totally unlocked

        // do special case for index 1 -- trasferring in the actual asset

		for (uint256 i = 2; i < internalAssets.length; i++) {
            // get the value of the asset and add to the total
			totalValue += internalAssets[i]._getValue();
            // TODO: unsure on input params to burn
            // TODO: probably some kind of balance check?
            burn(internalAssets[i], msg.sender, tokenAmountIn[i]);
		}
        // use the total value to create the yield token
        // the discount is the same thing as the number of YTs created (?)
        uint256 discount = _createYT(msg.sender, totalValue, expiration);
        // use the yield token and the total vlaue to create the principal token (is it principle?)
		uint256 ptsCreated = _createPT(msg.sender, totalValue - discount, expiration);
        // TODO: unsure of the destination inputs on the above two as well
		return (ptsCreated, discount);
	}

    // TODO: what does the general logic for this look like?
    function _getValue(tokenAmountIn) returns (uint256);

    /// @notice creates yield tokens
    /// @param destination the address the YTs belong to
    /// @param value the value of YTs to create
    /// @param expiration the expiration of the term
    /// @return the amount created
	function _createYT(address destination, uint256 value, uint256 expiration) returns (uint256) {
		uint256 id = _createYieldTokenID(block.timestamp, expiration);
        mint(id, destination, value);
        // TODO: shares logic
        // TODO: how do we calculate how many were created?
	}

    /// @notice creates principal tokens
    /// @param destination the address the PTs belong to
    /// @param value the value of the PTs to create
    /// @param expiration  the expiration of the term
    /// @return the amount created
	function _createPT(address destination, uint256 value, uint256 expiration) {
		uint256 id = _createPrincipalTokenID(expiration);
        // TODO: shares logic
        mint(id, destination, value);
	}

    // what did I want to return here?
    // do we need a distinction between destroy PT vs YT?
    function _destroyToken(uint256 tokenID, uint256 amount) returns (theValue) {
        burn(tokenID, amount);
        // TODO: shares logic

	/// @notice creates a YT spanning from current date to the end of the term
    /// @param destination the address to send the tokens to
    /// @param tokenID the ID of the YT to convert
    /// @param amount the amount of YT to convert
	function convertYT(address destination, uint256 tokenID, uint256 amount) external {
		uint256 currentTime = block.timestamp;
		// release earned yield from date to currentTime
        uint256 value = _destroyYT(tokenID, amount);
        uint256 newExpiration = _getExpirationFromID(tokenID);
        // transfer value to destination
        transferFrom(tokenID, msg.sender, destination, amount);
		// create yt that starts at currentTime and ends at the end of the term
        _createYT(destination, amount, newExpiration);
	}

	/// @dev removes all PTs & YTs input
    /// @param destination
	/// @param tokenIDs the IDs of the tokens to unlock
    /// @param amounts the amount of tokens to unlock 
	/// @return the total value of those things that have been unlocked
	function unlock(address destination, uint256[] tokenIDs, uint256[] amounts) external returns (uint256) {
        uint256 totalValue = 0;
		for (uint256 i = 0; i < assets.length; i++) {
			totalValue += asset[i]._getValue(amount);
            _destroyToken(tokenID[i], amount);
            burn(tokenIDs[i], msg.sender, amount);
		}
        // what would be the ID in this case?
        transferFrom(someID, msg.sender, destination, totalValue);
    }

        /// @notice initializes a new term and makes the first deposit
    /// @param expiration the expiration timestamp for the term
    /// @param andotherparams placeholder for other parameters we want for this function
    function initialize(uint256 expiration, uint256 startTime, ) external;
}  
