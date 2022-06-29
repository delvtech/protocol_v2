/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/libraries/Errors.sol";

/// @notice Arithmetic library with operations for fixed-point numbers.
/// @author Element Finance
library FixedPointMathLib {
    int256 private constant _ONE_18 = 1e18;

    // Internally, intermediate values are computed with higher precision as 20 decimal fixed point numbers, and in the
    // case of ln36, 36 decimals.
    int256 private constant _ONE_20 = 1e20;
    int256 private constant _ONE_36 = 1e36;

    // Bounds for ln_36's argument. Both ln(0.9) and ln(1.1) can be represented with 36 decimal places in a fixed point
    // 256 bit integer.
    int256 private constant _LN_36_LOWER_BOUND = _ONE_18 - 1e17;
    int256 private constant _LN_36_UPPER_BOUND = _ONE_18 + 1e17;

    // The domain of natural exponentiation is bound by the word size and number of decimals used.
    //
    // Because internally the result will be stored using 20 decimals, the largest possible result is
    // (2^255 - 1) / 10^20, which makes the largest exponent ln((2^255 - 1) / 10^20) = 130.700829182905140221.
    // The smallest possible result is 10^(-18), which makes largest negative argument
    // ln(10^(-18)) = -41.446531673892822312.
    // We use 130.0 and -41.0 to have some safety margin.
    int256 private constant _MAX_NATURAL_EXPONENT = 130e18;
    int256 private constant _MIN_NATURAL_EXPONENT = -41e18;

    uint256 private constant _MILD_EXPONENT_BOUND = 2**254 / uint256(_ONE_20);

    // 18 decimal constants
    int256 private constant _X0 = 128000000000000000000; // 2ˆ7
    int256 private constant _A0 =
        38877084059945950922200000000000000000000000000000000000; // eˆ(_X0) (no decimals)
    int256 private constant _X1 = 64000000000000000000; // 2ˆ6
    int256 private constant _A1 = 6235149080811616882910000000; // eˆ(_X1) (no decimals)

    // 20 decimal constants
    int256 private constant _X2 = 3200000000000000000000; // 2ˆ5
    int256 private constant _A2 = 7896296018268069516100000000000000; // eˆ(_X2)
    int256 private constant _X3 = 1600000000000000000000; // 2ˆ4
    int256 private constant _A3 = 888611052050787263676000000; // eˆ(_X3)
    int256 private constant _X4 = 800000000000000000000; // 2ˆ3
    int256 private constant _A4 = 298095798704172827474000; // eˆ(_X4)
    int256 private constant _X5 = 400000000000000000000; // 2ˆ2
    int256 private constant _A5 = 5459815003314423907810; // eˆ(_X5)
    int256 private constant _X6 = 200000000000000000000; // 2ˆ1
    int256 private constant _A6 = 738905609893065022723; // eˆ(_X6)
    int256 private constant _X7 = 100000000000000000000; // 2ˆ0
    int256 private constant _A7 = 271828182845904523536; // eˆ(_X7)
    int256 private constant _X8 = 50000000000000000000; // 2ˆ-1
    int256 private constant _A8 = 164872127070012814685; // eˆ(_X8)
    int256 private constant _X9 = 25000000000000000000; // 2ˆ-2
    int256 private constant _A9 = 128402541668774148407; // eˆ(_X9)
    int256 private constant _X10 = 12500000000000000000; // 2ˆ-3
    int256 private constant _A10 = 113314845306682631683; // eˆ(_X10)
    int256 private constant _X11 = 6250000000000000000; // 2ˆ-4
    int256 private constant _A11 = 106449445891785942956; // eˆ(_X11)

    /// @dev Credit to Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(d != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(d)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // Divide z by the d.
            z := div(z, d)
        }
    }

    /// @dev Credit to Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(d != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(d)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // First, divide z - 1 by the d and add 1.
            // We allow z - 1 to underflow if z is 0, because we multiply the
            // end result by 0 if z is zero, ensuring we return 0 if z is zero.
            z := mul(iszero(iszero(z)), add(div(sub(z, 1), d), 1))
        }
    }

    /**
     * @dev Exponentiation (x^y) with unsigned 18 decimal fixed point base and exponent.
     * @dev Credit to Balancer (https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/solidity-utils/contracts/math/LogExpMath.sol)
     * Reverts if ln(x) * y is smaller than `_MIN_NATURAL_EXPONENT`, or larger than `_MAX_NATURAL_EXPONENT`.
     */
    function pow(uint256 x, uint256 y) internal pure returns (uint256) {
        if (y == 0) {
            // We solve the 0^0 indetermination by making it equal one.
            return uint256(_ONE_18);
        }

        if (x == 0) {
            return 0;
        }

        // Instead of computing x^y directly, we instead rely on the properties of logarithms and exponentiation to
        // arrive at that result. In particular, exp(ln(x)) = x, and ln(x^y) = y * ln(x). This means
        // x^y = exp(y * ln(x)).

        // The ln function takes a signed value, so we need to make sure x fits in the signed 256 bit range.
        _require((x >> 255) == 0, Errors.X_OUT_OF_BOUNDS);
        int256 x_int256 = int256(x);

        // We will compute y * ln(x) in a single step. Depending on the value of x, we can either use ln or ln_36. In
        // both cases, we leave the division by _ONE_18 (due to fixed point multiplication) to the end.

        // This prevents y * ln(x) from overflowing, and at the same time guarantees y fits in the signed 256 bit range.
        _require(y < _MILD_EXPONENT_BOUND, Errors.Y_OUT_OF_BOUNDS);
        int256 y_int256 = int256(y);

        int256 logx_times_y;
        if (_LN_36_LOWER_BOUND < x_int256 && x_int256 < _LN_36_UPPER_BOUND) {
            int256 ln_36_x = _ln_36(x_int256);

            // ln_36_x has 36 decimal places, so multiplying by y_int256 isn't as straightforward, since we can't just
            // bring y_int256 to 36 decimal places, as it might overflow. Instead, we perform two 18 decimal
            // multiplications and add the results: one with the first 18 decimals of ln_36_x, and one with the
            // (downscaled) last 18 decimals.
            logx_times_y = ((ln_36_x / _ONE_18) *
                y_int256 +
                ((ln_36_x % _ONE_18) * y_int256) /
                _ONE_18);
        } else {
            logx_times_y = _ln(x_int256) * y_int256;
        }
        logx_times_y /= _ONE_18;

        // Finally, we compute exp(y * ln(x)) to arrive at x^y
        _require(
            _MIN_NATURAL_EXPONENT <= logx_times_y &&
                logx_times_y <= _MAX_NATURAL_EXPONENT,
            Errors.PRODUCT_OUT_OF_BOUNDS
        );

        return uint256(_exp(logx_times_y));
    }

    /**
     * @dev Exponentiation (x^y) with unsigned 18 decimal fixed point base and exponent.
     * @dev Credit to Balancer (https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/solidity-utils/contracts/math/LogExpMath.sol)
     * Reverts if ln(x) * y is smaller than `_MIN_NATURAL_EXPONENT`, or larger than `_MAX_NATURAL_EXPONENT`.
     */
    function pow2(uint256 x, uint256 y) internal pure returns (uint256) {
        if (y == 0) {
            // We solve the 0^0 indetermination by making it equal one.
            return uint256(_ONE_18);
        }

        if (x == 0) {
            return 0;
        }

        // Instead of computing x^y directly, we instead rely on the properties of logarithms and exponentiation to
        // arrive at that result. In particular, exp(ln(x)) = x, and ln(x^y) = y * ln(x). This means
        // x^y = exp(y * ln(x)).

        // The ln function takes a signed value, so we need to make sure x fits in the signed 256 bit range.
        _require((x >> 255) == 0, Errors.X_OUT_OF_BOUNDS);
        int256 x_int256 = int256(x);

        // We will compute y * ln(x) in a single step. Depending on the value of x, we can either use ln or ln_36. In
        // both cases, we leave the division by _ONE_18 (due to fixed point multiplication) to the end.

        // This prevents y * ln(x) from overflowing, and at the same time guarantees y fits in the signed 256 bit range.
        _require(y < _MILD_EXPONENT_BOUND, Errors.Y_OUT_OF_BOUNDS);
        int256 y_int256 = int256(y);

        int256 logx_times_y;
        if (_LN_36_LOWER_BOUND < x_int256 && x_int256 < _LN_36_UPPER_BOUND) {
            int256 ln_36_x = _ln_36(x_int256);

            // ln_36_x has 36 decimal places, so multiplying by y_int256 isn't as straightforward, since we can't just
            // bring y_int256 to 36 decimal places, as it might overflow. Instead, we perform two 18 decimal
            // multiplications and add the results: one with the first 18 decimals of ln_36_x, and one with the
            // (downscaled) last 18 decimals.
            logx_times_y = ((ln_36_x / _ONE_18) *
                y_int256 +
                ((ln_36_x % _ONE_18) * y_int256) /
                _ONE_18);
        } else {
            logx_times_y = _ln(x_int256) * y_int256;
        }
        logx_times_y /= _ONE_18;

        // Finally, we compute exp(y * ln(x)) to arrive at x^y
        _require(
            _MIN_NATURAL_EXPONENT <= logx_times_y &&
                logx_times_y <= _MAX_NATURAL_EXPONENT,
            Errors.PRODUCT_OUT_OF_BOUNDS
        );

        return uint256(_exp2(logx_times_y));
    }

    /// Computes e^x in 1e18 fixed point.
    /// @dev Credit to Remco (https://github.com/recmo/experiment-solexp/blob/main/src/FixedPointMathLib.sol)
    function _exp(int256 x) private pure returns (int256 r) {
        unchecked {
            // Input x is in fixed point format, with scale factor 1/1e18.

            // When the result is < 0.5 we return zero. This happens when
            // x <= floor(log(0.5e18) * 1e18) ~ -42e18
            if (x <= -42139678854452767551) {
                return 0;
            }

            // When the result is > (2**255 - 1) / 1e18 we can not represent it
            // as an int256. This happens when x >= floor(log((2**255 -1) / 1e18) * 1e18) ~ 135.
            _require(x < 135305999368893231589, Errors.INVALID_EXPONENT);

            // x is now in the range (-42, 136) * 1e18. Convert to (-42, 136) * 2**96
            // for more intermediate precision and a binary basis. This base conversion
            // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78.
            x = (x << 78) / 5**18;

            // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers of two
            // such that exp(x) = exp(x') * 2**k, where k is an integer.
            // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
            int256 k = ((x << 96) / 54916777467707473351141471128 + 2**95) >>
                96;
            x = x - k * 54916777467707473351141471128;
            // k is in the range [-61, 195].

            // Evaluate using a (6, 7)-term rational approximation
            // p is made monic, we will multiply by a scale factor later
            int256 p = x + 2772001395605857295435445496992;
            p = ((p * x) >> 96) + 44335888930127919016834873520032;
            p = ((p * x) >> 96) + 398888492587501845352592340339721;
            p = ((p * x) >> 96) + 1993839819670624470859228494792842;
            p = p * x + (4385272521454847904632057985693276 << 96);
            // We leave p in 2**192 basis so we don't need to scale it back up for the division.
            // Evaluate using using Knuth's scheme from p. 491.
            int256 z = x + 750530180792738023273180420736;
            z = ((z * x) >> 96) + 32788456221302202726307501949080;
            int256 w = x - 2218138959503481824038194425854;
            w = ((w * z) >> 96) + 892943633302991980437332862907700;
            int256 q = z + w - 78174809823045304726920794422040;
            q = ((q * w) >> 96) + 4203224763890128580604056984195872;
            assembly {
                // Div in assembly because solidity adds a zero check despite the `unchecked`.
                // The q polynomial is known not to have zeros in the domain. (All roots are complex)
                // No scaling required because p is already 2**96 too large.
                r := sdiv(p, q)
            }
            // r should be in the range (0.09, 0.25) * 2**96.

            // We now need to multiply r by
            //  * the scale factor s = ~6.031367120...,
            //  * the 2**k factor from the range reduction, and
            //  * the 1e18 / 2**96 factor for base converison.
            // We do all of this at once, with an intermediate result in 2**213 basis
            // so the final right shift is always by a positive amount.
            r = int256(
                (uint256(r) *
                    3822833074963236453042738258902158003155416615667) >>
                    uint256(195 - k)
            );
        }
    }

    /**
     * @dev Natural exponentiation (e^x) with signed 18 decimal fixed point exponent.
     * @dev Credit to Balancer (https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/solidity-utils/contracts/math/LogExpMath.sol)
     * Reverts if `x` is smaller than _MIN_NATURAL_EXPONENT, or larger than `_MAX_NATURAL_EXPONENT`.
     */
    function _exp2(int256 x) internal pure returns (int256) {
        _require(
            x >= _MIN_NATURAL_EXPONENT && x <= _MAX_NATURAL_EXPONENT,
            Errors.INVALID_EXPONENT
        );

        if (x < 0) {
            // We only handle positive exponents: e^(-x) is computed as 1 / e^x. We can safely make x positive since it
            // fits in the signed 256 bit range (as it is larger than _MIN_NATURAL_EXPONENT).
            // Fixed point division requires multiplying by _ONE_18.
            return ((_ONE_18 * _ONE_18) / _exp2(-x));
        }

        // First, we use the fact that e^(x+y) = e^x * e^y to decompose x into a sum of powers of two, which we call x_n,
        // where x_n == 2^(7 - n), and e^x_n = a_n has been precomputed. We choose the first x_n, _X0, to equal 2^7
        // because all larger powers are larger than _MAX_NATURAL_EXPONENT, and therefore not present in the
        // decomposition.
        // At the end of this process we will have the product of all e^x_n = a_n that apply, and the remainder of this
        // decomposition, which will be lower than the smallest x_n.
        // exp(x) = k_0 * a_0 * k_1 * a_1 * ... + k_n * a_n * exp(remainder), where each k_n equals either 0 or 1.
        // We mutate x by subtracting x_n, making it the remainder of the decomposition.

        // The first two a_n (e^(2^7) and e^(2^6)) are too large if stored as 18 decimal numbers, and could cause
        // intermediate overflows. Instead we store them as plain integers, with 0 decimals.
        // Additionally, _X0 + _X1 is larger than _MAX_NATURAL_EXPONENT, which means they will not both be present in the
        // decomposition.

        // For each x_n, we test if that term is present in the decomposition (if x is larger than it), and if so deduct
        // it and compute the accumulated product.

        int256 firstAN;
        if (x >= _X0) {
            x -= _X0;
            firstAN = _A0;
        } else if (x >= _X1) {
            x -= _X1;
            firstAN = _A1;
        } else {
            firstAN = 1; // One with no decimal places
        }

        // We now transform x into a 20 decimal fixed point number, to have enhanced precision when computing the
        // smaller terms.
        x *= 100;

        // `product` is the accumulated product of all a_n (except _A0 and _A1), which starts at 20 decimal fixed point
        // one. Recall that fixed point multiplication requires dividing by _ONE_20.
        int256 product = _ONE_20;

        if (x >= _X2) {
            x -= _X2;
            product = (product * _A2) / _ONE_20;
        }
        if (x >= _X3) {
            x -= _X3;
            product = (product * _A3) / _ONE_20;
        }
        if (x >= _X4) {
            x -= _X4;
            product = (product * _A4) / _ONE_20;
        }
        if (x >= _X5) {
            x -= _X5;
            product = (product * _A5) / _ONE_20;
        }
        if (x >= _X6) {
            x -= _X6;
            product = (product * _A6) / _ONE_20;
        }
        if (x >= _X7) {
            x -= _X7;
            product = (product * _A7) / _ONE_20;
        }
        if (x >= _X8) {
            x -= _X8;
            product = (product * _A8) / _ONE_20;
        }
        if (x >= _X9) {
            x -= _X9;
            product = (product * _A9) / _ONE_20;
        }

        // _X10 and _X11 are unnecessary here since we have high enough precision already.

        // Now we need to compute e^x, where x is small (in particular, it is smaller than _X9). We use the Taylor series
        // expansion for e^x: 1 + x + (x^2 / 2!) + (x^3 / 3!) + ... + (x^n / n!).

        int256 seriesSum = _ONE_20; // The initial one in the sum, with 20 decimal places.
        int256 term; // Each term in the sum, where the nth term is (x^n / n!).

        // The first term is simply x.
        term = x;
        seriesSum += term;

        // Each term (x^n / n!) equals the previous one times x, divided by n. Since x is a fixed point number,
        // multiplying by it requires dividing by _ONE_20, but dividing by the non-fixed point n values does not.

        term = ((term * x) / _ONE_20) / 2;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 3;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 4;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 5;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 6;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 7;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 8;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 9;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 10;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 11;
        seriesSum += term;

        term = ((term * x) / _ONE_20) / 12;
        seriesSum += term;

        // 12 Taylor terms are sufficient for 18 decimal precision.

        // We now have the first a_n (with no decimals), and the product of all other a_n present, and the Taylor
        // approximation of the exponentiation of the remainder (both with 20 decimals). All that remains is to multiply
        // all three (one 20 decimal fixed point multiplication, dividing by _ONE_20, and one integer multiplication),
        // and then drop two digits to return an 18 decimal value.

        return (((product * seriesSum) / _ONE_20) * firstAN) / 100;
    }

    /**
     * @dev Internal natural logarithm (ln(a)) with signed 18 decimal fixed point argument.
     * @dev Credit to Balancer (https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/solidity-utils/contracts/math/LogExpMath.sol)
     */
    function _ln(int256 a) private pure returns (int256) {
        if (a < _ONE_18) {
            // Since ln(a^k) = k * ln(a), we can compute ln(a) as ln(a) = ln((1/a)^(-1)) = - ln((1/a)). If a is less
            // than one, 1/a will be greater than one, and this if statement will not be entered in the recursive call.
            // Fixed point division requires multiplying by _ONE_18.
            return (-_ln((_ONE_18 * _ONE_18) / a));
        }

        // First, we use the fact that ln^(a * b) = ln(a) + ln(b) to decompose ln(a) into a sum of powers of two, which
        // we call x_n, where x_n == 2^(7 - n), which are the natural logarithm of precomputed quantities a_n (that is,
        // ln(a_n) = x_n). We choose the first x_n, _X0, to equal 2^7 because the exponential of all larger powers cannot
        // be represented as 18 fixed point decimal numbers in 256 bits, and are therefore larger than a.
        // At the end of this process we will have the sum of all x_n = ln(a_n) that apply, and the remainder of this
        // decomposition, which will be lower than the smallest a_n.
        // ln(a) = k_0 * x_0 + k_1 * x_1 + ... + k_n * x_n + ln(remainder), where each k_n equals either 0 or 1.
        // We mutate a by subtracting a_n, making it the remainder of the decomposition.

        // For reasons related to how `exp` works, the first two a_n (e^(2^7) and e^(2^6)) are not stored as fixed point
        // numbers with 18 decimals, but instead as plain integers with 0 decimals, so we need to multiply them by
        // _ONE_18 to convert them to fixed point.
        // For each a_n, we test if that term is present in the decomposition (if a is larger than it), and if so divide
        // by it and compute the accumulated sum.

        int256 sum = 0;
        if (a >= _A0 * _ONE_18) {
            a /= _A0; // Integer, not fixed point division
            sum += _X0;
        }

        if (a >= _A1 * _ONE_18) {
            a /= _A1; // Integer, not fixed point division
            sum += _X1;
        }

        // All other a_n and x_n are stored as 20 digit fixed point numbers, so we convert the sum and a to this format.
        sum *= 100;
        a *= 100;

        // Because further a_n are  20 digit fixed point numbers, we multiply by _ONE_20 when dividing by them.

        if (a >= _A2) {
            a = (a * _ONE_20) / _A2;
            sum += _X2;
        }

        if (a >= _A3) {
            a = (a * _ONE_20) / _A3;
            sum += _X3;
        }

        if (a >= _A4) {
            a = (a * _ONE_20) / _A4;
            sum += _X4;
        }

        if (a >= _A5) {
            a = (a * _ONE_20) / _A5;
            sum += _X5;
        }

        if (a >= _A6) {
            a = (a * _ONE_20) / _A6;
            sum += _X6;
        }

        if (a >= _A7) {
            a = (a * _ONE_20) / _A7;
            sum += _X7;
        }

        if (a >= _A8) {
            a = (a * _ONE_20) / _A8;
            sum += _X8;
        }

        if (a >= _A9) {
            a = (a * _ONE_20) / _A9;
            sum += _X9;
        }

        if (a >= _A10) {
            a = (a * _ONE_20) / _A10;
            sum += _X10;
        }

        if (a >= _A11) {
            a = (a * _ONE_20) / _A11;
            sum += _X11;
        }

        // a is now a small number (smaller than a_11, which roughly equals 1.06). This means we can use a Taylor series
        // that converges rapidly for values of `a` close to one - the same one used in ln_36.
        // Let z = (a - 1) / (a + 1).
        // ln(a) = 2 * (z + z^3 / 3 + z^5 / 5 + z^7 / 7 + ... + z^(2 * n + 1) / (2 * n + 1))

        // Recall that 20 digit fixed point division requires multiplying by _ONE_20, and multiplication requires
        // division by _ONE_20.
        int256 z = ((a - _ONE_20) * _ONE_20) / (a + _ONE_20);
        int256 z_squared = (z * z) / _ONE_20;

        // num is the numerator of the series: the z^(2 * n + 1) term
        int256 num = z;

        // seriesSum holds the accumulated sum of each term in the series, starting with the initial z
        int256 seriesSum = num;

        // In each step, the numerator is multiplied by z^2
        num = (num * z_squared) / _ONE_20;
        seriesSum += num / 3;

        num = (num * z_squared) / _ONE_20;
        seriesSum += num / 5;

        num = (num * z_squared) / _ONE_20;
        seriesSum += num / 7;

        num = (num * z_squared) / _ONE_20;
        seriesSum += num / 9;

        num = (num * z_squared) / _ONE_20;
        seriesSum += num / 11;

        // 6 Taylor terms are sufficient for 36 decimal precision.

        // Finally, we multiply by 2 (non fixed point) to compute ln(remainder)
        seriesSum *= 2;

        // We now have the sum of all x_n present, and the Taylor approximation of the logarithm of the remainder (both
        // with 20 decimals). All that remains is to sum these two, and then drop two digits to return a 18 decimal
        // value.

        return (sum + seriesSum) / 100;
    }

    /**
     * @dev Intrnal high precision (36 decimal places) natural logarithm (ln(x)) with signed 18 decimal fixed point argument,
     * for x close to one.
     * @dev Credit to Balancer (https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/solidity-utils/contracts/math/LogExpMath.sol)
     * Should only be used if x is between _LN_36_LOWER_BOUND and _LN_36_UPPER_BOUND.
     */
    function _ln_36(int256 x) private pure returns (int256) {
        // Since ln(1) = 0, a value of x close to one will yield a very small result, which makes using 36 digits
        // worthwhile.

        // First, we transform x to a 36 digit fixed point value.
        x *= _ONE_18;

        // We will use the following Taylor expansion, which converges very rapidly. Let z = (x - 1) / (x + 1).
        // ln(x) = 2 * (z + z^3 / 3 + z^5 / 5 + z^7 / 7 + ... + z^(2 * n + 1) / (2 * n + 1))

        // Recall that 36 digit fixed point division requires multiplying by _ONE_36, and multiplication requires
        // division by _ONE_36.
        int256 z = ((x - _ONE_36) * _ONE_36) / (x + _ONE_36);
        int256 z_squared = (z * z) / _ONE_36;

        // num is the numerator of the series: the z^(2 * n + 1) term
        int256 num = z;

        // seriesSum holds the accumulated sum of each term in the series, starting with the initial z
        int256 seriesSum = num;

        // In each step, the numerator is multiplied by z^2
        num = (num * z_squared) / _ONE_36;
        seriesSum += num / 3;

        num = (num * z_squared) / _ONE_36;
        seriesSum += num / 5;

        num = (num * z_squared) / _ONE_36;
        seriesSum += num / 7;

        num = (num * z_squared) / _ONE_36;
        seriesSum += num / 9;

        num = (num * z_squared) / _ONE_36;
        seriesSum += num / 11;

        num = (num * z_squared) / _ONE_36;
        seriesSum += num / 13;

        num = (num * z_squared) / _ONE_36;
        seriesSum += num / 15;

        // 8 Taylor terms are sufficient for 36 decimal precision.

        // All that remains is multiplying by 2 (non fixed point).
        return seriesSum * 2;
    }
}
