// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

// import "./interfaces/IMultiToken.sol";
// import "./interfaces/IForwarderFactory.sol";
// import "./ERC20Forwarder.sol";
import "./libraries/Authorizable.sol";
import "./Term.sol";
import "./Pool.sol";

// is authorizable
// goverence parameter
// set gov as auth
contract TermRegistery is Authorizable {
    struct TermInfo {
        // sstore
        uint160 termAddress; // address of the term contract
        uint160 poolAddress; // address of the pool contract,
        // sstore
        uint128 expiry; // token id
        uint128 yieldSourceId; // arb identifier i.e. 1 = Yearn, 2 = Compound, etc.

        // maybe principle token address
    }

    // maybe this should be a mapping of (baseAsset, tokenId) hash
    mapping(bytes32 => TermInfo) private _termData;

    //uint256 private _i = 1;

    // uint256[] public terms;

    constructor(address governance) {
        setOwner(governance); // set owner to gov
    }

    function registerTerm(
        Term term,
        uint256 expiry,
        Pool pool,
        uint128 yieldSourceId
    ) public onlyOwner {
        address tokenAddress = address(term.token);

        // todo validate that the term exist in multiterm contract

        bytes32 id = keccak256(abi.encodePacked(tokenAddress, expiry));

        // _termData[id] = TermInfo(term.address, pool.address, expiry, yieldSourceId);

        //termData[_index] = TermInfo(term.address, pool.address, expiry, yieldSourceId);
        // _index += 1;
    }

    // function getTermInfo(uint256 id) public view returns (TermInfo) {
    //     // require(termData[id] != 0, "no term info");

    //     return termData[id];
    // }

    // function deleteTerm(uint256 id) public onlyOwner returns (TermInfo) {
    //     require(termData[id] != 0, "no term info");

    //     delete termData[id];
    // }

    function getAllTerms() public returns (void) {}

    function getPrincipleToken() public returns (void) {}
}
