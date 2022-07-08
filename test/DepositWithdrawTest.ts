import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { MockYieldAdapter } from "typechain/MockYieldAdapter";
import { MockERC20YearnVault } from "typechain/MockERC20YearnVault";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { ForwarderFactory } from "typechain/ForwarderFactory";
import { TestERC20 } from "typechain/TestERC20";
import { advanceTime, getCurrentTimestamp, ONE_YEAR_IN_SECONDS, ONE_MINUTE_IN_SECONDS, ONE_WEEK_IN_SECONDS } from "./helpers/time";
import { BigNumber } from "ethers";


const { provider } = waffle;

// NOTE: broken placeholder ID maths
const YT_FLAG = 1 << 256;
function createID(start: number, expiration: number) {
    return YT_FLAG + (start * (2**128) + expiration);
}

describe("Deposit Tests", async () => {

  let token: TestERC20;
  let token2: TestERC20;
  let vault: MockERC20YearnVault;
  let yieldAdapter: MockYieldAdapter;
  let factory: ForwarderFactory;
  let signers: SignerWithAddress[];
  const token1 = "0x1";

  before(async () => {
    signers = await ethers.getSigners();
    const factoryFactory = await ethers.getContractFactory(
        "ForwarderFactory",
        signers[0]
      );
    factory = await factoryFactory.deploy();
    const tokenFactory = await ethers.getContractFactory(
        "TestERC20",
        signers[0]
      );
    token = await tokenFactory.deploy("token", "TKN", 18);
    token2 = await tokenFactory.deploy("USDC", "USDC", 18);
    const vaultFactory = await ethers.getContractFactory(
      "MockERC20YearnVault",
      signers[0]
    );
    vault = await vaultFactory.deploy(token.address);
    const adapterFactory = await ethers.getContractFactory(
      "MockYieldAdapter",
      signers[0]
    );
    yieldAdapter = await adapterFactory.deploy(
      vault.address,
      await factory.ERC20LINK_HASH(),
      factory.address,
      token.address
    );


    // TODO: probably loop this for multiple users so cleaner
    // set some token balance
    await token.mint(signers[0].address, 7e6);
    await token.mint(signers[1].address, 7e6);
    // set allowance for the yieldAdapter contract
    await token.connect(signers[0]).approve(yieldAdapter.address, 12e6);
    await token.connect(signers[1]).approve(yieldAdapter.address, 12e6); 
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe.only("Lock", async () => {
    it("Fails invalid expiry", async () => {
      const start = await getCurrentTimestamp(provider) + 1;
      const tx = yieldAdapter.lock(
        [],
        [],
        100,
        signers[0].address,
        signers[0].address,
        start,
        start - 1e6 // unix timestamp from the past
      );
      await expect(tx).to.be.revertedWith("todo nice error");
    });

    it.only("Single user successfully deposit underlying", async () => {
      const startBalance = await token.balanceOf(signers[0].address);
      // create beginning timestamp offset by a second to account for execution
      const start = await getCurrentTimestamp(provider);
      // create expiry timestamp in the future
      const expiration = start + ONE_YEAR_IN_SECONDS;
      await yieldAdapter.lock(
        [],
        [],
        1000,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
      const id = createID(start, expiration);

    //   // deploy ERC20Forwarder for the YT created
    //   await factory.create(yieldAdapter.address, ytID);
    //   const erc20Address = await factory.getForwarder(yieldAdapter.address, ytID);
    //   const erc20ContractFactory = await ethers.getContractFactory(
    //     "ERC20Forwarder",
    //     signers[0]
    //   );
    //   erc20 = erc20ContractFactory.attach(erc20Address);
    //   const ytBalance = await erc20.balanceOf(signers[0].address);

      // check that user's underlying balance decreased
      expect(await token.balanceOf(signers[0].address)).to.equal(startBalance.toNumber() - 1000);
      // check that vault's balance increased
      expect(await token.balanceOf(vault.address)).to.equal(5);
      // check that YT balance has increased
      expect(await yieldAdapter.balanceOf(id, signers[0].address)).to.equal(0); // todo: amount
    });

    it("Deposit underlying with different destination", async () => {
        const startBalance = await token.balanceOf(signers[0].address);
        // create beginning timestamp
        // TODO: logic with time is off, other function doesn't work as expected here
        const start = Math.floor(Date.now() / 1000);
      //   const now = await getCurrentTimestamp(provider);
        // create expiry timestamp in the future
        const expiration = start + ONE_YEAR_IN_SECONDS;
        await yieldAdapter.lock(
          [],
          [],
          5,
          signers[0].address,
          signers[1].address,
          start,
          expiration
        );
        // check that user's balance decreased
        expect(await token.balanceOf(signers[0].address)).to.equal(startBalance.toNumber() - 5);
        // check that vault's balance increased
        expect(await token.balanceOf(vault.address)).to.equal(5);
      });

    it("Multiple users successfully deposit underlying", async () => {
      // create beginning timestamp
      const start = Math.floor(Date.now() / 1000);
    //   const start = await getCurrentTimestamp(provider);
      // create expiry timestamp in the future
      const expiration = start + ONE_YEAR_IN_SECONDS;
      await yieldAdapter
        .connect(signers[0])
        .lock(
          [],
          [],
          5,
          signers[0].address,
          signers[0].address,
          start,
          expiration
        );
      await yieldAdapter
        .connect(signers[1])
        .lock(
          [],
          [],
          5,
          signers[1].address,
          signers[1].address,
          start,
          expiration
        );
      // check that user's balance decreased
      expect(await token.balanceOf(signers[0].address)).to.equal(7e6 - 5);
      expect(await token.balanceOf(signers[1].address)).to.equal(7e6 - 5);
      // check that vault's balance increased
      expect(await token.balanceOf(vault.address)).to.equal(10);
    });

    it("Users deposit underlying, time in between", async () => {
        // create beginning timestamp
        let start = Math.floor(Date.now() / 1000);
      //   const start = await getCurrentTimestamp(provider);
        // create expiry timestamp in the future
        let expiration = start + ONE_YEAR_IN_SECONDS;
        await yieldAdapter
          .connect(signers[0])
          .lock(
            [],
            [],
            5,
            signers[0].address,
            signers[0].address,
            start,
            expiration
          );
        await advanceTime(provider, start + ONE_YEAR_IN_SECONDS/2);
        start = Math.floor(Date.now() / 1000);
        expiration = start + ONE_YEAR_IN_SECONDS;
        await yieldAdapter
          .connect(signers[1])
          .lock(
            [],
            [],
            5,
            signers[1].address,
            signers[1].address,
            start,
            expiration
          );
        // check that user's balance decreased
        expect(await token.balanceOf(signers[0].address)).to.equal(7e6 - 5);
        expect(await token.balanceOf(signers[1].address)).to.equal(7e6 - 5);
        // check that vault's balance increased
        expect(await token.balanceOf(vault.address)).to.equal(10);
      });

    it("Deposit underlying with zero expiry", async () => {
      // create beginning timestamp
      const now = Math.floor(Date.now() / 1000);
      const id = createID(now, 0);
      const tx = yieldAdapter.lock(
        [],
        [],
        100,
        signers[0].address,
        signers[0].address,
        now,
        0
      );
      // check that YT's have been minted at the unlock ID
      await yieldAdapter.balanceOf(id, signers[0].address);
    });

    it("Valid backdating deposit", async () => {
      // TODO: this is not structured correctly
      const tx = yieldAdapter.lock(
        [],
        [],
        100,
        signers[0].address,
        signers[0].address,
        Math.floor(Date.now() / 1000),
        806774400 // unix timestamp from the past
      );
      await expect(tx).to.be.revertedWith("todo nice error");
    });

    // it.only("time travel", async () => {
    //     // // let t1 = now();
    //     // // console.log(t1);
    //     // // await advanceTime(provider, SIX_MONTHS_IN_SECONDS);
    //     // // t1 = now();
    //     // console.log(t1);
    //     console.log("--");
    //     let t2 = await getCurrentTimestamp(provider);
    //     console.log(t2);
    //     await advanceTime(provider, SIX_MONTHS_IN_SECONDS);
    //     t2 = await getCurrentTimestamp(provider);
    //     console.log(t2);
    // });

  });
//   describe("Unlock", async () => {
//     it("Unlock some reserves", async () => {
//       // deposit some underlying
//       const now = Math.floor(Date.now() / 1000);
//       const expiration = now + 1;
//       await yieldAdapter.lock(
//         [],
//         [],
//         5,
//         signers[0].address,
//         signers[0].address,
//         now,
//         expiration
//       );
//       const id = (1 << (255 + now)) << (128 + expiration);
//       const tx = await yieldAdapter.unlock(signers[0].address, [id], [1]);
//       // think I need to wait here, gives a weird division by zero
//     });
//   });
});
