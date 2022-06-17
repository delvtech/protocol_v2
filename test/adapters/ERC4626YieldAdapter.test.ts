import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, waffle } from "hardhat";
import { ERC20, ERC20__factory, ERC4626YieldAdapter } from "typechain-types";
import { createSnapshot, restoreSnapshot } from "../helpers/snapshots";

const { provider } = waffle;

describe("ERC4626YieldAdapter", async () => {
  let token: ERC20;
  let vault: ERC4626YieldAdapter;

  let deployer: SignerWithAddress;
  let user: SignerWithAddress;

  before(async () => {
    [deployer] = await ethers.getSigners();
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("Transfer", async () => {
    return;
  });
});
