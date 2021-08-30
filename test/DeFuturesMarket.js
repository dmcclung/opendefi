const DeFuturesMarket = artifacts.require("DeFuturesMarket");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("DeFuturesMarket", function (/* accounts */) {
  it("should deploy without error", async function () {
    await DeFuturesMarket.deployed();
    return assert.isTrue(true);
  });
});
