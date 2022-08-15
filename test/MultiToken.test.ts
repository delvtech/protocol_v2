import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import {
  MockMultiToken,
  ForwarderFactory,
  ERC20Forwarder,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getDigest, getDigestAll } from "./helpers/signatures";
import { impersonate } from "./helpers/impersonate";
import { ecsign } from "ethereumjs-util";

const { provider } = waffle;

describe("MultiToken", async () => {
  let token: MockMultiToken;
  let factory: ForwarderFactory;
  let signers: SignerWithAddress[];
  const token1 = "0x1";
  const token2 =
    "0x50331487306a5282e0eb5438db32c4d414a9fed9a045489f59a08b1257f465ef";
  const ten = ethers.utils.parseEther("10");
  const five = ethers.utils.parseEther("5");

  before(async () => {
    signers = await ethers.getSigners();
    const factoryFactory = await ethers.getContractFactory(
      "ForwarderFactory",
      signers[0]
    );
    factory = await factoryFactory.deploy();
    const multiTokenDeployer = await ethers.getContractFactory(
      "MockMultiToken",
      signers[0]
    );
    token = await multiTokenDeployer.deploy(
      await factory.ERC20LINK_HASH(),
      factory.address
    );

    await token.setBalance(token1, signers[0].address, ten);
    await token.setBalance(token2, signers[0].address, five);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("Transfer", async () => {
    it("Cannot transfer more than the user has", async () => {
      let tx = token.transferFrom(
        token1,
        signers[0].address,
        signers[1].address,
        ten.add(1)
      );
      await expect(tx).to.be.reverted;
      tx = token.transferFrom(
        token2,
        signers[0].address,
        signers[1].address,
        ethers.utils.parseEther("5").add(1)
      );
      await expect(tx).to.be.reverted;
    });

    it("Cannot transfer for another user", async () => {
      let tx = token
        .connect(signers[1])
        .transferFrom(
          token1,
          signers[0].address,
          signers[1].address,
          ten.sub(1)
        );
      await expect(tx).to.be.reverted;
      tx = token
        .connect(signers[1])
        .transferFrom(
          token2,
          signers[0].address,
          signers[1].address,
          ethers.utils.parseEther("5").sub(1)
        );
      await expect(tx).to.be.reverted;
    });

    it("Transfers user funds correctly", async () => {
      // Try the smallest possible transfer
      await token.transferFrom(
        token1,
        signers[0].address,
        signers[1].address,
        1
      );
      expect(await token.balanceOf(token1, signers[0].address)).to.be.eq(
        ten.sub(1)
      );
      expect(await token.balanceOf(token1, signers[1].address)).to.be.eq(1);
      // Try the largest possible transfer
      await token.transferFrom(
        token1,
        signers[0].address,
        signers[1].address,
        ten.sub(1)
      );
      expect(await token.balanceOf(token1, signers[0].address)).to.be.eq(0);
      expect(await token.balanceOf(token1, signers[1].address)).to.be.eq(ten);
      // something something something intermediate value theorem

      // Try both again on the second token

      await token.transferFrom(
        token2,
        signers[0].address,
        signers[1].address,
        1
      );
      expect(await token.balanceOf(token2, signers[0].address)).to.be.eq(
        five.sub(1)
      );
      expect(await token.balanceOf(token2, signers[1].address)).to.be.eq(1);

      await token.transferFrom(
        token2,
        signers[0].address,
        signers[1].address,
        five.sub(1)
      );
      expect(await token.balanceOf(token2, signers[0].address)).to.be.eq(0);
      expect(await token.balanceOf(token2, signers[1].address)).to.be.eq(five);
    });
  });

  describe("Approvals", async () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });

    afterEach(async () => {
      await restoreSnapshot(provider);
    });

    it("Approval for all allows transfer of both tokens", async () => {
      await token.setApprovalForAll(signers[1].address, true);

      await token
        .connect(signers[1])
        .transferFrom(token1, signers[0].address, signers[1].address, ten);
      await token
        .connect(signers[1])
        .transferFrom(token2, signers[0].address, signers[1].address, five);

      expect(await token.balanceOf(token1, signers[0].address)).to.be.eq(0);
      expect(await token.balanceOf(token1, signers[1].address)).to.be.eq(ten);
      expect(await token.balanceOf(token2, signers[0].address)).to.be.eq(0);
      expect(await token.balanceOf(token2, signers[1].address)).to.be.eq(five);
    });

    it("Per token approvals allow transfer to a limit", async () => {
      await token.setApproval(token1, signers[1].address, five);

      await token
        .connect(signers[1])
        .transferFrom(
          token1,
          signers[0].address,
          signers[1].address,
          five.sub(1)
        );
      const tx = token
        .connect(signers[1])
        .transferFrom(token1, signers[0].address, signers[1].address, 10);
      await expect(tx).to.be.reverted;
      expect(
        await token.perTokenApprovals(
          token1,
          signers[0].address,
          signers[1].address
        )
      ).to.be.eq(1);
      expect(await token.balanceOf(token1, signers[1].address)).to.be.eq(
        five.sub(1)
      );
      expect(await token.balanceOf(token1, signers[0].address)).to.be.eq(
        five.add(1)
      );
    });

    it("Per token approvals set to max are infinite", async () => {
      await token.setApproval(
        token1,
        signers[1].address,
        ethers.constants.MaxUint256
      );

      await token
        .connect(signers[1])
        .transferFrom(token1, signers[0].address, signers[1].address, five);

      const approvalAfter = await token.perTokenApprovals(
        token1,
        signers[0].address,
        signers[1].address
      );
      expect(approvalAfter).to.be.eq(ethers.constants.MaxUint256);
      expect(await token.balanceOf(token1, signers[1].address)).to.be.eq(five);
      expect(await token.balanceOf(token1, signers[0].address)).to.be.eq(five);
    });
  });

  describe("PermitForAll", async () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });

    afterEach(async () => {
      await restoreSnapshot(provider);
    });

    it("Successful permit all", async () => {
      const [wallet] = provider.getWallets();
      const domainSeparator = await token.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigestAll(
        "USD Coin",
        domainSeparator,
        token.address,
        wallet.address,
        signers[2].address,
        true,
        nonce,
        ethers.constants.MaxUint256
      );
      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      await token
        .connect(signers[1])
        .permitForAll(
          wallet.address,
          signers[2].address,
          true,
          ethers.constants.MaxUint256,
          v,
          r,
          s
        );
      // check that nonce increases
      expect(await token.nonces(wallet.address)).to.eq(1);
      // check that approval allows transfer of both tokens
      await token
        .connect(signers[2])
        .transferFrom(token1, wallet.address, signers[2].address, ten);
      await token
        .connect(signers[2])
        .transferFrom(token2, wallet.address, signers[2].address, five);
      expect(await token.balanceOf(token1, wallet.address)).to.be.eq(0);
      expect(await token.balanceOf(token1, signers[2].address)).to.be.eq(ten);
      expect(await token.balanceOf(token2, wallet.address)).to.be.eq(0);
      expect(await token.balanceOf(token2, signers[2].address)).to.be.eq(five);
    });
    it("Fails invalid signature", async () => {
      const [wallet] = provider.getWallets();
      const domainSeparator = await token.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigestAll(
        "USD Coin",
        domainSeparator,
        token.address,
        wallet.address,
        signers[2].address,
        true,
        nonce,
        ethers.constants.MaxUint256
      );
      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      const tx = token
        .connect(signers[1])
        .permitForAll(
          wallet.address,
          signers[2].address,
          true,
          ethers.constants.MaxUint256,
          v + 2,
          r,
          s
        );
      await expect(tx).to.be.revertedWith(
        "MultiToken__PermitForAll_OwnerIsNotSigner()"
      );
    });
    it("Fails invalid deadline", async () => {
      const badDeadline = 0;
      const [wallet] = provider.getWallets();
      const domainSeparator = await token.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigestAll(
        "USD Coin",
        domainSeparator,
        token.address,
        wallet.address,
        signers[2].address,
        true,
        nonce,
        badDeadline
      );
      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      const tx = token
        .connect(signers[1])
        .permitForAll(
          wallet.address,
          signers[2].address,
          true,
          badDeadline,
          v,
          r,
          s
        );
      await expect(tx).to.be.revertedWith(
        "MultiToken__PermitForAll_ExpiredDeadline()"
      );
    });
    it("Fails for zero address", async () => {
      const [wallet] = provider.getWallets();
      const domainSeparator = await token.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigestAll(
        "USD Coin",
        domainSeparator,
        token.address,
        wallet.address,
        signers[2].address,
        true,
        nonce,
        ethers.constants.MaxUint256
      );
      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      const tx = token
        .connect(signers[1])
        .permitForAll(
          "0x0000000000000000000000000000000000000000",
          signers[2].address,
          true,
          ethers.constants.MaxUint256,
          v,
          r,
          s
        );
      await expect(tx).to.be.revertedWith(
        "MultiToken__PermitForAll_OwnerIsZeroAddress()"
      );
    });
  });

  describe("ERC20 Link Tests", async () => {
    let erc20: ERC20Forwarder;

    before(async () => {
      // Create the actual token
      await factory.create(token.address, token1);
      const erc20Address = await factory.getForwarder(token.address, token1);
      const erc20ContractFactory = await ethers.getContractFactory(
        "ERC20Forwarder",
        signers[0]
      );
      erc20 = erc20ContractFactory.attach(erc20Address);
    });

    it("Blocks non forwarder calls to admin functions", async () => {
      let tx = token.setApprovalBridge(
        token1,
        signers[0].address,
        1,
        signers[0].address
      );
      await expect(tx).to.be.reverted;
      tx = token.transferFromBridge(
        token1,
        signers[0].address,
        signers[0].address,
        1,
        signers[0].address
      );
      await expect(tx).to.be.reverted;
    });

    it("Forwards approval calls properly", async () => {
      await erc20.approve(signers[1].address, ten);
      const ercApproval = await erc20.allowance(
        signers[0].address,
        signers[1].address
      );
      const approval = await token.perTokenApprovals(
        token1,
        signers[0].address,
        signers[1].address
      );
      expect(approval).to.be.eq(ten);
      expect(ercApproval).to.be.eq(ten);
    });

    it("Loads an approval for all allowance right", async () => {
      await token.setApprovalForAll(signers[2].address, true);
      const allowance = await erc20.allowance(
        signers[0].address,
        signers[2].address
      );
      expect(allowance).to.be.eq(ethers.constants.MaxUint256);
    });

    it("Forwards transfer from correctly", async () => {
      await erc20.transfer(signers[1].address, five);
      const balance0 = await token.balanceOf(token1, signers[0].address);
      const balance1 = await token.balanceOf(token1, signers[1].address);
      expect(balance0).to.be.eq(five);
      expect(balance1).to.be.eq(five);
      const balance0Erc = await erc20.balanceOf(signers[0].address);
      const balance1Erc = await erc20.balanceOf(signers[1].address);
      expect(balance0Erc).to.be.eq(five);
      expect(balance1Erc).to.be.eq(five);
    });

    it("Forwards transferFrom properly", async () => {
      await erc20.approve(signers[1].address, ten);
      await erc20
        .connect(signers[1])
        .transferFrom(signers[0].address, signers[1].address, five);
      const balance0 = await token.balanceOf(token1, signers[0].address);
      const balance1 = await token.balanceOf(token1, signers[1].address);
      expect(balance0).to.be.eq(five);
      expect(balance1).to.be.eq(five);
      const balance0Erc = await erc20.balanceOf(signers[0].address);
      const balance1Erc = await erc20.balanceOf(signers[1].address);
      expect(balance0Erc).to.be.eq(five);
      expect(balance1Erc).to.be.eq(five);
    });

    it("Gets state methods right", async () => {
      await token.setNameAndSymbol(token1, "Test Token", "TEST");
      expect(await erc20.name()).to.be.eq("Test Token");
      expect(await erc20.symbol()).to.be.eq("TEST");
      expect(await erc20.decimals()).to.be.eq(18);
    });

    it("Successful permit call", async () => {
      const [wallet] = provider.getWallets();
      const domainSeparator = await erc20.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigest(
        "USD Coin",
        domainSeparator,
        erc20.address,
        wallet.address,
        erc20.address,
        ethers.constants.MaxUint256,
        nonce,
        ethers.constants.MaxUint256
      );
      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      await erc20
        .connect(signers[0])
        .permit(
          wallet.address,
          erc20.address,
          ethers.constants.MaxUint256,
          ethers.constants.MaxUint256,
          v,
          r,
          s
        );
      // check that nonce increases
      expect(await erc20.nonces(wallet.address)).to.eq(1);
      // check the approval
      expect(await erc20.allowance(wallet.address, erc20.address)).to.eq(
        ethers.constants.MaxUint256
      );
    });

    it("Fails invalid permit", async () => {
      const [wallet] = provider.getWallets();
      const domainSeparator = await erc20.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigest(
        "USD Coin",
        domainSeparator,
        erc20.address,
        wallet.address,
        erc20.address,
        ethers.constants.MaxUint256,
        nonce,
        ethers.constants.MaxUint256
      );
      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      // impersonate wallet to get Signer for connection
      impersonate(wallet.address);
      const walletSigner = ethers.provider.getSigner(wallet.address);
      const tx = erc20
        .connect(walletSigner)
        .permit(
          wallet.address,
          erc20.address,
          ethers.constants.MaxUint256,
          ethers.constants.MaxUint256,
          v + 2,
          r,
          s
        );
      await expect(tx).to.be.revertedWith(
        "ERC20Forwarder__Permit_OwnerIsNotSigner()"
      );
    });
  });
});
