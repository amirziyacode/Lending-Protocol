// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "chainlink-local/data-feeds/interfaces/AggregatorV3Interface.sol";

contract PriceOracle {
    AggregatorV3Interface private priceFeed;

    constructor(address priceFeed_addressd) {
        priceFeed = AggregatorV3Interface(priceFeed_addressd);
    }

    function getPrice() public view returns (uint256) {
        (, int256 ethPrice,,,) = priceFeed.latestRoundData();
        return uint256(ethPrice * 10000000000);
    }
}
