import { waffle } from "hardhat";

const { provider } = waffle;

export const advanceTime = async (time: number) => {
  await provider.send("evm_increaseTime", [time]);
  await provider.send("evm_mine", []);
};
