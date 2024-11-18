// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

interface IBaseColors {
    struct ColorData {
        uint256 tokenId;
        bool isUsed;
        uint256 nameChangeCount;
        string[] modifiableTraits;
    }
    
    function tokenIdToColor(uint256 tokenId) external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getAttributesAsJson(uint256 tokenId) external view returns (string memory);
    function getColorData(string memory color) external view returns (ColorData memory);
}

contract BaseLogoNFT is ERC721, Ownable {
    using Strings for uint256;

    uint256 public mintPrice = 0.000001 ether;
    bool public isPriceChangeEnabled = true;
    address public immutable BASE_COLORS_ADDRESS;
    IBaseColors public immutable baseColors;
    
    uint256 private _currentTokenId;
    uint256 public constant MAX_SUPPLY = 10000;
    
    // Split configuration
    uint256 public baseColorOwnerSplit = 5000; // 50.00% - Using basis points (100% = 10000)
    bool public isSplitChangeEnabled = true;
    
    mapping(uint256 => string) private _overlayChunks;
    mapping(uint256 => uint256) private _baseColorTokenIds;
    mapping(uint256 => bool) private _baseColorTokenIdUsed;
    uint256 private _chunkCount;

    error InvalidBaseColorToken();
    error BaseColorTokenAlreadyUsed();
    error ColorNameNotFound();
    error BatchSizeTooLarge();
    error InsufficientPayment();
    error PaymentFailed();
    error MaxSupplyReached();
    error InvalidSplitPercentage();
    error SplitChangeDisabled();

    event TokenMinted(address indexed recipient, uint256 indexed tokenId, uint256 baseColorTokenId);
    event BatchMinted(address indexed recipient, uint256[] tokenIds, uint256[] baseColorTokenIds);
    event PaymentSplit(address indexed baseColorOwner, address indexed contractOwner, uint256 amount);
    event MintPriceChanged(uint256 newPrice);
    event SplitPercentageChanged(uint256 newSplitPercentage);
    event SplitChangeDisabledForever();

    uint256 public constant MAX_BATCH_SIZE = 20;
    uint256 private constant BASIS_POINTS = 10000; // 100.00%

    constructor(address baseColorsAddress) ERC721("Base Logos", "BLOGS") Ownable(msg.sender) {
        BASE_COLORS_ADDRESS = baseColorsAddress;
        baseColors = IBaseColors(baseColorsAddress);
    }

    function setSplitPercentage(uint256 newSplitPercentage) external onlyOwner {
        if (!isSplitChangeEnabled) revert SplitChangeDisabled();
        if (newSplitPercentage > BASIS_POINTS) revert InvalidSplitPercentage();
        baseColorOwnerSplit = newSplitPercentage;
        emit SplitPercentageChanged(newSplitPercentage);
    }

    function disableSplitChangeForever() external onlyOwner {
        isSplitChangeEnabled = false;
        emit SplitChangeDisabledForever();
    }

    function calculateSplitAmount(uint256 amount) public view returns (uint256) {
        return (amount * baseColorOwnerSplit) / BASIS_POINTS;
    }

    function getCurrentTokenId() external view returns (uint256) {
        return _currentTokenId;
    }

    function isAvailableForMint(uint256 baseColorTokenId) public view returns (bool) {
        try baseColors.ownerOf(baseColorTokenId) returns (address) {
            if (_baseColorTokenIdUsed[baseColorTokenId]) {
                return false;
            }

            try baseColors.tokenIdToColor(baseColorTokenId) returns (string memory color) {
                string memory colorName = getColorName(color);
                bytes memory colorNameBytes = bytes(colorName);
                if (colorNameBytes.length == 0 || keccak256(bytes(colorName)) == keccak256(bytes(color))) {
                    return false;
                }
                return true;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    function validateBaseColorToken(uint256 baseColorTokenId) internal view {
        if (!isAvailableForMint(baseColorTokenId)) {
            if (_baseColorTokenIdUsed[baseColorTokenId]) {
                revert BaseColorTokenAlreadyUsed();
            }
            
            try baseColors.tokenIdToColor(baseColorTokenId) returns (string memory color) {
                string memory colorName = getColorName(color);
                if (bytes(colorName).length == 0 || keccak256(bytes(colorName)) == keccak256(bytes(color))) {
                    revert ColorNameNotFound();
                }
            } catch {
                revert InvalidBaseColorToken();
            }
            
            revert InvalidBaseColorToken();
        }
    }

    function getColorName(string memory colorhex) public view returns (string memory) {
        try baseColors.getColorData(colorhex) returns (IBaseColors.ColorData memory colorData) {
            string memory attributes = baseColors.getAttributesAsJson(colorData.tokenId);
            bytes memory attributesBytes = bytes(attributes);
            bytes memory colorNameKey = bytes('"trait_type":"Color Name","value":"');
            bytes memory endKey = bytes('"}');

            uint256 start = 0;
            for (uint256 i = 0; i < attributesBytes.length - colorNameKey.length; i++) {
                bool ismatched = true;
                for (uint256 j = 0; j < colorNameKey.length; j++) {
                    if (attributesBytes[i + j] != colorNameKey[j]) {
                        ismatched = false;
                        break;
                    }
                }
                if (ismatched) {
                    start = i + colorNameKey.length;
                    break;
                }
            }

            uint256 end = start;
            for (uint256 i = start; i < attributesBytes.length - endKey.length; i++) {
                bool ismatched = true;
                for (uint256 j = 0; j < endKey.length; j++) {
                    if (attributesBytes[i + j] != endKey[j]) {
                        ismatched = false;
                        break;
                    }
                }
                if (ismatched) {
                    end = i;
                    break;
                }
            }

            bytes memory colorNameBytes = new bytes(end - start);
            for (uint256 i = 0; i < end - start; i++) {
                colorNameBytes[i] = attributesBytes[start + i];
            }
            return string(colorNameBytes);
        } catch {
            return colorhex;
        }
    }

    function batchMint(uint256[] calldata baseColorTokenIds) external payable {
        uint256 batchSize = baseColorTokenIds.length;
        if (batchSize == 0 || batchSize > MAX_BATCH_SIZE) revert BatchSizeTooLarge();
        if (_currentTokenId + batchSize > MAX_SUPPLY) revert MaxSupplyReached();
        
        uint256 totalCost = mintPrice * batchSize;
        if (msg.value < totalCost) revert InsufficientPayment();

        // Validate all tokens first to prevent partial mints
        for (uint256 i = 0; i < batchSize; i++) {
            validateBaseColorToken(baseColorTokenIds[i]);
        }

        // Track payment recipients and amounts
        address[] memory recipients = new address[](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);
        uint256 splitAmount = calculateSplitAmount(mintPrice);
        
        // Mint tokens and prepare payments
        uint256[] memory newTokenIds = new uint256[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            uint256 baseColorTokenId = baseColorTokenIds[i];
            address baseColorOwner = baseColors.ownerOf(baseColorTokenId);
            
            _currentTokenId++;
            uint256 newItemId = _currentTokenId;
            newTokenIds[i] = newItemId;

            _safeMint(msg.sender, newItemId);
            _baseColorTokenIds[newItemId] = baseColorTokenId;
            _baseColorTokenIdUsed[baseColorTokenId] = true;

            recipients[i] = baseColorOwner;
            amounts[i] = splitAmount;

            emit TokenMinted(msg.sender, newItemId, baseColorTokenId);
        }

        // Process payments
        uint256 baseColorOwnerTotal = splitAmount * batchSize;
        uint256 contractOwnerTotal = totalCost - baseColorOwnerTotal;
        
        // Pay contract owner
        (bool successOwner, ) = payable(owner()).call{value: contractOwnerTotal}("");
        if (!successOwner) revert PaymentFailed();

        // Pay base color owners
        for (uint256 i = 0; i < batchSize; i++) {
            (bool success, ) = payable(recipients[i]).call{value: amounts[i]}("");
            if (!success) revert PaymentFailed();
            emit PaymentSplit(recipients[i], owner(), amounts[i]);
        }

        emit BatchMinted(msg.sender, newTokenIds, baseColorTokenIds);
    }

    function mint(uint256 baseColorTokenId) external payable {
        if (_currentTokenId >= MAX_SUPPLY) revert MaxSupplyReached();
        if (msg.value < mintPrice) revert InsufficientPayment();
        validateBaseColorToken(baseColorTokenId);

        address baseColorOwner = baseColors.ownerOf(baseColorTokenId);

        uint256 baseColorOwnerAmount = calculateSplitAmount(mintPrice);
        uint256 contractOwnerAmount = mintPrice - baseColorOwnerAmount;
        
        (bool success1, ) = payable(baseColorOwner).call{value: baseColorOwnerAmount}("");
        if (!success1) revert PaymentFailed();
        
        (bool success2, ) = payable(owner()).call{value: contractOwnerAmount}("");
        if (!success2) revert PaymentFailed();

        emit PaymentSplit(baseColorOwner, owner(), baseColorOwnerAmount);

        _currentTokenId++;
        uint256 newItemId = _currentTokenId;

        _safeMint(msg.sender, newItemId);
        _baseColorTokenIds[newItemId] = baseColorTokenId;
        _baseColorTokenIdUsed[baseColorTokenId] = true;

        emit TokenMinted(msg.sender, newItemId, baseColorTokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        uint256 baseColorTokenId = _baseColorTokenIds[tokenId];
        string memory color = baseColors.tokenIdToColor(baseColorTokenId);
        string memory colorName = getColorName(color);

        string memory svg = generateSVG(color);

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "Base Logo #',
                            tokenId.toString(),
                            '", "description": "Base Logos is a collection of ',
                            Strings.toString(MAX_SUPPLY),
                            ' base logos colored with Base Colors. There is one logo for each of the first 10,000 Base Colors named. 50% of mint revenue goes to the owner of the Base Color used in the Base Logo.", "attributes": [{"trait_type": "Base Color", "value": "',
                            colorName,
                            '"}], "image": "data:image/svg+xml;base64,',
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
                '<image href="data:image/png+xml;base64,',
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