/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

library ElementUtils {
    /// @notice Encodes the Yield Token identifier from a start date and end date
    /// @param startDate The starting timestamp
    /// @param expirationDate The ending timestampa
    function encodeYieldTokenId(uint256 startDate, uint256 expirationDate)
        public
        pure
        returns (uint256)
    {
        return (1 << 255) + (startDate << 128) + expirationDate;
    }

    /// @notice Decodes an unknown assetId into either a YT or PT and gives the
    ///         relevant time paramaters
    /// @param assetId A YT or PT id
    function decodeAssetId(uint256 assetId)
        public
        pure
        returns (
            bool isYieldToken,
            uint256 startDate,
            uint256 expirationDate
        )
    {
        isYieldToken = assetId >> 255 == 1;
        if (isYieldToken) {
            startDate = ((assetId) & (2**255 - 1)) >> 128;
            expirationDate = assetId & (2**(128) - 1);
        } else {
            expirationDate = assetId;
        }
    }
}
