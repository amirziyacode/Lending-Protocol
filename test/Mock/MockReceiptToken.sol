// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title ReceiptToken from ERC20
 * @author AmirAli
 * @notice Mint and Burn Token
 */
contract MockReceiptToken is ERC20 {
    // ==================== error ====================
    error MockReceiptToken__NotOwner();

    // ==================== State Variables ====================
    address public pool;

    // ==================== Modifier ====================
    modifier onlyPool() {
        if (msg.sender != pool) {
            revert MockReceiptToken__NotOwner();
        }
        _;
    }

    constructor() ERC20("Receipt Token", "rTOKEN") {
        pool = msg.sender;
    }

    // ==================== Functiona ====================

    /**
     *
     * @param to  the address we want mint token
     * @param amount  the value we want to mint
     */
    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }

    /**
     *
     * @param to  the address we want burn token
     * @param amount  the value we want to burn
     */
    function burn(address to, uint256 amount) external onlyPool {
        _burn(to, amount);
    }
}
