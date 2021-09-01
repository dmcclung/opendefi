const LoanPredictionMarket = artifacts.require("LoanPredictionMarket");

module.exports = function (deployer) {
  deployer.deploy(LoanPredictionMarket);
};
