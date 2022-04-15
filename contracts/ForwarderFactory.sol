// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "./interfaces/IMultiToken.sol";
import "./interfaces/IForwarderFactory.sol";
import "./ERC20Forwarder.sol";

contract ForwarderFactory is IForwarderFactory {
    // Our multi token contract stores many internal ERC20 like tokens, in order
    // to maintain ERC20 compatibility we can deploy interfaces which are ERC20s.
    // This factory deploys them using create2 so that the multi token can do cheap
    // verification of the interfaces before they access sensitive functions.

    // The transient state variables used in deployment
    // Note - It saves us a bit of gas to not fully zero them at any point
    IMultiToken token = IMultiToken(address(1));
    uint256 tokenId = 1;

    // For reference
    bytes32 public constant ERC20LINK_HASH =
        keccak256(type(ERC20Forwarder).creationCode);

    constructor() {}

    /// @notice Uses create2 to deploy a forwarder at a predictable address as part of
    ///         our ERC20 multitoken implementation.
    /// @param _token The multitoken which the forwarder should link to
    /// @param _tokenId The id of the sub token from the multitoken which we are creating
    ///                 an interface for.
    /// @return returns the address of the deployed forwarder
    function create(IMultiToken _token, uint256 _tokenId)
        external
        returns (ERC20Forwarder)
    {
        // Set the transient state variables before deploy
        tokenId = _tokenId;
        token = _token;
        // The salt is the _tokenId hashed with the multi token
        bytes32 salt = keccak256(abi.encode(_token, _tokenId));
        // Deploy using create2 with that salt
        ERC20Forwarder deployed = new ERC20Forwarder{ salt: salt }();
        // As a consistency check we check that this is in the right address
        assert(address(deployed) == getForwarder(_token, _tokenId));
        // Reset the transient state
        token = IMultiToken(address(1));
        tokenId = 1;
        // return the deployed forwarder
        return (deployed);
    }

    /// @notice Returns the transient storage of this contract
    /// @return Returns the stored multitoken address and the sub token id
    function getDeployDetails() external view returns (IMultiToken, uint256) {
        return (token, tokenId);
    }

    /// @notice Helper to calculate expected forwarder contract addresses
    /// @param _token The multitoken which the forwarder should link to
    /// @param _tokenId The id of the sub token from the multitoken
    /// @return The expected address of the forwarder
    function getForwarder(IMultiToken _token, uint256 _tokenId)
        public
        view
        returns (address)
    {
        // Get the salt and hash to predict the address
        bytes32 salt = keccak256(abi.encode(_token, _tokenId));
        bytes32 addressBytes = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, ERC20LINK_HASH)
        );
        // Beautiful type safety from the solidity language
        return address(uint160(uint256(addressBytes)));
    }
}
