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
    /// @param shareReserves yield bearing vault shares reserve amount
    /// @param bondReserves bond reserves amount
    /// @param totalSupply total supply amount
    /// @param amountIn amount to be traded
    /// @param t time till maturity in seconds
    /// @param s time stretch coefficient.  e.g. 25 years in seconds
    /// @param c price of shares in terms of their base
    /// @param mu Normalization factor -- starts as c at initialization
    /// @param isBondOut determines if the output is bond or shares
    /// @return result the amount of shares a user would get for given amount of bond
    function calculateOutGivenIn(
        UFixedPoint shareReserves,
        UFixedPoint bondReserves,
        UFixedPoint totalSupply,
        UFixedPoint amountIn,
        UFixedPoint t,
        UFixedPoint s,
        UFixedPoint c,
        UFixedPoint mu,
        bool isBondOut
    ) internal pure returns (UFixedPoint result) {
        UFixedPoint outReserves;
        UFixedPoint rhs;
        // Notes: 1 >= 1-st >= 0
        UFixedPoint oneMinusT = TypedFixedPointMathLib.ONE_18.sub(s.mulDown(t));
        // c/mu
        UFixedPoint cDivMu = c.divDown(mu);
        // (mu*shareReserves)^(1-t)
        UFixedPoint scaledShareReserves = mu.mulDown(shareReserves).pow(
            oneMinusT
        );
        UFixedPoint modifiedBondReserves = bondReserves.add(totalSupply);

        if (isBondOut) {
            // bondOut = bondReserves - ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu*(shareReserves + shareIn))^(1-t) )^(1 / (1 - t))
            outReserves = modifiedBondReserves;
            // c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t)
            UFixedPoint k = cDivMu.mulDown(scaledShareReserves).add(
                modifiedBondReserves.pow(oneMinusT)
            );
            // (mu*(shareReserves + amountIn))^(1-t)
            UFixedPoint newScaledShareReserves = mu
                .mulDown(shareReserves.add(amountIn))
                .pow(oneMinusT);
            // c/mu * (mu*(shareReserves + amountIn))^(1-t)
            newScaledShareReserves = cDivMu.mulDown(newScaledShareReserves);
            // Notes: k - newScaledShareReserves >= 0 to avoid a complex number
            // ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu*(shareReserves + amountIn))^(1-t) )^(1 / (1 - t))
            rhs = k.sub(newScaledShareReserves).pow(
                TypedFixedPointMathLib.ONE_18.divDown(oneMinusT)
            );
        } else {
            // shareOut = shareReserves - [ ( c/mu * (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves + bondIn)^(1-t) ) / c/u  ]^(1 / (1 - t)) / mu
            outReserves = shareReserves;
            // c/mu * (mu*shareReserves)^(1-t)
            scaledShareReserves = cDivMu.mulDown(scaledShareReserves);
            // c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t)
            UFixedPoint k = scaledShareReserves.add(
                modifiedBondReserves.pow(oneMinusT)
            );
            // (bondReserves + bondIn)^(1-t)
            UFixedPoint newScaledBondReserves = modifiedBondReserves
                .add(amountIn)
                .pow(oneMinusT);
            // Notes: k - newScaledBondReserves >= 0 to avoid a complex number
            // [( (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves + bondIn)^(1-t) ) / c/u ]^(1 / (1 - t))
            rhs = k.sub(newScaledBondReserves).divDown(cDivMu).pow(
                TypedFixedPointMathLib.ONE_18.divDown(oneMinusT)
            );
            // [( (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves + bondIn)^(1-t) ) / c/u ]^(1 / (1 - t)) / mu
            rhs = rhs.divDown(mu);
        }
        // Notes: outReserves - rhs >= 0, but i think avoiding a complex number in the step above ensures this never happens
        result = outReserves.sub(rhs);
    }
}
