// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "forge-std/console.sol";

import {MockERC4626, ERC20} from "contracts/mocks/MockERC4626.sol";
import {MockERC20Permit} from "contracts/mocks/MockERC20Permit.sol";
import {ForwarderFactory} from "contracts/ForwarderFactory.sol";
import {ERC4626Term, IERC4626} from "contracts/ERC4626Term.sol";
import {Pool, ITerm, IERC20} from "contracts/Pool.sol";

contract PoolTest is Test {
    MockERC20Permit public USDC;
    MockERC4626 public yUSDC;
    ERC4626Term public term;
    Pool public pool;

    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    uint256 public TERM_START;
    uint256 public TERM_END;

    address deployer = vm.addr(0xDE9107E4);
    address user = vm.addr(0x02E4);

    uint32 T_STRETCH = 10245;

    // MockPool public pool;
    // MockYieldAdapter public yieldAdapter;
    // User public user1;
    // MockERC20Permit public usdc;
    // address governanceContract;
    // uint256 UNLOCKED_YT_ID;

    function setUp() public {
        /// Initialise underlying token
        USDC = new MockERC20Permit("USDC Coin", "USDC", 6);
        /// Initialise Vault
        yUSDC = new MockERC4626(ERC20(address(USDC)));

        vm.deal(deployer, 100 ether);
        vm.label(deployer, "deployer");
        vm.deal(user, 100 ether);
        vm.label(user, "user");

        vm.startPrank(deployer);

        /// Create term contract for vault
        ForwarderFactory forwarderFactory = new ForwarderFactory();
        term = new ERC4626Term(
            IERC4626(address(yUSDC)),
            forwarderFactory.ERC20LINK_HASH(),
            address(forwarderFactory),
            100_000e6,
            address(this)
        );

        /// Set initial price in term
        USDC.mint(deployer, 200_000_000e6);
        USDC.approve(address(term), type(uint256).max);

        // Define the start and end dates for the term
        TERM_START = block.timestamp;
        TERM_END = TERM_START + YEAR;

        uint256[] memory assetIds;
        uint256[] memory assetAmounts;
        term.lock(assetIds, assetAmounts, 90_000_000e6, false, address(this), address(this), TERM_START, TERM_END);
        term.depositUnlocked(90_000_000e6, 0, 0, address(this));

        USDC.transfer(address(yUSDC), 20_000_000e6);

        pool = new Pool(
            ITerm(address(term)),
            IERC20(address(USDC)),
            1,
            forwarderFactory.ERC20LINK_HASH(),
            deployer,
            address(forwarderFactory)
        );

        vm.stopPrank();

        // Give the user some USDC
        USDC.mint(user, 100_000e6);

        vm.startPrank(user);
        USDC.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // // Contract initialization
        // usdc = new MockERC20Permit("USDC", "USDC", 6);
        // governanceContract = address(
        //     0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8
        // );
        // MockERC20YearnVault yearnVault = new MockERC20YearnVault(address(usdc));
        // bytes32 linkerCodeHash = bytes32(0);
        // address forwarderFactory = address(1);
        // yieldAdapter = new MockYieldAdapter(
        //     address(yearnVault),
        //     governanceContract,
        //     linkerCodeHash,
        //     forwarderFactory,
        //     usdc
        // );
        // uint256 tradeFee = 10;
        // bytes32 erc20ForwarderCodeHash = bytes32(0);
        // address erc20ForwarderFactory = address(1);
        // pool = new MockPool(
        //     yieldAdapter,
        //     usdc,
        //     tradeFee,
        //     erc20ForwarderCodeHash,
        //     governanceContract,
        //     erc20ForwarderFactory
        // );

        // UNLOCKED_YT_ID = yieldAdapter.UNLOCKED_YT_ID();

        // // Configure approval so that YieldAdapter(term) can transfer usdc from Pool to itself
        // vm.prank(address(pool), address(pool));
        // usdc.approve(address(yieldAdapter), type(uint256).max);

        // // Configure user1
        // user1 = new User();
    }

    function test__initialState() public {
        assertEq(yUSDC.totalSupply(), 179_950_000e6);
        assertApproxEqAbs(yUSDC.convertToShares(1e6), 0.9e6, 50);
        assertEq(USDC.balanceOf(address(term)), term.targetReserve());
    }

    ////////////////////////////////////////////////////////////////////////////
    ///////
    ///////////////////////// Pool.registerPoolId() ////////////////////////////
    /////////////////////////                       ////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    // success case - no oracle initialization
    function test__RegisterPoolId__no_oracle_init() public {
        vm.startPrank(user);

        (uint32 pool_tStretch, uint224 pool_mu) = pool.parameters(TERM_END);

        assertEq(pool_tStretch, 0);
        assertEq(pool_mu, 0);

        uint256 userUnderlyingPreBalance = USDC.balanceOf(user);
        uint256 userLpPreBalance = pool.balanceOf(TERM_END, user);


        uint256 underlying = 10_000e6;

        uint256 sharesMinted = pool.registerPoolId(
           TERM_END,
           underlying,
           T_STRETCH,
           user,
           0,
           0
        );

        uint256 userUnderlyingPostBalance = USDC.balanceOf(user);
        uint256 userLpPostBalance = pool.balanceOf(TERM_END, user);

        uint256 userUnderlyingDiff = userUnderlyingPreBalance - userUnderlyingPostBalance;
        uint256 userLpDiff = userLpPostBalance - userLpPreBalance;

        assertEq(userUnderlyingDiff, underlying);
        assertEq(userLpDiff, 9000250076);
        assertEq(sharesMinted, 9000250076);

        (pool_tStretch, pool_mu) = pool.parameters(TERM_END);

        assertEq(pool_tStretch, T_STRETCH);
        assertEq(pool_mu, T_STRETCH);

    }

    // success case - initialize oracle
   //  function test__RegisterPoolId__init_oracle() public {
   //      vm.startPrank(user);

   //      uint256 userUnderlyingPreBalance = USDC.balanceOf(user);
   //      uint256 userLpPreBalance = pool.balanceOf(TERM_END, user);

   //      uint256 underlying = 10_000e6;
   //      uint256 sharesMinted = pool.registerPoolId(
   //         TERM_END,
   //         underlying,
   //         1,
   //         user,
   //         0,
   //         0
   //      );

   //      uint256 userUnderlyingPostBalance = USDC.balanceOf(user);
   //      uint256 userLpPostBalance = pool.balanceOf(TERM_END, user);

   //      uint256 userUnderlyingDiff = userUnderlyingPreBalance - userUnderlyingPostBalance;
   //      uint256 userLpDiff = userLpPostBalance - userLpPreBalance;

   //      assertEq(userUnderlyingDiff, underlying);
   //      assertEq(userLpDiff, 9000250076);
   //      assertEq(sharesMinted, 9000250076);
   // }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    // function testGovernanceTradeFeeClaimSuccess() public {
    //     // yieldAdapter.setBalance(UNLOCKED_YT_ID, address(pool), 150);
    //     // yieldAdapter.setBalance(100, address(pool), 100);
    //     // // set the fees for expiration at 100 to (150, 100)
    //     // pool.setFees(100, 150, 100);
    //     // // pretend to be governance
    //     // vm.startPrank(governanceContract);
    //     // // Call the function to claim fees
    //     // pool.collectFees(100, address(user1));
    //     // // Check the balances
    //     // uint256 shareBalance = yieldAdapter.balanceOf(
    //     //     UNLOCKED_YT_ID,
    //     //     address(user1)
    //     // );
    //     // uint256 bondBalance = yieldAdapter.balanceOf(100, address(user1));
    //     // // assert them equal
    //     // assertEq(150, shareBalance);
    //     // assertEq(100, bondBalance);
    // }
}
