// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./INft_Marketplace.sol";

contract Auction_Marketplace is INft_Marketplace, IERC721Receiver {
    using SafeMath for uint256;
    // From ERC721 registry assetId to Order (to avoid asset collision)
    mapping(address => mapping(uint256 => Order)) orderByAssetId;

    // From ERC721 registry assetId to Bid (to avoid asset collision)
    mapping(address => mapping(uint256 => Bid)) bidByOrderId;
    uint256 timeInterval = 0;

    constructor() public {}

    // 721 Interfaces
    bytes4 public constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    function createOrder(
        address _nftAddress,
        uint256 _assetId,
        string memory _tokenSymbol,
        uint256 _price,
        uint256 _expiresAt
    ) public returns (bytes32) {
        return
            _createOrder(
                _nftAddress,
                _assetId,
                _tokenSymbol,
                _price,
                _expiresAt
            );
    }

    function cancelOrder(address _nftAddress, uint256 _assetId) public {
        Order memory order = orderByAssetId[_nftAddress][_assetId];

        require(order.seller == msg.sender, "Marketplace: unauthorized sender");

        // Remove pending bid if any
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        if (bid.id != 0) {
            _cancelBid(_nftAddress, _assetId);
        }

        // Cancel order.
        _cancelOrder(order.id, _nftAddress, _assetId, msg.sender);
    }

    function safePlaceBid(
        address _nftAddress,
        uint256 _assetId,
        string memory _tokenSymbol,
        uint256 _price,
        uint256 _expiresAt
    ) public {
        _createBid(_nftAddress, _assetId, _tokenSymbol, _price, _expiresAt);
    }

    function cancelBid(address _nftAddress, uint256 _assetId) public {
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        require(
            bid.bidder == msg.sender || msg.sender == owner(),
            "Marketplace: Unauthorized sender"
        );

        _cancelBid(_nftAddress, _assetId);
    }

    function acceptBid(address _nftAddress, uint256 _assetId) public {
        // check order validity
        Order memory order = _getValidOrder(_nftAddress, _assetId);

        require(order.seller == msg.sender, "Marketplace: unauthorized sender");

        Bid memory bid = bidByOrderId[_nftAddress][_assetId];
        delete bidByOrderId[_nftAddress][_assetId];

        emit BidAccepted(bid.id);
        ERC20 acceptedToken = ERC20(order.acceptedToken);
        acceptedToken.transferFrom(
            address(this), //escrow
            order.seller, // seller
            bid.price
        );
        _executeOrder(order.id, bid.bidder, bid.price);
    }

    function _cancelBid(address _nftAddress, uint256 _assetId) internal {
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];
        delete bidByOrderId[_nftAddress][_assetId];
        ERC20 acceptedToken = ERC20(bid.acceptedToken);
        acceptedToken.transfer(bid.bidder, bid.price);
    }

    function _getValidOrder(address _nftAddress, uint256 _assetId)
        internal
        view
        returns (Order memory order)
    {
        order = orderByAssetId[_nftAddress][_assetId];
        require(order.id != 0, "Marketplace: asset not published");
    }

    function _executeOrder(
        bytes32 _orderId,
        address _buyer,
        uint256 _price
    ) internal {
        // remove order

        // Transfer NFT asset
        Order memory order = orderByAssetId[_nftAddress][_assetId];
        // Transfer NFT asset
        IERC721(_nftAddress).safeTransferFrom(
            address(this),
            _buyer,
            order.nftId
        );
        delete orderByAssetId[_nftAddress][_assetId];
    }

    function _createOrder(
        address _nftAddress,
        uint256 _assetId,
        address _acceptedToken,
        uint256 _price
    ) internal returns (bytes32) {
        // Check nft registry
        IERC721 nftRegistry = _requireERC721(_nftAddress);

        // Check order creator is the asset owner
        address assetOwner = nftRegistry.ownerOf(_assetId);

        require(
            assetOwner == msg.sender,
            "Marketplace: Only the asset owner can create orders"
        );

        require(_price > 0, "Marketplace: Price should be bigger than 0");

        // get NFT asset from seller
        nftRegistry.safeTransferFrom(assetOwner, address(this), _assetId);

        // create the orderId
        bytes32 orderId = keccak256(
            abi.encodePacked(
                block.timestamp,
                assetOwner,
                _nftAddress,
                _assetId,
                _acceptedToken,
                _price
            )
        );

        // save order
        orderByAssetId[_nftAddress][_assetId] = Order({
            id: orderId,
            seller: assetOwner,
            nftAddress: _nftAddress,
            nftId: _assetId,
            acceptedToken: _acceptedToken,
            price: _price
        });
        return orderId;
    }

    function _createBid(
        address _nftAddress,
        uint256 _assetId,
        uint256 _price
    ) internal {
        // Checks order validity
        Order memory order = _getValidOrder(_nftAddress, _assetId);

        // Check price if theres previous a bid
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        // if theres no previous bid, just check price > 0
        if (bid.id != 0) {
            require(
                bid.bidTime + timeInterval >= block.timestamp,
                "Marketplace: bid price should be higher than last bid"
            );
            require(
                _price > bid.price,
                "Marketplace: bid price should be higher than last bid"
            );
            _cancelBid(_nftAddress, _assetId);
        }

        // bidding is only with CifiToken ( this needs to be updated when we go live to Binance smart chain )
        ERC20 acceptedToken = ERC20(order.acceptedToken);

        acceptedToken.transferFrom(msg.sender, address(this), _price);

        bytes32 bidId = keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                order.id,
                _price,
                _expiresAt
            )
        );

        // Save Bid for this order
        bidByOrderId[_nftAddress][_assetId] = Bid({
            id: bidId,
            bidder: msg.sender,
            acceptedToken: order.acceptedToken,
            price: _price,
            expiresAt: _expiresAt
        });
    }

    function _requireERC721(address _nftAddress)
        internal
        view
        returns (IERC721)
    {
        require(
            IERC721(_nftAddress).supportsInterface(_INTERFACE_ID_ERC721),
            "The NFT contract has an invalid ERC721 implementation"
        );
        return IERC721(_nftAddress);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
