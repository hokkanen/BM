const BettingMarket = artifacts.require("BettingMarket");

module.exports = function(deployer) {
  deployer.deploy(BettingMarket);
};
