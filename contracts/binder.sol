// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract BinderContract {
    /* ================ Struct ================ */
    enum BinderState {
        NotRegistered,
        NoOwner,
        OnAuction,
        HasOwner,
        WaitingForRenewal
    }

    struct BinderStorage {
        BinderState currentState;
        address owner;
        uint256 lastInteractionTime;
    }

    /* ================ Variables ================ */
    /* ------ Admin & token & basic ------ */
    address public owner;
    IERC20 public tokenAddress;

    /* ------ Signature ------ */
    address public backendSigner;
    uint256 public SIGNATURE_VALID_TIME = 3 minutes;
    // uint256 immutable SIGNATURE_SALT;

    /* ------ State transfer ------ */
    uint256 public constant AUCTION_DURATION = 2 days;
    uint256 public constant RENEWAL_PERIOD = 90 days;
    uint256 public constant RENEWAL_WINDOW = 2 days;

    /* ------ Storage ------ */
    mapping(string => BinderStorage) public binderStorage; // TODO: change to get() functions
    mapping(string => uint256) public totalShareOf;
    mapping(string => mapping(address => uint256)) public userShareOf;
    mapping(string => mapping(address => uint256)) public userInvestedAmount;
    mapping(string => uint256) public userInvestedAmountMax;

    // TODO: change to `initialize`
    
    constructor(address tokenAddress_, address backendSigner_) {
        tokenAddress = IERC20(tokenAddress_);
        backendSigner = backendSigner_;
        // owner = address(0);
        // currentState = State.NotRegistered;
    }

    /* ================ Events ================ */
    // TODO: add events

    /* ================ Errors ================ */
    // TODO: add errors

    /* ================ Modifiers ================ */
    modifier onlyWhenStateIs(string memory binderName, BinderState state) {
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
        require(
            binderStorage[binderName].currentState == state,
            errorMessage
        );
        _;
    }

    modifier whenStateIsNot(string memory binderName, BinderState state) {
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
        require(
            binderStorage[binderName].currentState != state,
            errorMessage
        );
        _;
    }

    /* ================ View functions ================ */
    function bindingFunction(uint x) public pure returns (uint) {
        return 10 * x * x;
    }

    /* ================ Write functions ================ */
    /* ------ S0: NotRegistered ------ */
    function register(
        string memory binderName
        // bytes memory signature

    ) public onlyWhenStateIs(binderName, BinderState.NotRegistered) {
        binderStorage[binderName].currentState = BinderState.NoOwner;
    }

    /* ------ S1~S4: Can buy/sell ------ */
    // function buyShare
    // function sellShare

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
