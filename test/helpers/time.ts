import { ethers } from "ethers";
import hre from "hardhat";

export const HOUR = 3600;
export const DAY = 86400;
export const WEEK = 604800;
export const MONTH = 2629743;
export const YEAR = 31556926;

export const mine = async (seconds: number) => {
  const { timestamp: previous } = await hre.ethers.provider.getBlock("latest");
  const hexSeconds = ethers.utils.hexValue(seconds);
  await hre.network.provider.send("hardhat_mine", ["0x1", hexSeconds]);
  const { timestamp: latest } = await hre.ethers.provider.getBlock("latest");
  return { previous, latest, interval: latest - previous };
};
