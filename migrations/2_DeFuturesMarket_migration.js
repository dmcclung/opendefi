const DeFuturesMarket = artifacts.require("DeFuturesMarket");

module.exports = function (deployer) {
  deployer.deploy(DeFuturesMarket, "0x89e39306E07f212Ba14a74E70B790F49c3bE1FDC");
};
