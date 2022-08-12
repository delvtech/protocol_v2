// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/ForwarderFactory.sol";
import "../contracts/mocks/MockPool.sol";
import "../contracts/mocks/MockERC20Permit.sol";
import "../contracts/mocks/MockERC20YearnVault.sol";
import "../contracts/mocks/MockYieldAdapter.sol";

contract MockDeployer is Script {
    function run() external {
        vm.startBroadcast();

        uint256 timestamp = block.timestamp;

        // Create the fowarder factory
        // This factory will be referenced in other contracts
        // and will be used to deploy ERC20 proxy tokens for principle and LPs
        ForwarderFactory factory = new ForwarderFactory();

        // Create mock ERC20 tokens
        MockERC20Permit USDC = new MockERC20Permit("USDC", "USDC", 6);
        MockERC20Permit DAI = new MockERC20Permit("DAI", "DAI", 18);
        MockERC20Permit WETH = new MockERC20Permit("WETH", "WETH", 18);

        // Create mock yearn vaults for each token
        MockERC20YearnVault yvUSDC = new MockERC20YearnVault(address(USDC));
        MockERC20YearnVault yvDAI = new MockERC20YearnVault(address(DAI));
        MockERC20YearnVault yvWETH = new MockERC20YearnVault(address(WETH));

        // Create yield adapter (term) for every token
        address governance = address(msg.sender); // dummy gov address
        bytes32 linkHash = factory.ERC20LINK_HASH(); // ERC20 forwader contraction creation code

        MockYieldAdapter USDCTerm = new MockYieldAdapter(
            address(yvUSDC),
            governance,
            linkHash,
            address(factory),
            USDC
        );
        MockYieldAdapter DAITerm = new MockYieldAdapter(
            address(yvDAI),
            governance,
            linkHash,
            address(factory),
            DAI
        );
        MockYieldAdapter WETHTerm = new MockYieldAdapter(
            address(yvWETH),
            governance,
            linkHash,
            address(factory),
            WETH
        );

        // Authorize msg.sender to call redeem for each term
        USDCTerm.authorize(msg.sender);
        DAITerm.authorize(msg.sender);
        WETHTerm.authorize(msg.sender);

        // mint tokens to msg.sender to seed terms
        USDC.mint(msg.sender, 5_000_000 * 1e6); // 6 decimals
        DAI.mint(msg.sender, 5_000_000 * 1e18); // 18 decimals
        WETH.mint(msg.sender, 100_000 * 1e18); // 18 decimals

        // Create 30 / 60 / 90 day terms for each token

        // Timestamp expiries
        // These will be used as indentifers in multi-token contracts (Term, LP)
        uint256 oneDaySeconds = 60 * 60 * 24;
        uint256 oneMonthSeconds = oneDaySeconds * 30;
        uint256 oneMonthExpiry = timestamp + oneMonthSeconds;
        uint256 twoMonthExpiry = timestamp + oneMonthSeconds * 2;
        uint256 threeMonthExpiry = timestamp + oneMonthSeconds * 3;

        // Empty dynamic array to satisfy types
        uint256[] memory emptyArray;

        // Give allowance to term contracts
        USDC.approve(address(USDCTerm), type(uint256).max);
        DAI.approve(address(DAITerm), type(uint256).max);
        WETH.approve(address(WETHTerm), type(uint256).max);

        // Buffer for yield token start dates
        // When locking yield tokens that start in the future will start at the current timestamp
        uint256 ytBuffer = 3600;

        // USDC terms
        USDCTerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            100_000 * 1e6, // underlying amount
            false, // no prefunding
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            oneMonthExpiry // term ends in 30 days
        );

        USDCTerm.lock(
            emptyArray,
            emptyArray,
            100_000 * 1e6,
            false,
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            twoMonthExpiry // term ends in 60 days
        );

        USDCTerm.lock(
            emptyArray,
            emptyArray,
            100_000 * 1e6,
            false,
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            threeMonthExpiry // term ends in 90 days
        );

        // DAI terms
        DAITerm.lock(
            emptyArray,
            emptyArray,
            100_000 * 1e18,
            false,
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            oneMonthExpiry // term ends in 30 days
        );
        DAITerm.lock(
            emptyArray,
            emptyArray,
            100_000 * 1e18,
            false,
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            twoMonthExpiry // term ends in 60 days
        );
        DAITerm.lock(
            emptyArray,
            emptyArray,
            100_000 * 1e18,
            false,
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            threeMonthExpiry // term ends in 90 days
        );

        // WETH terms
        WETHTerm.lock(
            emptyArray,
            emptyArray,
            10_000 * 1e18,
            false,
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            oneMonthExpiry // term ends in 30 days
        );
        WETHTerm.lock(
            emptyArray,
            emptyArray,
            10_000 * 1e18,
            false,
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            twoMonthExpiry // term ends in 60 days
        );
        WETHTerm.lock(
            emptyArray,
            emptyArray,
            10_000 * 1e18,
            false,
            msg.sender,
            msg.sender,
            block.timestamp + ytBuffer,
            threeMonthExpiry // term ends in 90 days
        );

        // Deploy pools for each term
        uint256 fee = 2e17; // fee as 18 fixed point number

        MockPool USDCPool = new MockPool(
            USDCTerm,
            USDC,
            fee,
            linkHash,
            governance,
            address(factory)
        );
        MockPool DAIPool = new MockPool(
            DAITerm,
            DAI,
            fee,
            linkHash,
            governance,
            address(factory)
        );
        MockPool WETHPool = new MockPool(
            WETHTerm,
            WETH,
            fee,
            linkHash,
            governance,
            address(factory)
        );

        // Give allowance to pools
        USDC.approve(address(USDCPool), type(uint256).max);
        DAI.approve(address(DAIPool), type(uint256).max);
        WETH.approve(address(WETHPool), type(uint256).max);

        // USDC 30/60/90 day term pools
        // USDCPool.registerPoolId(
        //     oneMonthExpiry, // term expiry is pool id
        //     100_000 * 1e6, // amount in
        //     1000, // timestretch
        //     msg.sender,
        //     0, // max time (used for oracle)
        //     0 // max length (used for oracle)
        // );
        // USDCPool.registerPoolId(
        //     twoMonthExpiry,
        //     100_000 * 1e6,
        //     1000,
        //     msg.sender,
        //     0,
        //     0
        // );
        USDCPool.registerPoolId(
            threeMonthExpiry,
            100_000 * 1e6,
            1000,
            msg.sender,
            0,
            0
        );

        // // DAI 30/60/90 day term pools
        // DAIPool.registerPoolId(
        //     oneMonthExpiry,
        //     100_000 * 1e18,
        //     1000,
        //     msg.sender,
        //     0,
        //     0
        // );
        // DAIPool.registerPoolId(
        //     twoMonthExpiry,
        //     100_000 * 1e18,
        //     1000,
        //     msg.sender,
        //     0,
        //     0
        // );
        // DAIPool.registerPoolId(
        //     threeMonthExpiry,
        //     100_000 * 1e18,
        //     1000,
        //     msg.sender,
        //     0,
        //     0
        // );

        // // WETH 30/60/90 day term pools
        // WETHPool.registerPoolId(
        //     oneMonthExpiry,
        //     1_000 * 1e18,
        //     1000,
        //     msg.sender,
        //     0,
        //     0
        // );
        // WETHPool.registerPoolId(
        //     twoMonthExpiry,
        //     1_000 * 1e18,
        //     1000,
        //     msg.sender,
        //     0,
        //     0
        // );
        // WETHPool.registerPoolId(
        //     threeMonthExpiry,
        //     1_000 * 1e18,
        //     1000,
        //     msg.sender,
        //     0,
        //     0
        // );

        // Create ERC20 forwarder tokens for term principle and LP tokens

        // Principle tokens
        ERC20Forwarder pUSDC_30 = factory.create(USDCTerm, oneMonthExpiry);
        ERC20Forwarder pUSDC_60 = factory.create(USDCTerm, twoMonthExpiry);
        ERC20Forwarder pUSDC_90 = factory.create(USDCTerm, threeMonthExpiry);

        ERC20Forwarder pDAI_30 = factory.create(DAITerm, oneMonthExpiry);
        ERC20Forwarder pDAI_60 = factory.create(DAITerm, twoMonthExpiry);
        ERC20Forwarder pDAI_90 = factory.create(DAITerm, threeMonthExpiry);

        ERC20Forwarder pWETH_30 = factory.create(WETHTerm, oneMonthExpiry);
        ERC20Forwarder pWETH_60 = factory.create(WETHTerm, twoMonthExpiry);
        ERC20Forwarder pWETH_90 = factory.create(WETHTerm, threeMonthExpiry);

        // LP tokens
        ERC20Forwarder lpUSDC_30 = factory.create(USDCPool, oneMonthExpiry);
        ERC20Forwarder lpUSDC_60 = factory.create(USDCPool, twoMonthExpiry);
        ERC20Forwarder lpUSDC_90 = factory.create(USDCPool, threeMonthExpiry);

        ERC20Forwarder lpDAI_30 = factory.create(DAIPool, oneMonthExpiry);
        ERC20Forwarder lpDAI_60 = factory.create(DAIPool, twoMonthExpiry);
        ERC20Forwarder lpDAI_90 = factory.create(DAIPool, threeMonthExpiry);

        ERC20Forwarder lpWETH_30 = factory.create(WETHPool, oneMonthExpiry);
        ERC20Forwarder lpWETH_60 = factory.create(WETHPool, twoMonthExpiry);
        ERC20Forwarder lpWETH_90 = factory.create(WETHPool, threeMonthExpiry);

        // misc approvals
        USDCPool.setApproval(
            threeMonthExpiry,
            address(USDCTerm),
            type(uint256).max
        );

        USDCTerm.setApproval(
            threeMonthExpiry,
            address(USDCPool),
            type(uint256).max
        );

        // TODO @cashd: figure out how to init a pool with liquidity (v pls assist)
        // Using USDC 3 month term as an example
        // Initalize pool with liquidity
        USDCPool.tradeBonds(
            threeMonthExpiry,
            1_000 * 1e6,
            1,
            msg.sender,
            false
        );

        // below fails with a substraction overflow errror
        // when calculating impliedInterest in _quoteSaleAndFees function

        vm.stopBroadcast();

        // output token list
        // console.logString("Forwarder Factory address:");
        // console.logAddress(factoryAddress);

        // console.logString("USDC Token address:");
        // console.logAddress(address(USDC));
        // console.logString("DAI Token address:");
        // console.logAddress(address(DAI));
        // console.logString("WETH Token address:");
        // console.logAddress(address(WETH));

        // console.logString("yvUSDC address:");
        // console.logAddress(yvaddress(USDC));
        // console.logString("yvDAI address:");
        // console.logAddress(yvaddress(DAI));
        // console.logString("yvWETH address:");
        // console.logAddress(yvaddress(WETH));

        // console.logString("USDC Term address:");
        // console.logAddress(address(USDCTerm));
        // console.logString("DAI Term address:");
        // console.logAddress(address(DAITerm));
        // console.logString("WETH Term address:");
        // console.logAddress(address(WETHTerm));

        // console.logString("USDC Pool address:");
        // console.logAddress(address(USDCPool));
        // console.logString("DAI Pool address:");
        // console.logAddress(address(DAIPool));
        // console.logString("WETH Pool address:");
        // console.logAddress(address(WETHPool));

        // console.logString("pUSDC_30 Token address:");
        // console.logAddress(address(pUSDC_30));
        // console.logString("pUSDC_60 Token address:");
        // console.logAddress(address(pUSDC_60));
        // console.logString("pUSDC_90 Token address:");
        // console.logAddress(address(pUSDC_90));
        // console.logString("pDAI_30 Token address:");
        // console.logAddress(address(pDAI_30));
        // console.logString("pDAI_60 Token address:");
        // console.logAddress(address(pDAI_60));
        // console.logString("pDAI_90 Token address:");
        // console.logAddress(address(pDAI_90));
        // console.logString("pWETH_30 Token address:");
        // console.logAddress(address(pWETH_30));
        // console.logString("pWETH_60 Token address:");
        // console.logAddress(address(pWETH_60));
        // console.logString("pWETH_90 Token address:");
        // console.logAddress(address(pWETH_90));

        // console.logString("lpUSDC_30 Token address:");
        // console.logAddress(address(lpUSDC_30));
        // console.logString("lpUSDC_60 Token address:");
        // console.logAddress(address(lpUSDC_60));
        // console.logString("lpUSDC_90 Token address:");
        // console.logAddress(address(lpUSDC_90));
        // console.logString("lpDAI_30 Token address:");
        // console.logAddress(address(lpDAI_30));
        // console.logString("lpDAI_60 Token address:");
        // console.logAddress(address(lpDAI_60));
        // console.logString("lpDAI_90 Token address:");
        // console.logAddress(address(lpDAI_90));
        // console.logString("lpWETH_30 Token address:");
        // console.logAddress(address(lpWETH_30));
        // console.logString("lpWETH_60 Token address:");
        // console.logAddress(address(lpWETH_60));
        // console.logString("lpWETH_90 Token address:");
        // console.logAddress(address(lpWETH_90));
    }
}
