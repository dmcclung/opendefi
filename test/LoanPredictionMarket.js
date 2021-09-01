const LoanPredictionMarket = artifacts.require("LoanPredictionMarket");

/* 
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("LoanPredictionMarket", function (accounts) {
  it("should deploy without error", async function () {
    await LoanPredictionMarket.deployed();
    return assert.isTrue(true);
  });
});
