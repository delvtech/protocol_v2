import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import forEach from "mocha-each";
import fp from "evm-fp";
import { BigNumber as MathjsBigNumber, all, create } from "mathjs";
import { MockYieldSpaceMath } from "../../typechain-types";
import testTrades from "./testTradesV2.json";

const config = {
  number: "BigNumber",
  precision: 79,
};
const math = create(all, config)!;
const mbn = math.bignumber!;

function abs(x: string): string {
  return (<MathjsBigNumber>math.abs!(mbn(x))).toString();
}

function add(x: string, y: string): string {
  return (<MathjsBigNumber>math.add!(mbn(x), mbn(y))).toString();
}

function sub(x: string, y: string): string {
  return (<MathjsBigNumber>math.subtract!(mbn(x), mbn(y))).toString();
}

function mul(x: string, y: string): string {
  return (<MathjsBigNumber>math.multiply!(mbn(x), mbn(y))).toString();
}

function div(x: string, y: string): string {
  return (<MathjsBigNumber>math.divide!(mbn(x), mbn(y))).toString();
}
// This simulation loads the data from ./testTrades.json and makes sure that
// our quotes are with-in episilon of the quotes from the python script
describe("YieldSpaceMath Numerical Accuracy Tests", function () {
  let DECIMALS: number;
  let EPSILON: number;
  let epsilon: number;
  let mockYieldSpaceMath: MockYieldSpaceMath;

  interface TradeData {
    input: {
      amount_in: number;
      x_reserves: number;
      y_reserves: number;
      total_supply: number;
      time: number;
      c: number;
      u: number;
      token_in: string;
      token_out: string;
      direction: string;
    };
    output: {
      fee: number;
      amount_out: number;
    };
  }

  before(async () => {
    DECIMALS = (testTrades as any).init.decimals;
    EPSILON = Math.max(10, 18 - DECIMALS + 1);
    epsilon = Number(ethers.utils.parseUnits("1", EPSILON));
    const factory = await ethers.getContractFactory("MockYieldSpaceMath");
    mockYieldSpaceMath = await factory.deploy();
  });

  forEach(testTrades.trades).it(
    "handles trade 1",
    async function (trade: TradeData) {
      const expected = trade.output.amount_out;
      const isBondOut = trade.input.token_out === "fyt";
      const shareReserves = fp(
        div(trade.input.x_reserves.toString(), trade.input.c.toString())
      );
      const amountIn = fp(
        div(trade.input.amount_in.toString(), trade.input.c.toString())
      );
      const result: BigNumber = await mockYieldSpaceMath.calculateOutGivenIn(
        shareReserves.toString(),
        fp(trade.input.y_reserves.toString()),
        fp(trade.input.total_supply.toString()),
        amountIn.toString(),
        fp(trade.input.time.toString()),
        fp("1"),
        fp(trade.input.c.toString()),
        fp(trade.input.u.toString()),
        isBondOut
      );
      const delta = Number(
        abs(sub(div(result.toString(), "1e18"), expected.toString()))
      );
      expect(delta).to.be.lessThanOrEqual(epsilon);
    }
  );
});
