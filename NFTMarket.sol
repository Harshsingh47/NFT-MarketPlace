// SPDX-License-Identifier:MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./NFT.sol";

/*  NFT Marketplace
    List NFT, 
    Buy NFT, 
    Offer NFT, 
    Accept offer, 
    Create auction, 
    Bid place,
    & service fee
*/

contract NFTMarketplace is Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _itemIds;

    address private feeRecipient;
    uint256 marketplaceServiceFee = 1;

    struct ItemStruct {
        uint256 itemId;
        string tokenURI;
        uint256 tokenId;
        address nftAddress;
        uint256 price;
        address payable seller;
        address payable owner;
        string category;
        string genre;
        bool sold;
        address createdBy;
        uint256 updatedAt;
        uint256 createdAt;
    }

    struct ListStruct {
        uint256 itemId;
        uint256 price;
        bool completed;
        address updatedBy;
        address createdBy;
        uint256 updatedAt;
        uint256 createdAt;
    }

    struct UserOfferStruct {
        uint256 itemId;
        address offerer;
        uint256 offerPrice;
        uint256 offerFrom;
        uint256 offerTo;
        uint256 createdAt;
    }

    struct OfferStruct {
        uint256 itemId;
        bool accepted;
        address createdBy;
        uint256 updatedAt;
        uint256 createdAt;
    }

    struct AuctionStruct {
        uint256 itemId;
        uint256 intialPrice;
        uint256 lastBidPrice;
        uint256 currentBidPrice;
        uint256 startTime;
        uint256 endTime;
        address winner;
        bool completed;
        address createdBy;
        uint256 updatedAt;
        uint256 createdAt;
    }

    mapping(uint256 => ItemStruct) private Items;
    mapping(uint256 => ListStruct) private Lists;
    mapping(uint256 => OfferStruct) private Offers;
    mapping(address => UserOfferStruct) private UserOffers;
    mapping(uint256 => AuctionStruct) private Auctions;

    // events
    event ItemEvent(
        uint256 indexed itemId,
        string tokenUri,
        uint256 indexed tokenId,
        uint256 price,
        address indexed nftAddress,
        address seller,
        address owner,
        string category,
        string genre,
        bool sold,
        address createdBy,
        uint256 createdAt
    );

    event ListEvent(
        uint256 indexed itemId,
        uint256 price,
        address seller,
        address owner,
        string status,
        bool completed,
        uint256 createdAt
    );

    event OfferEvent(
        uint256 indexed itemId,
        address seller,
        address owner,
        address offerer,
        uint256 offerPrice,
        uint256 offerFrom,
        uint256 offerTo,
        string status,
        bool accepted,
        uint256 createdAt
    );

    event AuctionEvent(
        uint256 indexed itemId,
        address seller,
        address owner,
        uint256 intialPrice,
        uint256 lastBidPrice,
        uint256 currentBidPrice,
        address winner,
        string status,
        bool completed,
        address createdBy,
        uint256 createdAt
    );

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    function createItem(
        address _nftAddress,
        string memory _tokenUri,
        string memory _category,
        string memory _genre
    ) public payable returns (uint256, uint256) {
        _itemIds.increment();
        uint256 itemId = _itemIds.current();
        NFT _nftContract = NFT(_nftAddress);

        uint256 tokenId = _nftContract.createToken(_tokenUri);

        // transferring nft to msg.sender from address(this)
        _nftContract.transferFrom(address(this), msg.sender, tokenId);

        Items[itemId] = ItemStruct({
            itemId: itemId,
            tokenURI: _tokenUri,
            tokenId: tokenId,
            nftAddress: _nftAddress,
            price: 0,
            seller: payable(address(this)),
            owner: payable(msg.sender),
            category: _category,
            genre: _genre,
            sold: false,
            createdBy: msg.sender,
            updatedAt: block.timestamp,
            createdAt: block.timestamp
        });

        emit ItemEvent(
            itemId,
            _tokenUri,
            tokenId,
            0,
            _nftAddress,
            address(this),
            msg.sender,
            _category,
            _genre,
            false,
            msg.sender,
            block.timestamp
        );
        return (itemId, tokenId);
    }

    // @notice List NFT on Marketplace
    function listItem(
        uint256 _itemId,
        uint256 _price,
        string memory _type,
        uint256 _startTime,
        uint256 _endTime
    ) external {
        ItemStruct memory item = Items[_itemId];
        NFT nft = NFT(item.nftAddress);
        if (
            keccak256(abi.encodePacked(_type)) ==
            keccak256(abi.encodePacked("timed_auction"))
        ) {
            createAuction(_itemId, _price, _startTime, _endTime);
        } else if (
            keccak256(abi.encodePacked(_type)) ==
            keccak256(abi.encodePacked("fixed_price"))
        ) {
            require(_price > 0, "Price should be greater than zero");
            require(nft.ownerOf(item.tokenId) == msg.sender, "not nft owner");

            Lists[_itemId] = ListStruct({
                itemId: _itemId,
                price: _price,
                completed: false,
                updatedBy: msg.sender,
                createdBy: msg.sender,
                updatedAt: block.timestamp,
                createdAt: block.timestamp
            });

            emit ListEvent(
                _itemId,
                _price,
                msg.sender,
                item.owner,
                "created",
                false,
                block.timestamp
            );
        } else if (
            keccak256(abi.encodePacked(_type)) ==
            keccak256(abi.encodePacked("open_for_bids"))
        ) {
            createOfferForSale(_itemId);
        } else {
            revert("Enter correct type");
        }
    }

    // @notice Cancel listed NFT
    function cancelListedItem(uint256 _itemId) external {
        // isListedItems(_itemId);
        ItemStruct memory item = Items[_itemId];
        NFT nft = NFT(item.nftAddress);

        require(nft.ownerOf(item.tokenId) == msg.sender, "not listed owner");
        ListStruct memory list = Lists[item.itemId];
        delete Lists[item.itemId]; //delete the storage in the mapping

        emit ListEvent(
            item.itemId,
            list.price,
            msg.sender,
            item.owner,
            "canceled",
            false,
            block.timestamp
        );
    }

    // @notice Buy listed NFT
    function buyItem(uint256 _itemId) external payable {
        ListStruct memory list = Lists[_itemId];
        ItemStruct memory item = Items[_itemId];
        NFT nft = NFT(item.nftAddress);

        require(!list.completed, "nft already sold");

        uint256 royaltyFeeValue = nft.royaltyFee();
        require(
            royaltyFeeValue <= 10,
            "Royality fees should be equal or less than 10%!"
        );

        uint256 serviceFee = 0;
        // Transfering service fees to marketplace recipient
        if (marketplaceServiceFee > 0) {
            serviceFee = (list.price * marketplaceServiceFee) / 100; // MarketPlace Fee 1%
            (bool isPaidMPFee, ) = payable(feeRecipient).call{
                value: serviceFee
            }("");
            require(isPaidMPFee, "Service fee not send to marketplace owner!");
        }

        // Transfering royality fees to NFT owner
        uint256 royaltyFee = 0;
        if (royaltyFeeValue > 0) {
            royaltyFee = (list.price * royaltyFeeValue) / 100;
            if (royaltyFeeValue > 0) {
                (bool isPaidRoyaltyFee, ) = payable(item.createdBy).call{
                    value: royaltyFee
                }("");
                require(
                    isPaidRoyaltyFee,
                    "Royality fee not send to item owner!"
                );
            }
        }

        uint256 remaingPrice = list.price - serviceFee - royaltyFee; // Remaing balance after sending 10%
        // Sending remainingPrice to NFT seller
        (bool isPaidItemActualAmount, ) = payable(item.owner).call{
            value: remaingPrice
        }("");
        require(isPaidItemActualAmount, "Amount not send to owner!");

        // Transfer NFT to buyer
        nft.transferFrom(item.owner, msg.sender, item.tokenId);

        // calling listItem struct and Event from callListFunction
        callListItem(_itemId);
        // calling Item struct and Event form callItemFunction
        callItem(_itemId);
    }

    function createOfferForSale(uint256 _itemId) public {
        ItemStruct memory item = Items[_itemId];
        require(item.itemId > 0, "Item not created yet!");

        Offers[_itemId] = OfferStruct({
            itemId: _itemId,
            accepted: false,
            createdBy: msg.sender,
            updatedAt: block.timestamp,
            createdAt: block.timestamp
        });

        emit OfferEvent(
            _itemId,
            msg.sender,
            item.owner,
            address(0),
            0,
            0,
            0,
            "initiate",
            false,
            block.timestamp
        );
    }

    // @notice Offer listed NFT
    function createOfferForItem(
        uint256 _itemId,
        uint256 _offerPrice,
        uint256 _offerFrom,
        uint256 _offerTo
    ) public {
        require(_offerPrice > 0, "price can not be zero");
        require(
            _offerFrom >= block.timestamp,
            "Time should be equal and greater than current time!"
        );
        require(
            _offerTo > _offerFrom,
            "Offer to should be greater than Offer from"
        );

        ItemStruct memory item = Items[_itemId];
        UserOffers[msg.sender] = UserOfferStruct({
            itemId: _itemId,
            offerer: msg.sender,
            offerPrice: _offerPrice,
            offerFrom: _offerFrom,
            offerTo: _offerTo,
            createdAt: block.timestamp
        });

        emit OfferEvent(
            _itemId,
            item.seller,
            item.owner,
            msg.sender,
            _offerPrice,
            _offerFrom,
            _offerTo,
            "created",
            false,
            block.timestamp
        );
    }

    // @notice Offerer cancel offerring
    function cancelItemFromOffer(uint256 _itemId) external {
        ItemStruct memory item = Items[_itemId];
        OfferStruct memory offer = Offers[_itemId];
        NFT nft = NFT(item.nftAddress);

        require(nft.ownerOf(item.tokenId) == msg.sender, "not nft owner");
        require(!offer.accepted, "offer already accepted");

        delete Offers[_itemId];

        emit OfferEvent(
            item.itemId,
            msg.sender,
            item.owner,
            address(0),
            0,
            0,
            0,
            "canceled",
            false,
            block.timestamp
        );
    }

    // @notice listed NFT owner accept offerring
    function acceptOfferForItem(uint256 _itemId, address _offerer) external {
        ItemStruct memory item = Items[_itemId];
        OfferStruct memory offer = Offers[item.itemId];
        UserOfferStruct memory userOffer = UserOffers[_offerer];
        NFT nft = NFT(item.nftAddress);
        require(nft.ownerOf(item.tokenId) == msg.sender, "not listed owner");
        require(!offer.accepted, "offer already accepted");
        require(
            userOffer.offerFrom <= block.timestamp &&
                userOffer.offerTo >= block.timestamp,
            "Offer expired!"
        );
        uint256 marketPlaceServiceFee = (userOffer.offerPrice *
            marketplaceServiceFee) / 100; // MarketPlace Fee 1%
        // // Transfering 1% to MarketPlace owner
        (bool isPaidMPFee, ) = payable(feeRecipient).call{
            value: marketPlaceServiceFee
        }("");
        if (isPaidMPFee) {
            uint256 royaltyFeeValue = nft.royaltyFee();
            uint256 royaltyFee = (item.price * royaltyFeeValue) / 100; // Royalty Fee 1%
            (bool isPaidRoyaltyFee, ) = payable(item.createdBy).call{
                value: royaltyFee
            }("");
            require(isPaidRoyaltyFee);
            uint256 remaingPrice = userOffer.offerPrice -
                marketPlaceServiceFee -
                royaltyFee; // Remaing balance after sending 10%
            // Sending remainingPrice to NFT seller
            (bool isPaidItemActualAmount, ) = payable(item.seller).call{
                value: remaingPrice
            }("");
            require(isPaidItemActualAmount);
            // Transfer NFT to buyer
            nft.transferFrom(item.owner, msg.sender, item.tokenId);

            callItem(_itemId);

            callOfferEvent(_itemId, _offerer); // calling offer event
        }
    }

    // @notice Create autcion
    function createAuction(
        uint256 _itemId,
        uint256 _minBid,
        uint256 _startTime,
        uint256 _endTime
    ) internal {
        ItemStruct memory item = Items[_itemId];
        NFT nft = NFT(item.nftAddress);
        require(nft.ownerOf(item.tokenId) == msg.sender, "not nft owner");
        require(
            _startTime >= block.timestamp,
            "Start time should be greater than current time"
        );
        require(
            _endTime > _startTime,
            "End time should be greater than start time"
        );

        Auctions[_itemId] = AuctionStruct({
            itemId: _itemId,
            intialPrice: _minBid,
            lastBidPrice: _minBid,
            currentBidPrice: _minBid,
            startTime: _startTime,
            endTime: _endTime,
            winner: address(0),
            completed: false,
            createdBy: msg.sender,
            updatedAt: block.timestamp,
            createdAt: block.timestamp
        });

        emit AuctionEvent(
            item.itemId,
            item.seller,
            item.owner,
            _minBid,
            _minBid,
            _minBid,
            address(0),
            "created",
            false,
            msg.sender,
            block.timestamp
        );
    }

    // @notice Cancel auction
    function cancelAuction(uint256 _itemId) external {
        ItemStruct memory item = Items[_itemId];
        AuctionStruct memory auction = Auctions[_itemId];
        NFT nft = NFT(item.nftAddress);

        require(nft.ownerOf(item.tokenId) == msg.sender, "not nft owner");
        require(
            block.timestamp >= auction.startTime &&
                block.timestamp <= auction.endTime,
            "Auction is already stop!"
        ); //changed this
        require(!auction.completed, "Already completed!");

        delete Auctions[_itemId];
        emit AuctionEvent(
            item.itemId,
            msg.sender,
            item.owner,
            auction.intialPrice,
            auction.lastBidPrice,
            auction.currentBidPrice,
            address(0),
            "canceled",
            false,
            msg.sender,
            block.timestamp
        );
    }

    // @notice Bid place auction
    function bidPlace(uint256 _itemId, uint256 _bidPrice) external {
        AuctionStruct memory auction = Auctions[_itemId];
        require(
            block.timestamp >= auction.startTime &&
                block.timestamp <= auction.endTime,
            "Auction time expired!"
        );
        require(
            _bidPrice > auction.currentBidPrice,
            "Bid price should greater than current price!"
        );
        require(!auction.completed, "Auction already completed!");
        require(
            auction.winner != msg.sender,
            "You are already a higer bidder!"
        );

        auction.lastBidPrice = auction.currentBidPrice;
        auction.currentBidPrice = _bidPrice;
        auction.updatedAt = block.timestamp;
        auction.winner = msg.sender;

        ItemStruct memory item = Items[_itemId];
        Auctions[item.itemId] = auction;

        emit AuctionEvent(
            item.itemId,
            item.owner,
            item.owner,
            auction.intialPrice,
            auction.lastBidPrice,
            _bidPrice,
            address(0),
            "place_bid",
            false,
            msg.sender,
            block.timestamp
        );
    }

    // @notice Result auction, can call by auction creator, heighest bidder, or marketplace owner only!
    function transferItemAuction(uint256 _itemId) external {
        ItemStruct memory item = Items[_itemId];
        AuctionStruct memory auction = Auctions[_itemId];

        NFT nft = NFT(item.nftAddress);
        require(!auction.completed, "Auction already completed!");
        require(
            auction.winner != item.owner,
            "You are already a owner of this item"
        );
        require(
            auction.startTime < block.timestamp &&
                auction.endTime < block.timestamp,
            "Auction not ended!"
        );

        auction.completed = true;
        Auctions[_itemId] = auction;

        uint256 royaltyFeeValue = nft.royaltyFee();
        require(
            royaltyFeeValue <= 10,
            "Royality fees should be equal or less than 10%!"
        );

        uint256 serviceFee = 0;
        // Transfering service fees to marketplace recipient
        if (marketplaceServiceFee > 0) {
            serviceFee =
                (auction.currentBidPrice * marketplaceServiceFee) /
                100; // MarketPlace Fee 1%
            (bool isPaidMPFee, ) = payable(feeRecipient).call{
                value: serviceFee
            }("");
            require(isPaidMPFee, "Service fee not send to marketplace owner!");
        }

        // Transfering royality fees to NFT owner
        uint256 royaltyFee = 0;
        if (royaltyFeeValue > 0) {
            royaltyFee = (auction.currentBidPrice * royaltyFeeValue) / 100;
            if (royaltyFeeValue > 0) {
                (bool isPaidRoyaltyFee, ) = payable(item.createdBy).call{
                    value: royaltyFee
                }("");
                require(
                    isPaidRoyaltyFee,
                    "Royality fee not send to item owner!"
                );
            }
        }

        uint256 remaingPrice = auction.currentBidPrice -
            serviceFee -
            royaltyFee; // Remaing balance after sending 10%
        // Sending remainingPrice to NFT seller
        (bool isPaidItemActualAmount, ) = payable(item.owner).call{
            value: remaingPrice
        }("");
        require(isPaidItemActualAmount, "Amount not send to owner!");

        // Transfer NFT to buyer
        nft.transferFrom(item.owner, msg.sender, item.tokenId);

        // calling Item struct and Event form callItemFunction
        callItem(_itemId);

        emit AuctionEvent(
            item.itemId,
            msg.sender,
            item.owner,
            auction.intialPrice,
            auction.lastBidPrice,
            auction.currentBidPrice,
            auction.winner,
            "completed",
            true,
            msg.sender,
            block.timestamp
        );
    }

    function getListedItem(uint256 _itemId)
        public
        view
        returns (ListStruct memory)
    {
        return Lists[_itemId];
    }

    function getAuctionItem(uint256 _itemId)
        public
        view
        returns (AuctionStruct memory)
    {
        return Auctions[_itemId];
    }

    function getOfferItem(uint256 _itemId)
        public
        view
        returns (OfferStruct memory)
    {
        return Offers[_itemId];
    }

    function setMarketplaceRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "can't be 0 address");
        feeRecipient = _feeRecipient;
    }

    // Return marketplace fee
    function getmarketplaceServiceFee() public view returns (uint256) {
        return marketplaceServiceFee;
    }

    // Set marketplace fee
    function setmarketplaceServiceFee(uint256 _fee) public onlyOwner {
        marketplaceServiceFee = _fee;
    }

    function callItem(uint256 _itemId) private {
        ListStruct memory list = Lists[_itemId];
        ItemStruct memory item = Items[_itemId];
        uint256 itemId = list.itemId;
        require(itemId > 0, "Item is not listed!");

        Items[itemId] = ItemStruct(
            itemId,
            item.tokenURI,
            item.tokenId,
            item.nftAddress,
            list.price,
            payable(item.owner),
            payable(msg.sender),
            item.category,
            item.genre,
            true,
            item.createdBy,
            block.timestamp,
            item.createdAt
        );
        emit ItemEvent(
            item.itemId,
            item.tokenURI,
            item.tokenId,
            list.price,
            item.nftAddress,
            item.owner,
            msg.sender,
            item.category,
            item.genre,
            true,
            item.createdBy,
            block.timestamp
        );
    }

    function callListItem(uint256 _itemId) private {
        ListStruct memory list = Lists[_itemId];
        ItemStruct memory item = Items[_itemId];
        uint256 itemId = list.itemId;

        require(itemId > 0, "Item is not listed!");
        Lists[itemId] = ListStruct(
            itemId,
            list.price,
            true,
            msg.sender,
            item.createdBy,
            block.timestamp,
            item.createdAt
        );

        emit ListEvent(
            itemId,
            list.price,
            msg.sender,
            msg.sender,
            "bought",
            true,
            block.timestamp
        );
    }

    function callOfferEvent(uint256 _itemId, address _offerer) private {
        ItemStruct memory item = Items[_itemId];
        OfferStruct memory offer = Offers[item.itemId];
        UserOfferStruct memory userOffer = UserOffers[_offerer];
        uint256 itemId = item.itemId;

        require(itemId > 0, "Item is not listed!");

        emit OfferEvent(
            item.itemId,
            msg.sender,
            item.owner,
            userOffer.offerer,
            userOffer.offerPrice,
            userOffer.offerFrom,
            userOffer.offerTo,
            " ",
            true,
            offer.createdAt
        );
    }
}
