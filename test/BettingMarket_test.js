const BN = require("bn.js");
const truffleAssert = require("truffle-assertions");
const { assert } = require("console");

const BettingMarket = artifacts.require("BettingMarket");
const Proxy = artifacts.require('Proxy');

contract("BettingMarket", async function(accounts){

  let bm;
  let proxy;
  let instance;

  beforeEach(async function (){
    //deploy BM and Proxy
    bm = await BettingMarket.new();
    proxy = await Proxy.new(bm.address);

    //use BM through Proxy
    instance = await BettingMarket.at(proxy.address);
  });

  //// PROXY UPGRADE TESTS (INTERNAL FUNCTIONS) ////

  it("check contract address", async function(){
    assert(bm.address === await proxy.getContract.call(), "invalid contract address");
  });

  it("allow contract upgrade for owner", async function(){
    await truffleAssert.passes(proxy.upgradeContract(accounts[0], {from: accounts[0]}));
    assert(accounts[0] === await proxy.getContract.call(), "contract upgrade failed");
  });

  it("prevent contract upgrade from non-owner", async function(){
    await truffleAssert.fails(proxy.upgradeContract(accounts[1], {from: accounts[1]}), truffleAssert.ErrorType.REVERT);
  });

  //// PROXY -> BM TESTS (EXTERNAL FUNCTIONS) ////

  it("check owner", async function(){
    assert(accounts[0] === await instance.getOwner.call(), "invalid owner");
  });

  it("allow owner update for owner", async function(){
    await instance.updateOwner(accounts[2]);
    assert(accounts[2] === await instance.getOwner.call(), "updated owner does not match");
  });

  it("prevent owner update from non-owner", async function(){
    await truffleAssert.fails(instance.updateOwner(accounts[2], {from: accounts[1]}), truffleAssert.ErrorType.REVERT);
  });

  it("15 gwei donation adds 15 gwei to Proxy balance", async function(){
    //check that instance balance is updated correctly
    const balanceBefore = new BN(await instance.getContractBalance());
    await instance.donation({value: web3.utils.toWei("15", "gwei")});
    const balanceAfter = new BN(await instance.getContractBalance());
    const expected = balanceBefore.add(new BN(web3.utils.toWei("15", "gwei")));
    assert(balanceAfter.eq(expected), "donation failed");
    //check that instance balance == Proxy balance
    const balanceProxy = new BN(await web3.eth.getBalance(proxy.address));
    assert(balanceAfter.eq(balanceProxy), "Proxy balance not equal to instance balance");
    //check that BM balance is zero
    const balanceBM = new BN(await web3.eth.getBalance(bm.address));
    assert(balanceBM.eq(new BN(0)), "BM contract balance is not zero");
  });
});
