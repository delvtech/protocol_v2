// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/ERC20/extensions./ERC20TokenizedVault.sol";
import "./MockAsset.sol";
import "@prb/math/contracts/PRBMathUD60x18Typed.sol";
import "hardhat/console.sol";

/// USED FOR TESTING: ** UNSAFE **
///
/// Intention here is to provide a single instance contract which can generalise
/// an external yield source and provide a mechanism for generalising yield
/// accrual in isolation when testing interior protocol logic.
///
/// Yield is accrued linearly ad inifinitum according to an asset per second
/// issuance rate which is intended to be easily manipulable by convenience
/// helper functions.
///
///
/// The MockVault itself is the owner of the MockAsset token and
/// will simulate yield accrual by directly minting new MockAsset tokens
/// into the vault at a continuous compounding nominal interest rate defined by
/// the variable `apr`.
///
contract MockVault is ERC20TokenizedVault {
    using PRBMathUD60x18Typed for PRBMath.UD60x18;

    uint256 public apr; // nominal annual interest rate - used to continuosly compound
    uint256 public apy; // real annual interest rate - display purposes only
    uint256 public tick; // time when yield was last accrued
    uint256 public immutable YEAR = 31556926; // Unix year in seconds

    address private _owner;
    MockAsset private immutable _asset;

    uint256 private locked = 1; // Used in reentrancy check.

    constructor(address _receiver)
        ERC20("MockShareToken", "xMAT")
        ERC20TokenizedVault(new MockAsset(1_000_000 ether, _receiver))
    {
        _owner = msg.sender;
        tick = block.timestamp;
        updateAPR(0.05 ether);
    }

    modifier nonReentrant() {
        require(locked == 1, "locked");
        locked = 2;
        _;
        locked = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Sender not owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    // function accrue() public nonReentrant() {
    //     uint256 t = block.timestamp - tick;
    //     console.log("time since last tick: %s", t);
    //     tick = block.timestamp;
    //     MockAsset(asset()).mint(calcCompoundInterest(totalAssets(), t));
    // }

    function updateAPR(uint256 _apr) public onlyOwner() {
        accrue(); // accrue interest up until current block
        apr = _apr;
        apy = _calcAPY();
    }

    /// principal * e ^ (rate * time)
    function calcCompoundInterest(uint256 _principal, uint256 _time)
        public
        view
        returns (uint256)
    {
        PRBMath.UD60x18 memory interestRatePerSecond = PRBMath
            .UD60x18({ value: apr })
            .div(PRBMath.UD60x18({ value: YEAR * 10**18 }));

        uint256 newPrincipal = PRBMathUD60x18Typed
            .e()
            .pow(
                PRBMath.UD60x18({ value: interestRatePerSecond.value * _time })
            )
            .mul(PRBMath.UD60x18({ value: _principal }))
            .value;

        return newPrincipal - _principal;
    }

    function _calcAPY() internal view returns (uint256) {
        return
            PRBMath
                .UD60x18({ value: calcCompoundInterest(1 ether, YEAR) })
                .div(PRBMath.UD60x18({ value: 1 ether }))
                .value;
    }
}
