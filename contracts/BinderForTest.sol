// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Binder.sol";

contract BinderForTest is BinderContract {

    /**
     * This is a test contract that inherits from the Binder contract. We reduce the 
     * time parameters to make testing easier, including the auction duration, holding
     * period, and renewal window. If needed, the signature valid time can also be
     * reduced by calling `setSignatureValidTime` function
     */

    function getAutcionDuration() public override pure returns (uint256) {
        return 3 minutes;
    }

    function getHoldingPeriod() public override pure returns (uint256) {
        return 10 minutes;
    }

    function getRenewalWindow() public override pure returns (uint256) {
        return 3 minutes;
    }
}