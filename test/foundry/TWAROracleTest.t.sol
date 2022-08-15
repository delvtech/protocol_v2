// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "contracts/mocks/MockTWAROracle.sol";
import "contracts/libraries/Errors.sol";

// solhint-disable func-name-mixedcase

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract TWAROracleTest is Test {
    MockTWAROracle public oracle;
    User public user;

    uint16 public constant MAX_TIME = 5;
    uint16 public constant MAX_LENGTH = 5;
    uint256 public constant BUFFER_ID = 1;

    function setUp() public {
        oracle = new MockTWAROracle();
        user = new User();
    }

    function testCannotInitialize_OutOfBounds() public {
        uint16 maxLength = 65535;
        vm.expectRevert(
            ElementError.TWAROracle__InitializeBuffer_ZeroMinTimeStep.selector
        );
        oracle.initializeBuffer(BUFFER_ID, MAX_TIME, maxLength);
    }

    function testCannotInitialize_MaxLengthTooSmall() public {
        vm.expectRevert(
            ElementError
                .TWAROracle__InitializeBuffer_IncorrectBufferLength
                .selector
        );
        oracle.initializeBuffer(BUFFER_ID, MAX_TIME, 0);
    }

    function testCannotInitialize_AlreadyInitialized() public {
        oracle.initializeBuffer(BUFFER_ID, MAX_TIME, MAX_LENGTH);
        vm.expectRevert(
            ElementError
                .TWAROracle__InitializeBuffer_BufferAlreadyInitialized
                .selector
        );
        oracle.initializeBuffer(BUFFER_ID, MAX_TIME, MAX_LENGTH);
    }

    function testInitializationWithFuzzing(uint256 bufferId) public {
        oracle.initializeBuffer(bufferId, MAX_TIME, MAX_LENGTH);

        (
            uint32 minTimeStep,
            uint32 timeStamp,
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        ) = oracle.readMetadataParsed(bufferId);

        assertEq(minTimeStep, 1);
        assertEq(timeStamp, block.timestamp);
        assertEq(headIndex, 0);
        assertEq(5, maxLength);
        assertEq(0, bufferLength);
    }

    function test_ShouldAddFirstValueToSum(uint224 amount) public {
        oracle.initializeBuffer(BUFFER_ID, MAX_TIME, MAX_LENGTH);

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        oracle.updateBuffer(BUFFER_ID, amount);

        (
            uint32 minTimeStep,
            uint32 timeStamp,
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        ) = oracle.readMetadataParsed(BUFFER_ID);

        assertEq(minTimeStep, 1);
        assertEq(timeStamp, block.timestamp);
        assertEq(headIndex, 0);
        assertEq(maxLength, 5);
        assertEq(bufferLength, 1);

        (uint32 newTimeStamp, uint224 cumulativeSum) = oracle
            .readSumAndTimeStampForPool(BUFFER_ID, 0);

        assertEq(newTimeStamp, block.timestamp);
        assertEq(cumulativeSum, amount);
    }

    function test_ShouldAddManyValuesToSum() public {
        uint224 oneEther = 1e18;
        oracle.initializeBuffer(BUFFER_ID, MAX_TIME, MAX_LENGTH);

        uint32 previousTimeStamp = uint32(block.timestamp);
        uint224 previousSum = 0;

        for (uint256 i = 0; i < 4; i++) {
            vm.warp(block.timestamp + 1);
            vm.roll(block.number + 1);
            oracle.updateBuffer(BUFFER_ID, oneEther);
        }

        for (uint16 index = 0; index < 4; index++) {
            (uint32 timeStamp, uint224 cumulativeSum) = oracle
                .readSumAndTimeStampForPool(BUFFER_ID, index);

            uint224 weightedValue = oneEther * (timeStamp - previousTimeStamp);

            assertTrue(cumulativeSum == weightedValue + previousSum);

            previousSum += weightedValue;
            previousTimeStamp = timeStamp;
        }
    }
}
