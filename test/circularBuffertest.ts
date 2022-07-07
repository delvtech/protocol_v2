import "module-alias/register";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { CircularBuffers, CircularBuffers__factory } from "typechain-types";

import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

const MAX_LENGTH = 5;
// this one is initialized for all tests
const BUFFER_ID = 1;
// this one is un initialized
const NEW_BUFFER_ID = 2;

describe("CircularBuffers", function () {
  let signers: SignerWithAddress[];
  let bufferDeployer: CircularBuffers__factory;
  let circularBufferContract: CircularBuffers;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();

    bufferDeployer = new CircularBuffers__factory(signers[0] as Signer);

    circularBufferContract = await bufferDeployer.deploy();
    await circularBufferContract.initialize(BUFFER_ID, MAX_LENGTH);
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
      await circularBufferContract.initialize(NEW_BUFFER_ID, "0xffff");
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("max length is 65534");
      } else {
        throw error;
      }
    }

    try {
      await circularBufferContract.initialize(NEW_BUFFER_ID, "0");
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("min length is 1");
      } else {
        throw error;
      }
    }
  });

  it("should fail to initialize if already initialized", async () => {
    try {
      await circularBufferContract.initialize(BUFFER_ID, MAX_LENGTH);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("buffer already initialized");
      } else {
        throw error;
      }
    }
  });

  it("should initialize", async () => {
    const initialMetadata = await circularBufferContract.readMetadata(
      BUFFER_ID
    );
    expect(initialMetadata.toHexString()).to.equal("0xffff00050000");

    const initialMetadataParsed =
      await circularBufferContract.readMetadataParsed(BUFFER_ID);
    expect(initialMetadataParsed).to.deep.equal([
      0, // blockNumber
      0, // timestamp
      65535, // headIndex (0xffff)
      5, // maxLength
      0, // bufferLength
    ]);
  });

  it("should add an item", async () => {
    const initialMetadata = await circularBufferContract.readMetadata(
      BUFFER_ID
    );
    expect(initialMetadata.toHexString()).to.equal("0xffff00050000");

    await circularBufferContract.addValue(BUFFER_ID, 1);
    const metadata = await circularBufferContract.readMetadataParsed(BUFFER_ID);
    // headIndex now zero, maxLength still 5, bufferLength now 1
    const blockNumber = await provider.getBlockNumber();
    const block = await provider.getBlock(blockNumber);

    expect(metadata).to.deep.equal([
      blockNumber, // blockNumber
      block.timestamp, // timestamp
      0, // headIndex
      5, // maxLength
      1, // bufferLength
    ]);

    const result = await circularBufferContract.getValue(BUFFER_ID, 0);
    expect(result.toString()).to.equal("1");
  });

  it("should fail to read an item that's out of bounds", async () => {
    try {
      await circularBufferContract.getValue(BUFFER_ID, 0);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("index out of bounds");
      } else {
        throw error;
      }
    }

    await circularBufferContract.addValue(BUFFER_ID, 1);
    const result = await circularBufferContract.getValue(BUFFER_ID, 0);
    expect(result.toString()).to.equal("1");

    try {
      await circularBufferContract.getValue(BUFFER_ID, 1);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("index out of bounds");
      } else {
        throw error;
      }
    }
  });

  it("buffer should wrap when adding items", async () => {
    const initialMetadata = await circularBufferContract.readMetadata(
      BUFFER_ID
    );
    expect(initialMetadata.toHexString()).to.equal("0xffff00050000");

    // max length is 5, so the buffer should wrap back to the beginning
    await circularBufferContract.addValue(BUFFER_ID, 1);
    await circularBufferContract.addValue(BUFFER_ID, 2);
    await circularBufferContract.addValue(BUFFER_ID, 3);
    await circularBufferContract.addValue(BUFFER_ID, 4);
    await circularBufferContract.addValue(BUFFER_ID, 5);
    await circularBufferContract.addValue(BUFFER_ID, 6);

    const metadata = await circularBufferContract.readMetadataParsed(BUFFER_ID);
    // headIndex now back at zero, maxLength still 5, bufferLength now 5
    const blockNumber = await provider.getBlockNumber();
    const block = await provider.getBlock(blockNumber);

    expect(metadata).to.deep.equal([
      blockNumber, // blockNumber
      block.timestamp, // timestamp
      0, // headIndex
      5, // maxLength
      5, // bufferLength
    ]);

    const result0 = await circularBufferContract.getValue(BUFFER_ID, 0);
    const result1 = await circularBufferContract.getValue(BUFFER_ID, 1);
    const result2 = await circularBufferContract.getValue(BUFFER_ID, 2);
    const result3 = await circularBufferContract.getValue(BUFFER_ID, 3);
    const result4 = await circularBufferContract.getValue(BUFFER_ID, 4);

    // buffer[0] is 6 because the the buffer rolled over and replaced '1'
    expect(result0.toString()).to.equal("6");
    expect(result1.toString()).to.equal("2");
    expect(result2.toString()).to.equal("3");
    expect(result3.toString()).to.equal("4");
    expect(result4.toString()).to.equal("5");
  });
});

interface ErrorWithReason {
  reason: string;
}

function isErrorWithReason(error: unknown): error is ErrorWithReason {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return !!(error as any).reason;
}
