import { TestDynamicArray } from "typechain-types/mocks/TestDynamicArray";
import { TestDynamicArray__factory } from "typechain-types/factories/mocks/TestDynamicArray__factory";
import { Signer } from "ethers";
import { expect } from "chai";
import "module-alias/register";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { ethers, waffle } from "hardhat";

import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

describe.only("dynamicArrayTest", function () {
  let signers: SignerWithAddress[];
  let arrayContract: TestDynamicArray;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();

    const arrayDeployer = new TestDynamicArray__factory(signers[0] as Signer);

    arrayContract = await arrayDeployer.deploy();
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

  it("should add items", async () => {
    await arrayContract.addValue(1, 0, 1);
    const md1 = await arrayContract.readMetadata();
    expect(md1.toString()).to.equal("1");

    await arrayContract.addValue(1234123412341234, 1, 2);
    expect(true).to.equal(true);

    const md2 = await arrayContract.readMetadata();
    expect(md2.toString()).to.equal("1234123412341234");

    await arrayContract.addValue(1234, 2, 3);

    const result0 = await arrayContract.list(0);
    console.log("result0", result0);
    const result1 = await arrayContract.list(1);
    console.log("result1", result1);
    const result2 = await arrayContract.list(2);
    console.log("result2", result2);
    expect(true).to.equal(true);
  });

  it("should add items no keccak", async () => {
    await arrayContract.addValueNoKeccak(1, 0, 1);
    expect(true).to.equal(true);
    const md1 = await arrayContract.readMetadata();
    expect(md1.toString()).to.equal("1");

    await arrayContract.addValueNoKeccak(1234123412341234, 1, 2);
    expect(true).to.equal(true);

    const md2 = await arrayContract.readMetadata();
    expect(md2.toString()).to.equal("1234123412341234");

    await arrayContract.addValueNoKeccak(1234, 2, 3);

    const result0 = await arrayContract.list(0);
    console.log("result0", result0);
    const result1 = await arrayContract.list(1);
    console.log("result1", result1);
    const result2 = await arrayContract.list(2);
    console.log("result2", result2);
    expect(true).to.equal(true);
  });

  it("should add items using high level solidity", async () => {
    await arrayContract.addValueHighLevel(1, 0, 1);
    expect(true).to.equal(true);
    const md1 = await arrayContract.readMetadata();
    expect(md1.toString()).to.equal("1");

    await arrayContract.addValueHighLevel(1234123412341234, 1, 2);
    expect(true).to.equal(true);

    const md2 = await arrayContract.readMetadata();
    expect(md2.toString()).to.equal("1234123412341234");

    await arrayContract.addValueHighLevel(1234, 2, 3);

    const result0 = await arrayContract.list(0);
    console.log("result0", result0);
    const result1 = await arrayContract.list(1);
    console.log("result1", result1);
    const result2 = await arrayContract.list(2);
    console.log("result2", result2);
    expect(true).to.equal(true);
  });
});
