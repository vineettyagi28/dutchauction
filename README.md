# DutchAuction
A basic implementation of Dutch auction is given in DutchAuction.sol. This smart contract can be used for the sales of any ERC20 token by providing the token address while starting an auction.
Dutch auction ensures that every bidder gets the same price. Dutch auction contract constructor takes the start price, reserve price, time after which tokens can be claimed, minimum bid, address (to which unused token can be sent), number of intervals and time between two intervals.
To start an aunction, owner of the auction contract must provide the token address and number of tokens to be auctioned
A bidder can simply send the ethers to the auction contract to bid.
