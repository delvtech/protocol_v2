import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

describe("Aave Proxy Tests", async () => {
  let signers: SignerWithAddress[];

  before(async () => {
    signers = await ethers.getSigners();
  });
});
