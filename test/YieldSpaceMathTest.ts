import { ethers } from "hardhat";
import chai, { expect } from "chai";
import { MockYieldSpaceMath } from "typechain-types";
import fp from "evm-fp";
import forEach from "mocha-each";
import { BigNumber as MathjsBigNumber, all, create } from "mathjs";
import { StringifyOptions } from "querystring";

const config = {
  number: "BigNumber",
  precision: 79,
};

const math = create(all, config)!;
const mbn = math.bignumber!;

describe("YieldSpaceMath Tests", function () {
  let MockYieldSpaceMath: MockYieldSpaceMath;

  before(async () => {
    const factory = await ethers.getContractFactory("MockYieldSpaceMath");
    MockYieldSpaceMath = await factory.deploy();
  });

  describe("calculateBondOutGivenShareIn()", function () {
    // [shareReserves, bondReserves, totalSupply, shareIn, t, s, c, mu]
    const testSets = [
      [
        "56.79314253",
        "62.38101813",
        "119.1741606776616",
        "5.03176076",
        "0.08065076081220067",
        "1",
        "1",
        "1",
      ],
    ];
    forEach(testSets).it(
      "handles trade 1",
      async function (
        shareReserves: string,
        bondReserves: string,
        totalSupply: string,
        shareIn: string,
        t: string,
        s: string,
        c: string,
        mu: string
      ) {
        const expected = fp("5.500250311701939");
        const result = await MockYieldSpaceMath.calculateOutGivenIn(
          fp(shareReserves),
          fp(bondReserves),
          fp(totalSupply),
          fp(shareIn),
          fp(t),
          fp(s),
          fp(c),
          fp(mu),
          true
        );
        // console.log(Number(ethers.utils.formatEther(result)));
        // console.log(Number(ethers.utils.formatEther(expected)));
        expect(Number(ethers.utils.formatEther(result))).to.be.equal(
          Number(ethers.utils.formatEther(expected))
        );
      }
    );
  });

  describe("calculateShareOutGivenBondIn()", function () {
    // [shareReserves, bondReserves, totalSupply, bondIn, t, s, c, mu]
    const testSets = [
      [
        "61.824903300361854",
        "56.92761678068477",
        "119.1741606776616",
        "5.500250311701939",
        "0.08065076081220067",
        "1",
        "1",
        "1",
      ],
    ];
    forEach(testSets).it(
      "handles trade 1",
      async function (
        shareReserves: string,
        bondReserves: string,
        totalSupply: string,
        bondIn: string,
        t: string,
        s: string,
        c: string,
        mu: string
      ) {
        const expected = fp("5.031654806080805");
        const result = await MockYieldSpaceMath.calculateOutGivenIn(
          fp(shareReserves),
          fp(bondReserves),
          fp(totalSupply),
          fp(bondIn),
          fp(t),
          fp(s),
          fp(c),
          fp(mu),
          false
        );
        // console.log(Number(ethers.utils.formatEther(result)));
        // console.log(Number(ethers.utils.formatEther(expected)));
        expect(Number(ethers.utils.formatEther(result))).to.be.equal(
          Number(ethers.utils.formatEther(expected))
        );
      }
    );
  });
});
