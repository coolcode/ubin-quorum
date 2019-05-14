const fs = require('fs');
var nodes = JSON.parse(fs.readFileSync('../testnet.json', 'utf8'))['nodes'];

var PaymentAgent = artifacts.require("./PaymentAgent.sol")
var SGDz = artifacts.require("./SGDz.sol")
// var ZSLPrecompile = artifacts.require("./ZSLPrecompile.sol")


contract('HealthDapp', ([deployer]) => {

    before(async () => {
        await web3.eth.personal.unlockAccount(deployer, "", 360000);

        console.log(`"deployer" : "${deployer}",`);
        // deployer.deploy(ZSLPrecompile);
        // deployer.new(SGDz);
        // deployer.deploy(PaymentAgent, {privateFor: nodes.slice(1)});

        // deploy
        this.sgdz = await SGDz.new();
        this.paymentAgent = await PaymentAgent.new({privateFor: nodes.slice(1)});


        console.log(`"SGDz": "${this.sgdz.address}",`);
        console.log(`"PaymentAgent": "${this.paymentAgent.address}",`);
    })
});
