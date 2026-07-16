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

    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;

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

    modifier deposite() {
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

    function testDepositCollateral_withMultiUser() public {
        address person = makeAddr("person");
        uint256 userAmount = 500;
        uint256 personAmount = 500;

        vm.prank(owner);
        mockToken.mint(person, AMOUNT);

        uint256 poolBalanceBefore = mockToken.balanceOf(address(pool)); // 0 token
        uint256 userBalanceBefore = mockToken.balanceOf(user); // 1000 token
        uint256 personBalanceBefore = mockToken.balanceOf(person); // 1000 token

        // ============ person =============
        vm.startPrank(person);

        mockToken.approve(address(pool), personAmount);

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Deposited(person, personAmount);

        pool.depositCollateral(personAmount);

        vm.stopPrank();

        // ========= user ===========
        vm.startPrank(user);

        mockToken.approve(address(pool), userAmount);

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Deposited(user, userAmount);

        pool.depositCollateral(userAmount);

        vm.stopPrank();

        uint256 getUserDeposited = pool.getUserDeposite(user);
        uint256 getPersonDeposite = pool.getUserDeposite(person);
        uint256 getTotalDepostie = pool.getTotalDeposits();
        uint256 poolBalanceAfter = mockToken.balanceOf(address(pool)); // 1000 token
        uint256 userBalanceAfter = mockToken.balanceOf(user); // 500 token
        uint256 personBalanceAfter = mockToken.balanceOf(person);

        assertEq(getUserDeposited, userAmount);
        assertEq(getPersonDeposite, personAmount);
        assertEq(getTotalDepostie, getUserDeposited + getPersonDeposite);
        assertEq(pool.receiptToken().balanceOf(user), userAmount);
        assertEq(pool.receiptToken().balanceOf(person), personAmount);
        assertEq(poolBalanceAfter, poolBalanceBefore + userAmount + personAmount);
        assertEq(userBalanceAfter, userBalanceBefore - userAmount);
        assertEq(personBalanceAfter, personBalanceBefore - personAmount);
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

    function testBorrow_revert_NotOkhealthFactor() public deposite {
        uint256 borrowAmount = 400;

        vm.expectRevert(LendingPool.LendingPool__HeathFactorNotOk.selector);
        vm.prank(user);
        pool.borrow(borrowAmount);
    }

    function testBorrow() public deposite {
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
    function testFuzz_Borrow_withAnyAmount(uint256 borrowAmount) public deposite {
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

    // ==================== Repay ====================

    function testRepay_revert_ZeroAmount() public {
        uint256 repayAmount = 0;
        vm.expectRevert(LendingPool.LendingPool__ZeroAmount.selector);
        vm.prank(user);
        pool.repay(repayAmount);
    }

    function testRepay_revert_RepayTooMuch() public deposite {
        uint256 borrowAmount = 300;
        vm.prank(user);
        pool.borrow(borrowAmount);

        uint256 repayAmount = 310;

        vm.expectRevert(LendingPool.LendingPool__RepayTooMuch.selector);
        vm.prank(user);
        pool.repay(repayAmount);
    }

    function testRepay() public deposite {
        uint256 borrowAmount = 300;
        vm.prank(user);
        pool.borrow(borrowAmount);

        uint256 userBalanceBefore = mockToken.balanceOf(user); // 800 token
        uint256 poolBalanceBefore = mockToken.balanceOf(address(pool)); // 200 token

        vm.startPrank(user);

        uint256 repayAmount = 300;

        mockToken.approve(address(pool), repayAmount);

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Repay(user, repayAmount);

        pool.repay(repayAmount);

        vm.stopPrank();

        uint256 getBorrowed = pool.getUserBorrowed(user);
        uint256 userBalanceAfter = mockToken.balanceOf(user); // 500 token
        uint256 poolBalanceAfter = mockToken.balanceOf(address(pool)); // 500 token

        assertEq(pool.receiptToken().balanceOf(user), 500);
        assertEq(getBorrowed, 0);
        assertEq(poolBalanceAfter, poolBalanceBefore + repayAmount);
        assertEq(userBalanceAfter, userBalanceBefore - repayAmount);
    }

    function testFuzz_RepayWithAnyAmount(uint256 amount) public deposite {
        uint256 borrowAmount = 300;
        uint256 repayAmount = bound(amount, 1, borrowAmount);

        vm.prank(user);
        pool.borrow(borrowAmount);

        uint256 userBalanceBefore = mockToken.balanceOf(user);
        uint256 poolBalanceBefore = mockToken.balanceOf(address(pool));

        vm.startPrank(user);

        mockToken.approve(address(pool), repayAmount);

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Repay(user, repayAmount);

        pool.repay(repayAmount);

        vm.stopPrank();

        uint256 getBorrowed = pool.getUserBorrowed(user);
        uint256 userBalanceAfter = mockToken.balanceOf(user);
        uint256 poolBalanceAfter = mockToken.balanceOf(address(pool));

        assertEq(pool.receiptToken().balanceOf(user), 500);
        assertEq(getBorrowed, borrowAmount - repayAmount);
        assertEq(poolBalanceAfter, poolBalanceBefore + repayAmount);
        assertEq(userBalanceAfter, userBalanceBefore - repayAmount);
    }

    // ==================== WithDraw ====================
    function testWithdraw_revert_ZeroAmount() public {
        uint256 withDrawAmount = 0;
        vm.expectRevert(LendingPool.LendingPool__ZeroAmount.selector);
        vm.prank(user);
        pool.withdraw(withDrawAmount);
    }

    function testWithdraw_revert_InsufficientCollateral() public {
        uint256 withDrawAmount = 100;
        vm.expectRevert(LendingPool.LendingPool__InsufficientCollateral.selector);
        vm.prank(user);
        pool.withdraw(withDrawAmount);
    }

    function testWithdraw_revert_HeathFactorNotOk() public deposite {
        uint256 withdrawAmount = 400;

        vm.prank(user);
        pool.borrow(300);

        vm.expectRevert(LendingPool.LendingPool__HeathFactorNotOk.selector);
        vm.prank(user);
        pool.withdraw(withdrawAmount);
    }

    function testWithdraw_NotDebt_OkhealthFactor() public deposite {
        uint256 withdrawAmount = 400;

        vm.prank(user);
        pool.withdraw(withdrawAmount);

        assertTrue(pool.getHealthFactor(user) > MINIMUM_HEALTH_FACTOR);
    }

    function testWithdraw_NotDebt() public deposite {
        uint256 withdrawAmount = 400;
        uint256 getUserDeposited = pool.getUserDeposite(user);
        uint256 poolBalanceBefore = mockToken.balanceOf(address(pool));
        uint256 userBalanceBefore = mockToken.balanceOf(user);

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Withdrawn(user, withdrawAmount);

        vm.prank(user);
        pool.withdraw(withdrawAmount);

        uint256 getPoolDeposited = pool.getTotalDeposits();

        uint256 poolBalanceAfter = mockToken.balanceOf(address(pool));
        uint256 userBalanceAfter = mockToken.balanceOf(user);

        assertEq(getPoolDeposited, getUserDeposited - withdrawAmount);
        assertEq(poolBalanceAfter, poolBalanceBefore - withdrawAmount);
        assertEq(userBalanceAfter, userBalanceBefore + withdrawAmount);
    }

    function test_RevertWhen_WithdrawBreaksHealthFactor() public deposite {
        uint256 withdrawAmount = 101;

        vm.prank(user);
        pool.borrow(300);

        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__HeathFactorNotOk.selector);
        pool.withdraw(withdrawAmount);
    }

    function test_WithdrawUnlimited_WhenNoDebtEverTaken() public deposite {
        vm.prank(user);
        pool.withdraw(500);

        assertEq(mockToken.balanceOf(user), AMOUNT);
    }

    function testFuzz_WithdrawAnyAmount_withNoDebt(uint256 amount) public deposite {
        uint256 maxWithDraw = pool.getUserDeposite(user);
        uint256 withdrawAmount = bound(amount, 1, maxWithDraw);

        uint256 getUserDeposited = pool.getUserDeposite(user);
        uint256 poolBalanceBefore = mockToken.balanceOf(address(pool));
        uint256 userBalanceBefore = mockToken.balanceOf(user);

        vm.expectEmit(true, false, false, true);
        emit LendingPool.Withdrawn(user, withdrawAmount);

        vm.prank(user);
        pool.withdraw(withdrawAmount);

        uint256 getPoolDeposited = pool.getTotalDeposits();

        uint256 poolBalanceAfter = mockToken.balanceOf(address(pool));
        uint256 userBalanceAfter = mockToken.balanceOf(user);

        assertEq(getPoolDeposited, getUserDeposited - withdrawAmount);
        assertEq(poolBalanceAfter, poolBalanceBefore - withdrawAmount);
        assertEq(userBalanceAfter, userBalanceBefore + withdrawAmount);
    }

    // ==================== Getter ====================
    function test_getLTV() public view {
        uint256 LTV = 80;
        assertEq(pool.getLTV(), LTV);
    }
}
