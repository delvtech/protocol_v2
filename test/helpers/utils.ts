import { BigNumber, ethers } from "ethers";

export const printEther = (num: BigNumber): void => {
  console.log(ethers.utils.formatEther(num));
};
