import { advanceBlock, advanceTime, advanceTimeOnly } from "./helpers/time";
import "module-alias/register";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import {
  formatEther,
  formatUnits,
  parseEther,
  parseUnits,
} from "ethers/lib/utils";
import { ethers, waffle } from "hardhat";
import { MockTWAROracle, MockTWAROracle__factory } from "typechain-types";

import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

const MAX_TIME = 5;
const MAX_LENGTH = 5;
// this one is initialized for all tests
const BUFFER_ID = 1;
// this one is un initialized
const NEW_BUFFER_ID = 2;

describe("TWAR Oracle", function () {
  let signers: SignerWithAddress[];
  let oracleDeployer: MockTWAROracle__factory;
  let oracleContract: MockTWAROracle;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();

    oracleDeployer = new MockTWAROracle__factory(signers[0] as Signer);

    oracleContract = await oracleDeployer.deploy();
    await oracleContract.initializeBuffer(BUFFER_ID, MAX_TIME, MAX_LENGTH);
  });

  after(async () => {
    await restoreSnapshot(provider);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });
  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  it("should fail to initialize if out of bounds", async () => {
    try {
      await oracleContract.initializeBuffer(NEW_BUFFER_ID, MAX_TIME, "0x10000");
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("value out-of-bounds");
      } else {
        throw error;
      }
    }

    try {
      await oracleContract.initializeBuffer(NEW_BUFFER_ID, MAX_TIME, "0");
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("TWAROracle_IncorrectBufferLength()");
      } else {
        throw error;
      }
    }
  });

  it("should fail to initialize if already initialized", async () => {
    try {
      await oracleContract.initializeBuffer(BUFFER_ID, MAX_TIME, MAX_LENGTH);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include(
          "TWAROracle_BufferAlreadyInitialized()"
        );
      } else {
        throw error;
      }
    }
  });

  it("should initialize", async () => {
    const initialMetadataParsed = await oracleContract.readMetadataParsed(
      BUFFER_ID
    );
    const block = await provider.getBlock("latest");
    expect(initialMetadataParsed).to.deep.equal([
      1, // minTimeStep
      block.timestamp, // timeStamp
      0, // headIndex
      5, // maxLength
      0, // bufferLength
    ]);
  });

  it("should add first value to sum", async () => {
    const oneEther = parseEther("1");
    await oracleContract.updateBuffer(BUFFER_ID, oneEther);
    const result = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      0
    );
    const block = await provider.getBlock("latest");
    expect(result.timeStamp).to.equal(block.timestamp);
    expect(result.cumulativeSum).to.equal(oneEther.toString());
  });

  it("should add many values to sum", async () => {
    const { timeStamp: initialTimeStamp } =
      await oracleContract.readMetadataParsed(BUFFER_ID);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1"));
    await advanceTime(provider, 1);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1"));
    await advanceTime(provider, 1);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1"));
    await advanceTime(provider, 1);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1"));
    await advanceTime(provider, 1);

    const result0 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      0
    );
    const result1 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      1
    );
    const result2 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      2
    );
    const result3 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      3
    );

    expect(result0.cumulativeSum).to.equal(
      parseEther("1")
        .mul(result0.timeStamp - initialTimeStamp)
        .add(0)
    );

    expect(result1.cumulativeSum).to.equal(
      parseEther("1")
        .mul(result1.timeStamp - result0.timeStamp)
        .add(result0.cumulativeSum)
    );

    expect(result2.cumulativeSum).to.equal(
      parseEther("1")
        .mul(result2.timeStamp - result1.timeStamp)
        .add(result1.cumulativeSum)
    );

    expect(result3.cumulativeSum).to.equal(
      parseEther("1")
        .mul(result3.timeStamp - result2.timeStamp)
        .add(result2.cumulativeSum)
    );
  });

  it("should fail to add value to sum if time step is too small", async () => {
    // time step is 2 (maxTime / maxLength)
    await oracleContract.initializeBuffer(NEW_BUFFER_ID, 4, 2);
    // this update happens too quickly so it fails silently
    await oracleContract.updateBuffer(NEW_BUFFER_ID, parseEther("1"));
    // wait long enough to update
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(NEW_BUFFER_ID, parseEther("1"));
    // this one also fails silently
    await oracleContract.updateBuffer(NEW_BUFFER_ID, parseEther("1"));

    const metadata = await oracleContract.readMetadataParsed(NEW_BUFFER_ID);
    const { bufferLength } = metadata;
    expect(bufferLength).to.equal(1);
  });

  xit("should fail to read an item that's out of bounds", async () => {
    try {
      await oracleContract.readSumAndTimeStampForPool(BUFFER_ID, 0);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("index out of bounds");
      } else {
        throw error;
      }
    }

    await oracleContract.updateBuffer(BUFFER_ID, 1);
    const result = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      0
    );
    expect(result.cumulativeSum.toString()).to.equal("1");

    try {
      await oracleContract.readSumAndTimeStampForPool(BUFFER_ID, 1);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("index out of bounds");
      } else {
        throw error;
      }
    }
  });

  it("buffer should wrap when adding items", async () => {
    // max length is 5, so the buffer should wrap back to the beginning
    await oracleContract.updateBuffer(BUFFER_ID, 1);
    await advanceTimeOnly(provider, 1);
    await oracleContract.updateBuffer(BUFFER_ID, 1);
    await advanceTimeOnly(provider, 1);
    await oracleContract.updateBuffer(BUFFER_ID, 1);
    await advanceTimeOnly(provider, 1);
    await oracleContract.updateBuffer(BUFFER_ID, 1);
    await advanceTimeOnly(provider, 1);
    await oracleContract.updateBuffer(BUFFER_ID, 1);
    await advanceTimeOnly(provider, 1);
    await oracleContract.updateBuffer(BUFFER_ID, 1);

    const metadata = await oracleContract.readMetadataParsed(BUFFER_ID);
    // headIndex now back at zero, maxLength still 5, bufferLength now 5
    const block = await provider.getBlock("latest");

    expect(metadata).to.deep.equal([
      1, // minTimeStep
      block.timestamp, // timestamp
      0, // headIndex
      5, // maxLength
      5, // bufferLength
    ]);

    const result0 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      0
    );
    const result1 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      1
    );
    const result2 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      2
    );
    const result3 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      3
    );
    const result4 = await oracleContract.readSumAndTimeStampForPool(
      BUFFER_ID,
      4
    );

    // buffer[0] is 6 because the the buffer rolled over and replaced '1'
    expect(result0.cumulativeSum.toString()).to.equal("6");
    expect(result1.cumulativeSum.toString()).to.equal("2");
    expect(result2.cumulativeSum.toString()).to.equal("3");
    expect(result3.cumulativeSum.toString()).to.equal("4");
    expect(result4.cumulativeSum.toString()).to.equal("5");
  });

  it("should calculate an average value", async () => {
    // the value never changes, always one, but the cumulative sum is increasing
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 1
    await advanceTimeOnly(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 1, sum 2
    await advanceTimeOnly(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 2, sum 3
    await advanceTimeOnly(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 3, sum 4
    await advanceTimeOnly(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 4, sum 5
    await advanceTimeOnly(provider, 3);

    // lets reach back 3 steps
    const { timeStamp: startTime } =
      await oracleContract.readSumAndTimeStampForPool(BUFFER_ID, 2);

    const block = await provider.getBlock("latest");
    const lastBlockTimeStamp = block.timestamp;
    // should be about 10  seconds, between position 1 and 2
    const timeInSeconds = lastBlockTimeStamp - startTime + 1;

    const averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatEther(averageValue)).to.equal("1.0");
  });

  // Tests when there are many elements, but the timeInSeconds isn't large
  // enough to reach the newest update.  It should return the last average value.
  it("should work when no buffer elements included", async () => {
    // the value never changes, always one, but the cumulative sum is increasing
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 1
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 1, sum 2
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 2, sum 3
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 3, sum 4
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("2")); // position 4, sum 5
    await advanceTime(provider, 3);
    // record a new block so when we try to provide a time that's less than 3s we won't
    // even hit the last update to the buffer
    await advanceBlock(provider);

    // let's barely step back, shouldn't even go back to the last recorded update to the buffer
    const timeInSeconds = 2;

    const averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatEther(averageValue)).to.equal("2.0");
  });

  it("should work when exactly one buffer element included", async () => {
    // the value never changes, always one, but the cumulative sum is increasing
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 1
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 1, sum 2
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 2, sum 3
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 3, sum 4
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 4, sum 5

    // let's barely step back, should just cover one update
    const timeInSeconds = 2;

    const averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatEther(averageValue)).to.equal("1.0");
  });

  it("should work when all buffer elements included", async () => {
    // the value never changes, always one, but the cumulative sum is increasing
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 1
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 1, sum 2
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 2, sum 3
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 3, sum 4
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 4, sum 5

    // this is much larger than the 12s of recorded time between all updates
    const timeInSeconds = 50;

    const averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatEther(averageValue)).to.equal("1.0");
  });

  it("should work when wrapping the buffer", async () => {
    // the value never changes, always one, but the cumulative sum is increasing
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 1
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 1, sum 2
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 2, sum 3
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 3, sum 4
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 4, sum 5
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 6

    // this is much larger than the 15s of recorded time between all updates, will include all the
    // elements and wrap the buffer
    const timeInSeconds = 50;

    const averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatEther(averageValue)).to.equal("1.0");
  });

  xit("should fail when there are less than two elements in the buffer", async () => {
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 1
    try {
      await oracleContract.calculateAverageWeightedValue(BUFFER_ID, 1);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("not enough elements");
      } else {
        throw error;
      }
    }
  });

  it("should work when there are only two elements in the buffer", async () => {
    // the value never changes, always one, but the cumulative sum is increasing
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 1
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("1")); // position 0, sum 1

    // grab the one element
    let timeInSeconds = 1;

    let averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatEther(averageValue)).to.equal("1.0");

    // go way past the one element's timeStamp
    timeInSeconds = 50;
    averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatEther(averageValue)).to.equal("1.0");

    await advanceTime(provider, 3);
    // record a new block so when we try to provide a time that's less than 3s we won't
    // even hit the last update to the buffer
    await advanceBlock(provider);

    // don't grab the one element
    timeInSeconds = 1;

    averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatEther(averageValue)).to.equal("1.0");
  });

  it("should work with smaller decimal tokens", async () => {
    const parseUSDC = (value: string) => parseUnits(value, 6);
    const formatUSDC = (value: BigNumber) => formatUnits(value, 6);
    // the value never changes, always one, but the cumulative sum is increasing
    await oracleContract.updateBuffer(BUFFER_ID, parseUSDC("1")); // position 0, sum 1
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseUSDC("1")); // position 1, sum 2
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseUSDC("1")); // position 2, sum 3
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseUSDC("1")); // position 3, sum 4
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseUSDC("1")); // position 4, sum 5
    await advanceTime(provider, 3);
    await oracleContract.updateBuffer(BUFFER_ID, parseUSDC("1")); // position 0, sum 6

    // this is much larger than the 15s of recorded time between all updates, will include all the
    // elements and wrap the buffer
    let timeInSeconds = 50;

    let averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatUSDC(averageValue)).to.equal("1.0");

    await advanceTime(provider, 3);
    await advanceBlock(provider);
    // timeInSeconds won't even reach back to the last update, but we should still use that average value
    timeInSeconds = 1;

    averageValue = await oracleContract.calculateAverageWeightedValue(
      BUFFER_ID,
      timeInSeconds
    );

    expect(formatUSDC(averageValue)).to.equal("1.0");
  });
});

interface ErrorWithReason {
  reason: string;
}

function isErrorWithReason(error: unknown): error is ErrorWithReason {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return !!(error as any).reason;
}
