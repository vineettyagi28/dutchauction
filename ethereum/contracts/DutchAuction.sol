pragma solidity ^ 0.4 .23;

import "./Z_ERC20.sol";
import "./F_SafeMath.sol";

contract DutchAuction {
    using SafeMath
    for uint256;
    // Auction Bid
    struct Bid {
        uint256 price;
        uint256 transfer;
        bool placed;
        bool claimed;
    }

    // Auction Stages
    enum Stages {
        AuctionDeployed,
        AuctionStarted,
        AuctionEnded,
        TokensDistributed
    }

    // Auction Ending Reasons
    enum Endings {
        Manual,
        TimeLimit,
        SoldOut,
        SoldOutBonus
    }

    // Auction Events
    event AuctionDeployed(uint256 indexed priceStart);
    event AuctionStarted(uint256 _startTime);
    event AuctionEnded(uint256 priceFinal, uint256 _endTime, Endings ending);
    event BidAccepted(address indexed _address, uint256 price, uint256 transfer);
    event BidPartiallyRefunded(address indexed _address, uint256 transfer);
    event FundsTransfered(address indexed _bidder, address indexed _wallet, uint256 amount);
    event TokensClaimed(address indexed _address, uint256 amount);
    event TokensDistributed();

    //intervals
    uint256 public intervals;

    //interval divider
    uint256 public interval_divider;

    // Token contract reference
    ERC20 public token;

    // Current stage
    Stages public current_stage;

    // `address` ⇒ `Bid` mapping
    mapping(address => Bid) public bids;

    // Auction owner address
    address public owner_address;

    // Wallet address
    address public wallet_address;

    // Starting price in wei
    uint256 public price_start;

    //Reserve price in wei
    uint256 public price_reserve;

    // Final price in wei
    uint256 public price_final;

    // Number of received wei
    uint256 public received_wei = 0;

    // Number of claimed wei
    uint256 public claimed_wei = 0;

    // Total number of token units for auction
    uint256 public initial_offering;

    // Auction start time
    uint256 public start_time;

    // Auction end time
    uint256 public end_time;

    // Time after the end of the auction, before anyone can claim tokens
    uint256 public claim_period;

    // Minimum bid amount
    uint256 public minimum_bid;

    // Stage modifier
    modifier atStage(Stages _stage) {
        require(current_stage == _stage);
        _;
    }

    // Owner modifier
    modifier isOwner() {
        require(msg.sender == owner_address);
        _;
    }

    constructor(
        uint256 _priceStart,
        uint256 _priceReserve,
        uint256 _minimumBid,
        uint256 _claimPeriod,
        address _walletAddress,
        uint256 _intervals,
        uint256 _intervalDivider
    ) public {
        // Set auction owner address
        owner_address = msg.sender;
        wallet_address = _walletAddress;

        // Set auction parameters
        price_start = _priceStart;
        price_reserve = _priceReserve;
        price_final = _priceStart;
        minimum_bid = _minimumBid;
        claim_period = _claimPeriod;
        intervals = _intervals;
        interval_divider = _intervalDivider;

        // Update auction stage and fire event
        current_stage = Stages.AuctionDeployed;
        emit AuctionDeployed(_priceStart);
    }

    // Default fallback function
    function() public payable atStage(Stages.AuctionStarted) {
        placeBidGeneric(msg.sender, msg.value);
    }

    // Setup auction
    function startAuction(address _tokenAddress, uint256 offering) external isOwner atStage(Stages.AuctionDeployed) {
        // Initialize external contract type
        token = ERC20(_tokenAddress);
        uint256 balance = token.balanceOf(owner_address);

        // Verify & Initialize starting parameters
        require(balance > offering); //TODO
        initial_offering = offering;

        // Update auction stage and fire event
        start_time = block.timestamp;
        current_stage = Stages.AuctionStarted;
        emit AuctionStarted(start_time);
    }

    // End auction
    function endAuction() external isOwner atStage(Stages.AuctionStarted) {
        endImmediately(price_final, Endings.Manual);
    }

    // Generic bid validation from ETH or BTC origin
    function placeBidGeneric(address sender, uint256 bidValue) private atStage(Stages.AuctionStarted) {

        // Input validation
        uint256 currentInterval = (block.timestamp.sub(start_time)).div(interval_divider);
        require(!bids[sender].placed && currentInterval < intervals && bidValue >= minimum_bid);

        // Check if value of received bids equals or exceeds the implied value of all tokens
        uint256 currentPrice = calcPrice(price_start, currentInterval);

        // current price should not be less than reserved price
        if (currentPrice < price_reserve) {
            currentPrice = price_reserve;
        }

        uint256 acceptableWei = (currentPrice.mul(initial_offering)).sub(received_wei);
        if (bidValue > acceptableWei) {
            // Place last bid with oversubscription bonus
            uint256 acceptedWei = currentPrice.add(acceptableWei);
            if (bidValue <= acceptedWei) {
                // Place bid with all available value
                placeBidInner(sender, currentPrice, bidValue);
            } else {
                // Place bid with available value
                placeBidInner(sender, currentPrice, acceptedWei);

                // Refund remaining value
                uint256 returnedWei = bidValue.sub(acceptedWei);
                sender.transfer(returnedWei);
                emit BidPartiallyRefunded(sender, returnedWei);
            }

            // End auction
            endImmediately(currentPrice, Endings.SoldOutBonus);
        } else if (bidValue == acceptableWei) {
            // Place last bid && end auction
            placeBidInner(sender, currentPrice, acceptableWei);
            endImmediately(currentPrice, Endings.SoldOut);
        } else {
            // Place bid and update last price
            placeBidInner(sender, currentPrice, bidValue);
        }
    }

    // Inner function for placing bid
    function placeBidInner(address sender, uint256 price, uint256 value) private atStage(Stages.AuctionStarted) {
        // Create bid
        Bid memory bid = Bid({
            price: price,
            transfer: value,
            placed: true,
            claimed: false
        });

        // Save and fire event
        bids[sender] = bid;
        emit BidAccepted(sender, price, value);

        // Update received wei and last price
        received_wei = received_wei.add(value);
        if (price < price_final) {
            price_final = price;
        }

        // Send bid amount to owner

        wallet_address.transfer(value);
        emit FundsTransfered(sender, wallet_address, value);

    }

    // Inner function for ending auction
    function endImmediately(uint256 atPrice, Endings ending) private atStage(Stages.AuctionStarted) {
        end_time = block.timestamp;
        price_final = atPrice;
        current_stage = Stages.AuctionEnded;
        emit AuctionEnded(price_final, end_time, ending);
    }

    // Claim tokens
    function claimTokens() external atStage(Stages.AuctionEnded) {
        // Input validation
        require(block.timestamp >= end_time.add(claim_period));
        require(bids[msg.sender].placed && !bids[msg.sender].claimed);

        // Calculate tokens to receive
        uint256 tokens = bids[msg.sender].transfer.div(price_final);
        uint256 auctionTokensBalance = token.balanceOf(owner_address);
        if (tokens > auctionTokensBalance) {
            // Unreachable code
            tokens = auctionTokensBalance;
        }

        // Transfer tokens and fire event
        token.transferFrom(owner_address, msg.sender, tokens);
        emit TokensClaimed(msg.sender, tokens);

        //Update the total amount of funds for which tokens have been claimed
        claimed_wei = claimed_wei + bids[msg.sender].transfer;
        bids[msg.sender].claimed = true;

        // Set new state if all tokens distributed
        if (claimed_wei >= received_wei) {
            current_stage = Stages.TokensDistributed;
            emit TokensDistributed();
        }
    }

    // Transfer unused tokens back to the wallet
    function transferBack() external isOwner atStage(Stages.TokensDistributed) {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0);
        token.transfer(wallet_address, balance);
    }

    // Returns intervals passed
    // Used for unit tests
    function getIntervals() public atStage(Stages.AuctionStarted) view returns(uint256) {
        return (block.timestamp.sub(start_time)).div(interval_divider);
    }

    // Returns current price
    // Used for unit tests
    function getPrice() public atStage(Stages.AuctionStarted) view returns(uint256) {
        uint256 currentInterval = getIntervals();
        if (currentInterval > intervals.sub(1)) {
            currentInterval = intervals.sub(1);
        }

        uint256 price = calcPrice(price_start, currentInterval);

        if (price < price_reserve) {
            price = price_reserve;
        }

        return price;
    }

    function calcPrice(uint256 priceStart, uint256 currentInterval) internal view returns(uint256) {
        return priceStart.sub(priceStart.sub(price_reserve).mul(currentInterval).div(intervals.sub(1)));
    }

    function getTokenBal(address accAddress) public view returns(uint) {
        return token.balanceOf(accAddress);
    }
}