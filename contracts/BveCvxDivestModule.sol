// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "interfaces/chainlink/KeeperCompatibleInterface.sol";

import "interfaces/gnosis/IGnosisSafe.sol";
import "interfaces/curve/ICurvePool.sol";
import "interfaces/uniswap/IUniswapRouterV3.sol";
import "interfaces/badger/IBvecvx.sol";

import {ModuleUtils} from "./ModuleUtils.sol";

/// @title   BveCvxDivestModule
/// @dev  Allows whitelisted executors to trigger `performUpkeep` with limited scoped
/// in our case to carry the divesting of bveCVX into USDC whenever unlocks in schedules
/// occurs with a breathing factor of 60% to allow users to withdraw
contract BveCvxDivestModule is
    ModuleUtils,
    KeeperCompatibleInterface,
    Pausable,
    ReentrancyGuard
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ========== STATE VARIABLES ========== */
    address public guardian;
    uint256 public initialcvxTimestampWeekSelling;
    uint256 public weeklyCvxSold;

    EnumerableSet.AddressSet internal _executors;

    /* ========== EVENT ========== */

    event ExecutorAdded(address indexed _user, uint256 _timestamp);
    event ExecutorRemoved(address indexed _user, uint256 _timestamp);
    event GuardianUpdated(
        address indexed newGuardian,
        address indexed oldGuardian,
        uint256 timestamp
    );

    constructor(address _guardian) {
        guardian = _guardian;
    }

    /***************************************
                    MODIFIERS
    ****************************************/
    modifier onlyGovernance() {
        require(msg.sender == GOVERNANCE, "not-governance!");
        _;
    }

    modifier onlyExecutors() {
        require(_executors.contains(msg.sender), "not-executor!");
        _;
    }

    modifier onlyGovernanceOrGuardian() {
        require(
            msg.sender == GOVERNANCE || msg.sender == guardian,
            "not-gov-or-guardian"
        );
        _;
    }

    /***************************************
               ADMIN - GOVERNANCE
    ****************************************/

    /// @dev Adds an executor to the Set of allowed addresses.
    /// @notice Only callable by governance.
    /// @param _executor Address which will have rights to call `checkTransactionAndExecute`.
    function addExecutor(address _executor) external onlyGovernance {
        require(_executor != address(0), "zero-address!");
        require(_executors.add(_executor), "not-add-in-set!");
        emit ExecutorAdded(_executor, block.timestamp);
    }

    /// @dev Removes an executor to the Set of allowed addresses.
    /// @notice Only callable by governance.
    /// @param _executor Address which will not have rights to call `checkTransactionAndExecute`.
    function removeExecutor(address _executor) external onlyGovernance {
        require(_executor != address(0), "zero-address!");
        require(_executors.remove(_executor), "not-remove-in-set!");
        emit ExecutorRemoved(_executor, block.timestamp);
    }

    /// @dev Updates the guardian address
    /// @notice Only callable by governance.
    /// @param _guardian Address which will beccome guardian
    function setGuardian(address _guardian) external onlyGovernance {
        require(_guardian != address(0), "zero-address!");
        address oldGuardian = _guardian;
        guardian = _guardian;
        emit GuardianUpdated(_guardian, oldGuardian, block.timestamp);
    }

    /// @dev Pauses the contract, which prevents executing performUpkeep.
    function pause() external onlyGovernanceOrGuardian {
        _pause();
    }

    /// @dev Unpauses the contract.
    function unpause() external onlyGovernance {
        _unpause();
    }

    /***************************************
                KEEPERS - EXECUTORS
    ****************************************/

    /// @dev Runs off-chain at every block to determine if the `performUpkeep`
    /// function should be called on-chain.
    function checkUpkeep(bytes calldata)
        external
        view
        override
        whenNotPaused
        returns (bool upkeepNeeded, bytes memory checkData)
    {
        uint256 totalWdBveCvx = totalCvxWithdrawable();
        uint256 bveCVXSafeBal = BVE_CVX.balanceOf(address(SAFE));

        // NOTE: if there is anything available to wd, keeper will proceed & ts lower than 00:00 utc 6th Jan
        if (
            totalWdBveCvx > 0 &&
            bveCVXSafeBal > 0 &&
            block.timestamp <= KEEPER_DEADLINE
        ) {
            upkeepNeeded = true;
        }
    }

    /// @dev Contains the logic that should be executed on-chain when
    /// `checkUpkeep` returns true.
    function performUpkeep(bytes calldata performData)
        external
        override
        onlyExecutors
        whenNotPaused
        nonReentrant
    {
        /// @dev safety check, ensuring onchain module is config
        require(SAFE.isModuleEnabled(address(this)), "no-module-enabled!");
        // 1. wd bvecvx with factor 0.6
        _withdrawBveCvx();
        // 2. swap cvx balance to weth
        _swapCvxForWeth();
        // 3. swap weth to usdc and send to treasury
        _swapWethToUsdc();
    }

    /***************************************
                INTERNAL
    ****************************************/

    function _withdrawBveCvx() internal {
        uint256 bveCVXSafeBal = BVE_CVX.balanceOf(address(SAFE));
        if (bveCVXSafeBal > 0) {
            uint256 totalWdBveCvx = totalCvxWithdrawable();
            /// @dev covers corner case when nothing might be withdrawable
            if (totalWdBveCvx > 0) {
                uint256 bveCvxBalance = BVE_CVX.balance();
                uint256 bveCvxTotalSupply = BVE_CVX.totalSupply();

                _checkTransactionAndExecute(
                    address(BVE_CVX),
                    abi.encodeCall(
                        IBveCvx.withdraw,
                        (((totalWdBveCvx * bveCvxTotalSupply) / bveCvxBalance) *
                            MAX_FACTOR_WD) / MAX_BPS
                    )
                );
            }
        }
    }

    function _swapCvxForWeth() internal {
        uint256 cvxBal = CVX.balanceOf(address(SAFE));
        if (cvxBal > 0) {
            /// @dev will be used as condition to limit amount sold weekly
            if (block.timestamp > initialcvxTimestampWeekSelling + ONE_WEEK) {
                initialcvxTimestampWeekSelling = block.timestamp;
                weeklyCvxSold = 0;
            }

            // NOTE: limit the spot selling given 5k/weekly limit
            uint256 cvxSpotSellLimit = MAX_WEEKLY_CVX_SPOT - weeklyCvxSold;
            uint256 cvxSpotSell = cvxSpotSellLimit > cvxBal
                ? cvxBal
                : weeklyCvxSold;
            weeklyCvxSold += cvxSpotSell;

            if (cvxSpotSell > 0) {
                // 1. Approve CVX into curve pool
                _checkTransactionAndExecute(
                    address(CVX),
                    abi.encodeCall(
                        IERC20.approve,
                        (CVX_ETH_CURVE_POOL, cvxSpotSell)
                    )
                );
                // 2. Swap CVX -> WETH
                _checkTransactionAndExecute(
                    CVX_ETH_CURVE_POOL,
                    abi.encodeCall(
                        ICurvePool.exchange,
                        (
                            1,
                            0,
                            cvxSpotSell,
                            (getCvxAmountInEth(cvxSpotSell) * MIN_OUT_SWAP) /
                                MAX_BPS
                        )
                    )
                );
            }
        }
    }

    function _swapWethToUsdc() internal {
        // Swap WETH -> USDC
        uint256 wethBal = WETH.balanceOf(address(SAFE));
        if (wethBal > 0) {
            // 1. Approve WETH into univ3 router
            _checkTransactionAndExecute(
                address(WETH),
                abi.encodeCall(IERC20.approve, (UNIV3_ROUTER, wethBal))
            );
            // 2. Swap WETH to USDC
            IUniswapRouterV3.ExactInputSingleParams memory params = IUniswapRouterV3
                .ExactInputSingleParams({
                    tokenIn: address(WETH),
                    tokenOut: address(USDC),
                    fee: uint24(500),
                    recipient: TREASURY,
                    deadline: type(uint256).max,
                    amountIn: wethBal,
                    amountOutMinimum: (getWethAmountInDai(wethBal) *
                        MIN_OUT_SWAP) / MAX_BPS,
                    sqrtPriceLimitX96: 0 // Inactive param
                });
            _checkTransactionAndExecute(
                UNIV3_ROUTER,
                abi.encodeCall(IUniswapRouterV3.exactInputSingle, (params))
            );
        }
    }

    /// @dev Allows executing specific calldata into an address thru a gnosis-safe, which have enable this contract as module.
    /// @notice Only callable by executors.
    /// @param to Contract address where we will execute the calldata.
    /// @param data Calldata to be executed within the boundaries of the `allowedFunctions`.
    function _checkTransactionAndExecute(address to, bytes memory data)
        internal
    {
        if (data.length >= 4) {
            require(
                SAFE.execTransactionFromModule(
                    to,
                    0,
                    data,
                    IGnosisSafe.Operation.Call
                ),
                "exec-error!"
            );
        }
    }

    /***************************************
               PUBLIC FUNCTION
    ****************************************/
    /// @dev Returns all addresses which have executor role
    function getExecutors() public view returns (address[] memory) {
        return _executors.values();
    }

    /// @dev returns the total amount withdrawable at current moment
    /// @return totalWdCvx Total amount of CVX withdrawable, summation of available in vault, strat and unlockable
    function totalCvxWithdrawable() public view returns (uint256 totalWdCvx) {
        /// @dev check avail CONVEX to avoid wd reverts
        uint256 cvxInVault = CVX.balanceOf(address(BVE_CVX));
        uint256 cvxInStrat = CVX.balanceOf(address(BVECVX_STRAT));
        (, uint256 unlockableStrat, , ) = LOCKER.lockedBalances(BVECVX_STRAT);
        totalWdCvx = cvxInVault + cvxInStrat + unlockableStrat;
    }
}
