/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./FixedPointMathLib.sol";

type UFixedPoint is uint256;

/// @notice A typed fixed-point math library.
/// @author Element Finance
library TypedFixedPointMathLib {
    uint256 internal constant _ONE_18 = 1e18; // The scalar of ETH and most ERC20s.
    UFixedPoint public constant ONE_18 = UFixedPoint.wrap(_ONE_18);

    function add(UFixedPoint a, UFixedPoint b)
        internal
        pure
        returns (UFixedPoint)
    {
        return
            UFixedPoint.wrap(
                FixedPointMathLib.add(
                    UFixedPoint.unwrap(a),
                    UFixedPoint.unwrap(b)
                )
            );
    }

    function sub(UFixedPoint a, UFixedPoint b)
        internal
        pure
        returns (UFixedPoint)
    {
        return
            UFixedPoint.wrap(
                FixedPointMathLib.sub(
                    UFixedPoint.unwrap(a),
                    UFixedPoint.unwrap(b)
                )
            );
    }

    function mulDown(UFixedPoint a, UFixedPoint b)
        internal
        pure
        returns (UFixedPoint)
    {
        return
            UFixedPoint.wrap(
                FixedPointMathLib.mulDivDown(
                    UFixedPoint.unwrap(a),
                    UFixedPoint.unwrap(b),
                    _ONE_18
                )
            ); // Equivalent to (a * b) / 1e18 rounded down.
    }

    function mulUp(UFixedPoint a, UFixedPoint b)
        internal
        pure
        returns (UFixedPoint)
    {
        return
            UFixedPoint.wrap(
                FixedPointMathLib.mulDivUp(
                    UFixedPoint.unwrap(a),
                    UFixedPoint.unwrap(b),
                    _ONE_18
                )
            ); // Equivalent to (a * b) / 1e18 rounded up.
    }

    function divDown(UFixedPoint a, UFixedPoint b)
        internal
        pure
        returns (UFixedPoint)
    {
        return
            UFixedPoint.wrap(
                FixedPointMathLib.mulDivDown(
                    UFixedPoint.unwrap(a),
                    _ONE_18,
                    UFixedPoint.unwrap(b)
                )
            ); // Equivalent to (a * 1e18) / b rounded down.
    }

    function divUp(UFixedPoint a, UFixedPoint b)
        internal
        pure
        returns (UFixedPoint)
    {
        return
            UFixedPoint.wrap(
                FixedPointMathLib.mulDivUp(
                    UFixedPoint.unwrap(a),
                    _ONE_18,
                    UFixedPoint.unwrap(b)
                )
            ); // Equivalent to (a * 1e18) / b rounded up.
    }

    function pow(UFixedPoint x, UFixedPoint y)
        internal
        pure
        returns (UFixedPoint)
    {
        return
            UFixedPoint.wrap(
                FixedPointMathLib.pow(
                    UFixedPoint.unwrap(x),
                    UFixedPoint.unwrap(y)
                )
            );
    }

    function toUFixedPoint(uint256 a) internal pure returns (UFixedPoint) {
        return UFixedPoint.wrap(a * _ONE_18);
    }
}
