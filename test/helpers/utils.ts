import { BigNumber, ethers } from "ethers";

export const printEther = (num: BigNumber): void => {
  console.log(ethers.utils.formatEther(num));
};

export const now = () => Math.floor(Date.now() / 1000);

export const $ether = (s: string | number) =>
  ethers.utils.parseEther(s.toString());
