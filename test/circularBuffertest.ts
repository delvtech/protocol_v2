import { Signer } from "ethers";
import { TestCircularBuffer__factory } from "typechain-types/factories/mocks/TestCircularBuffer__factory";
import { TestCircularBuffer } from "typechain-types/mocks/TestCircularBuffer";
import { expect } from "chai";
import "module-alias/register";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { ethers, waffle } from "hardhat";

import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

const MAX_LENGTH = 5;

describe.only("CircularBuffer", function () {
  let signers: SignerWithAddress[];
  let bufferDeployer: TestCircularBuffer__factory;
  let circularBufferContract: TestCircularBuffer;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();

    const bufferLibDeployer = await ethers.getContractFactory(
      "CircularBuffer",
      signers[0]
    );
    const bufferLib = await bufferLibDeployer.deploy();

    bufferDeployer = new TestCircularBuffer__factory(
      {
        ["contracts/libraries/CircularBuffer.sol:CircularBuffer"]:
          bufferLib.address,
      },
      signers[0] as Signer
    );

    circularBufferContract = await bufferDeployer.deploy(MAX_LENGTH);
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
      await bufferDeployer.deploy("0xffff");
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("value out-of-bounds");
      } else {
        throw error;
      }
    }
  });

  it("should initialize", async () => {
    const initialMetadata = await circularBufferContract.readMetadata();
    // 0xffff is the head index, should roll over to zero when the first item is added
    // 0x0005 is the max length
    // 0x0000 is the current buffer length
    expect(initialMetadata.toHexString()).to.equal("0xffff00050000");
  });

  it("should add an item", async () => {
    const initialMetadata = await circularBufferContract.readMetadata();
    expect(initialMetadata.toHexString()).to.equal("0xffff00050000");

    await circularBufferContract.addValue(1);
    const metadata = await circularBufferContract.readMetadata();
    // headIndex now zero, maxLength still 5, bufferLength now 1
    expect(metadata.toHexString()).to.equal("0x050001");

    const result = await circularBufferContract.getValue(0);
    expect(result.toString()).to.equal("1");
  });

  it("should fail to read an item that's out of bounds", async () => {
    try {
      await circularBufferContract.getValue(0);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("index out of bounds");
      } else {
        throw error;
      }
    }

    await circularBufferContract.addValue(0);
    const result = await circularBufferContract.getValue(0);
    expect(result.toString()).to.equal("1");

    try {
      await circularBufferContract.getValue(1);
    } catch (error) {
      if (isErrorWithReason(error)) {
        expect(error.reason).to.include("index out of bounds");
      } else {
        throw error;
      }
    }
  });

  it("buffer should wrap when adding items", async () => {
    const initialMetadata = await circularBufferContract.readMetadata();
    expect(initialMetadata.toHexString()).to.equal("0xffff00050000");

    // max length is 5, so the buffer should wrap back to the beginning
    await circularBufferContract.addValue(1);
    await circularBufferContract.addValue(2);
    await circularBufferContract.addValue(3);
    await circularBufferContract.addValue(4);
    await circularBufferContract.addValue(5);
    await circularBufferContract.addValue(6);

    const metadata = await circularBufferContract.readMetadata();
    // headIndex now back at zero, maxLength still 5, bufferLength now 5
    expect(metadata.toHexString()).to.equal("0x050005");

    const result0 = await circularBufferContract.getValue(0);
    const result1 = await circularBufferContract.getValue(1);
    const result2 = await circularBufferContract.getValue(2);
    const result3 = await circularBufferContract.getValue(3);
    const result4 = await circularBufferContract.getValue(4);

    // value at buffer[0] is 6 because the the buffer rolled over
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
