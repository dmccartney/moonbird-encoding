//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@divergencetech/ethier/contracts/utils/DynamicBuffer.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// WIP
// This renders each moonbird as an SVG along with the metadata JSON.
//
// See Renderer.test.js and README.md for details.
contract Renderer is Ownable {
    using DynamicBuffer for bytes;
    using Strings for uint256;

    struct Trait {
        string trait_type;
        string value;
        uint256 valueCode;
    }

    struct Metadata {
        Trait[8] traits;
        uint16 rlePixelCount;
    }

    // Pixels are stored as run-length encoded tiles.
    // Each entry identifies a color that is repeated some number of times.
    struct RLEPixel {
        uint8 repeatCount; // decoded from 5 bits
        uint16 colorCode; // decoded from 11 bits
    }

    // This maps tokenId to the encoded metadata header and pixel list.
    mapping(uint256 => mapping(uint256 => bytes32)) tokenData;
    // This maps color codes to their RGB equivalent.
    mapping(uint16 => uint24) colors;

    string[8] TRAIT_NAMES = [
        "Background",
        "Beak",
        "Body",
        "Eyes",
        "Eyewear",
        "Feathers",
        "Headwear",
        "Outerwear"
    ];
    // The size of each trait in the metadata header atop each `tokenData` buffer.
    uint8[8] TRAIT_BIT_COUNTS = [4, 2, 5, 4, 4, 5, 6, 4];
    string[11] BACKGROUND_VALUES = [
        "(absent)",
        "Blue",
        "Cosmic Purple",
        "Enlightened Purple",
        "Glitch Red",
        "Gray",
        "Green",
        "Jade Green",
        "Pink",
        "Purple",
        "Yellow"
    ];
    string[4] BEAK_VALUES = ["(absent)", "Long", "Short", "Small"];
    string[18] BODY_VALUES = [
        "(absent)",
        "Brave",
        "Cosmic",
        "Crescent",
        "Emperor",
        "Enlightened",
        "Glitch",
        "Golden",
        "Guardian",
        "Jade",
        "Professor",
        "Robot",
        "Ruby Skeleton",
        "Sage",
        "Skeleton",
        "Stark",
        "Tabby",
        "Tranquil"
    ];
    string[12] EYES_VALUES = [
        "(absent)",
        "Adorable",
        "Angry",
        "Diamond",
        "Discerning",
        "Fire",
        "Heart",
        "Moon",
        "Open",
        "Rainbow",
        "Relaxed",
        "Side-eye"
    ];
    string[13] EYEWEAR_VALUES = [
        "(absent)",
        "3D Glasses",
        "Aviators",
        "Big Tech",
        "Black-rimmed Glasses",
        "Eyepatch",
        "Gazelles",
        "Half-moon Spectacles",
        "Jobs Glasses",
        "Monocle",
        "Rose-Colored Glasses",
        "Sunglasses",
        "Visor"
    ];
    string[19] FEATHERS_VALUES = [
        "(absent)",
        "Black",
        "Blue",
        "Bone",
        "Brown",
        "Gray",
        "Green",
        "Legendary Bone",
        "Legendary Brave",
        "Legendary Crescent",
        "Legendary Emperor",
        "Legendary Guardian",
        "Legendary Professor",
        "Legendary Sage",
        "Metal",
        "Pink",
        "Purple",
        "Red",
        "White"
    ];
    string[38] HEADWEAR_VALUES = [
        "(absent)",
        "Aviator's Cap",
        "Backwards Hat",
        "Bandana",
        "Beanie",
        "Bow",
        "Bucket Hat",
        "Captain's Cap",
        "Chromie",
        "Cowboy Hat",
        "Crescent Talisman",
        "Dancing Flame",
        "Diamond",
        "Durag",
        "Fire",
        "Flower",
        "Forest Ranger",
        "Grail",
        "Gremplin",
        "Halo",
        "Headband",
        "Headphones",
        "Hero's Cap",
        "Karate Band",
        "Lincoln",
        "Mohawk (Green)",
        "Mohawk (Pink)",
        "Moon Hat",
        "Pirate's Hat",
        "Queen's Crown",
        "Raincloud",
        "Rubber Duck",
        "Skully",
        "Space Helmet",
        "Tiara",
        "Tiny Crown",
        "Witch's Hat",
        "Wizard's Hat"
    ];
    string[9] OUTERWEAR_VALUES = [
        "(absent)",
        "Bomber Jacket",
        "Diamond Necklace",
        "Gold Chain",
        "Hero's Tunic",
        "Hoodie",
        "Hoodie Down",
        "Jean Jacket",
        "Punk Jacket"
    ];

    constructor() {}

    // TODO: tokenUri method that brings together renderSVG + metadataHeader

    // visible for testing
    function renderSVG(uint256 tokenId)
        public
        view
        returns (bytes memory svg_)
    {
        // This is an array of all the pixels in the image.
        // Each entry describes a run of the same color (e.g. 5 pink, 1 white, 32 green).
        RLEPixel[] memory pixels = pixelsOf(tokenId);
        bytes memory svg = DynamicBuffer.allocate(2**19);
        assembly {
            svg_ := svg
        }
        // The view box for the image is 1008x1008 (24*42) because it is 42x42 square tiles of size 24px each.
        svg.appendUnchecked(
            '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="1008" height="1008" viewBox="0 0 1008 1008">\n'
        );
        // To reduce the number of <rect>s, we draw the background color as a single full-size <rect>.
        // We guess the background color by just using the value of the first (top-left) pixel.
        // TODO: consider changing background based on things like proof-pass ownership.
        uint16 bgColorCode = pixels[0].colorCode;
        bytes memory bgColor = colorForCode(bgColorCode);
        svg.appendUnchecked('<rect width="100%" height="100%" stroke="');
        svg.appendUnchecked(bgColor);
        svg.appendUnchecked('" fill="');
        svg.appendUnchecked(bgColor);
        svg.appendUnchecked('"/>\n');
        uint256 t = 0;

        for (uint256 i = 0; i < pixels.length; i++) {
            // This captures a repeated run of the same color tile (repeatCount + colorCode).
            RLEPixel memory p = pixels[i];
            if (p.colorCode == bgColorCode) {
                // We skip background tiles because we already put it behind everything.
                t += p.repeatCount;
                continue;
            }
            bytes memory color = colorForCode(p.colorCode);
            uint256 j = 0;
            // Now we draw the `repeatCount` tiles of `color`.
            while (j < p.repeatCount) {
                uint256 x = 24 * (t % 42);
                uint256 y = 24 * (t / 42);
                uint256 width = 24;
                t += 1;
                j += 1;

                // We reduce the # of <rect>s by merging identical tiles horizontally.
                //  e.g. [X][X][X][X][X] becomes [<---- X ---->]
                // Merging stops after `repeatCount` or at the end of the row.
                while (j < p.repeatCount && t % 42 != 0) {
                    width += 24;
                    t += 1;
                    j += 1;
                }
                svg.appendUnchecked('<rect x="');
                svg.appendUnchecked(bytes(x.toString()));
                svg.appendUnchecked('" y="');
                svg.appendUnchecked(bytes(y.toString()));
                svg.appendUnchecked('" width="');
                svg.appendUnchecked(bytes(width.toString()));
                svg.appendUnchecked('" height="24" stroke="');
                svg.appendUnchecked(color);
                svg.appendUnchecked('" fill="');
                svg.appendUnchecked(color);
                svg.appendUnchecked('"/>\n');
            }
        }
        svg.appendUnchecked("</svg>");
    }

    // visible for testing
    function metadataHeaderOf(uint256 tokenId)
        public
        view
        returns (Metadata memory)
    {
        Trait[8] memory traits;
        uint256 header = uint256(uint48(bytes6(tokenData[tokenId][0])));
        uint16 rlePixelCount = uint16(header & ((1 << 14) - 1));
        header >>= 14;
        for (uint256 i = 0; i < TRAIT_NAMES.length; i++) {
            uint256 n = TRAIT_NAMES.length - i - 1;
            uint256 bitCount = uint256(TRAIT_BIT_COUNTS[n]);
            uint256 valueCode = header & ((1 << bitCount) - 1);
            traits[n] = Trait({
                trait_type: TRAIT_NAMES[n],
                value: traitValueName(n, valueCode),
                valueCode: valueCode
            });
            header >>= bitCount;
        }
        return Metadata(traits, rlePixelCount);
    }

    function traitValueName(uint256 traitIndex, uint256 valueCode)
        internal
        view
        returns (string memory)
    {
        if (traitIndex < 1) {
            return BACKGROUND_VALUES[valueCode];
        } else if (traitIndex < 2) {
            return BEAK_VALUES[valueCode];
        } else if (traitIndex < 3) {
            return BODY_VALUES[valueCode];
        } else if (traitIndex < 4) {
            return EYES_VALUES[valueCode];
        } else if (traitIndex < 5) {
            return EYEWEAR_VALUES[valueCode];
        } else if (traitIndex < 6) {
            return FEATHERS_VALUES[valueCode];
        } else if (traitIndex < 7) {
            return HEADWEAR_VALUES[valueCode];
        } else {
            // (traitIndex < 8)
            return OUTERWEAR_VALUES[valueCode];
        }
    }

    // visible for testing
    function pixelsOf(uint256 tokenId) public view returns (RLEPixel[] memory) {
        Metadata memory metadata = metadataHeaderOf(tokenId);
        RLEPixel[] memory pixels = new RLEPixel[](metadata.rlePixelCount);
        mapping(uint256 => bytes32) storage blocks = tokenData[tokenId];

        uint256 blockIndex = 0;
        bytes32 b = blocks[blockIndex];
        uint256 byteIndex = 6; // Start at 6 to skip the metadata header (not pixel data).
        for (uint256 i = 0; i < pixels.length; i++) {
            if (byteIndex >= 32) {
                blockIndex += 1;
                b = blocks[blockIndex];
                byteIndex = 0;
            }
            uint16 item = (uint16(uint8(b[byteIndex])) << 8) |
                uint16(uint8(b[byteIndex + 1]));
            uint8 count = uint8(item >> 11) + 1;
            uint16 code = uint16(item & ((1 << 11) - 1));
            pixels[i] = RLEPixel(count, code);
            byteIndex += 2;
        }
        return pixels;
    }

    bytes16 internal constant HEX_DIGITS = "0123456789abcdef";

    // visible for testing
    function colorForCode(uint16 code) public view returns (bytes memory) {
        bytes memory result = new bytes(7);
        uint24 color = colors[code];
        result[0] = "#";
        for (uint256 i = 1; i < 7; i++) {
            result[7 - i] = HEX_DIGITS[color & 0xf];
            color >>= 4;
        }
        return result;
    }

    function setTokenData(uint256[] calldata tokenIds, bytes[] calldata datas)
        public
        onlyOwner
    {
        require(tokenIds.length == datas.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            bytes calldata data = datas[i];
            mapping(uint256 => bytes32) storage blocks = tokenData[tokenId];
            uint256 blockCount = Math.ceilDiv(data.length, 32);
            for (uint256 j = 0; j < blockCount; j++) {
                uint256 start = 32 * j;
                uint256 end = Math.min(32 * j + 32, data.length);
                blocks[j] = bytes32(data[start:end]);
            }
        }
    }

    function setColorCodes(uint16[] calldata _codes, uint24[] calldata _colors)
        public
        onlyOwner
    {
        require(_codes.length == _colors.length);
        for (uint256 i = 0; i < _codes.length; i++) {
            colors[_codes[i]] = _colors[i];
        }
    }
}
