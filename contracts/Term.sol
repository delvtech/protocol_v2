// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "./MultiToken.sol";
import "./interfaces/IYieldSource.sol";

abstract contract Term is MultiToken, IYieldSource {}
