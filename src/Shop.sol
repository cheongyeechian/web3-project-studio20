// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Token.sol";

contract ShopManager is ERC721URIStorage, Ownable {
    IERC20 public token;
    uint256 private _tokenIds;

    struct Item {
        string name;
        string description;
        uint256 price; // Price in project tokens
        bool isAvailable;
    }

    // Mappings
    mapping(uint256 => Item) public items;

    // Events
    event ItemListed(uint256 indexed itemId, string name, uint256 price);
    event ItemPurchased(
        uint256 indexed itemId,
        address indexed buyer,
        uint256 price
    );
    event ItemRemoved(uint256 indexed itemId);

    constructor(
        address _token
    ) ERC721("Project Rewards", "REWARD") Ownable(msg.sender) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }

    // Admin function to list new items
    function listItem(
        string memory name,
        string memory description,
        uint256 price,
        string memory uri
    ) external onlyOwner returns (uint256) {
        require(price > 0, "Price must be positive");

        uint256 itemId = _tokenIds;

        items[itemId] = Item({
            name: name,
            description: description,
            price: price,
            isAvailable: true
        });

        _setTokenURI(itemId, uri);
        _tokenIds += 1;

        emit ItemListed(itemId, name, price);
        return itemId;
    }

    // User function to purchase items
    function purchaseItem(uint256 itemId) external {
        Item storage item = items[itemId];
        require(item.isAvailable, "Item not available");

        // Check token allowance and balance
        require(
            token.allowance(msg.sender, address(this)) >= item.price,
            "Insufficient allowance"
        );
        require(
            token.balanceOf(msg.sender) >= item.price,
            "Insufficient balance"
        );

        // Transfer and burn tokens
        require(
            token.transferFrom(msg.sender, address(this), item.price),
            "Transfer failed"
        );

        // Mint NFT to buyer
        _safeMint(msg.sender, itemId);

        // Mark item as unavailable
        item.isAvailable = false;

        emit ItemPurchased(itemId, msg.sender, item.price);
    }

    // Admin function to remove items
    function removeItem(uint256 itemId) external onlyOwner {
        require(items[itemId].isAvailable, "Item not available");
        items[itemId].isAvailable = false;
        emit ItemRemoved(itemId);
    }

    // View function to get item details
    function getItem(uint256 itemId) external view returns (Item memory) {
        return items[itemId];
    }

    // Admin function to withdraw and burn tokens
    function withdrawBurnedTokens() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        Token(address(token)).burn(balance);
    }
}
