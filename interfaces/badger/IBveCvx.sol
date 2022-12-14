// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBveCvx {
    function balanceOf(address account) external view returns (uint256);

    function balance() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function withdraw(uint256 _amount) external;

    function withdrawAll() external;
}
