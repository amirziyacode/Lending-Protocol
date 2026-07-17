// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {InterestModel} from "src/InterestModel.sol";
import {Test} from "forge-std/Test.sol";

contract InterestModelTest is Test {
    InterestModel internal model;

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant OPTIMAL_UTILIZATION = 70e16;
    uint256 internal constant LOW_RATE = 5e16;
    uint256 internal constant HIGH_RATE = 15e16;

    function setUp() public {
        model = new InterestModel();
    }

    /*//////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////*/

    function test_Constants() public view {
        assertEq(model.OPTIMAL_UTILIZATION(), 70e16);
        assertEq(model.LOW_RATE(), 5e16);
        assertEq(model.HIGH_RATE(), 15e16);
    }

    /*//////////////////////////////////////////////////////////
                        ZERO DEPOSITS BRANCH
    //////////////////////////////////////////////////////////*/

    function test_ZeroDeposits_ReturnsZero() public view {
        assertEq(model.getBorrowRate(0, 0), 0);
    }

    function test_ZeroDeposits_WithNonZeroBorrows_ReturnsZero() public view {
        // totalBorrows > totalDeposits (== 0) is a degenerate state, but the
        // function should short-circuit on totalDeposits == 0 before doing
        // any division, and never revert here.
        assertEq(model.getBorrowRate(0, 1_000e18), 0);
    }

    function testFuzz_ZeroDeposits_AlwaysReturnsZero(uint256 totalBorrows) public view {
        assertEq(model.getBorrowRate(0, totalBorrows), 0);
    }

    /*//////////////////////////////////////////////////////////
                        LOW UTILIZATION BRANCH
    //////////////////////////////////////////////////////////*/

    function test_ZeroUtilization_ReturnsLowRate() public view {
        assertEq(model.getBorrowRate(1_000e18, 0), LOW_RATE);
    }

    function test_LowUtilization_ReturnsLowRate() public view {
        // 50% utilization
        assertEq(model.getBorrowRate(1_000e18, 500e18), LOW_RATE);
    }

    function test_JustBelowOptimal_ReturnsLowRate() public view {
        // 69.999999...% utilization -> just under the 70% threshold
        uint256 totalDeposits = 1_000_000e18;
        uint256 totalBorrows = (totalDeposits * (OPTIMAL_UTILIZATION - 1)) / PRECISION;
        assertEq(model.getBorrowRate(totalDeposits, totalBorrows), LOW_RATE);
    }

    /*//////////////////////////////////////////////////////////
                       HIGH UTILIZATION BRANCH
    //////////////////////////////////////////////////////////*/

    function test_ExactlyOptimalUtilization_ReturnsHighRate() public view {
        // utilization == OPTIMAL_UTILIZATION is NOT < OPTIMAL_UTILIZATION,
        // so it should fall into the high-rate branch (boundary is inclusive
        // on the high side).
        uint256 totalDeposits = 1_000e18;
        uint256 totalBorrows = 700e18; // exactly 70%
        assertEq(model.getBorrowRate(totalDeposits, totalBorrows), HIGH_RATE);
    }

    function test_JustAboveOptimal_ReturnsHighRate() public view {
        uint256 totalDeposits = 1_000_000e18;
        uint256 totalBorrows = (totalDeposits * (OPTIMAL_UTILIZATION + 1)) / PRECISION;
        assertEq(model.getBorrowRate(totalDeposits, totalBorrows), HIGH_RATE);
    }

    function test_HighUtilization_ReturnsHighRate() public view {
        // 90% utilization
        assertEq(model.getBorrowRate(1_000e18, 900e18), HIGH_RATE);
    }

    function test_FullUtilization_ReturnsHighRate() public view {
        // 100% utilization (totalBorrows == totalDeposits)
        assertEq(model.getBorrowRate(1_000e18, 1_000e18), HIGH_RATE);
    }

    function test_OverUtilization_ReturnsHighRate() public view {
        // totalBorrows > totalDeposits — shouldn't normally happen in a real
        // protocol, but the pure math should still resolve to HIGH_RATE
        // rather than reverting, as long as it doesn't overflow.
        assertEq(model.getBorrowRate(1_000e18, 5_000e18), HIGH_RATE);
    }

    /*//////////////////////////////////////////////////////////
                           OVERFLOW BEHAVIOR
    //////////////////////////////////////////////////////////*/

    function test_RevertsOnMultiplicationOverflow() public {
        // totalBorrows * PRECISION overflows uint256 for sufficiently large
        // totalBorrows. Solidity 0.8's checked arithmetic should revert.
        uint256 totalDeposits = 1e18;
        uint256 totalBorrows = type(uint256).max; // will overflow when * 1e18
        vm.expectRevert();
        model.getBorrowRate(totalDeposits, totalBorrows);
    }

    /*//////////////////////////////////////////////////////////
                                FUZZ
    //////////////////////////////////////////////////////////*/

    function testFuzz_RateIsAlwaysLowOrHigh(uint128 totalDeposits, uint128 totalBorrows) public view {
        // Bound to uint128 to comfortably avoid overflow in
        // totalBorrows * PRECISION while still exercising a huge input space.
        vm.assume(totalDeposits > 0);

        uint256 rate = model.getBorrowRate(totalDeposits, totalBorrows);
        assertTrue(rate == LOW_RATE || rate == HIGH_RATE);
    }

    function testFuzz_ThresholdBoundaryIsRespected(uint128 totalDeposits, uint128 totalBorrows) public view {
        vm.assume(totalDeposits > 0);

        uint256 utilization = (uint256(totalBorrows) * PRECISION) / uint256(totalDeposits);
        uint256 rate = model.getBorrowRate(totalDeposits, totalBorrows);

        if (utilization < OPTIMAL_UTILIZATION) {
            assertEq(rate, LOW_RATE);
        } else {
            assertEq(rate, HIGH_RATE);
        }
    }

    function testFuzz_ZeroDepositsAlwaysZeroRegardlessOfBorrows(uint256 totalBorrows) public view {
        assertEq(model.getBorrowRate(0, totalBorrows), 0);
    }

    /*//////////////////////////////////////////////////////////
                            SUPPLY RATE
    //////////////////////////////////////////////////////////*/

    function test_SupplyRate_ZeroDeposits_Reverts() public {
        // BUG (or at least an inconsistency): unlike getBorrowRate, this
        // function does not guard against totalDeposits == 0 before
        // dividing, so it panics with a division-by-zero error instead of
        // returning 0. This test documents the CURRENT behavior so it fails
        // loudly if/when the contract is fixed to return 0 instead, at
        // which point this test should be updated.
        vm.expectRevert(); // Panic(0x12): division or modulo by zero
        model.getSupplyRate(0, 0);
    }

    function test_SupplyRate_ZeroUtilization_ReturnsZero() public view {
        // borrowRate = LOW_RATE, utilization = 0 -> supplyRate = 0
        assertEq(model.getSupplyRate(1_000e18, 0), 0);
    }

    function test_SupplyRate_LowUtilization_MatchesFormula() public view {
        // 50% utilization, LOW_RATE branch
        uint256 totalDeposits = 1_000e18;
        uint256 totalBorrows = 500e18;

        uint256 expectedUtilization = 50e16; // 50%
        uint256 expectedSupplyRate = (LOW_RATE * expectedUtilization) / PRECISION;

        assertEq(model.getSupplyRate(totalDeposits, totalBorrows), expectedSupplyRate);
        // Sanity: 5% borrow rate * 50% utilization = 2.5%
        assertEq(expectedSupplyRate, 25e15);
    }

    function test_SupplyRate_AtOptimalUtilization_MatchesFormula() public view {
        // Exactly 70% utilization, HIGH_RATE branch (boundary inclusive on high side)
        uint256 totalDeposits = 1_000e18;
        uint256 totalBorrows = 700e18;

        uint256 expectedSupplyRate = (HIGH_RATE * OPTIMAL_UTILIZATION) / PRECISION;
        assertEq(model.getSupplyRate(totalDeposits, totalBorrows), expectedSupplyRate);
        // Sanity: 15% borrow rate * 70% utilization = 10.5%
        assertEq(expectedSupplyRate, 105e15);
    }

    function test_SupplyRate_FullUtilization_EqualsBorrowRate() public view {
        // 100% utilization -> supplyRate == borrowRate (HIGH_RATE), since
        // supplyRate = borrowRate * 1.0
        uint256 totalDeposits = 1_000e18;
        uint256 totalBorrows = 1_000e18;

        assertEq(model.getSupplyRate(totalDeposits, totalBorrows), HIGH_RATE);
    }

    function test_SupplyRate_OverUtilization_ExceedsBorrowRate() public view {
        // totalBorrows > totalDeposits -> utilization > 100% -> supplyRate > borrowRate.
        // Degenerate state for a real protocol, but worth pinning down the math.
        uint256 totalDeposits = 1_000e18;
        uint256 totalBorrows = 2_000e18; // 200% utilization

        uint256 supplyRate = model.getSupplyRate(totalDeposits, totalBorrows);
        assertEq(supplyRate, HIGH_RATE * 2);
        assertGt(supplyRate, HIGH_RATE);
    }

    function test_SupplyRate_RevertsOnMultiplicationOverflow() public {
        vm.expectRevert();
        model.getSupplyRate(1e18, type(uint256).max);
    }

    function testFuzz_SupplyRate_NeverExceedsBorrowRate_WhenFullyBacked(uint128 totalDeposits, uint128 totalBorrows)
        public
        view
    {
        // When borrows never exceed deposits (the sane, non-degenerate case),
        // utilization <= 100%, so supplyRate should never exceed borrowRate.
        vm.assume(totalDeposits > 0);
        vm.assume(totalBorrows <= totalDeposits);

        uint256 borrowRate = model.getBorrowRate(totalDeposits, totalBorrows);
        uint256 supplyRate = model.getSupplyRate(totalDeposits, totalBorrows);

        assertLe(supplyRate, borrowRate);
    }

    function testFuzz_SupplyRate_MatchesFormula(uint128 totalDeposits, uint128 totalBorrows) public view {
        vm.assume(totalDeposits > 0);

        uint256 utilization = (uint256(totalBorrows) * PRECISION) / uint256(totalDeposits);
        uint256 borrowRate = model.getBorrowRate(totalDeposits, totalBorrows);
        uint256 expectedSupplyRate = (borrowRate * utilization) / PRECISION;

        assertEq(model.getSupplyRate(totalDeposits, totalBorrows), expectedSupplyRate);
    }
}
