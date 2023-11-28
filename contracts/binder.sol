// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BinderContract is OwnableUpgradeable {
    /* =========================== Struct =========================== */
    enum BinderState {
        NotRegistered,
        NoOwner,
        OnAuction,
        HasOwner,
        WaitingForRenewal
    }

    enum Trade {
        Buy,
        Sell
    }

    struct BinderStorage {
        BinderState state;
        address owner;  // Owner of the binder. Default to the contract address. (TODO: confirm this)
        uint lastTimePoint;
        uint16 auctionEpoch; // The epoch of the auction. Add 1 only when auction starts again.
    }

    /* =========================== Variables =========================== */
    /* ------ Time period ------ */
    uint public constant AUCTION_DURATION = 2 days;
    uint public constant HOLDING_PERIOD = 90 days;
    uint public constant RENEWAL_WINDOW = 2 days;

    /* ------ Admin & token & basic ------ */
    IERC20 public tokenAddress;

    /* ------ Signature ------ */
    address public backendSigner;
    uint public SIGNATURE_VALID_TIME = 3 minutes;
    // uint immutable SIGNATURE_SALT;

    /* ------ Tax ------ */
    uint public taxBasePointProtocol;
    uint public taxBasePointOwner;
    uint public feeCollectedProtocol;
    mapping(string => uint) public feeCollectedOwner;

    /* ------ Storage ------ */
    mapping(string => BinderStorage) public binders; // TODO: change to get() functions
    mapping(string => uint) public totalShare; // binder => total share num
    mapping(string => mapping(address => uint)) public userShare; // binder => user => user's share num
    mapping(string => mapping(uint16 => address [])) public userList; // binder => epoch => address[]
    mapping(string => mapping(uint16 => mapping(address => int))) public userInvested; // binder => epoch => user => user's invested amount

    /* =========================== Constructor =========================== */
    function initialize(
        address tokenAddress_,
        address backendSigner_
    ) public initializer {
        // Init parent contracts
        __Ownable_init();

        // Init token address & signer address
        tokenAddress = IERC20(tokenAddress_);
        backendSigner = backendSigner_;

        // Init tax base points (`500` means 5%)
        taxBasePointProtocol = 500;
        taxBasePointOwner = 500;
    }

    /* =========================== Events =========================== */
    // TODO: add events

    /* =========================== Errors =========================== */
    // TODO: add errors

    /* =========================== Modifiers =========================== */
    modifier shareNumNotZero(uint shareNum) {
        require(shareNum > 0, "Share num cannot be zero!");
        _;
    }

    modifier onlyWhenStateIs(string memory name, BinderState state) {
        string memory errorMessage;
        if (state == BinderState.NotRegistered) {
            errorMessage = "Not in state 'NotRegistered'!";
        } else if (state == BinderState.NoOwner) {
            errorMessage = "Not in state 'NoOwner'!";
        } else if (state == BinderState.OnAuction) {
            errorMessage = "Not in state 'OnAuction'!";
        } else if (state == BinderState.HasOwner) {
            errorMessage = "Not in state 'HasOwner'!";
        } else if (state == BinderState.WaitingForRenewal) {
            errorMessage = "Not in state 'WaitingForRenewal'!";
        } else {
            errorMessage = "Invalid state!";
        }
        require(binders[name].state == state, errorMessage);
        _;
    }

    modifier whenStateIsNot(string memory name, BinderState state) {
        string memory errorMessage;
        if (state == BinderState.NotRegistered) {
            errorMessage = "In state 'NotRegistered'!";
        } else if (state == BinderState.NoOwner) {
            errorMessage = "In state 'NoOwner'!";
        } else if (state == BinderState.OnAuction) {
            errorMessage = "In state 'OnAuction'!";
        } else if (state == BinderState.HasOwner) {
            errorMessage = "In state 'HasOwner'!";
        } else if (state == BinderState.WaitingForRenewal) {
            errorMessage = "In state 'WaitingForRenewal'!";
        } else {
            errorMessage = "Invalid state!";
        }
        require(binders[name].state != state, errorMessage);
        _;
    }

    /* =========================== View functions =========================== */
    function bindingFunction(uint x) public virtual pure returns (uint) {
        return 10 * x * x;
    }

    function bindingSumExclusive(uint start, uint end) public virtual pure returns (uint) {
        uint sum = 0;
        for (uint i = start; i < end; i++) {
            sum += bindingFunction(i);
        }
        return sum;
    }

    function findTopInvestor(string memory name, uint16 epoch) public view returns (address) {
        address [] memory userListThis = userList[name][epoch];
        address topInvestor = userListThis[0];
        int topInvestedAmount = userInvested[name][epoch][topInvestor];
        for (uint i = 1; i < userListThis.length; i++) {
            address investor = userListThis[i];
            int amount = userInvested[name][epoch][investor];
            if (amount > topInvestedAmount) {   // If tied for the top, the first one wins.
                topInvestor = investor;
                topInvestedAmount = amount;
            }
        }
        return topInvestor;
    }

    /* =========================== Write functions =========================== */
    function register(string memory name)
        public
        onlyWhenStateIs(name, BinderState.NotRegistered)
    {
        // TODO: Check signature

        // Register the binder
        binders[name].state = BinderState.NoOwner;
    }

    /* ------ State transition related functions ------ */
    function _countdownTriggerOnAuction(string memory name)
        internal
        onlyWhenStateIs(name, BinderState.OnAuction)
        returns (bool stateChanged)
    {
        uint16 epoch = binders[name].auctionEpoch;

        if (block.timestamp - binders[name].lastTimePoint > AUCTION_DURATION) {
            // The auction is over. The binder has an owner now.
            address topInvestor = findTopInvestor(name, epoch);
            binders[name] = BinderStorage({
                state: BinderState.HasOwner,    // State: 2 -> 3
                owner: topInvestor,
                lastTimePoint: block.timestamp,
                auctionEpoch: epoch
            });
            stateChanged = true;
        }
        stateChanged = false;
    }

    function _countdownTriggerHasOwner(string memory name)
        internal
        onlyWhenStateIs(name, BinderState.HasOwner)
        returns (bool stateChanged)
    {
        if (block.timestamp - binders[name].lastTimePoint > HOLDING_PERIOD) {
            // The owner's holding period is over. Now waiting for the owner's renewal.
            binders[name].state = BinderState.WaitingForRenewal;    // State: 3 -> 4
            binders[name].lastTimePoint = block.timestamp;
            stateChanged = true;
        }
        stateChanged = false;
    }

    function _countdownTriggerWaitingForRenewal(string memory name)
        internal
        onlyWhenStateIs(name, BinderState.WaitingForRenewal)
        returns (bool stateChanged)
    {
        if (block.timestamp - binders[name].lastTimePoint > RENEWAL_WINDOW) {
            // The renewal window is over. The binder is back to the NoOwner state.
            binders[name].state = BinderState.NoOwner;              // State: 4 -> 1
            binders[name].owner = address(this);
            stateChanged = true;
        }
        stateChanged = false;
    }
    
    function _countdownTrigger(string memory name)
        internal
        whenStateIsNot(name, BinderState.NotRegistered)
        whenStateIsNot(name, BinderState.NoOwner)
        returns (bool stateChanged)
    {
        BinderState currentState = binders[name].state;

        /* Case `OnAuction`: It's in the auction phase currently. */
        if (currentState == BinderState.OnAuction) {
            stateChanged = _countdownTriggerOnAuction(name);
        } 
        
        /* Case `HasOwner`: It's in the secure phase currently. The binder has an owner. */
        else if (currentState == BinderState.HasOwner) {
            stateChanged = _countdownTriggerHasOwner(name);
        } 
        
        /* Case `WaitingForRenewal`: Waiting for the owner's renewal. */
        else if (currentState == BinderState.WaitingForRenewal) {
            stateChanged = _countdownTriggerWaitingForRenewal(name);
        }

        else {
            revert("Unreachable code!");
        }
    }

    function _stateTransitionToAuction(string memory name)
        internal
        onlyWhenStateIs(name, BinderState.NoOwner)
    {
        uint16 epoch = binders[name].auctionEpoch;

        binders[name] = BinderStorage({
            state: BinderState.OnAuction,       // State: 1 -> 2
            owner: address(this),
            lastTimePoint: block.timestamp,
            auctionEpoch: epoch + 1             // Only place to add 1 to the epoch
        });
    }

    function _stateTransitionWhenRenewed(string memory name)
        internal
        onlyWhenStateIs(name, BinderState.WaitingForRenewal)
    {
        binders[name].state = BinderState.HasOwner;    // State: 4 -> 3
        binders[name].lastTimePoint = block.timestamp;
    }

    function _userListManage(string memory name, uint16 epoch, address user)
        internal
    {
        if (binders[name].state == BinderState.OnAuction && userInvested[name][epoch][user] == 0) {
            userList[name][epoch].push(user);
        }
        
            // uint16 epoch = binders[name].auctionEpoch;
            // if (binders[name].state == BinderState.OnAuction 
            //         && userInvested[name][epoch][user] == 0) {
            //     userList[name][epoch].push(user);
            // }
    }


    function buyShare(
        string memory name,
        uint shareNum
    )
        public
        whenStateIsNot(name, BinderState.NotRegistered)
        shareNumNotZero(shareNum)
        returns (bool stateChanged)
    {
        // TODO: Check signature

        // Transfer tokens
        address user = _msgSender();
        uint totalCost = bindingSumExclusive(totalShare[name], totalShare[name] + shareNum);
        tokenAddress.transferFrom(user, address(this), totalCost);

        // Update storage (state transfer)
        if (binders[name].state == BinderState.NoOwner) {
            _stateTransitionToAuction(name);
            userList[name][binders[name].auctionEpoch] = [user];
            stateChanged = true;
        } else {
            stateChanged = _countdownTrigger(name);
            uint16 epoch = binders[name].auctionEpoch;
            if (binders[name].state == BinderState.OnAuction 
                    && userInvested[name][epoch][user] == 0) {
                userList[name][epoch].push(user);
            }
        }

        // Update storage (share and token amount)
        totalShare[name] += shareNum;
        userShare[name][user] += shareNum;
        userInvested[name][binders[name].auctionEpoch][user] += int(totalCost);
    }


    function sellShare(
        string memory name,
        uint shareNum
    )
        public
        whenStateIsNot(name, BinderState.NotRegistered)
        shareNumNotZero(shareNum)
        returns (bool stateChanged)
    {
        address user = _msgSender();

        // // TODO: Check signature

        // Update storage (state transfer)
        if (binders[name].state != BinderState.NoOwner) {
            stateChanged = _countdownTrigger(name);
            // uint16 epoch = binders[name].auctionEpoch;
            // if (binders[name].state == BinderState.OnAuction 
            //         && userInvested[name][epoch][user] == 0) {
            //     userList[name][epoch].push(user);
            // }
        } else {
            // _stateTransitionToAuction(name);
            // userList[name][binders[name].auctionEpoch] = [user];
            // stateChanged = true;
        }

        // Transfer tokens
        uint totalReward = bindingSumExclusive(totalShare[name] - shareNum, totalShare[name]);
        uint feeForProtocol = totalReward * taxBasePointProtocol / 10000;
        uint feeForOwner = totalReward * taxBasePointOwner / 10000;
        uint actualReward = totalReward - feeForProtocol - feeForOwner;
        tokenAddress.transfer(user, actualReward);

        // Update storage (share and token amount)
        feeCollectedProtocol += feeForProtocol;
        feeCollectedOwner[name] += feeForOwner;
        totalShare[name] -= shareNum;
        userShare[name][user] -= shareNum;
        userInvested[name][binders[name].auctionEpoch][user] -= int(totalReward);
    }


    // function sellShare

    // function claimFee




    /* ------ S4: WaitingForRenewal ------ */
    // function renewOwnership

    // function renewOwnership() public onlyOwner {
    //     require(block.timestamp - lastInteraction <= RENEWAL_WINDOW, "Renewal period has expired");
    //     currentState = State.HasOwner;
    //     lastInteraction = block.timestamp;
    //     emit Renewal();
    // }

    // function transferOwnership(address newOwner) public onlyOwner {
    //     require(newOwner != address(0), "New owner is the zero address");
    //     emit OwnershipTransferred(owner, newOwner);
    //     owner = newOwner;
    // }

    // // Additional logic for auction and transferring shares would go here

}
