import { MockProvider } from "ethereum-waffle";

export const mine = (provider: MockProvider) => provider.send('evm_mine', []);
export const stopMining = (provider: MockProvider) => provider.send("evm_setAutomine", [false]);
export const startMining = (provider: MockProvider) => provider.send('evm_setAutomine', [true]);
export const nowBlock = async (provider: MockProvider) => (await provider.getBlock('latest')).timestamp;
export const setTime = (provider: MockProvider, timestamp: number) => provider.send('evm_setNextBlockTimestamp', [timestamp]);
export const setTimeAndMine = async (provider: MockProvider, timestamp: number) => {
  await setTime(provider, timestamp);
  await mine(provider);
};