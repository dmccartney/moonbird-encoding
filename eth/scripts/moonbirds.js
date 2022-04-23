const path = require("path");
const fs = require("fs");

function loadMoonbird(tokenId) {
  let file = path.resolve(
    __dirname,
    "..",
    "..",
    "analysis",
    "token",
    "bin",
    `${tokenId}.bin`
  );
  return fs.readFileSync(file);
}

module.exports = {
  loadMoonbird,
};
