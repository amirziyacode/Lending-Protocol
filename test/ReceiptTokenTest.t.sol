// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {ReceiptToken} from "src/ReceiptToken.sol";

contract ReceiptTokenTest is Test {
    ReceiptToken public token;

    uint256 private constant TOTALSUPPLY = 1000;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");

    function setUp() public {
        token = new ReceiptToken();
    }

    function testShouldOwnerMintToken() public {
        vm.startPrank(owner);
        token = new ReceiptToken();

        token.mint(user, TOTALSUPPLY);

        uint256 balance = token.balanceOf(user);

        assertEq(balance, TOTALSUPPLY);

        vm.stopPrank();
    }

    function test_Should_revert_when_user_call_mintToken() public {
        vm.startPrank(user);

        vm.expectRevert(ReceiptToken.ReceiptToken__NotOwner.selector);

        token.mint(user, TOTALSUPPLY);

        vm.stopPrank();
    }

    function testburnToken() public {
        vm.startPrank(user);

        token = new ReceiptToken();

        token.mint(user, TOTALSUPPLY);

        token.burn(user, 100);

        uint256 excpectBalance = 900;

        uint256 actualBalance = token.balanceOf(user);

        assertEq(actualBalance, excpectBalance);

        vm.stopPrank();
    }

    function testburnToken_revert_NotOwner() public {
        vm.expectRevert(ReceiptToken.ReceiptToken__NotOwner.selector);

        vm.prank(user);
        token.burn(user, 100);
    }
}
