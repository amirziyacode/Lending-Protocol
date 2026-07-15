// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "src/LendingPool.sol";
import {MockReceiptToken} from "./Mock/MockReceiptToken.sol";

contract LendingPoolTest is Test {
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    LendingPool pool;

    address private constant SEPOLIA_NETWORK = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    MockReceiptToken mockToken;

    uint256 private constant AMOUNT = 1000;

    function setUp() public {
        vm.startPrank(owner);

        mockToken = new MockReceiptToken();

        pool = new LendingPool(address(mockToken), SEPOLIA_NETWORK);

        mockToken.mint(user, AMOUNT);

        vm.stopPrank();
    }

    function testSetUp() public view {
        assertEq(address(pool.token()), address(mockToken));
        assertEq(mockToken.balanceOf(user), AMOUNT);
    }

    modifier deposit() {
        uint256 amount = 500;

        vm.startPrank(user);

        mockToken.approve(address(pool), amount);

        pool.depositCollateral(amount);

        vm.stopPrank();
        _;
    }

    // ==================== DepositCollateral ====================
    function testDepositCollateral_revert_ZeroAmount() public {
        vm.expectRevert(LendingPool.LendingPool__ZeroAmount.selector);

        vm.prank(user);
        pool.depositCollateral(0);
    }

    function testDepositCollateral() public {
        uint256 poolBalanceBefore = mockToken.balanceOf(address(pool)); // 0 token
        uint256 userBalanceBefore = mockToken.balanceOf(user); // 1000 token

        uint256 amount = 500;

        vm.startPrank(user);

        mockToken.approve(address(pool), amount);

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Deposited(user, amount);

        pool.depositCollateral(amount);

        vm.stopPrank();

        uint256 getDeposite = pool.getUserDeposite(user);
        uint256 getTotalDeposits = pool.getTotalDeposits();
        uint256 poolBalanceAfter = mockToken.balanceOf(address(pool)); // 500 token
        uint256 userBalanceAfter = mockToken.balanceOf(user); // 500 token

        assertEq(getDeposite, amount);
        assertEq(getTotalDeposits, amount);
        assertEq(pool.receiptToken().balanceOf(user), amount);
        assertEq(poolBalanceAfter, poolBalanceBefore + amount);
        assertEq(userBalanceAfter, userBalanceBefore - amount);
    }

    function testFuzz_DepositCollateral_withAnyAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount <= AMOUNT);

        uint256 poolBalanceBefore = mockToken.balanceOf(address(pool)); // 0 token
        uint256 userBalanceBefore = mockToken.balanceOf(user); // 1000 token

        vm.startPrank(user);

        mockToken.approve(address(pool), amount);

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Deposited(user, amount);

        pool.depositCollateral(amount);

        vm.stopPrank();

        uint256 getDeposite = pool.getUserDeposite(user);
        uint256 getTotalDeposits = pool.getTotalDeposits();
        uint256 poolBalanceAfter = mockToken.balanceOf(address(pool)); // 500 token
        uint256 userBalanceAfter = mockToken.balanceOf(user); // 500 token

        assertEq(getDeposite, amount);
        assertEq(getTotalDeposits, amount);
        assertEq(pool.receiptToken().balanceOf(user), amount);
        assertEq(poolBalanceAfter, poolBalanceBefore + amount);
        assertEq(userBalanceAfter, userBalanceBefore - amount);
    }

    // ==================== Borrow ====================
    function testBorrow_revert_ZeroAmount() public {
        vm.expectRevert(LendingPool.LendingPool__ZeroAmount.selector);
        vm.prank(user);
        pool.borrow(0);
    }

    function testBorrow_revert_MaxBorrow() public {
        vm.startPrank(user);
        uint256 amount = 700;
        mockToken.approve(address(pool), amount);

        pool.depositCollateral(amount);

        vm.stopPrank();

        vm.expectRevert(LendingPool.LendingPool__OutOf_MaxBorrow.selector);
        uint256 borrowAmount = 600;
        vm.prank(user);
        pool.borrow(borrowAmount);
    }

    function testBorrow_revert_InsufficientLiquidity() public {
        vm.expectRevert(LendingPool.LendingPool__InsufficientLiquidity.selector);
        vm.prank(user);
        pool.borrow(300);
    }

    function testBorrow_revert_NotOkhealthFactor() public deposit {
        uint256 borrowAmount = 400;

        vm.expectRevert(LendingPool.LendingPool__HeathFactorNotOk.selector);
        vm.prank(user);
        pool.borrow(borrowAmount);
    }

    function testBorrow() public deposit {
        uint256 borrowAmount = 300;
        uint256 balancePoolBefore = mockToken.balanceOf(address(pool)); // 500 token
        uint256 balanceUserBefore = mockToken.balanceOf(user); // 500 token

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Borrow(user, borrowAmount);
        vm.prank(user);
        pool.borrow(borrowAmount);

        uint256 getBorrowed = pool.getUserBorrowed(user);
        uint256 balancePoolAfter = mockToken.balanceOf(address(pool)); // 200 token
        uint256 balanceUserAfter = mockToken.balanceOf(user); // 800 token

        assertEq(getBorrowed, borrowAmount);
        assertEq(balancePoolAfter, balancePoolBefore - borrowAmount);
        assertEq(balanceUserAfter, balanceUserBefore + borrowAmount);
    }

    /**
     * 
     * @param borrowAmount value to borrowed
     * @notice maxBorrowed is limited from healthFacotr
     */
    function testFuzz_Borrow_withAnyAmount(uint256 borrowAmount) public deposit {
        uint256 maxBorrowed = 375;
        vm.assume(borrowAmount > 0 && borrowAmount < maxBorrowed);
        uint256 balancePoolBefore = mockToken.balanceOf(address(pool)); // 500 token
        uint256 balanceUserBefore = mockToken.balanceOf(user); // 500 token

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Borrow(user, borrowAmount);
        vm.prank(user);
        pool.borrow(borrowAmount);

        uint256 getBorrowed = pool.getUserBorrowed(user);
        uint256 balancePoolAfter = mockToken.balanceOf(address(pool)); // 200 token
        uint256 balanceUserAfter = mockToken.balanceOf(user); // 800 token

        assertEq(getBorrowed, borrowAmount);
        assertEq(balancePoolAfter, balancePoolBefore - borrowAmount);
        assertEq(balanceUserAfter, balanceUserBefore + borrowAmount);
    }
}
