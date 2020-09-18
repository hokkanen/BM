const BettingMarket = artifacts.require("BettingMarket");
const Proxy = artifacts.require('Proxy');

module.exports = async function(deployer, network, accounts){
  deployer.deploy(BettingMarket).then(function(){
    return deployer.deploy(Proxy, BettingMarket.address);
  });
};
