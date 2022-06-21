// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

interface IMultiToken {
    function name(uint256 id) external view returns (string memory);

    function symbol(uint256 id) external view returns (string memory);

    function isApprovedForAll(address owner, address spender)
        external
        view
        returns (bool);

    function perTokenApprovals(
        uint256 tokenId,
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(uint256 tokenId, address owner)
        external
        view
        returns (uint256);

    function transferFrom(
        uint256 tokenID,
        address source,
        address destination,
        uint256 amount
    ) external;

    function transferFromBridge(
        uint256 tokenID,
        address source,
        address destination,
        uint256 amount,
        address caller
    ) external;

    function setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount
    ) external;

    function setApprovalBridge(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) external;

    function totalSupply(uint256 id) external view returns (uint256);
}
