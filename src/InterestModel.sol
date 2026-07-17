// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IInterestRateModel} from "./intefercafes/IInterestRateModel.sol";

/**
 * @title InterestModel
 * @author Amirali
 * @notice   Calculate Rate for price feed in ChinLinkOracle
 */
contract InterestModel is IInterestRateModel {
    uint256 public constant OPTIMAL_UTILIZATION = 70e16; // 70%
    uint256 public constant LOW_RATE = 5e16; // 5%
    uint256 public constant HIGH_RATE = 15e16; // 15%
    uint256 private constant PRECISION = 1e18;

    function getBorrowRate(uint256 totalDeposits, uint256 totalBorrows) external pure override returns (uint256) {
        if (totalDeposits == 0) return 0;

        uint256 utilization = (totalBorrows * PRECISION) / totalDeposits;

        if (utilization < OPTIMAL_UTILIZATION) {
            return LOW_RATE;
        }

        return HIGH_RATE;
    }
}
