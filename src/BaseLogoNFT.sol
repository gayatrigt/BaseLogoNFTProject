// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

interface IBaseColors {
    function tokenIdToColor(uint256 tokenId) external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract BaseLogoNFT is ERC721, Ownable {
    using Strings for uint256;

    uint256 public mintPrice = 0 ether;
    bool public isPriceChangeEnabled = true;
    address public immutable BASE_COLORS_ADDRESS;
    
    uint256 private _currentTokenId;
    
    mapping(uint256 => string) private _overlayChunks;
    mapping(uint256 => uint256) private _baseColorTokenIds;
    uint256 private _chunkCount;

    event TokenMinted(address indexed recipient, uint256 indexed tokenId, uint256 baseColorTokenId);
    event PaymentSplit(address indexed baseColorOwner, address indexed contractOwner, uint256 amount);
    event MintPriceChanged(uint256 newPrice);

    constructor(address baseColorsAddress) ERC721("BaseLogoNFT", "BLNFT") Ownable(msg.sender) {
        BASE_COLORS_ADDRESS = baseColorsAddress;
    }

    function mint(uint256 baseColorTokenId) external payable {
        IBaseColors baseColors = IBaseColors(BASE_COLORS_ADDRESS);
        address baseColorOwner = baseColors.ownerOf(baseColorTokenId);

        uint256 splitAmount = mintPrice / 2;
        
        (bool success1, ) = payable(baseColorOwner).call{value: splitAmount}("");
        require(success1, "Payment to color owner failed");
        
        (bool success2, ) = payable(owner()).call{value: splitAmount}("");
        require(success2, "Payment to contract owner failed");

        emit PaymentSplit(baseColorOwner, owner(), splitAmount);

        _currentTokenId++;
        uint256 newItemId = _currentTokenId;

        _safeMint(msg.sender, newItemId);
        _baseColorTokenIds[newItemId] = baseColorTokenId;

        emit TokenMinted(msg.sender, newItemId, baseColorTokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        IBaseColors baseColors = IBaseColors(BASE_COLORS_ADDRESS);
        uint256 baseColorTokenId = _baseColorTokenIds[tokenId];
        string memory color = baseColors.tokenIdToColor(baseColorTokenId);

        string memory svg = generateSVG(color);

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "BaseLogoNFT #',
                            tokenId.toString(),
                            '", "description": "An NFT with a colored background and overlay image", "image": "data:image/svg+xml;base64,',
                            Base64.encode(bytes(svg)),
                            '"}'
                        )
                    )
                )
            )
        );
    }

    function generateSVG(string memory color) internal view returns (string memory) {
        string memory overlayBase64 = assembleOverlay();
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">',
                '<rect width="100" height="100" fill="',
                color,
                '"/>',
                '<image href="data:image/svg+xml;base64,',
                overlayBase64,
                '" width="100" height="100"/>',
                "</svg>"
            )
        );
    }

    function assembleOverlay() internal view returns (string memory) {
        string memory result = "";
        for (uint256 i = 0; i < _chunkCount; i++) {
            result = string(abi.encodePacked(result, _overlayChunks[i]));
        }
        return result;
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        require(isPriceChangeEnabled, "Price changes are disabled");
        mintPrice = newPrice;
        emit MintPriceChanged(newPrice);
    }

    function setOverlayChunk(uint256 chunkIndex, string calldata chunkData) external onlyOwner {
        _overlayChunks[chunkIndex] = chunkData;
        if (chunkIndex >= _chunkCount) {
            _chunkCount = chunkIndex + 1;
        }
    }

    function getBaseColorTokenId(uint256 tokenId) external view returns (uint256) {
        return _baseColorTokenIds[tokenId];
    }

    function getOverlayChunk(uint256 chunkIndex) external view returns (string memory) {
        return _overlayChunks[chunkIndex];
    }

    function getChunkCount() external view returns (uint256) {
        return _chunkCount;
    }
}