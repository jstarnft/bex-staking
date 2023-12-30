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
        BinderState state;          // Current state of the binder
        address owner;              // Owner of the binder. Defaults to the contract address
        uint256 lastTimePoint;      // Timestamp of the last time-related event of this binder
        uint16 auctionEpoch;        // The epoch of the auction, add by 1 when a new auction starts
    }


    /* ============================ Variables =========================== */

    /* --------------- Time period -------------- */
    uint256 constant AUCTION_DURATION = 2 days;
    uint256 constant HOLDING_PERIOD = 90 days;
    uint256 constant RENEWAL_WINDOW = 2 days;

    /* ------------ Super parameters ------------ */
    IERC20 public tokenAddress;
    address public backendSigner;
    uint256 public signatureValidTime;
    uint256 public taxBasePointProtocol;
    uint256 public taxBasePointOwner;

    /* ----------------- Storage ---------------- */
    // Total fee collected for the protocol
    uint256 public feeCollectedProtocol;

    // binder => [fee collected for this binder's owner]
    mapping(string => uint256) public feeCollectedBinder;

    // binder => [storage for this binder]
    mapping(string => BinderStorage) binders;

    // binder => [total share num of this binder]
    mapping(string => uint256) public totalShare;

    // binder => user => [user's share num of this binder]
    mapping(string => mapping(address => uint256)) public userShare;

    // binder => epoch => [participated user list of this binder in this epoch]
    mapping(string => mapping(uint16 => address [])) userList;

    // binder => epoch => user => [user's invested amount for this binder in this epoch]
    mapping(string => mapping(uint16 => mapping(address => int))) userInvested;

    // keccak256(signature) => [whether this signature is used]
    mapping(bytes32 => bool) public signatureIsUsed;


    /* ============================= Events ============================= */

    /* ------------- State transfer ------------- */
    event BinderRegistered(string name, address indexed registerAddress);
    event AuctionStarted(string name, uint16 indexed epoch);
    event AuctionEnded(string name, uint16 indexed epoch, address indexed newOwner);
    event StartWaitingForRenewal(string name);
    event OwnershipRenewed(string name, address indexed owner);
    event OwnershipTransferred(string name, address indexed oldOwner, address indexed newOwner);

    /* ------------- User's behavior ------------ */
    event BuyShare(
        string name, address indexed user, uint256 shareNum, uint256 spentToken, uint256 nextId
    );
    event SellShare(
        string name, address indexed user, uint256 shareNum, uint256 receivedToken, uint256 nextId, uint256 feeForOwner, uint256 feeForProtocol
    );
    event CollectFeeForOwner(string name, address indexed binderOwner, uint256 tokenAmount);

    /* ------------- Admin's behavior ----------- */
    event CollectFeeForProtocol(address indexed admin, uint256 tokenAmount);
    event UpdatedackendSigner(address indexed oldSigner, address indexed newSigner);
    event UpdatedSignatureValidTime(uint256 oldTime, uint256 newTime);
    event UpdatedTaxBasePointProtocol(uint256 oldTax, uint256 newTax);
    event UpdatedTaxBasePointOwner(uint256 oldTax, uint256 newTax);


    /* ============================= Errors ============================= */
    error NotBinderOwner();
    error ShareNumCannotBeZero();
    error BinderNotRegistered();
    error BinderNotInExpectedState(BinderState state);
    error SignatureExpired();
    error SignatureInvalid();
    error SignatureAlreadyUsed();
    error TimestampError();
    error TotalCostMoreThanExpected();
    error TotalRewardLessThanExpected();


    /* ============================ Modifiers =========================== */
    modifier onlyBinderOwner(string memory name) {
        if (_msgSender() != binders[name].owner) {
            revert NotBinderOwner();
        }
        _;
    }

    modifier shareNumNotZero(uint256 shareNum) {
        if (shareNum == 0) {
            revert ShareNumCannotBeZero();
        }
        _;
    }

    modifier binderIsRegistered(string memory name) {
        if (binders[name].state == BinderState.NotRegistered) {
            revert BinderNotRegistered();
        }
        _;
    }

    modifier onlyWhenStateIs(string memory name, BinderState expectedState) {
        if (binders[name].state != expectedState) {
            revert BinderNotInExpectedState(expectedState);
        }
        _;
    }


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

        // Init signature valid time
        signatureValidTime = 3 minutes;
    }


    /* ===================== Pure functions ==================== */
    function getAutcionDuration() public virtual pure returns (uint256) {
        return AUCTION_DURATION;      // For convinience of overrided in test contract
    }

    function getHoldingPeriod() public virtual pure returns (uint256) {
        return HOLDING_PERIOD;
    }

    function getRenewalWindow() public virtual pure returns (uint256) {
        return RENEWAL_WINDOW;
    }

    function bindingFunction(uint256 x) public virtual pure returns (uint256) {
        return 10 * x * x;
    }

    function bindingSumExclusive(uint256 start, uint256 end) 
        public virtual pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = start; i < end; i++) {
            sum += bindingFunction(i);
        }
        return sum;
    }


    /* ========================= View functions ========================= */
    function getBinderState(string memory name) public view returns (BinderState) {
        return binders[name].state;
    }

    function getBinderOwner(string memory name) public view returns (address) {
        return binders[name].owner;
    }

    function getBinderLastTimePoint(string memory name) public view returns (uint256) {
        return binders[name].lastTimePoint;
    }

    function getBinderLeftTime(string memory name) public view returns (uint256) {
        BinderState currentState = binders[name].state;

        if (currentState == BinderState.NotRegistered 
            || currentState == BinderState.NoOwner) return 0;
        
        uint256 passedTime = block.timestamp - binders[name].lastTimePoint;
        
        if (currentState == BinderState.OnAuction) 
            return getAutcionDuration() > passedTime ? getAutcionDuration() - passedTime : 0;
        
        else if (currentState == BinderState.HasOwner)
            return getHoldingPeriod() > passedTime ? getHoldingPeriod() - passedTime : 0;
        
        else
            return getRenewalWindow() > passedTime ? getRenewalWindow() - passedTime : 0;
    }

    function getBinderAuctionEpoch(string memory name) public view returns (uint16) {
        return binders[name].auctionEpoch;
    }

    function getUserInvestedAmount(string memory name, address user) public view returns (int) {
        return userInvested[name][binders[name].auctionEpoch][user];
    }

    function getUserHistoryInvestedAmount(
        string memory name, address user, uint16 epoch
    ) public view returns (int) {
        return userInvested[name][epoch][user];
    }

    function getCurrentInvestedUsers(string memory name) public view returns (address [] memory) {
        return userList[name][binders[name].auctionEpoch];
    }

    function findCurrentTopInvestor(string memory name) public view returns (address) {
        return findTopInvestor(name, binders[name].auctionEpoch);
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


    /* ========================= Write functions ======================== */

    /* --------- Internal state transfer -------- */
    function _countdownTriggerOnAuction(string memory name)
        internal
        returns (bool stateChanged)
    {
        uint16 epoch = binders[name].auctionEpoch;

        if (block.timestamp - binders[name].lastTimePoint > getAutcionDuration()) {
            // The auction is over. The binder has an owner now.
            address topInvestor = findTopInvestor(name, epoch);
            binders[name] = BinderStorage({
                state: BinderState.HasOwner,    // State: 2 -> 3
                owner: topInvestor,
                lastTimePoint: block.timestamp,
                auctionEpoch: epoch
            });
            stateChanged = true;
            emit AuctionEnded(name, epoch, topInvestor);
            emit OwnershipTransferred(name, address(0), topInvestor);
        } else {
            stateChanged = false;
        }
    }

    function _countdownTriggerHasOwner(string memory name)
        internal
        returns (bool stateChanged)
    {
        if (block.timestamp - binders[name].lastTimePoint > getHoldingPeriod()) {
            // The owner's holding period is over. Now waiting for the owner's renewal.
            binders[name].state = BinderState.WaitingForRenewal;    // State: 3 -> 4
            binders[name].lastTimePoint = block.timestamp;
            stateChanged = true;
            emit StartWaitingForRenewal(name);
        } else {
            stateChanged = false;
        }
    }

    function _countdownTriggerWaitingForRenewal(string memory name)
        internal
        returns (bool stateChanged)
    {
        if (block.timestamp - binders[name].lastTimePoint > getRenewalWindow()) {
            // The renewal window is over. The binder is back to the NoOwner state.
            address oldOwner = binders[name].owner;
            binders[name].state = BinderState.NoOwner;              // State: 4 -> 1
            binders[name].owner = address(0);
            stateChanged = true;
            emit OwnershipTransferred(name, oldOwner, address(0));
        } else {
            stateChanged = false;
        }
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
            owner: address(0),
            lastTimePoint: block.timestamp,
            auctionEpoch: epoch + 1             // Only place to add 1 to the epoch
        });
        emit AuctionStarted(name, epoch + 1);
    }

    function _stateTransitionWhenRenewed(string memory name) internal {
        binders[name].state = BinderState.HasOwner;    // State: 4 -> 3
        binders[name].lastTimePoint = block.timestamp;
        emit OwnershipRenewed(name, binders[name].owner);
    }

    function _userListManage(string memory name, uint16 epoch, address user) internal {
        if (binders[name].state == BinderState.OnAuction && userInvested[name][epoch][user] == 0)
            userList[name][epoch].push(user);
    }

    /* ---------------- Signature --------------- */
    function consumeSignature(
        bytes4 selector,
        string memory name,
        uint256 content,    // Share amount or token amount or `0`.
        address user,
        uint256 timestamp,
        bytes memory signature
    ) public {
        // Prevent replay attack
        bytes32 sigHash = keccak256(signature);
        if (signatureIsUsed[sigHash]) 
            revert SignatureAlreadyUsed();
        signatureIsUsed[sigHash] = true;

        // Check the signature timestamp
        if (block.timestamp - timestamp > signatureValidTime)
            revert SignatureExpired();
        if (block.timestamp < timestamp)
            revert TimestampError();

        // Check the signature content
        bytes memory data = abi.encodePacked(
            selector,
            name,
            content,
            user,
            timestamp
        );
        bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(data);
        address signer = ECDSA.recover(signedMessageHash, signature);
        if (signer != backendSigner)
            if (!DISABLE_SIG_MODE)  // Just for debug. Will delete this later.
                revert SignatureInvalid();
    }

    /* ---------- Register & Buy & Sell --------- */
    function register(
        string memory name,
        uint256 timestamp,
        bytes memory signature
    )
        public
        onlyWhenStateIs(name, BinderState.NotRegistered)
    {
        // Check signature
        consumeSignature(
            this.register.selector, name, 0,
            _msgSender(), timestamp, signature
        );

        // Register the binder
        binders[name].state = BinderState.NoOwner;
        emit BinderRegistered(name, _msgSender());
    }

    function buyShare(
        string memory name,
        uint256 shareNum,
        uint256 timestamp,
        uint256 maxOutTokenAmount,
        bytes memory signature
    )
        public
        binderIsRegistered(name)
        shareNumNotZero(shareNum)
        returns (bool stateChanged)
    {
        // Check signature
        address user = _msgSender();
        consumeSignature(
            this.buyShare.selector, name, shareNum,
            user, timestamp, signature
        );

        // Transfer tokens to contract
        uint256 totalCost = bindingSumExclusive(totalShare[name], totalShare[name] + shareNum);
        if (totalCost > maxOutTokenAmount) 
            revert TotalCostMoreThanExpected();
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
        uint256 nextId = totalShare[name];
        emit BuyShare(name, user, shareNum, totalCost, nextId);
    }

    function sellShare(
        string memory name,
        uint256 shareNum,
        uint256 timestamp,
        uint256 minInTokenAmount,
        bytes memory signature
    )
        public
        binderIsRegistered(name)
        shareNumNotZero(shareNum)
        returns (bool stateChanged)
    {
        // Check signature
        address user = _msgSender();
        consumeSignature(
            this.sellShare.selector, name, shareNum,
            user, timestamp, signature
        );

        // Update storage (state transfer)
        if (binders[name].state == BinderState.NoOwner) {
            stateChanged = false;
        } else {
            stateChanged = _countdownTrigger(name);
        }
        uint16 epoch = binders[name].auctionEpoch;  // Prevent `stack too deep` error
        _userListManage(name, epoch, user);

        // Calculate and update fees
        uint256 totalReward = bindingSumExclusive(totalShare[name] - shareNum, totalShare[name]);
        if (totalReward < minInTokenAmount) 
            revert TotalRewardLessThanExpected();
        uint256 feeForProtocol = totalReward * taxBasePointProtocol / 10000;
        uint256 feeForOwner = totalReward * taxBasePointOwner / 10000;
        feeCollectedProtocol += feeForProtocol;
        feeCollectedBinder[name] += feeForOwner;

        // Update storage (share and token amount)
        totalShare[name] -= shareNum;
        userShare[name][user] -= shareNum;
        userInvested[name][epoch][user] -= int(totalReward);
        
        // Transfer tokens to user
        uint256 actualReward = totalReward - feeForProtocol - feeForOwner;
        tokenAddress.transfer(user, actualReward);
        uint256 nextId = totalShare[name];
        emit SellShare(name, user, shareNum, totalReward, nextId, feeForOwner, feeForProtocol);
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
        // Check if the renewal window is over
        if (block.timestamp - binders[name].lastTimePoint > getRenewalWindow())
            revert("Renewal window is over!");

        // Check signature
        consumeSignature(
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

    function transferBinderOwnership(   
        string memory name,
        address newOwner
    )   // There's a `transferOwnership` function in `OwnableUpgradeable`!
        public
        onlyBinderOwner(name)
        onlyWhenStateIs(name, BinderState.HasOwner)
    {
        binders[name].owner = newOwner;
        emit OwnershipTransferred(name, _msgSender(), newOwner);
    }

    function collectFeeForOwner(string memory name)
        public
        onlyBinderOwner(name)
        binderIsRegistered(name)
    {
        uint256 fee = feeCollectedBinder[name];
        feeCollectedBinder[name] = 0;
        tokenAddress.transfer(_msgSender(), fee);
        emit CollectFeeForOwner(name, _msgSender(), fee);
    }

    function collectFeeForOwnerBatch(string [] memory names)
        public
    {
        for (uint256 i = 0; i < names.length; i++) {
            collectFeeForOwner(names[i]);
        }
    }

    /* ---------------- For admin --------------- */
    function collectFeeForProtocol() public onlyOwner {
        uint256 fee = feeCollectedProtocol;
        feeCollectedProtocol = 0;
        tokenAddress.transfer(_msgSender(), fee);
        emit CollectFeeForProtocol(_msgSender(), fee);
    }

    function setBackendSigner(address backendSigner_) public onlyOwner {
        emit UpdatedackendSigner(backendSigner, backendSigner_);
        backendSigner = backendSigner_;
    }

    function setSignatureValidTime(uint256 signatureValidTime_) public onlyOwner {
        emit UpdatedSignatureValidTime(signatureValidTime, signatureValidTime_);
        signatureValidTime = signatureValidTime_;
    }

    function setTaxBasePointProtocol(uint256 taxBasePointProtocol_) public onlyOwner {
        emit UpdatedTaxBasePointProtocol(taxBasePointProtocol, taxBasePointProtocol_);
        taxBasePointProtocol = taxBasePointProtocol_;
    }

    function setTaxBasePointOwner(uint256 taxBasePointOwner_) public onlyOwner {
        emit UpdatedTaxBasePointOwner(taxBasePointOwner, taxBasePointOwner_);
        taxBasePointOwner = taxBasePointOwner_;
    }

}
