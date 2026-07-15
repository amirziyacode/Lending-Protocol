// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ReceiptToken} from "src/ReceiptToken.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LendingProtocol
 * @author AmirAli
 * @notice it just for learing !!
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
        uint256 lastInterestUpdate;
    }

    // ==================== State Variables ====================
    IERC20 public token;
    ReceiptToken public receiptToken;
    PriceOracle private oracle;

    mapping(address => UserPosition) private positions;

    uint256 public totalDeposits;

    uint256 public totalBorrows;

    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;

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
     *
     * @param price_feed is for network we want to get ETH price from offchain like sepolia
     */
    constructor(address _token, address price_feed) {
        token = IERC20(_token);
        receiptToken = new ReceiptToken();
        oracle = new PriceOracle(price_feed);
    }

    /**
     *
     * @param amount ETH value send it
     */
    function depositCollateral(uint256 amount) external {
        if (amount == 0) {
            revert LendingPool__ZeroAmount();
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        positions[msg.sender].deposited += amount;
        totalDeposits += amount;

        receiptToken.mint(msg.sender, amount);

        emit Deposited(msg.sender, amount);
    }

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

        token.safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        if (amount == 0) {
            revert LendingPool__ZeroAmount();
        }

        if (amount > positions[msg.sender].borrowed) {
            revert LendingPool__RepayTooMuch();
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        positions[msg.sender].borrowed -= amount;

        emit Repay(msg.sender, amount);
    }

    function Withdraw(uint256 amount) external {
        if (amount == 0) {
            revert LendingPool__ZeroAmount();
        }

        if (amount < positions[msg.sender].deposited) {
            revert LendingPool__InsufficientCollateral();
        }

        positions[msg.sender].deposited -= amount;

        if (_healthFactor(msg.sender) < MINIMUM_HEALTH_FACTOR) {
            revert LendingPool__HeathFactorNotOk();
        }

        totalDeposits -= amount;

        receiptToken.burn(msg.sender, amount);

        token.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // ==================== Internal Functions ====================
    function _healthFactor(address _user) internal view returns (uint256) {
        uint256 collateral = positions[_user].deposited;
        uint256 debt = positions[_user].borrowed;

        if (debt == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateral = (collateral * LIQUIDATION_THRESHOLD) / 100;

        return (adjustedCollateral * PRECISION) / debt;
    }

    function _isBorrowAllowed(address user, uint256 borrowAmount) internal view returns (bool) {
        uint256 currentDebt = positions[user].borrowed;
        uint256 borrowLimit = (positions[user].deposited * LTV) / 100;

        return (currentDebt + borrowAmount) <= borrowLimit;
    }

    // ==================== Getter Functions ====================

    function getUserDeposite(address user) external view returns (uint256) {
        return positions[user].deposited;
    }

    function getUserBorrowed(address user) external view returns (uint256) {
        return positions[user].borrowed;
    }

    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }

    function getLTV() external pure returns (uint256) {
        return LTV;
    }
}
