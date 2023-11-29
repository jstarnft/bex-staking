// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BinderContract is OwnableUpgradeable, PausableUpgradeable {

    bool constant DISABLE_SIG_MODE = true;  // Just for debug. Will delete this later.

    /* ============================= Struct ============================= */
    enum BinderState {
        NotRegistered,
        NoOwner,
        OnAuction,
        HasOwner,
        WaitingForRenewal
    }

    struct BinderStorage {
        BinderState state;    // Current state of the binder
        address owner;        // Owner of the binder. Defaults to the contract address
        uint256 lastTimePoint;   // Timestamp of the last time-related event of this binder
        uint16 auctionEpoch;  // The epoch of the auction, add by 1 when a new auction starts
    }

    /* ============================ Variables =========================== */

    /* --------------- Time period -------------- */
    uint256 public constant AUCTION_DURATION = 2 days;
    uint256 public constant HOLDING_PERIOD = 90 days;
    uint256 public constant RENEWAL_WINDOW = 2 days;

    /* -------------- Token address ------------- */
    IERC20 public tokenAddress;

    /* ---------------- Signature --------------- */
    address public backendSigner;
    uint256 public SIGNATURE_VALID_TIME = 3 minutes;

    /* ------------------- Tax ------------------ */
    uint256 public taxBasePointProtocol;
    uint256 public taxBasePointOwner;
    uint256 public feeCollectedProtocol;
    mapping(string => uint256) public feeCollectedOwner;

    /* ----------------- Storage ---------------- */
    // binder => [storage for this binder]
    mapping(string => BinderStorage) public binders; // TODO: change to get() functions

    // binder => [total share num of this binder]
    mapping(string => uint256) public totalShare;

    // binder => user => [user's share num of this binder]
    mapping(string => mapping(address => uint256)) public userShare;

    // binder => epoch => [participated user list of this binder in this epoch]
    mapping(string => mapping(uint16 => address [])) public userList;

    // binder => epoch => user => [user's invested amount for this binder in this epoch]
    mapping(string => mapping(uint16 => mapping(address => int))) public userInvested; 


    /* =========================== Constructor ========================== */
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


    /* ============================= Events ============================= */
    // TODO: add events


    /* ============================= Errors ============================= */
    // TODO: add errors


    /* ============================ Modifiers =========================== */
    modifier shareNumNotZero(uint256 shareNum) {
        require(shareNum > 0, "Share num cannot be zero!");
        _;
    }

    modifier onlyBinderOwner(string memory name) {
        require(
            binders[name].owner == _msgSender(), 
            "Only the binder owner can call this function!"
        );
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


    /* ========================= View functions ========================= */
    function bindingFunction(uint256 x) public virtual pure returns (uint256) {
        return 10 * x * x;
    }

    function bindingSumExclusive(uint256 start, uint256 end) public virtual pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = start; i < end; i++) {
            sum += bindingFunction(i);
        }
        return sum;
    }

    function findTopInvestor(string memory name, uint16 epoch) public view returns (address) {
        address [] memory userListThis = userList[name][epoch];
        address topInvestor = userListThis[0];
        int topInvestedAmount = userInvested[name][epoch][topInvestor];
        for (uint256 i = 1; i < userListThis.length; i++) {
            address investor = userListThis[i];
            int amount = userInvested[name][epoch][investor];
            if (amount > topInvestedAmount) {   // If tied for the top, the first one wins.
                topInvestor = investor;
                topInvestedAmount = amount;
            }
        }
        return topInvestor;
    }

    function checkSignature(
        bytes4 selector,
        string memory name,
        uint256 content,    // Share amount or token amount or `0`.
        address user,
        uint256 timestamp,
        bytes memory signature
    ) public view {
        bytes memory data = abi.encodePacked(
            selector,
            name,
            content,
            user,
            timestamp
        );
        bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(data);
        address signer = ECDSA.recover(signedMessageHash, signature);
        
        require(
            block.timestamp - timestamp <= SIGNATURE_VALID_TIME,
            "Signature expired!"
        );

        require(
            block.timestamp > timestamp,
            "Invalid timestamp! Check the backend."
        );

        require(
            signer == backendSigner || DISABLE_SIG_MODE, // Just for debug. Will delete this later.
            "Not the correct signer or invalid signature!"
        );
    }

    /* ========================= Write functions ======================== */

    /* --------- Internal state transfer -------- */
    function _countdownTriggerOnAuction(string memory name)
        internal
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

    function _stateTransitionToAuction(string memory name) internal {
        uint16 epoch = binders[name].auctionEpoch;
        binders[name] = BinderStorage({
            state: BinderState.OnAuction,       // State: 1 -> 2
            owner: address(this),
            lastTimePoint: block.timestamp,
            auctionEpoch: epoch + 1             // Only place to add 1 to the epoch
        });
    }

    function _stateTransitionWhenRenewed(string memory name) internal {
        binders[name].state = BinderState.HasOwner;    // State: 4 -> 3
        binders[name].lastTimePoint = block.timestamp;
    }

    function _userListManage(string memory name, uint16 epoch, address user) internal {
        if (binders[name].state == BinderState.OnAuction && userInvested[name][epoch][user] == 0) {
            userList[name][epoch].push(user);
        }
    }

    /* --------------- Register & Buy & Sell --------------- */
    function register(
        string memory name,
        uint256 timestamp,
        bytes memory signature
    )
        public
        onlyWhenStateIs(name, BinderState.NotRegistered)
    {
        // Check signature
        checkSignature(
            this.register.selector, name, 0,
            _msgSender(), timestamp, signature
        );

        // Register the binder
        binders[name].state = BinderState.NoOwner;
    }

    function buyShare(
        string memory name,
        uint256 shareNum,
        uint256 timestamp,
        bytes memory signature
    )
        public
        whenStateIsNot(name, BinderState.NotRegistered)
        shareNumNotZero(shareNum)
        returns (bool stateChanged)
    {
        // Check signature
        address user = _msgSender();
        checkSignature(
            this.buyShare.selector, name, shareNum,
            user, timestamp, signature
        );

        // Transfer tokens to contract
        uint256 totalCost = bindingSumExclusive(totalShare[name], totalShare[name] + shareNum);
        tokenAddress.transferFrom(user, address(this), totalCost);

        // Update storage (state transfer)
        if (binders[name].state == BinderState.NoOwner) {
            _stateTransitionToAuction(name);
            stateChanged = true;
        } else {
            stateChanged = _countdownTrigger(name);
        }
        _userListManage(name, binders[name].auctionEpoch, user);

        // Update storage (share and token amount)
        totalShare[name] += shareNum;
        userShare[name][user] += shareNum;
        userInvested[name][binders[name].auctionEpoch][user] += int(totalCost);
    }

    function sellShare(
        string memory name,
        uint256 shareNum,
        uint256 timestamp,
        bytes memory signature
    )
        public
        whenStateIsNot(name, BinderState.NotRegistered)
        shareNumNotZero(shareNum)
        returns (bool stateChanged)
    {
        // Check signature
        address user = _msgSender();
        checkSignature(
            this.sellShare.selector, name, shareNum,
            user, timestamp, signature
        );

        // Update storage (state transfer)
        if (binders[name].state == BinderState.NoOwner) {
            stateChanged = true;
        } else {
            stateChanged = _countdownTrigger(name);
        }
        _userListManage(name, binders[name].auctionEpoch, user);

        // Calculate and update fees
        uint256 totalReward = bindingSumExclusive(totalShare[name] - shareNum, totalShare[name]);
        uint256 feeForProtocol = totalReward * taxBasePointProtocol / 10000;
        uint256 feeForOwner = totalReward * taxBasePointOwner / 10000;
        feeCollectedProtocol += feeForProtocol;
        feeCollectedOwner[name] += feeForOwner;

        // Update storage (share and token amount)
        totalShare[name] -= shareNum;
        userShare[name][user] -= shareNum;
        userInvested[name][binders[name].auctionEpoch][user] -= int(totalReward);
        
        // Transfer tokens to user
        uint256 actualReward = totalReward - feeForProtocol - feeForOwner;
        tokenAddress.transfer(user, actualReward);
    }

    /* ------------ For binder owner ------------ */
    function renewOwnership(
        string memory name,
        uint256 tokenAmount,
        uint256 timestamp,
        bytes memory signature
    )
        public
        onlyBinderOwner(name)
        onlyWhenStateIs(name, BinderState.WaitingForRenewal)
    {
        // Check signature
        checkSignature(
            this.renewOwnership.selector, name, tokenAmount,
            _msgSender(), timestamp, signature
        );

        // Transfer tokens to contract
        tokenAddress.transferFrom(_msgSender(), address(this), tokenAmount);

        // Update storage (state transfer)
        _stateTransitionWhenRenewed(name);

        // Update storage (share and token amount)
        feeCollectedProtocol += tokenAmount;
    }

    function collectFeeForOwner(string memory name)
        public
        onlyBinderOwner(name)
        whenStateIsNot(name, BinderState.NotRegistered)
    {
        uint256 fee = feeCollectedOwner[name];
        feeCollectedOwner[name] = 0;
        tokenAddress.transfer(_msgSender(), fee);
    }

    /* ---------------- For admin --------------- */
    function collectFeeForProtocol()
        public
        onlyOwner
    {
        uint256 fee = feeCollectedProtocol;
        feeCollectedProtocol = 0;
        tokenAddress.transfer(_msgSender(), fee);
    }

}
