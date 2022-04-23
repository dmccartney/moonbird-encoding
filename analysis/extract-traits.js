#!/usr/bin/env node
const fs = require("fs");

// This contains scraps of my scripts to explore
// extracting and encoding metadata traits.

// Returns a list of all traits with every possible value.
function analyzeMetadata() {
  let traits = {}
  for (let i = 0; i < 10_000; i++) {
    let m = require(`./metadata/json/${i}.json`);
    for (let j = 0; j < m.attributes.length; j++) {
      let {trait_type, value} = m.attributes[j];
      let values = traits[trait_type] || ["(absent)"];
      if (values.indexOf(value) === -1) {
        traits[trait_type] = values.concat([value])
      }
    }
  }
  // Object.keys(traits).sort().forEach(t => {
  //   console.log(`| ${t} | ${traits[t].length} | ${Math.ceil(Math.log2(traits[t].length))} | ${traits[t].sort().join(", ")} |`)
  // })
  // console.log("totals:")
  // console.log(" trait count:", Object.keys(traits).length)
  // console.log(" value count:", Object.keys(traits).reduce((n, t) => (traits[t].length + n), 0))
  // console.log(" bit count:", Object.keys(traits).reduce((n, t) => (Math.ceil(Math.log2(traits[t].length)) + n), 0))

  return Object.keys(traits).sort().map(t => ({
    trait_type: t,
    values: traits[t].sort(),
    bitCount: Math.ceil(Math.log2(traits[t].length)),
  }));
}

// Return a BigInt with a uint48 representing the 6-byte metadata header for the specified token.
function encodeTokenMetadata(tokenId, metadata) {
  let m = require(`./metadata/json/${tokenId}.json`);
  let bits = 0n;
  for (let j = 0; j < metadata.length; j++) {
    let {trait_type, bitCount, values} = metadata[j];
    let a = m.attributes.find(it => it.trait_type === trait_type);
    let value = a ? values.indexOf(a.value) : 0;
    bits <<= BigInt(bitCount);
    bits += BigInt(value);
    // process.stdout.write(BigInt(value).toString(2).padStart(bitCount, "0") + " ")
  }
  // Include space for the 14 bits of header used for the size of the pixel list.
  bits <<= BigInt(14);
  // process.stdout.write("".padStart(14, "0") + "\n");

  // Convert the uint48 to a byte buffer.
  let out = Buffer.alloc(6);
  for (let j = 0; j < 6; j++) {
    out.writeUInt8(Number(BigInt.asUintN(8, bits)), 5 - j);
    bits >>= BigInt(8);
  }
  return out;
}

// Write all 10,000 files, 6-bytes each, one for each bird's metadata header.
function writeMetadataFiles(metadata) {
  for (let i = 0; i < 10_000; i++) {
    let buffer = encodeTokenMetadata(i, metadata)
    // console.log(buffer)
    fs.writeFileSync(`./metadata/bin/${i}.bin`, buffer);
  }
}

// (for debugging) decode binary token attributes.
function decodeTokenAttributes(tokenId, metadata) {
  let bin = fs.readFileSync(`./metadata/bin/${tokenId}.bin`);
  let bits = 0n;
  for (let i = 0; i < 6; i++) {
    bits += BigInt(bin.readUInt8(i));
    if (i < 5) {
      bits <<= BigInt(8);
    }
  }
  // console.log(bits.toString(2).padStart(48, "0"))

  let out = []
  bits >>= 14n // ignore the RLE pixel count
  for (let i = metadata.length - 1; i >= 0; i--) {
    let {trait_type, bitCount, values} = metadata[i];
    let valueIndex = BigInt.asUintN(bitCount, bits);
    let value = values[valueIndex];
    bits >>= BigInt(bitCount);
    if (value !== "(absent)") { // equiv: valueIndex !== 0
      out.push({
        trait_type,
        value,
      })
    }
  }
  return out.reverse();
}

async function main() {
  let metadata = analyzeMetadata();
  writeMetadataFiles(metadata);
  // console.log(decodeTokenAttributes(6158, metadata));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });