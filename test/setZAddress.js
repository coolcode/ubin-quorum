const fs = require('fs');
var nodes = JSON.parse(fs.readFileSync('config/config.json', 'utf8'));
var PaymentAgent = artifacts.require("./PaymentAgent.sol");
var util = require('../util.js');
var u = require('./test-utils.js');
let currentNetwork = util.getCurrentNetwork(web3);
let account = web3.eth.accounts[0]|| nodes[0].ethKey;
console.log("account", account);

let stashName = u.getStashName(nodes, account);
nodes = u.removeMe(nodes, stashName);

let constellationKeys = u.getValueFromAllNodes(nodes, 'constKey');

let zAddress = fs.readFileSync('config/zAddress', 'utf8');//'0x1932c48b2bf8102ba33b4a6b545c32236e342f34';

module.exports = (done) => {
  let paymentAgent = null;

  PaymentAgent.deployed().then((instance) => {
    paymentAgent = instance;

    return paymentAgent.setZAddress(zAddress, {privateFor: constellationKeys});
  }).then((result) => {
    console.log("\tmined!, block: "+result.receipt.blockNumber+", tx hash: "+result.tx);
    console.log("");
    
    done()
  }).catch((e) => {
    console.error(e);
    done();
  });
  
}
