// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICvxLocker {
    struct LockedBalance {
        uint112 amount;
        uint32 unlockTime;
    }

    function lockedBalances(address _user)
        external
        view
        returns (
            uint256 total,
            uint256 unlockable,
            uint256 locked,
            LockedBalance[] memory lockData
        );
}
