// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBinderContract {
    function register(string memory name) external;
    function buyShare(string memory name, uint256 shareNum) external;
    function sellShare(string memory name, uint256 shareNum) external;
    function renewOwnership(string memory name, uint256 tokenAmount) external;
}