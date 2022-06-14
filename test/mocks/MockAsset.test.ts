import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { MockAsset, MockAsset__factory } from "typechain-types";
import { createSnapshot, restoreSnapshot } from "../helpers/snapshots";

const { provider } = waffle;

export const MOCK_ASSET_TOKEN_NAME = "MockAssetToken";
export const MOCK_ASSET_TOKEN_SYMBOL = "MAT";
export const MOCK_ASSET_TOKEN_SUPPLY = ethers.utils.parseEther("100000");

describe("MockAsset", async () => {
  let asset: MockAsset;
  let assetOwner: SignerWithAddress;

  let user1: SignerWithAddress;
  before(async () => {
    [assetOwner, user1] = await ethers.getSigners();
    asset = await new MockAsset__factory()
      .connect(assetOwner)
      .deploy(MOCK_ASSET_TOKEN_SUPPLY, assetOwner.address);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  it(`should have correct owner`, async () => {
    const owner = await asset.owner();
    expect(owner).to.be.eq(assetOwner.address);
  });

  it(`should have correct name: ${MOCK_ASSET_TOKEN_NAME} and symbol: ${MOCK_ASSET_TOKEN_SYMBOL}`, async () => {
    const name = await asset.name();
    const symbol = await asset.symbol();

    expect(name).to.be.eq(MOCK_ASSET_TOKEN_NAME);
    expect(symbol).to.be.eq(MOCK_ASSET_TOKEN_SYMBOL);
  });

  it(`should have correct supply of ${ethers.utils.formatEther(
    MOCK_ASSET_TOKEN_SUPPLY
  )} ${MOCK_ASSET_TOKEN_SYMBOL}`, async () => {
    const totalSupply = await asset.totalSupply();
    expect(totalSupply).to.be.eq(MOCK_ASSET_TOKEN_SUPPLY);
  });

  it(`should have minted all of the initial supply to the owner`, async () => {
    const ownerBalance = await asset.balanceOf(assetOwner.address);
    expect(ownerBalance).to.be.eq(MOCK_ASSET_TOKEN_SUPPLY);
  });

  it(`should mint only to the owner`, async () => {
    const tx = asset.connect(user1).mint(ethers.utils.parseEther("1"));
    expect(tx).to.be.revertedWith("Sender not owner");

    await asset.connect(assetOwner).mint(ethers.utils.parseEther("1"));
    const ownerBalance = await asset.balanceOf(assetOwner.address);
    const newTotalSupply = MOCK_ASSET_TOKEN_SUPPLY.add(
      ethers.utils.parseEther("1")
    );
    expect(ownerBalance).to.be.eq(newTotalSupply);

    const totalSupply = await asset.totalSupply();
    expect(totalSupply).to.be.eq(newTotalSupply);
  });

  it(`should burn only from the owner`, async () => {
    const tx = asset.connect(user1).burn(ethers.utils.parseEther("1"));
    expect(tx).to.be.revertedWith("Sender not owner");

    await asset.connect(assetOwner).burn(ethers.utils.parseEther("1"));
    const ownerBalance = await asset.balanceOf(assetOwner.address);
    const newTotalSupply = MOCK_ASSET_TOKEN_SUPPLY.sub(
      ethers.utils.parseEther("1")
    );
    expect(ownerBalance).to.be.eq(newTotalSupply);

    const totalSupply = await asset.totalSupply();
    expect(totalSupply).to.be.eq(newTotalSupply);
  });
});
