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

    struct BinderStorage {
        BinderState state;
        address owner;  // Owner of the binder. Default to the contract address. (TODO: confirm this)
        // address userInvestedMost; // The user who has invested the most to this binder, in this epoch.
        // int userInvestedAmountMax; // The amount of token which this user has invested, in this epoch.
        uint lastTimePoint;
        uint totalShare;
        uint16 auctionEpoch; // The epoch of the auction. Add 1 only when auction starts again.
    }

    struct UserBinderStorage {
        uint userShare;
        int investedAmount; // The amount of token that a user has invested to this binder, in this epoch.
        uint16 investedEpoch; // Add 1 only when a user invests again in a new auction epoch.
    }

    /* ================ Variables ================ */
    /* ------ Admin & token & basic ------ */
    IERC20 public tokenAddress;

    /* ------ Signature ------ */
    address public backendSigner;
    uint256 public SIGNATURE_VALID_TIME = 3 minutes;
    // uint256 immutable SIGNATURE_SALT;

    /* ------ States ------ */
    uint256 public constant AUCTION_DURATION = 2 days;
    uint256 public constant RENEWAL_PERIOD = 90 days;
    uint256 public constant RENEWAL_WINDOW = 2 days;

    /* ------ Tax ------ */
    uint256 public taxBasePointProtocol;
    uint256 public taxBasePointOwner;

    /* ------ Storage ------ */
    mapping(string => BinderStorage) public binders; // TODO: change to get() functions
    mapping(string => mapping(address => UserBinderStorage)) public users;
    mapping(string => address []) public participantList;

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

    function findTopInvestor(string memory name) public view returns (address) {
        address topInvestor = participantList[name][0];
        int topInvestedAmount = users[name][topInvestor].investedAmount;
        for (uint i = 1; i < participantList[name].length; i++) {
            address investor = participantList[name][i];
            int amount = users[name][investor].investedAmount;
            if (amount > topInvestedAmount) {
                topInvestor = investor;
                topInvestedAmount = amount;
            }
        }
        return topInvestor;
    }

    /* ================ Write functions ================ */
    /* ------ S0: NotRegistered ------ */
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

    /* ------ S1~S4: Can buy/sell ------ */
    function _stateChangingBuyNoOwner(
        address user,
        string memory name,
        uint256 shareNum
    )
        internal
        shareNumNotZero(shareNum) // TODO: delete this when main function is done
        onlyWhenStateIs(name, BinderState.NoOwner)
    {   
        BinderStorage memory currentBinder = binders[name];
        UserBinderStorage memory currentUser = users[name][user];

        binders[name] = BinderStorage({
            state: BinderState.OnAuction, // State: 1 -> 2
            owner: address(this),
            lastTimePoint: block.timestamp,
            totalShare: currentBinder.totalShare + shareNum,
            auctionEpoch: currentBinder.auctionEpoch + 1
        });

        users[name][user] = UserBinderStorage({
            userShare: currentUser.userShare + shareNum,
            investedAmount: 0,
            investedEpoch: currentBinder.auctionEpoch + 1
        });

        participantList[name] = [user];
    }

    function _stateChangeingBuyOnAuction(
        address user,
        string memory name,
        uint256 shareNum
    )
        internal
        shareNumNotZero(shareNum)
        onlyWhenStateIs(name, BinderState.OnAuction)
    {
        BinderStorage memory currentBinder = binders[name];
        UserBinderStorage memory currentUser = users[name][user];

        // if (currentUser.investedEpoch != currentBinder.auctionEpoch) {
        //     users[name][user] = UserBinderStorage({
        //         userShare: currentUser.userShare + shareNum,
        //         investedAmount: 0, // TODO: Add the invested amount outside
        //         investedEpoch: currentBinder.auctionEpoch   // Synchrnoize the epoch
        //     });
        // } else {
        //     users[name][user].userShare += shareNum;
        // }

        if (block.timestamp - currentBinder.lastTimePoint > AUCTION_DURATION) {
            // The auction is over!
            address topInvestor = findTopInvestor(name);
            binders[name] = BinderStorage({
                state: BinderState.HasOwner, // State: 2 -> 3
                owner: topInvestor,
                lastTimePoint: block.timestamp,
                totalShare: currentBinder.totalShare + shareNum,
                auctionEpoch: currentBinder.auctionEpoch
            });

            // No longer need to update the user invested amount
        } else {

        }



        // binders[name] = BinderStorage({
        //     state: BinderState.OnAuction, // State: 2 -> 2
        //     owner: address(this),
        //     lastTimePoint: block.timestamp,
        //     totalShare: currentBinder.totalShare + shareNum,
        //     auctionEpoch: currentBinder.auctionEpoch
        // });

        // users[name][user] = UserBinderStorage({
        //     userShare: currentUser.userShare + shareNum,
        //     investedAmount: currentUser.investedAmount,
        //     investedEpoch: currentBinder.auctionEpoch
        // });

        // participantList[name].push(user);
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
        address user = msg.sender;
        BinderStorage memory currentBinder = binders[name];
        // UserBinderStorage memory currentUserStorage = users[name][user];

        // TODO: Check signature

        // Transfer tokens
        uint totalCost = bindingSumExclusive(
            binders[name].totalShare, 
            binders[name].totalShare + shareNum
        );
        tokenAddress.transferFrom(msg.sender, address(this), totalCost);

        // BinderState state;
        // address owner;  // Owner of the binder. Default to the contract address. (TODO: confirm this)
        // uint lastTimePoint;
        // uint totalShare;
        // uint16 auctionEpoch; // The epoch of the auction. Add 1 only when auction starts again.

        // int investedAmount; // The amount of token that a user has invested to this binder, in this epoch.
        // uint userShare;
        // uint16 investedEpoch; // Add 1 only when a user invests again in a new auction epoch.

        // Case 1: The behavior of this buyer invoke a new epoch of auction... 
        if (currentBinder.state == BinderState.NoOwner) {
            users[name][user].investedAmount = 0;   // Reset the invested amount
            users[name][user].investedEpoch = currentBinder.auctionEpoch + 1;

            binders[name] = BinderStorage({
                state: BinderState.OnAuction,
                owner: address(this),
                lastTimePoint: block.timestamp,
                totalShare: currentBinder.totalShare + shareNum,
                auctionEpoch: currentBinder.auctionEpoch + 1
            });
        } 
        
        // Case 2: It's in the auction phase currently...
        else if (currentBinder.state == BinderState.OnAuction) {
            if (users[name][user].investedEpoch != binders[name].auctionEpoch) {
                users[name][user].investedAmount = 0;
                users[name][user].investedEpoch = binders[name].auctionEpoch;   // Synchrnoize the epoch
            } else {
                // Do nothing. Delete this.
            }

            if (block.timestamp - currentBinder.lastTimePoint > AUCTION_DURATION) {
                // The auction is over!
                // binders[name] = BinderStorage({
                //     state: BinderState.HasOwner,
                //     owner: address(this),
                //     // lastTimePoint: block.timestamp,
                //     // totalShare: currentBinder.totalShare + shareNum,
                //     // userInvestedAmountMax: int(totalCost),
                //     // auctionEpoch: currentBinder.auctionEpoch
                // });
            } else {
                // ...
            }




            
            // binders[name].totalShare += shareNum;
            // binders[name].userInvestedAmountMax += int(totalCost);
        } else if (currentBinder.state == BinderState.HasOwner) {
            // binders[name].totalShare += shareNum;
            // binders[name].userInvestedAmountMax += int(totalCost);
        } else if (currentBinder.state == BinderState.WaitingForRenewal) {
            // binders[name].currentState = BinderState.OnAuction;
            // binders[name].lastTimePoint = block.timestamp;
            // binders[name].totalShare = shareNum;
            // binders[name].userInvestedAmountMax = int(totalCost);
            // binders[name].auctionEpoch += 1;
        } else {
            revert("Invalid state!");
        }

        // Whatever is the case, some fields should be updated
        users[name][user].userShare += shareNum;
        users[name][user].investedAmount += int(totalCost);


    }



    // function sellShare

    // function claimFee




    /* ------ S4: WaitingForRenewal ------ */
    // function renewOwnership

    // function register() public {
    //     require(currentState == State.NotRegistered, "Binder already registered");
    //     currentState = State.NoOwner;
    //     lastInteraction = block.timestamp;
    //     emit Registered();
    // }

    // function buyShare() public payable {
    //     require(currentState == State.NoOwner, "Cannot buy share, Binder has owner");
    //     owner = msg.sender;
    //     currentState = State.HasOwner;
    //     lastInteraction = block.timestamp;
    //     emit OwnershipTransferred(address(0), msg.sender);
    // }

    // function startAuction() public onlyOwner {
    //     require(block.timestamp - lastInteraction >= RENEWAL_PERIOD, "Cannot start auction yet");
    //     currentState = State.OnAuction;
    //     lastInteraction = block.timestamp;
    //     emit AuctionStarted();
    // }

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

    // // Check the state of the Binder based on the last interaction
    // function checkState() public {
    //     if (currentState == State.HasOwner && block.timestamp - lastInteraction >= RENEWAL_PERIOD) {
    //         currentState = State.WaitingForRenewal;
    //     } else if (currentState == State.WaitingForRenewal && block.timestamp - lastInteraction >= RENEWAL_WINDOW) {
    //         currentState = State.NoOwner;
    //         owner = address(0);
    //     }
    // }
}
