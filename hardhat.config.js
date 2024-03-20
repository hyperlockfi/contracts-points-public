require("@nomiclabs/hardhat-vyper");

const settings = {
  metadata: {
    // Not including the metadata hash
    // https://github.com/paulrberg/solidity-template/issues/31
    bytecodeHash: "none",
  },
  // Disable the optimizer when debugging
  // https://hardhat.org/hardhat-network/#solidity-optimizer-support
  optimizer: {
    enabled: true,
    runs: 800,
  },
};

module.exports = {
  defaultNetwork: "hardhat",
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings,
      },
      {
        version: "0.8.11",
        settings,
      },
    ],
  },
  vyper: {
    compilers: [
      { version: "0.3.3" },
      { version: "0.3.1" },
      {
        version: "0.2.4",
      },
      {
        version: "0.2.7",
      },
      {
        version: "0.2.12",
      },
    ],
  },
};
