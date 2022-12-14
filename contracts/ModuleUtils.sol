// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "interfaces/chainlink/IAggregatorV3.sol";

import {ModuleConstants} from "./ModuleConstants.sol";

contract ModuleUtils is ModuleConstants {
    /* ========== ERRORS ========== */

    error StalePriceFeed(
        uint256 currentTime,
        uint256 updateTime,
        uint256 maxPeriod
    );

    function getCvxAmountInEth(uint256 _cvxAmount)
        internal
        view
        returns (uint256 usdcAmount_)
    {
        uint256 cvxInEth = fetchPriceFromClFeed(
            CVX_ETH_FEED,
            CL_FEED_DAY_HEARTBEAT
        );
        // Divisor is 10^18 and uint256 max ~ 10^77 so this shouldn't overflow for normal amounts
        usdcAmount_ = (_cvxAmount * cvxInEth) / FEED_DIVISOR_ETH;
    }

    function getWethAmountInDai(uint256 _wethAmount)
        internal
        view
        returns (uint256 daiAmount_)
    {
        uint256 daiInWeth = fetchPriceFromClFeed(
            DAI_ETH_FEED,
            CL_FEED_DAY_HEARTBEAT
        );
        // Divide by the rate from oracle since it is dai expressed in eth
        // FEED_DIVISOR_ETH has 1e18 precision
        daiAmount_ = (_wethAmount * FEED_DIVISOR_ETH) / daiInWeth;
    }

    function fetchPriceFromClFeed(IAggregatorV3 _feed, uint256 _maxStalePeriod)
        internal
        view
        returns (uint256 answerUint256_)
    {
        (, int256 answer, , uint256 updateTime, ) = _feed.latestRoundData();

        if (block.timestamp - updateTime > _maxStalePeriod) {
            revert StalePriceFeed(block.timestamp, updateTime, _maxStalePeriod);
        }

        answerUint256_ = uint256(answer);
    }
}
