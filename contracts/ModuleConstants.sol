// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "interfaces/chainlink/IAggregatorV3.sol";

import "interfaces/gnosis/IGnosisSafe.sol";
import "interfaces/badger/IBveCvx.sol";
import "interfaces/convex/ICvxLocker.sol";

abstract contract ModuleConstants {
    address public constant TREASURY =
        0xD0A7A8B98957b9CD3cFB9c0425AbE44551158e9e;
    address public constant GOVERNANCE =
        0xA9ed98B5Fb8428d68664f3C5027c62A10d45826b;
    IGnosisSafe public constant SAFE = IGnosisSafe(GOVERNANCE);

    // badger product
    IBveCvx constant BVE_CVX =
        IBveCvx(0xfd05D3C7fe2924020620A8bE4961bBaA747e6305);
    address constant BVECVX_STRAT = 0x898111d1F4eB55025D0036568212425EE2274082;

    // convex locker v2
    ICvxLocker internal constant LOCKER =
        ICvxLocker(0x72a19342e8F1838460eBFCCEf09F6585e32db86E);

    // tokens involved
    IERC20 internal constant CVX =
        IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 internal constant WETH =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 internal constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // curve pools
    address internal constant CVX_ETH_CURVE_POOL =
        0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;

    // uniswap v3
    address internal constant UNIV3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // CL feed oracles
    IAggregatorV3 internal constant CVX_ETH_FEED =
        IAggregatorV3(0xC9CbF687f43176B302F03f5e58470b77D07c61c6);
    IAggregatorV3 internal constant DAI_ETH_FEED =
        IAggregatorV3(0x773616E4d11A78F511299002da57A0a94577F1f4);
    uint256 internal constant CL_FEED_DAY_HEARTBEAT = 24 hours;

    // NOTE: all CL eth feeds are expressed in 18 decimals
    uint256 internal constant FEED_DIVISOR_ETH = 1e18;

    uint256 constant MAX_BPS = 10_000;
    uint256 constant MAX_FACTOR_WD = 6_000;
    uint256 constant MIN_OUT_SWAP = 9_850;

    // hardcoded timestamp where keeper always should return `false`
    uint256 constant KEEPER_DEADLINE = 1672963200;

    // max selling spot weekly
    uint256 constant MAX_WEEKLY_CVX_SPOT = 5_000e18;
    uint256 constant ONE_WEEK = 1 weeks;
}
