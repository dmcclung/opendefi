const IDeFuturesMarket = artifacts.require("IDeFuturesMarket");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("IDeFuturesMarket", function (/* accounts */) {
  it("should deploy without error", async function () {
    await IDeFuturesMarket_test.deployed();
    return assert.isTrue(true);
  });
});
