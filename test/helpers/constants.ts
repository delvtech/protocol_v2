import { ethers } from "ethers";

export const ZERO = ethers.constants.Zero;
export const ONE_ETHER = ethers.utils.parseEther("1");

export const ONE_THOUSAND_ETHER = ethers.utils.parseEther("1000");

export const HUNDRED_THOUSAND_ETHER = ONE_THOUSAND_ETHER.mul(100);

export const MAX_UINT256 = ethers.constants.MaxUint256;
