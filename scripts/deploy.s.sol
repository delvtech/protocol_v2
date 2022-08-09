// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/ForwarderFactory.sol";
import "../contracts/mocks/MockPool.sol";
import "../contracts/mocks/MockERC20Permit.sol";
import "../contracts/mocks/MockERC20YearnVault.sol";
import "../contracts/mocks/MockYieldAdapter.sol";

contract Deployer is Script {
    function run() external {
        vm.startBroadcast();

        // Create the forwader factory
        ForwarderFactory factory = new ForwarderFactory();
        address factoryAddress = address(factory);

        // Create mock ERC20 tokens & addresses
        // public & unlimited supply tokens
        MockERC20Permit USDC = new MockERC20Permit("USDC", "USDC", 6);
        address USDCAddress = address(USDC);

        MockERC20Permit DAI = new MockERC20Permit("DAI", "DAI", 18);
        address DAIAddress = address(DAI);

        MockERC20Permit WETH = new MockERC20Permit("WETH", "WETH", 18);
        address WETHAddress = address(WETH);

        // Create mock yearn vaults for each token
        MockERC20YearnVault yvUSDC = new MockERC20YearnVault(USDCAddress);
        address yvUSDCAddress = address(yvUSDC);

        MockERC20YearnVault yvDAI = new MockERC20YearnVault(DAIAddress);
        address yvDAIAddress = address(yvDAI);

        MockERC20YearnVault yvWETH = new MockERC20YearnVault(WETHAddress);
        address yvWETHAddress = address(yvWETH);

        // deploy yield adapter (term) for every token
        address governance = address(msg.sender);
        bytes32 linkHash = factory.ERC20LINK_HASH();

        MockYieldAdapter USDCTerm = new MockYieldAdapter(
            yvUSDCAddress,
            governance,
            linkHash,
            factoryAddress,
            USDC
        );
        MockYieldAdapter DAITerm = new MockYieldAdapter(
            yvDAIAddress,
            governance,
            linkHash,
            factoryAddress,
            DAI
        );
        MockYieldAdapter WETHTerm = new MockYieldAdapter(
            yvWETHAddress,
            governance,
            linkHash,
            factoryAddress,
            WETH
        );

        // authorize msg.sender to call redeem for each term
        USDCTerm.authorize(msg.sender);
        DAITerm.authorize(msg.sender);
        WETHTerm.authorize(msg.sender);

        // mint tokens to msg.sender to seed terms
        USDC.mint(msg.sender, 1_000_000);
        DAI.mint(msg.sender, 1_000_000);
        WETH.mint(msg.sender, 100_000);

        // start off 30/60/90 day terms for each token
        uint256 oneDaySeconds = 60 * 60 * 24;
        uint256 oneMonthTerm = block.timestamp + oneDaySeconds * 30;

        uint256[] memory emptyArray;

        USDC.approve(address(USDCTerm), 1_000_000);
        DAI.approve(address(DAITerm), 1_000_000);
        WETH.approve(address(WETHTerm), 100_000);

        //  USDC terms
        USDCTerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            100_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 60, // term starts now
            oneMonthTerm // term ends in 30 days
        );

        USDCTerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            100_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 120, // term starts now
            oneMonthTerm * 2 // term ends in 60 days
        );

        USDCTerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            100_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 180, // term starts now
            oneMonthTerm * 3 // term ends in 90 days
        );

        //  DAI terms
        DAITerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            100_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 60, // term starts now
            oneMonthTerm // term ends in 30 days
        );
        DAITerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            100_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 120, // term starts now
            oneMonthTerm * 2 // term ends in 60 days
        );
        DAITerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            100_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 180, // term starts now
            oneMonthTerm * 3 // term ends in 90 days
        );

        //  WETH terms
        WETHTerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            10_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 60, // term starts now
            oneMonthTerm // term ends in 30 days
        );
        WETHTerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            10_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 120, // term starts now
            oneMonthTerm * 2 // term ends in 60 days
        );
        WETHTerm.lock(
            emptyArray, // no assets (PT, YT, unlocked shares) to lock
            emptyArray, // no assets amounts to lock
            10_000,
            false, // no prefunding i.e. no tokens previouslly transfered to lock
            msg.sender,
            msg.sender,
            block.timestamp + 180, // term starts now
            oneMonthTerm * 3 // term ends in 90 days
        );

        // ================================================ //
        // ================================================ //
        // deploy pools for each term
        uint256 fee = 10;

        MockPool USDCPool = new MockPool(
            USDCTerm,
            USDC,
            fee,
            linkHash,
            governance,
            factoryAddress
        );
        MockPool DAIPool = new MockPool(
            DAITerm,
            DAI,
            fee,
            linkHash,
            governance,
            factoryAddress
        );
        MockPool WETHPool = new MockPool(
            WETHTerm,
            WETH,
            fee,
            linkHash,
            governance,
            factoryAddress
        );

        // ================================================ //
        // ================================================ //
        // register a poolId for each term

        USDC.approve(address(USDCPool), type(uint256).max);
        DAI.approve(address(DAIPool), type(uint256).max);
        WETH.approve(address(WETHPool), type(uint256).max);

        // usdc 30/60/90 day terms
        USDCPool.registerPoolId(
            oneMonthTerm, // term expiry is pool id
            100_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );

        USDCPool.registerPoolId(
            oneMonthTerm * 2, // term expiry is pool id
            100_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );
        USDCPool.registerPoolId(
            oneMonthTerm * 3, // term expiry is pool id
            100_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );

        // DAI 30/60/90 day terms
        DAIPool.registerPoolId(
            oneMonthTerm, // term expiry is pool id
            100_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );
        DAIPool.registerPoolId(
            oneMonthTerm * 2, // term expiry is pool id
            100_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );
        DAIPool.registerPoolId(
            oneMonthTerm * 3, // term expiry is pool id
            1_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );

        // WETH 30/60/90 day terms
        WETHPool.registerPoolId(
            oneMonthTerm, // term expiry is pool id
            1_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );
        WETHPool.registerPoolId(
            oneMonthTerm * 2, // term expiry is pool id
            1_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );
        WETHPool.registerPoolId(
            oneMonthTerm * 3, // term expiry is pool id
            1_000, // amount in
            1, // timestretch HUH
            msg.sender,
            0, // max time
            0 // max length
        );

        // Create ERC20 forwarder tokens for term principleTokens and LP tokens

        // principle tokens
        ERC20Forwarder pUSDC30 = factory.create(USDCTerm, oneMonthTerm);
        ERC20Forwarder pUSDC60 = factory.create(USDCTerm, oneMonthTerm * 2);
        ERC20Forwarder pUSDC90 = factory.create(USDCTerm, oneMonthTerm * 3);

        ERC20Forwarder pDAI30 = factory.create(DAITerm, oneMonthTerm);
        ERC20Forwarder pDAI60 = factory.create(DAITerm, oneMonthTerm * 2);
        ERC20Forwarder pDAI90 = factory.create(DAITerm, oneMonthTerm * 3);

        ERC20Forwarder pWETH30 = factory.create(WETHTerm, oneMonthTerm);
        ERC20Forwarder pWETH60 = factory.create(WETHTerm, oneMonthTerm * 2);
        ERC20Forwarder pWETH90 = factory.create(WETHTerm, oneMonthTerm * 3);

        // lp tokens
        ERC20Forwarder lpUSDC30 = factory.create(USDCPool, oneMonthTerm);
        ERC20Forwarder lpUSDC60 = factory.create(USDCPool, oneMonthTerm * 2);
        ERC20Forwarder lpUSDC90 = factory.create(USDCPool, oneMonthTerm * 3);

        ERC20Forwarder lpDAI30 = factory.create(DAIPool, oneMonthTerm);
        ERC20Forwarder lpDAI60 = factory.create(DAIPool, oneMonthTerm * 2);
        ERC20Forwarder lpDAI90 = factory.create(DAIPool, oneMonthTerm * 3);

        ERC20Forwarder lpWETH30 = factory.create(WETHPool, oneMonthTerm);
        ERC20Forwarder lpWETH60 = factory.create(WETHPool, oneMonthTerm * 2);
        ERC20Forwarder lpWETH90 = factory.create(WETHPool, oneMonthTerm * 3);

        vm.stopBroadcast();
    }
}
