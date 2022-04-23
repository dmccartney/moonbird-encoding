const { expect } = require("chai");
const { ethers } = require("hardhat");

const colors = require("../scripts/colors");
const { loadMoonbird } = require("../scripts/moonbirds");

describe("Renderer", function () {
  it("color codes", async function () {
    let renderer = await deployRenderer();

    await renderer.setColorCodes(
      [0, 1, 2, 3, 4, 5],
      [0x001122, 0x334455, 0x667788, 0x999999, 0xaabbcc, 0xddeeff]
    );

    expect(asString(await renderer.colorForCode(0))).to.equal("#001122");
    expect(asString(await renderer.colorForCode(1))).to.equal("#334455");
    expect(asString(await renderer.colorForCode(2))).to.equal("#667788");
    expect(asString(await renderer.colorForCode(3))).to.equal("#999999");
    expect(asString(await renderer.colorForCode(4))).to.equal("#aabbcc");
    expect(asString(await renderer.colorForCode(5))).to.equal("#ddeeff");

    // Unknown yields black
    expect(asString(await renderer.colorForCode(999))).to.equal("#000000");
  });

  it("all color codes", async function () {
    let renderer = await deployRenderer();

    await Promise.all(
      colors.map((color, i) => renderer.setColorCodes([i], [color]))
    );

    expect(asString(await renderer.colorForCode(0))).to.equal("#000000");
    expect(asString(await renderer.colorForCode(1))).to.equal("#002d3d");
    // ...
    expect(asString(await renderer.colorForCode(1607))).to.equal("#ffffff");

    // Unknown yields black
    expect(asString(await renderer.colorForCode(9999))).to.equal("#000000");
  });

  it("metadata should be loaded", async function () {
    let renderer = await deployRenderer();

    await renderer.setTokenData([6158], [loadMoonbird(6158)]);

    let metadata = await renderer.metadataHeaderOf(6158);

    expect(metadata.rlePixelCount).to.equal(307);
    [
      {
        trait_type: "Background",
        value: "Green",
      },
      {
        trait_type: "Beak",
        value: "Small",
      },
      {
        trait_type: "Body",
        value: "Crescent",
      },
      {
        trait_type: "Eyes",
        value: "Rainbow",
      },
      {
        trait_type: "Eyewear",
        value: "(absent)",
      },
      {
        trait_type: "Feathers",
        value: "Black",
      },
      {
        trait_type: "Headwear",
        value: "Halo",
      },
      {
        trait_type: "Outerwear",
        value: "(absent)",
      },
    ].forEach((trait, i) => {
      expect(metadata.traits[i].trait_type).to.equal(trait.trait_type);
      expect(metadata.traits[i].value).to.equal(trait.value);
    });
  });

  async function setMoonbirdTokenData(renderer, tokenIds) {
    return renderer.setTokenData(
      tokenIds,
      tokenIds.map((n) => loadMoonbird(n))
    );
  }

  it("pixel data", async function () {
    let renderer = await deployRenderer();

    await setMoonbirdTokenData(renderer, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

    let pixels = await renderer.pixelsOf(1);

    // These magic numbers reflect the contents of Moonbird #1 encoded.
    expect(pixels.length).to.equal(372);
    expect(pixels[0]).to.eql([32, 1562]);
    expect(pixels[227]).to.eql([3, 1499]);
    expect(pixels[371]).to.eql([8, 1562]);
  });

  it("rendering SVG", async function () {
    let renderer = await deployRenderer();

    await Promise.all(
      colors.map((color, i) => renderer.setColorCodes([i], [color]))
    );
    await renderer.setTokenData([1], [loadMoonbird(1)]);

    let svg = asString(
      await renderer.renderSVG(1, {
        gasLimit: 20_000_000,
      })
    );
    expect(svg).to.contain(`<svg xmlns="http://www.w3.org/2000/svg" `);
    // ...
    expect(svg).to.contain(
      `<rect width="100%" height="100%" stroke="#fcb5db" fill="#fcb5db"/>`
    );
    // ...
    expect(svg).to.contain(
      `<rect x="792" y="984" width="24" height="24" stroke="#192e4d" fill="#192e4d"/>`
    );
    // ...
    expect(svg.match(/<rect /g).length).to.equal(325);
    expect(svg).to.contain("</svg>");
  });

  it("big rendering SVG", async function () {
    let renderer = await deployRenderer();

    await Promise.all(
      colors.map((color, i) => renderer.setColorCodes([i], [color]))
    );
    await renderer.setTokenData([974], [loadMoonbird(974)]);

    let svg = asString(
      await renderer.renderSVG(974, {
        gasLimit: 50_000_000,
      })
    );
    expect(svg).to.contain(`<svg xmlns="http://www.w3.org/2000/svg" `);
    // ...
    expect(svg.match(/<rect /g).length).to.equal(1180);
    expect(svg).to.contain("</svg>");
  });
});

// Helpers

function asString(bytes) {
  return ethers.utils.toUtf8String(bytes);
}

async function deployRenderer() {
  const Renderer = await ethers.getContractFactory("Renderer");
  const renderer = await Renderer.deploy();
  await renderer.deployed();
  return renderer;
}
