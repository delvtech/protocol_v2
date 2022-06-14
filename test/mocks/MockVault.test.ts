import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import {
  MockAsset,
  MockAsset__factory,
  MockVault,
  MockVault__factory,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "../helpers/snapshots";
import {
  MOCK_ASSET_TOKEN_NAME,
  MOCK_ASSET_TOKEN_SUPPLY,
  MOCK_ASSET_TOKEN_SYMBOL,
} from "./MockAsset.test";

const { provider } = waffle;

export const MOCK_SHARE_TOKEN_NAME = "MockShareToken";
export const MOCK_SHARE_TOKEN_SYMBOL = "xMAT";

const ONE_MILLION_ETHER = ethers.utils.parseEther("1000000");

describe.only("MockVault", async () => {
  let asset: MockAsset;
  let vault: MockVault;
  let owner: SignerWithAddress;

  let user: SignerWithAddress;
  before(async () => {
    [owner, user] = await ethers.getSigners();

    vault = await new MockVault__factory().connect(owner).deploy(user.address);

    vault = vault.connect(user);
    const _asset = await vault.asset();
    asset = MockAsset__factory.connect(_asset, user);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  it(`should have correct owner`, async () => {
    const _owner = await vault.owner();
    expect(_owner).to.be.eq(owner.address);
  });

  describe("deployment", async () => {
    it("should initialise $xMAT", async () => {
      const name = await vault.name();
      const symbol = await vault.symbol();
      const decimals = await vault.decimals();

      expect(name).to.be.eq(MOCK_SHARE_TOKEN_NAME);
      expect(symbol).to.be.eq(MOCK_SHARE_TOKEN_SYMBOL);
      expect(decimals).to.be.eq(18);
    });

    it("should deploy $MAT", async () => {
      const name = await asset.name();
      const symbol = await asset.symbol();
      const decimals = await asset.decimals();

      expect(name).to.be.eq(MOCK_ASSET_TOKEN_NAME);
      expect(symbol).to.be.eq(MOCK_ASSET_TOKEN_SYMBOL);
      expect(decimals).to.be.eq(18);
    });

    it("should initialise $MAT with correct supply", async () => {
      const totalSupply = await asset.totalSupply();
      expect(totalSupply).to.be.eq(ONE_MILLION_ETHER);
    });

    it("should mint initial $MAT supply to specified receiver", async () => {
      const balance = await asset.balanceOf(user.address);
      expect(balance).to.be.eq(ONE_MILLION_ETHER);
    });

    it("should set correct owner for both $MAT and vault contracts", async () => {
      const assetOwner = await asset.owner();
      const vaultOwner = await vault.owner();
      expect(assetOwner).to.be.eq(vault.address);
      expect(vaultOwner).to.be.eq(owner.address);
    });

    it(`should have 0 assets deposited and 0 shares issued`, async () => {
      const totalAssets = await vault.totalAssets();
      const totalShares = await vault.totalSupply();

      expect(totalAssets).to.be.eq(ethers.constants.Zero);
      expect(totalShares).to.be.eq(ethers.constants.Zero);
    });

    it(`should initially price assets:shares as 1:1`, async () => {
      const sharesPerAsset = await vault.convertToShares(ethers.constants.One);
      const assetsPerShare = await vault.convertToAssets(ethers.constants.One);

      expect(sharesPerAsset).to.be.eq(ethers.constants.One);
      expect(assetsPerShare).to.be.eq(ethers.constants.One);
    });
  });

  describe;
});
