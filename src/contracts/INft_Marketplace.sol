// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

interface INft_Marketplace {
    struct Order {
        // Order ID
        bytes32 id;
        // Owner of the NFT
        address seller;
        // NFT registry address
        address nftAddress;
        // NFT ID
        uint256 nftId;
        // accepted token
        address acceptedToken;
        // Price for the published item
        uint256 price;
    }

    struct Bid {
        // Bid Id
        bytes32 id;
        // Bidder address
        address bidder;
        // accepted token
        address acceptedToken;
        // Price for the bid
        uint256 price;
        // Time when this bid ends
        uint256 bidTime;
    }
}
