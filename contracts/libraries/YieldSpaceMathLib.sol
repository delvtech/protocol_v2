/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/libraries/Errors.sol";
import "contracts/libraries/TypedFixedPointMathLib.sol";
import "hardhat/console.sol";

/// @notice YieldSpace math library.
/// @author Element Finance
library YieldSpaceMathLib {
    using TypedFixedPointMathLib for UFixedPoint;

    /// Calculates the amount of bond a user would get for given amount of shares.
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param bondReserves bond reserves amount
    /// @param totalSupply total supply amount
    /// @param shareIn shares amount to be traded
    /// @param t time till maturity in seconds
    /// @param s time stretch coefficient.  e.g. 25 years in seconds
    /// @param c price of shares in terms of their base
    /// @param mu Normalization factor -- starts as c at initialization
    /// @return result the amount of bond a user would get for given amount of shares
    function calculateBondOutGivenShareIn(
        UFixedPoint shareReserves,
        UFixedPoint bondReserves,
        UFixedPoint totalSupply,
        UFixedPoint shareIn,
        UFixedPoint t,
        UFixedPoint s,
        UFixedPoint c,
        UFixedPoint mu
    ) internal view returns (UFixedPoint result) {
        // bondOut = bondReserves - ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu * shareReserves + mu * shareIn)^(1-t) )^(1 / (1 - t))

        // Notes: 1 >= 1-st >= 0
        UFixedPoint oneMinusT = TypedFixedPointMathLib.ONE_18.sub(s.mulDown(t));
        // c/mu
        UFixedPoint cDivMu = c.divDown(mu);
        // (mu*shareReserves)^(1-t)
        UFixedPoint scaledShareReserves = mu.mulDown(shareReserves).pow(
            oneMinusT
        );
        // c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t)
        UFixedPoint k = cDivMu.mulDown(scaledShareReserves).add(
            bondReserves.add(totalSupply).pow(oneMinusT)
        );
        // (mu * shareReserves + mu * shareIn)^(1-t)
        UFixedPoint newScaledShareReserves = mu
            .mulDown(shareReserves)
            .add(mu.mulDown(shareIn))
            .pow(oneMinusT);
        // c/mu * (mu * shareReserves + mu * shareIn)^(1-t)
        //newScaledShareReserves = TypedFixedPointMathLib.mulDown(cDivMu,TypedFixedPointMathLib.pow(newScaledShareReserves,oneMinusT));
        newScaledShareReserves = cDivMu.mulDown(newScaledShareReserves);
        // Notes: k - newScaledShareReserves >= 0 to avoid a complex number
        // ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu * shareReserves + mu * shareIn)^(1-t) )^(1 / (1 - t))
        result = k.sub(newScaledShareReserves).pow(
            TypedFixedPointMathLib.ONE_18.divDown(oneMinusT)
        );
        // Notes: bondReserves - result >= 0, but i think avoiding a complex number ini the step above ensures this never happens
        result = bondReserves.add(totalSupply).sub(result);
    }

    /// Calculates the amount of bond a user would get for given amount of shares.
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param bondReserves bond reserves amount
    /// @param totalSupply total supply amount
    /// @param bondIn shares amount to be traded
    /// @param t time till maturity in seconds
    /// @param s time stretch coefficient.  e.g. 25 years in seconds
    /// @param c price of shares in terms of their base
    /// @param mu Normalization factor -- starts as c at initialization
    /// @return result the amount of shares a user would get for given amount of bond
    function calculateShareOutGivenBondIn(
        UFixedPoint shareReserves,
        UFixedPoint bondReserves,
        UFixedPoint totalSupply,
        UFixedPoint bondIn,
        UFixedPoint t,
        UFixedPoint s,
        UFixedPoint c,
        UFixedPoint mu
    ) internal pure returns (UFixedPoint result) {
        // shareOut = shareReserves - 1/mu( (mu * shareReserves)^(1-t) + mu/c * bondReserves^(1-t) -  mu/c * (bondReserves + bondIn)^(1-t) )^(1 / (1 - t))

        // Notes: 1 >= 1-st >= 0
        UFixedPoint oneMinusT = TypedFixedPointMathLib.ONE_18.sub(s.mulDown(t));
        // mu/c
        UFixedPoint muDivC = mu.divDown(c);
        // (mu*shareReserves)^(1-t)
        UFixedPoint scaledShareReserves = mu.mulDown(shareReserves).pow(
            oneMinusT
        );
        // (mu * shareReserves)^(1-t) + mu/c * bondReserves^(1-t)
        UFixedPoint k = scaledShareReserves.add(
            muDivC.mulDown(bondReserves.add(totalSupply).pow(oneMinusT))
        );
        // (bondReserves + bondIn)^(1-t)
        UFixedPoint newScaledBondReserves = bondReserves
            .add(totalSupply)
            .add(bondIn)
            .pow(oneMinusT);
        // mu/c * (bondReserves + bondIn)^(1-t)
        newScaledBondReserves = muDivC.mulDown(newScaledBondReserves);
        // Notes: k - newScaledBondReserves >= 0 to avoid a complex number
        // ( (mu * shareReserves)^(1-t) + mu/c * bondReserves^(1-t) -  mu/c * (bondReserves + bondIn)^(1-t) )^(1 / (1 - t))
        result = k.sub(newScaledBondReserves).pow(
            TypedFixedPointMathLib.ONE_18.divDown(oneMinusT)
        );
        // 1/mu( (mu * shareReserves)^(1-t) + mu/c * bondReserves^(1-t) -  mu/c * (bondReserves + bondIn)^(1-t) )^(1 / (1 - t))
        result = TypedFixedPointMathLib.ONE_18.divDown(mu).mulDown(result);
        // Notes: shareReserves - result >= 0, but i think avoiding a complex number ini the step above ensures this never happens
        result = shareReserves.sub(result);
    }
}
