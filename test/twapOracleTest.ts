import "module-alias/register";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { MockTWAPOracle, MockTWAPOracle__factory } from "typechain-types";

import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { parseEther } from "ethers/lib/utils";

const { provider } = waffle;

const MAX_LENGTH = 10;
// this one is initialized for all tests
const BUFFER_ID = 1;

describe.only("TWAP Oracle", function () {
  let signers: SignerWithAddress[];
  let oracleDeployer: MockTWAPOracle__factory;
  let oracleContract: MockTWAPOracle;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();

    oracleDeployer = new MockTWAPOracle__factory(signers[0] as Signer);

    oracleContract = await oracleDeployer.deploy();
    await oracleContract.initializeBuffer(BUFFER_ID, MAX_LENGTH);
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

  it("should initialize", async () => {
    const initialMetadataParsed = await oracleContract.readMetadataParsed(
      BUFFER_ID
    );
    const block = await provider.getBlock("latest");
    expect(initialMetadataParsed).to.deep.equal([
      block.number, // blockNumber
      block.timestamp, // timestamp
      0, // headIndex
      10, // maxLength
      0, // bufferLength
    ]);
  });

  // TODO: we should initialize buffer with current timestamp, not zero
  it("should add first price to sum", async () => {
    const oneEther = parseEther("1");
    await oracleContract.updateBuffer(BUFFER_ID, oneEther);
    const result = await oracleContract.readSumAndTimestampForPool(
      BUFFER_ID,
      0
    );
    const block = await provider.getBlock("latest");
    expect(result.timestamp).to.equal(block.timestamp);
    expect(result.cumulativeSum).to.equal(oneEther.toString());
  });

  it("should add many prices to sum", async () => {
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("0.3"));
    const block0 = await provider.getBlock("latest");
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("0.4"));
    const block1 = await provider.getBlock("latest");
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("0.5"));
    const block2 = await provider.getBlock("latest");
    await oracleContract.updateBuffer(BUFFER_ID, parseEther("0.6"));
    const block3 = await provider.getBlock("latest");

    const result0 = await oracleContract.readSumAndTimestampForPool(
      BUFFER_ID,
      0
    );
    const result1 = await oracleContract.readSumAndTimestampForPool(
      BUFFER_ID,
      1
    );
    const result2 = await oracleContract.readSumAndTimestampForPool(
      BUFFER_ID,
      2
    );
    const result3 = await oracleContract.readSumAndTimestampForPool(
      BUFFER_ID,
      3
    );

    expect(result0.timestamp).to.equal(block0.timestamp);
    expect(result0.cumulativeSum).to.equal(parseEther("0.3"));

    expect(result1.cumulativeSum).to.equal(
      parseEther("0.4")
        .mul(block1.timestamp - block0.timestamp)
        .add(result0.cumulativeSum)
    );

    expect(result2.cumulativeSum).to.equal(
      parseEther("0.5")
        .mul(block2.timestamp - block1.timestamp)
        .add(result1.cumulativeSum)
    );

    expect(result3.cumulativeSum).to.equal(
      parseEther("0.6")
        .mul(block3.timestamp - block2.timestamp)
        .add(result2.cumulativeSum)
    );
  });
});
