// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "./interfaces/IMultiToken.sol";

// A lite version of a semi fungible, which removes some methods and so
// is not technically a 1155 compliant multi-token semi fungible, but almost
// follows the standard.
// NOTE - We remove on transfer callbacks and safe transfer because of the
//        risk of external calls to untrusted code.

contract MultiToken is IMultiToken {
    // TOOD - Choose to change names to perfect match the 1155 ie adding 'safe',
    //        choose whether to support the batch methods, and to support token uris
    //        or names

    // Allows loading of each balance
    mapping(uint256 => mapping(address => uint256)) public override balanceOf;
    // Allows loading of each total supply
    mapping(uint256 => uint256) public totalSupply;
    // Uniform approval for all tokens
    mapping(address => mapping(address => bool))
        public
        override isApprovedForAll;
    // Additional optional per token approvals
    // Note - non standard for erc1150 but we want to replicate erc20 interface
    mapping(uint256 => mapping(address => mapping(address => uint256)))
        public
        override perTokenApprovals;
    // Sub Token Name and Symbol, created by inheriting contracts
    mapping(uint256 => string) public override name;
    mapping(uint256 => string) public override symbol;
    // Error triggered when the create2 verification fails
    error NonLinkerCaller();

    // The contract which deployed this one
    address public immutable factory;
    // The bytecode hash of the contract which forwards purely erc20 calls
    // to this contract
    bytes32 public immutable linkerCodeHash;

    /// @notice Runs the initial deployment code
    /// @param _linkerCodeHash The hash of the erc20 linker contract deploy code
    /// @param _factory The factory which is used to deploy the linking contracts
    constructor(bytes32 _linkerCodeHash, address _factory) {
        // Set the immutables
        factory = _factory;
        linkerCodeHash = _linkerCodeHash;
    }

    //  Our architecture maintains ERC20 compatibility by allowing the option
    //  of the factory deploying ERC20 compatibility bridges which forward ERC20 calls
    //  to this contract. To maintain trustless deployment they are create2 deployed
    //  with tokenID as salt by the factory, and can be verified by the pre image of
    //  the address.

    /// @notice This modifier checks the caller is the create2 validated ERC20 bridge
    /// @param tokenID The internal token identifier
    modifier onlyLinker(uint256 tokenID) {
        // Get the salt which is used by the deploying contract
        bytes32 salt = keccak256(abi.encode(address(this), tokenID));
        // Preform the hash which determines the address of a create2 deployment
        bytes32 addressBytes = keccak256(
            abi.encodePacked(bytes1(0xff), factory, salt, linkerCodeHash)
        );

        // If the caller does not match the address hash, we revert because it is not
        // allowed to access permission-ed methods.
        if (msg.sender != address(uint160(uint256(addressBytes))))
            revert NonLinkerCaller();
        // Execute the following function
        _;
    }

    /// @notice Transfers an amount of assets from the source to the destination
    /// @param tokenID The token identifier
    /// @param source The address who's balance will be reduced
    /// @param destination The address who's balance will be increased
    /// @param amount The amount of token to move
    function transferFrom(
        uint256 tokenID,
        address source,
        address destination,
        uint256 amount
    ) external override {
        // Forward to our internal version
        _transferFrom(tokenID, source, destination, amount, msg.sender);
    }

    /// @notice Permission-ed transfer for the bridge to access, only callable by
    ///         the ERC20 linking bridge
    /// @param tokenID The token identifier
    /// @param source The address who's balance will be reduced
    /// @param destination The address who's balance will be increased
    /// @param amount The amount of token to move
    /// @param caller The msg.sender from the bridge
    function transferFromBridge(
        uint256 tokenID,
        address source,
        address destination,
        uint256 amount,
        address caller
    ) external override onlyLinker(tokenID) {
        // Route to our internal transfer
        _transferFrom(tokenID, source, destination, amount, caller);
    }

    /// @notice Preforms the actual transfer logic
    /// @param tokenID The token identifier
    /// @param source The address who's balance will be reduced
    /// @param destination The address who's balance will be increased
    /// @param amount The amount of token to move
    /// @param caller The msg.sender either here or in the compatibility link contract
    function _transferFrom(
        uint256 tokenID,
        address source,
        address destination,
        uint256 amount,
        address caller
    ) internal {
        // If ethereum transaction sender is calling no need for further validation
        if (caller != source) {
            // Or if the transaction sender can access all user assets, no need for
            // more validation
            if (!isApprovedForAll[source][caller]) {
                // Finally we load the per asset approval
                uint256 approved = perTokenApprovals[tokenID][source][caller];
                // If it is not an infinite approval
                if (approved != type(uint256).max) {
                    // Then we subtract the amount the caller wants to use
                    // from how much they can use, reverting on underflow.
                    // NOTE - This reverts without message for unapproved callers when
                    //         debugging that's the likely source of any mystery reverts
                    perTokenApprovals[tokenID][source][caller] -= amount;
                }
            }
        }

        // Reaching this point implies the transfer is authorized so we remove
        // from the source and add to the destination.
        balanceOf[tokenID][source] -= amount;
        balanceOf[tokenID][destination] += amount;
    }

    /// @notice Allows a user to approve an operator to use all of their assets
    /// @param _operator The eth address which can access the caller's assets
    /// @param _approved True to approve, false to remove approval
    function setApprovalForAll(address _operator, bool _approved) external {
        // set the appropriate state
        isApprovedForAll[msg.sender][_operator] = _approved;
    }

    /// @notice Allows a user to set an approval for an individual asset with specific amount.
    /// @param tokenID The asset to approve the use of
    /// @param operator The address who will be able to use the tokens
    /// @param amount The max tokens the approved person can use, setting to uint256.max
    ///               will cause the value to never decrement [saving gas on transfer]
    function setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount
    ) external override {
        _setApproval(tokenID, operator, amount, msg.sender);
    }

    /// @notice Allows the compatibility linking contract to forward calls to set asset approvals
    /// @param tokenID The asset to approve the use of
    /// @param operator The address who will be able to use the tokens
    /// @param amount The max tokens the approved person can use, setting to uint256.max
    ///               will cause the value to never decrement [saving gas on transfer]
    /// @param caller The eth address which called the linking contract
    function setApprovalBridge(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) external override onlyLinker(tokenID) {
        _setApproval(tokenID, operator, amount, caller);
    }

    /// @notice internal function to change approvals
    /// @param tokenID The asset to approve the use of
    /// @param operator The address who will be able to use the tokens
    /// @param amount The max tokens the approved person can use, setting to uint256.max
    ///               will cause the value to never decrement [saving gas on transfer]
    /// @param caller The eth address which initiated the approval call
    function _setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) internal {
        perTokenApprovals[tokenID][caller][operator] = amount;
    }

    /// @notice Minting function to create tokens
    /// @param tokenID The asset type to create
    /// @param to The address who's balance to increase
    /// @param amount The number of tokens to create
    /// @dev Must be used from inheriting contracts
    function _mint(
        uint256 tokenID,
        address to,
        uint256 amount
    ) internal {
        balanceOf[tokenID][to] += amount;
        totalSupply[tokenID] += amount;
    }

    /// @notice Burning function to remove tokens
    /// @param tokenID The asset type to remove
    /// @param source The address who's balance to decrease
    /// @param amount The number of tokens to remove
    /// @dev Must be used from inheriting contracts
    function _burn(
        uint256 tokenID,
        address source,
        uint256 amount
    ) internal {
        // Decrement from the source and supply
        balanceOf[tokenID][source] -= amount;
        totalSupply[tokenID] -= amount;
    }

    /// @notice Returns the amount of tokens in existence
    /// @param tokenID The asset to query supply of
    function totalSupply(uint256 tokenID) external view returns (uint256) {
        return totalSupply[tokenID];
    }

    function batchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _values, bytes calldata _data) external {
        require(_from != address(0), "transfer from the zero address");
        require(_to != address(0), "transfer to the zero address");
        require(_ids.length == _values.length, "ids and values length mismatch");

        for (uint256 i = 0; i < _ids.length; i++) {
            _transferFrom(_ids[i], _from, _to, _values[i], msg.sender);
        }
    }
}
