import { BigNumber } from "ethers";

// constructs a YT token ID for the given start and expiration
export function getTokenId(start: number, expiration: number) {
  // YTs are constructed with a leading 1
  const ytFlag = BigNumber.from(1).shl(255);
  // shift start by 128 bits
  const shiftedStart = BigNumber.from(start).shl(128);
  const id = ytFlag.add(shiftedStart).add(BigNumber.from(expiration));
  return id;
}
