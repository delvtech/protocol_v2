// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.12;

import "../YieldAdapter.sol";
import "../interfaces/IERC4626.sol";
import "../interfaces/IERC20.sol";
import "hardhat/console.sol";
import "@prb/math/contracts/PRBMathUD60x18Typed.sol";

contract ERC4626Adapter is YieldAdapter {
    using PRBMathUD60x18Typed for PRBMath.UD60x18;

    // The ERC4626 vault the protocol wishes to interface with
    IERC4626 public immutable vault;

    // These variables store the token balances of this contract and
    // should be packed by solidity into a single slot.
    uint128 public reserveUnderlying;
    uint128 public reserveShares;

    uint256 public rate;

    uint256 public immutable SCALE;

    // The reserve limit is a upper bound for deposits and withdrawals which
    // if not met, will make those deposits and withdrawals using the internal
    // cash reserves
    // uint256 public immutable reserveLimit;

    // This is the total amount of reserve deposits
    // uint256 public reserveSupply;

    constructor(IERC4626 _vault, uint256 _reserveLimit) {
        vault = _vault;
        //reserveLimit = _reserveLimit;

        SCALE = 10**IERC20(_vault.asset()).decimals();
        rate = 10**(SCALE - 2); // 0.01
        IERC20(_vault.asset()).approve(address(_vault), type(uint256).max);
    }

    /// @notice Makes deposit into vault
    function _deposit(ShareState _state)
        internal
        override
        returns (uint256, uint256)
    {
        // load the current cash reserves of both underlying and shares
        (uint256 localUnderlying, uint256 localShares) = _getReserves();

        // Get the amount deposited
        uint256 amount =
            IERC20(vault.asset()).balanceOf(address(this)) -
            localUnderlying;

        // If state is locked, we deposit directly and just account for
        // change in shares
        if (_state == ShareState.Locked) {
            uint256 shares = vault.deposit(amount, address(this));
            _setReserves(localUnderlying, localShares + shares);
            return (amount, shares);
        }

        // UNLOCKED

        // calculate the expected shares
        uint256 neededShares = vault.previewDeposit(amount);

        // if localShares covers the amount of shares needed, we don't make the
        // deposit in the vault
        if (localShares > neededShares) {
            // We add the deposited amount to the underlying reserve and
            // remove the desired shares from the shares reserve
            _setReserves(localUnderlying + amount, localShares - neededShares);

            return (amount, neededShares);
        }

        // Deposit both the deposited amount and the underlying reserve
        // into the vault and mint all back to this contract
        uint256 shares = vault.deposit(localUnderlying + amount, address(this));

        // For deposits greater than share reserves we take a percentage cut
        // on the portion greater than localUnderlying which is used to fill
        // cash reserves
        uint256 userShare = amount -
            ((rate * (amount - localUnderlying)) / SCALE);

        // set the reserves
        _setReserves(0, localShares + shares - userShare);

        // return the amount deposited and the shares the user received
        return (amount, userShare);
    }

    // check if funds
    // cache old yearn price or read directly
    //
    // The current underlying is added to the value of all yearn shares
    // in the unlocked series. Shares are minted for the user according
    // to the price implied by that total value divided by the total
    // supply of unlocked shares. The underlying is not deposited, but a
    // check is made that the balance of uninvested token is not more
    // than a max univested token constant. If it is a deposit to the
    // 4626 vault is triggered so that the reserve has a
    // ‘goal_uninvested’ constant amount of underlying left.
    // underlying is added to the value of all shares
    // uint256 totalUnlockShares = unlockShares + amountUnderlying;
    // uint256 price = (unlockShares + amountUnderlying / unlockShares);
    // shares = amountUnderlying * price;
    // unlockShares += (shares + amountUnderlying);
    // // shares are "minted"
    // shares = amountUnderlying *
    // function _reserveDeposit(ShareState _state)
    //     internal
    //     override
    //     returns (uint256 amountUnderlying, uint256 shares)
    // {
    //     IERC20(_vault.asset()).transferFrom(msg.sender, address(this), );
    // }

    function _withdraw(
        uint256 _amountShares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256 amountAssets) {
        if (_state == ShareState.Unlocked) {
            // todo
            amountAssets = 0;
        } else {
            amountAssets = vault.redeem(_amountShares, _dest, address(this));
        }
    }

    function _convert(ShareState, uint256) internal override returns (uint256) {
        return 0;
    }

    // TODO rename sharesForUnderlying and also provide inverse function
    // underlyingForShares
    function _underlying(uint256 _amountShares, ShareState)
        internal
        view
        override
        returns (uint256)
    {
        return vault.previewRedeem(_amountShares);
    }

    /// @notice Helper to get the reserves with one sload
    /// @return Tuple (reserve underlying, reserve shares)
    function _getReserves() internal view returns (uint256, uint256) {
        return (uint256(reserveUnderlying), uint256(reserveShares));
    }

    /// @notice Helper to set reserves using one sstore
    /// @param _newReserveUnderlying The new reserve of underlying
    /// @param _newReserveShares The new reserve of wrapped position shares
    function _setReserves(
        uint256 _newReserveUnderlying,
        uint256 _newReserveShares
    ) internal {
        reserveUnderlying = uint128(_newReserveUnderlying);
        reserveShares = uint128(_newReserveShares);
    }
}
