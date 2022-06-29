import { ethers } from "hardhat";
import { expect } from "chai";
import { MockFixedPointMath } from "typechain-types";

describe("FixedPointMath Tests", async () => {
  let MockFixedPointMath: MockFixedPointMath;

  before(async () => {
    const factory = await ethers.getContractFactory("MockFixedPointMath");
    MockFixedPointMath = await factory.deploy();
  });

  describe("Balancer pow(), Balancer ln(), Remco exp()", async () => {
    it("int^int", async () => {
      const epsilon = 16;
      const x = ethers.utils.parseUnits("2", 18);
      const y = ethers.utils.parseUnits("3", 18);
      const answer = ethers.utils.parseUnits("8", 18);
      const result = await MockFixedPointMath.pow(x, y);
      expect(answer.sub(result).abs().lte(epsilon)).to.be.eq(true);
    });

    it("int^decimal", async () => {
      const epsilon = 1;
      const x = ethers.utils.parseUnits("4", 18);
      const y = ethers.utils.parseUnits(".5", 18);
      const answer = ethers.utils.parseUnits("2", 18);
      const result = await MockFixedPointMath.pow(x, y);
      expect(answer.sub(result).abs().lte(epsilon)).to.be.eq(true);
    });

    it("decimal^decimal", async () => {
      const epsilon = 1;
      const x = ethers.utils.parseUnits(".25", 18);
      const y = ethers.utils.parseUnits(".5", 18);
      const answer = ethers.utils.parseUnits(".5", 18);
      const result = await MockFixedPointMath.pow(x, y);
      expect(answer.sub(result).abs().lte(epsilon)).to.be.eq(true);
    });
  });

  describe("Balancer pow(), Balancer ln(), Balancer exp()", async () => {
    it("int^int", async () => {
      const epsilon = 16;
      const x = ethers.utils.parseUnits("2", 18);
      const y = ethers.utils.parseUnits("3", 18);
      const answer = ethers.utils.parseUnits("8", 18);
      const result = await MockFixedPointMath.pow2(x, y);
      expect(answer.sub(result).abs().lte(epsilon)).to.be.eq(true);
    });

    it("int^decimal", async () => {
      const epsilon = 2;
      const x = ethers.utils.parseUnits("4", 18);
      const y = ethers.utils.parseUnits(".5", 18);
      const answer = ethers.utils.parseUnits("2", 18);
      const result = await MockFixedPointMath.pow2(x, y);
      expect(answer.sub(result).abs().lte(epsilon)).to.be.eq(true);
    });

    it("decimal^decimal", async () => {
      const epsilon = 1;
      const x = ethers.utils.parseUnits(".25", 18);
      const y = ethers.utils.parseUnits(".5", 18);
      const answer = ethers.utils.parseUnits(".5", 18);
      const result = await MockFixedPointMath.pow2(x, y);
      expect(answer.sub(result).abs().lte(epsilon)).to.be.eq(true);
    });
  });
});
