// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "./MultiToken.sol";
import "./interfaces/IYieldSource.sol";
import "./interfaces/ITerm.sol";

contract Term is ITerm, MultiToken, IYieldSource {
    // a mapping of unlock timestamps to number of shares
    mapping(uint256 => uint256) public timestampShares;

    /// @notice Runs the initial deployment code
    /// @param _linkerCodeHash The hash of the erc20 linker contract deploy code
    /// @param _factory The factory which is used to deploy the linking contracts
    constructor(bytes32 _linkerCodeHash, address _factory)
        MultiToken(_linkerCodeHash, _factory)
    {}

    /// @dev sums inputs to create new PTs and YTs from the deposit amount
    /// @param internalAssets an array of token IDs
    /// @param internalAmounts how much of each asset to burn
    /// @param underlyingAmount,
    /// @param ytDestination the address to mint the YTs to
    /// @param ptDestination the address to mint the PTs to
    /// @param ytBeginDate the start timestamp of the YTs
    /// @param expiration the expiration timestamp
    /// @return a tuple of the number of PT's and YT's created
    function lock(
        uint256[] memory internalAssets,
        uint256[] memory internalAmounts,
        uint256 underlyingAmount,
        address ytDestination,
        address ptDestination,
        uint256 ytBeginDate,
        uint256 expiration
    ) external returns (uint256, uint256) {
        uint256 totalValue = 0;

        // todo: special case for index 0, 1
        for (uint256 i = 2; i < internalAssets.length; i++) {
            // get the value of the asset and add to the total
            totalValue += _getTokenValue(internalAmounts[i]);
            // burn the specified amount
            _burn(internalAssets[i], msg.sender, internalAmounts[i]);
        }

        // use the total value to create the yield tokens
        uint256 discount = _createYT(
            ytDestination,
            totalValue,
            ytBeginDate,
            expiration
        );
        // use the YT discount to create the principal tokens
        uint256 ptsCreated = _createPT(
            ptDestination,
            totalValue - discount,
            expiration
        );

        return (ptsCreated, discount);
    }

    /// @notice removes all PTs and YTS input
    /// @param destination the address to send unlocked tokens to
    /// @param tokenIDs the IDs of the tokens to unlock
    /// @param amount the amount to unlock
    /// @return the total value of the tokens that have been unlocked
    function unlock(
        address destination,
        uint256[] memory tokenIDs,
        uint256[] memory amount
    ) external returns (uint256) {}

    /// @notice gets the actual value of the input number of tokens
    /// @param tokenAmount the amount of tokens to retrieve the value of
    /// @return the value of the tokens
    function _getTokenValue(uint256 tokenAmount) internal returns (uint256) {}

    /// @notice creates yield tokens
    /// @param destination the address the YTs belong to
    /// @param value the value of YTs to create
    /// @param expiration the expiration of the term
    /// @return the amount created
    function _createYT(
        address destination,
        uint256 value,
        uint256 startDate,
        uint256 expiration
    ) internal returns (uint256) {}

    /// @notice creates principal tokens
    /// @param destination the address the PTs belong to
    /// @param value the value of the PTs to create
    /// @param expiration  the expiration of the term
    /// @return the amount created
    function _createPT(
        address destination,
        uint256 value,
        uint256 expiration
    ) internal returns (uint256) {}

    /// TODO: below functions are from Yield Source interface that is still WIP
    function deposit() external returns (uint256, uint256) {}

    function withdraw(
        uint256,
        address,
        uint256
    ) external returns (uint256) {}

    /// @return The amount of underlying the input is worth
    function underlying(uint256) external view returns (uint256) {}
}
