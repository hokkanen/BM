const OracleAdaptor = artifacts.require("OracleAdaptor");

module.exports = function(deployer) {
  deployer.deploy(OracleAdaptor);
};
