const DeFuturesMarket = artifacts.require("DeFuturesMarket");

module.exports = function (deployer) {
  deployer.deploy(DeFuturesMarket);
};
