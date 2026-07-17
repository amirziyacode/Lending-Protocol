// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {InterestModel} from "./InterestModel.sol";
import {IInterestRateModel} from "./intefercafes/IInterestRateModel.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ReceiptToken} from "src/ReceiptToken.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LendingProtocol
 * @author AmirAli
 * @notice A simple collateralized lending pool for learning purposes.
 */
contract LendingPool {
    using SafeERC20 for IERC20;
    // ==================== Erros ====================
    error LendingPool__ZeroAmount();
    error LendingPool__HeathFactorNotOk();
    error LendingPool__InsufficientCollateral();
    error LendingPool__OutOf_MaxBorrow();
    error LendingPool__InsufficientLiquidity();
    error LendingPool__RepayTooMuch();

    // ==================== Type Declarations ====================
    struct UserPosition {
        uint256 deposited;
        uint256 borrowed;
        uint256 lastBorrowUpdate;
        uint256 lastDepositUpdate;
        uint256 accruedDepositInterest;
        uint256 accruedBorrowInterest;
    }

    // ==================== State Variables ====================
    IERC20 public token;
    ReceiptToken public receiptToken;
    PriceOracle public oracle;
    IInterestRateModel public interestModel;

    mapping(address => UserPosition) private positions;
    mapping(address => uint256) private userBorrowRate;

    uint256 private totalDeposits;
    uint256 private totalBorrows;

    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant YEAR = 365 days;
    uint256 constant PRECISION = 1e18;

    uint256 private constant LTV = 80; // LTV = 80 %

    uint256 private constant LIQUIDATION_THRESHOLD = 75; // 75 %

    // ==================== Event ====================

    event Deposited(address indexed sender, uint256 amount);
    event Withdrawn(address indexed sender, uint256 amount);
    event Borrow(address indexed sender, uint256 amount);
    event Repay(address indexed sender, uint256 amount);

    // ==================== External Functions ====================

    /**
     * @notice Deploys the lending pool and its dependent contracts.
     * @param _token The ERC20 token used as collateral and liquidity.
     * @param price_feed The Chainlink price feed address for the collateral asset.
     */
    constructor(address _token, address price_feed) {
        token = IERC20(_token);
        receiptToken = new ReceiptToken();
        oracle = new PriceOracle(price_feed);
        interestModel = new InterestModel();
    }

    /**
     * @notice Deposits collateral into the pool and mints receipt tokens to the sender.
     * @param amount The amount of tokens to deposit.
     */
    function depositCollateral(uint256 amount) external {
        if (amount == 0) {
            revert LendingPool__ZeroAmount();
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        positions[msg.sender].lastDepositUpdate = block.timestamp;
        positions[msg.sender].deposited += amount;
        totalDeposits += amount;

        receiptToken.mint(msg.sender, amount);

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Borrows tokens from the pool against deposited collateral.
     * @dev Updates the borrow rate, accrual timestamp, and total borrows before transferring funds.
     * @param amount The amount of tokens to borrow.
     */
    function borrow(uint256 amount) external {
        if (amount == 0) {
            revert LendingPool__ZeroAmount();
        }

        if (token.balanceOf(address(this)) < amount) {
            revert LendingPool__InsufficientLiquidity();
        }

        if (!_isBorrowAllowed(msg.sender, amount)) {
            revert LendingPool__OutOf_MaxBorrow();
        }

        positions[msg.sender].borrowed += amount;

        if (_healthFactor(msg.sender) < MINIMUM_HEALTH_FACTOR) {
            revert LendingPool__HeathFactorNotOk();
        }
        totalBorrows += amount;
        uint256 rate = interestModel.getBorrowRate(totalDeposits, totalBorrows);

        positions[msg.sender].lastBorrowUpdate = block.timestamp;
        userBorrowRate[msg.sender] = rate;
        token.safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, amount);
    }

    /**
     * @notice Repays outstanding debt, applying payment to accrued interest first.
     * @dev Accrues pending interest before validating the repayment amount.
     * @param amount The amount of tokens to repay.
     */
    function repay(uint256 amount) external {
        if (amount == 0) {
            revert LendingPool__ZeroAmount();
        }

        uint256 repayAmount = amount;
        _accrueBorrowInterest(msg.sender);
        uint256 debt = positions[msg.sender].borrowed + positions[msg.sender].accruedBorrowInterest;

        if (amount > debt) {
            revert LendingPool__RepayTooMuch();
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        if (amount >= positions[msg.sender].accruedBorrowInterest) {
            amount -= positions[msg.sender].accruedBorrowInterest;
            positions[msg.sender].accruedBorrowInterest = 0;
            positions[msg.sender].borrowed -= amount;
        } else {
            positions[msg.sender].accruedBorrowInterest -= amount;
        }

        positions[msg.sender].lastBorrowUpdate = block.timestamp;

        emit Repay(msg.sender, repayAmount);
    }

    /**
     * @notice Withdraws deposited collateral and burns the corresponding receipt tokens.
     * @dev Reverts if the withdrawal would leave the user's health factor below the minimum.
     * @param amount The amount of collateral to withdraw.
     */
    function withdraw(uint256 amount) external {
        if (amount == 0) {
            revert LendingPool__ZeroAmount();
        }

        _accrueWithdrawInterest(msg.sender);
        uint256 amountSender = amount;
        uint256 principal = positions[msg.sender].deposited;
        uint256 interest = positions[msg.sender].accruedDepositInterest;
        uint256 totalBalance = principal + interest;

        if (amount > totalBalance) {
            revert LendingPool__InsufficientCollateral();
        }

        if (totalBalance >= positions[msg.sender].accruedDepositInterest) {
            amount -= positions[msg.sender].accruedDepositInterest;
            positions[msg.sender].accruedDepositInterest = 0;
            positions[msg.sender].deposited -= amount;
        } else {
            positions[msg.sender].accruedDepositInterest -= amount;
        }

        if (_healthFactor(msg.sender) < MINIMUM_HEALTH_FACTOR) {
            revert LendingPool__HeathFactorNotOk();
        }

        totalDeposits -= amountSender;
        uint256 remaining = amount - interest;

        receiptToken.burn(msg.sender, remaining);

        token.safeTransfer(msg.sender, amountSender);

        emit Withdrawn(msg.sender, amountSender);
    }

    // ==================== Internal Functions ====================
    /**
     * @notice Calculates the health factor for a user position.
     * @dev Returns the maximum uint256 value when the user has no debt.
     * @param _user The address of the user to evaluate.
     * @return The health factor scaled by `PRECISION` (1e18).
     */
    function _healthFactor(address _user) internal view returns (uint256) {
        uint256 collateral = positions[_user].deposited;
        uint256 debt = positions[_user].borrowed;
        uint256 totalDebt = debt + positions[_user].accruedBorrowInterest;

        if (totalDebt == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateral = (collateral * LIQUIDATION_THRESHOLD) / 100;

        return (adjustedCollateral * PRECISION) / totalDebt;
    }

    /**
     * @notice Checks whether a borrow amount stays within the user's LTV limit.
     * @param user The address of the borrower.
     * @param borrowAmount The additional amount the user wants to borrow.
     * @return True if the borrow is allowed, false otherwise.
     */
    function _isBorrowAllowed(address user, uint256 borrowAmount) internal view returns (bool) {
        uint256 currentDebt = positions[user].borrowed;
        uint256 borrowLimit = (positions[user].deposited * LTV) / 100;

        return (currentDebt + borrowAmount) <= borrowLimit;
    }

    /**
     * @notice Accrues interest on a user's outstanding borrow since the last update.
     * @dev Adds the computed interest to `accruedInterest` and updates `lastInterestUpdate`.
     * @param user The address of the borrower.
     */
    function _accrueBorrowInterest(address user) internal {
        uint256 elapsed = block.timestamp - positions[user].lastBorrowUpdate;

        uint256 interest = (positions[user].borrowed * userBorrowRate[user] * elapsed) / (PRECISION * YEAR);

        positions[user].accruedBorrowInterest += interest;

        positions[user].lastBorrowUpdate = block.timestamp;
    }

    /**
     * @notice Accrues interest on a user's outstanding deposit since the last update.
     * @dev Adds the computed interest to `accruedInterest` and updates `lastInterestUpdate`.
     * @param user The address of the borrower.
     */
    function _accrueWithdrawInterest(address user) internal {
        uint256 supplyRate = interestModel.getSupplyRate(totalDeposits, totalBorrows);
        uint256 elapsed = block.timestamp - positions[user].lastDepositUpdate;
        uint256 interest = (positions[msg.sender].deposited * supplyRate * elapsed) / (PRECISION * YEAR);

        positions[user].accruedDepositInterest += interest;
        positions[user].lastDepositUpdate = block.timestamp;
    }

    // ==================== Getter Functions ====================

    /**
     * @notice Returns the amount of collateral a user has deposited.
     * @param user The address of the user.
     * @return The deposited collateral amount.
     */
    function getUserDeposit(address user) external view returns (uint256) {
        return positions[user].deposited;
    }

    /**
     * @notice Returns the principal amount a user has borrowed.
     * @param user The address of the user.
     * @return The borrowed principal, excluding accrued interest.
     */
    function getUserBorrowed(address user) external view returns (uint256) {
        return positions[user].borrowed;
    }

    /**
     * @notice Returns the timestamp of the user's last interest accrual update.
     * @param user The address of the user.
     * @return The Unix timestamp of the last interest update.
     */
    function getUserLastInterestUpdate(address user) external view returns (uint256) {
        return positions[user].lastBorrowUpdate;
    }

    /**
     * @notice Returns the timestamp of the user's last interest accrual update.
     * @param user The address of the user.
     * @return The Unix timestamp of the last interest update.
     */
    function getUserLastDepositUpdate(address user) external view returns (uint256) {
        return positions[user].lastDepositUpdate;
    }

    /**
     * @notice Returns the interest accrued on a user's borrow that has not yet been repaid.
     * @param user The address of the user.
     * @return The accrued interest amount.
     */
    function getUserAccruedInterest(address user) external view returns (uint256) {
        return positions[user].accruedBorrowInterest;
    }

    /**
     * @notice Returns the interest accrued on a user's deposit that has not yet been repaid.
     * @param user The address of the user.
     * @return The accrued interest amount.
     */
    function getUserAccruedDepositInterest(address user) external view returns (uint256) {
        return positions[user].accruedDepositInterest;
    }

    /**
     * @notice Returns the total collateral deposited across all users.
     * @return The total deposited amount.
     */
    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }

    /**
     * @notice Returns the total principal borrowed across all users.
     * @return The total borrowed amount.
     */
    function getTotalBorrows() external view returns (uint256) {
        return totalBorrows;
    }

    /**
     * @notice Returns the loan-to-value ratio used for borrow limits.
     * @return The LTV percentage (e.g. 80 for 80%).
     */
    function getLTV() external pure returns (uint256) {
        return LTV;
    }

    /**
     * @notice Returns the borrow rate locked in for a user at their last borrow.
     * @param _user The address of the user.
     * @return The borrow rate scaled by `PRECISION` (1e18).
     */
    function getUserBorrowRate(address _user) external view returns (uint256) {
        return userBorrowRate[_user];
    }

    /**
     * @notice Returns the current health factor for a user.
     * @param _user The address of the user.
     * @return The health factor scaled by `PRECISION` (1e18).
     */
    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }

    /**
     * @notice Returns the user's total debt including principal, stored accrued interest, and pending interest.
     * @dev Computes pending interest from the last update timestamp without modifying state.
     * @param user The address of the user.
     * @return The total debt amount.
     */
    function getDebt(address user) external view returns (uint256) {
        uint256 elapsed = block.timestamp - positions[user].lastBorrowUpdate;
        uint256 rate = userBorrowRate[user];

        uint256 interest = (positions[user].borrowed * rate * elapsed) / (1e18 * YEAR);

        return positions[user].borrowed + positions[user].accruedBorrowInterest + interest;
    }
}
