// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BinderContract is OwnableUpgradeable {
    /* ================ Struct ================ */
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

    /* ================ Variables ================ */
    /* ------ Time period ------ */
    uint256 public constant AUCTION_DURATION = 2 days;
    uint256 public constant HOLDING_PERIOD = 90 days;
    uint256 public constant RENEWAL_WINDOW = 2 days;

    /* ------ Admin & token & basic ------ */
    IERC20 public tokenAddress;

    /* ------ Signature ------ */
    address public backendSigner;
    uint256 public SIGNATURE_VALID_TIME = 3 minutes;
    // uint256 immutable SIGNATURE_SALT;

    /* ------ Tax ------ */
    uint256 public taxBasePointProtocol;
    uint256 public taxBasePointOwner;

    /* ------ Storage ------ */
    mapping(string => BinderStorage) public binders; // TODO: change to get() functions
    mapping(string => uint) public totalShare; // binder => total share num
    mapping(string => mapping(address => uint)) public userShare; // binder => user => user's share num
    mapping(string => mapping(uint16 => address [])) public userList; // binder => epoch => address[]
    mapping(string => mapping(uint16 => mapping(address => int))) public userInvested; // binder => epoch => user => user's invested amount

    /* ================ Constructor ================ */
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

    /* ================ Events ================ */
    // TODO: add events

    /* ================ Errors ================ */
    // TODO: add errors

    /* ================ Modifiers ================ */
    modifier shareNumNotZero(uint256 shareNum) {
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

    /* ================ View functions ================ */
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
            if (amount > topInvestedAmount) {
                topInvestor = investor;
                topInvestedAmount = amount;
            }
        }
        return topInvestor;
    }

    /* ================ Write functions ================ */
    function register(
        string memory name
    )
        public
        onlyWhenStateIs(name, BinderState.NotRegistered)
    {
        // TODO: Check signature

        // Register the binder
        binders[name].state = BinderState.NoOwner;
    }

    function _checkStateNoOwner(
        address user,
        string memory name
    )
        internal
        onlyWhenStateIs(name, BinderState.NoOwner)
    {
        uint16 newEpoch = binders[name].auctionEpoch + 1;

        binders[name] = BinderStorage({
            state: BinderState.OnAuction, // State: 1 -> 2
            owner: address(this),
            lastTimePoint: block.timestamp,
            auctionEpoch: newEpoch
        });

        userList[name][newEpoch] = [user];
        
        // It won't cause any state change when selling in the NoOwner state.
    }

    function _checkStateOnAuction(
        address user,
        string memory name
    )
        internal
        onlyWhenStateIs(name, BinderState.OnAuction)
    {
        uint16 epoch = binders[name].auctionEpoch;

        if (block.timestamp - binders[name].lastTimePoint > AUCTION_DURATION) {
            // The auction is over. The binder has an owner now.
            address topInvestor = findTopInvestor(name, epoch);
            binders[name] = BinderStorage({
                state: BinderState.HasOwner, // State: 2 -> 3
                owner: topInvestor,
                lastTimePoint: block.timestamp,
                auctionEpoch: epoch
            });
        } else if (userInvested[name][epoch][user] == 0) {
            userList[name][epoch].push(user);
        }
    }

    function _checkStateHasOwner(
        address,
        string memory name
    )
        internal
        onlyWhenStateIs(name, BinderState.HasOwner)
    {
        if (block.timestamp - binders[name].lastTimePoint > HOLDING_PERIOD) {
            // The owner's holding period is over. Now waiting for the owner's renewal.
            binders[name].state = BinderState.WaitingForRenewal; // State: 3 -> 4
            binders[name].lastTimePoint = block.timestamp;
        }
    }

    function _checkStateWaitingForRenewal(
        address,
        string memory name
    )
        internal
        onlyWhenStateIs(name, BinderState.WaitingForRenewal)
    {
        if (block.timestamp - binders[name].lastTimePoint > RENEWAL_WINDOW) {
            // The renewal window is over. The binder is back to the NoOwner state.
            binders[name].state = BinderState.NoOwner; // State: 4 -> 1
            binders[name].owner = address(this);
        }
    }



    function buyShare(
        string memory name,
        uint256 shareNum
    )
        public
        whenStateIsNot(name, BinderState.NotRegistered)
        shareNumNotZero(shareNum)
    {
        // Init variables
        BinderState currentState = binders[name].state;
        address user = msg.sender;

        // TODO: Check signature

        // Transfer tokens
        uint totalCost = bindingSumExclusive(totalShare[name], totalShare[name] + shareNum);
        tokenAddress.transferFrom(user, address(this), totalCost);

        // Update storage (state of the binder)
        if (currentState == BinderState.NoOwner) {
            /* 
                Case 1: The behavior of this buyer invoke a new epoch of auction.
             */ 
            _checkStateNoOwner(user, name);
        } else if (currentState == BinderState.OnAuction) {
            /*
                Case 2: It's in the auction phase currently.
             */
            _checkStateOnAuction(user, name);
        } else if (currentState == BinderState.HasOwner) {
            /*
                Case 3: It's in the secure phase currently. The binder has an owner.
             */
            _checkStateHasOwner(user, name);
        } else if (currentState == BinderState.WaitingForRenewal) {
            /*
                Case 4: Waiting for the owner's renewal.
             */
            _checkStateWaitingForRenewal(user, name);
        }

        // Update storage (share and token amount)
        totalShare[name] += shareNum;
        userShare[name][user] += shareNum;
        userInvested[name][binders[name].auctionEpoch][user] += int(totalCost);
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
