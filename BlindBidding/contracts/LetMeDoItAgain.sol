pragma solidity ^0.8.4;

import "./ERC20Contract.sol";
import "./ERC721Contract.sol";

contract BlindAuction {
    struct Bid {
        bytes32 blindedBid;
        uint deposit;
    }

    ERC20Contract private _erc20; // Money that is going to be used while bidding
    ERC721Contract private _erc721; // Product for bidding

    address payable public owner; // the person who manages the bidding

    uint public fir_bidEnd;
    uint public fir_revealEnd;
    uint public sec_bidEnd;
    uint public sec_revealEnd;

    bool public ended;

    mapping(address => Bid[]) public bids;
    mapping(uint256 => uint256) private _tokenPrice;

    address public highestBidder;
    uint public highestBid;

    mapping(address => uint) pendingReturns;

    event AuctionEnded(address winner, uint highestBid);

    error TooEarly(uint time);
    error TooLate(uint time);
    error AuctionEndAlreadyCalled();

    modifier onlyBefore(uint time) {
        if (block.timestamp >= time) revert TooLate(time - block.timestamp);
        _;
    }
    modifier onlyAfter(uint time) {
        if (block.timestamp <= time) revert TooEarly(time - block.timestamp);
        _;
    }

    constructor(
        address erc20,
        address erc721, // set the token instance
        uint biddingTime,
        uint revealTime,
        address payable ownerAddress
    ) {
        _erc20 = ERC20Contract(erc20);
        _erc721 = ERC721Contract(erc721);
        owner = ownerAddress;
        fir_bidEnd = block.timestamp + biddingTime;
        fir_revealEnd = fir_bidEnd + revealTime;
        sec_bidEnd = fir_revealEnd + biddingTime;
        sec_revealEnd = sec_bidEnd + revealTime;

    }

    uint256 public minimumPrice;

    // biddingReady
    function enrollProduct(uint256 tokenId, uint256 price) public { // enroll the product and minimum price
        require( // check whether real owner calls the function
            _erc721.ownerOf(tokenId) == msg.sender, // msg.sender =  owner
            "Error: You are not the owner of this Product"
        );
        minimumPrice = price; // starting price
        ended = false; // reset in case of another auction
    }

    uint256 public reservedPrice = minimumPrice;

    // first bidding
    function first_bidding(uint256 suggestedprice) public onlyBefore(fir_bidEnd) {
        uint _balances = _erc20.balanceOf(msg.sender);
        require (minimumPrice <= suggestedprice, "Error: Suggested price is lower than the previous price"); // check whether the money is suggested more than the minimum
        require (_balances >= suggestedprice, "Error: You don't have enough money to pay"); // check whether price suggested is lower than the money in my wallet

        if (reservedPrice < suggestedprice) { // find out the most highest bid
            reservedPrice = suggestedprice;
        }
    }

    // first reveal
    function first_bidding_reveal()
        public
        view
        onlyAfter(fir_bidEnd)
        onlyBefore(fir_revealEnd)
        returns(uint) {
            return reservedPrice;
    }

    //second bidding
    function blind_a_bid(uint price, bytes32 secret) 
        public 
        pure 
        returns (bytes32){
        return keccak256(abi.encodePacked(price, secret));
    }

    function bid(bytes32 blindedBid, uint256 price)
        external
        payable
        onlyBefore(sec_bidEnd)
    {
        uint _balances = _erc20.balanceOf(msg.sender);
        require(_balances >= price, "Error: You don't have enough money to pay");
        bids[msg.sender].push(Bid({
            blindedBid: blindedBid, 
            deposit: price // price for check correct price is suggested later
        }));
    }

    function reveal(
        uint[] calldata prices,
        bytes32[] calldata secrets
    )
        external
        onlyAfter(sec_bidEnd)
        onlyBefore(sec_revealEnd)
    {
        uint length = bids[msg.sender].length;
        require(prices.length == length);
        require(secrets.length == length);

        for (uint i = 0; i < length; i++) {
            Bid storage bidToCheck = bids[msg.sender][i];
            (uint price, bytes32 secret) =
                    (prices[i], secrets[i]);
            if (bidToCheck.blindedBid != keccak256(abi.encodePacked(price, secret))) {
                "Error: Something went wrong"; // In case price does not match
            }
            if (bidToCheck.deposit >= price) {
                checkHighest(msg.sender, price); // check whether it is the highest price
            }
            bidToCheck.blindedBid = bytes32(0);
        }
    }

    function auctionEnd(uint256 tokenId)
        public
        onlyAfter(sec_revealEnd)
    {
        if (ended) revert AuctionEndAlreadyCalled();

        _tokenPrice[tokenId] = highestBid;
        address _owner = _erc721.ownerOf(tokenId);

        _erc20.transferFrom(highestBidder, _owner, _tokenPrice[tokenId]);  // erc20:  buyer-price -> seller 
        _erc721.transferFrom(_owner, highestBidder, tokenId); // erc721: seller-token -> buyer 

        emit AuctionEnded(highestBidder, highestBid); // emit event
        ended = true; // end the auction
    }

    function checkHighest(address bidder, uint price) internal returns (bool success) {
        if (price <= highestBid) {
            return false;
        }
        if (highestBidder != address(0)) {
            pendingReturns[highestBidder] += highestBid;
        }
        highestBid = price; // store the highest price
        highestBidder = bidder; // store the highest bidder's address
        return true;
    }
}
