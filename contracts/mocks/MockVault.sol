// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
contract MockVault is ERC20, IERC4626 {
    using Math for uint256;
    using PRBMathUD60x18Typed for PRBMath.UD60x18;

    uint256 public apr; // nominal annual interest rate - used to continuosly compound
    uint256 public apy; // real annual interest rate - display purposes only
    uint256 public tick; // time when yield was last accrued
    uint256 public immutable YEAR = 31556926; // Unix year in seconds

    address private _owner;
    MockAsset private immutable _asset;

    uint256 private locked = 1; // Used in reentrancy check.

    constructor(address _receiver) ERC20("MockShareToken", "xMAT") {
        _asset = new MockAsset(1_000_000 ether, _receiver);
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

    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256 shares)
    {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256 assets)
    {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function maxDeposit(address)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _isVaultCollateralized() ? type(uint256).max : 0;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Down);
    }

    function maxRedeem(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    function previewMint(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToShares(assets, Math.Rounding.Up);
    }

    function previewRedeem(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function accrue() public nonReentrant {
        uint256 t = block.timestamp - tick;
        tick = block.timestamp;
        MockAsset(asset()).mint(calcCompoundInterest(totalAssets(), t));
    }

    function updateAPR(uint256 _apr) public onlyOwner {
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

    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        returns (uint256)
    {
        require(
            assets <= maxDeposit(receiver),
            "ERC4626: deposit more than max"
        );
        accrue();
        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        returns (uint256)
    {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        accrue();
        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /** @dev See {IERC4262-withdraw} */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(
            assets <= maxWithdraw(owner),
            "ERC4626: withdraw more than max"
        );

        accrue();
        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /** @dev See {IERC4262-redeem} */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /////////////////////////////////////////////
    //////////   Internal Functions /////////////
    /////////////////////////////////////////////

    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 shares)
    {
        uint256 supply = totalSupply();
        return
            (assets == 0 || supply == 0)
                ? assets.mulDiv(10**decimals(), 10**_asset.decimals(), rounding)
                : assets.mulDiv(supply, totalAssets(), rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 assets)
    {
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? shares.mulDiv(10**_asset.decimals(), 10**decimals(), rounding)
                : shares.mulDiv(totalAssets(), supply, rounding);
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) private {
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) private {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        SafeERC20.safeTransfer(_asset, receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _isVaultCollateralized() private view returns (bool) {
        return totalAssets() > 0 || totalSupply() == 0;
    }

    function _calcAPY() internal view returns (uint256) {
        return
            PRBMath
                .UD60x18({ value: calcCompoundInterest(1 ether, YEAR) })
                .div(PRBMath.UD60x18({ value: 1 ether }))
                .value;
    }
}
