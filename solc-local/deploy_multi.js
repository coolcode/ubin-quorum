const fs = require('fs');
const solc = require('solc');
const Web3 = require('web3');

// To do : Update host and port to read from deployment script
// const host = "3.216.212.77";
// const port = "22001";
const host = "127.0.0.1";
const port = "7545";
const web3 = new Web3(new Web3.providers.HttpProvider("http://" + host + ":" + port));


var sgdz_compiled = JSON.parse(fs.readFileSync('../build/contracts/SGDz.json', 'utf8'));

var sgdzContract = web3.eth.contract(sgdz_compiled["abi"]);

var sgdz = sgdzContract.new({
    from: web3.eth.accounts[0],
    data: "0x" + sgdz_compiled["bytecode"],
    gas: '114700000'
}, (e, contract) => {
    if (e) {
        console.log("err creating contract", e);
    } else {
        if (!contract.address) {
            console.log("Contract transaction send: TransactionHash: " + contract.transactionHash
                + " waiting to be mined...");
        } else {
            console.log("'SGDz' Contract mined! Address: " + contract.address);

            fs.writeFile('zAddress', contract.address,
                err => { if (err) console.log(err); });

            fs.writeFile('../test/config/zAddress', contract.address,
                err => { if (err) console.log(err); });
        }
    }
});


var pa_compiled = JSON.parse(fs.readFileSync('../build/contracts/GridlockQueue.json', 'utf8'));
console.log("contract: ", pa_compiled.contractName);

var paContract = web3.eth.contract(pa_compiled["abi"]);

var pa = paContract.new({
    from: web3.eth.accounts[0],
    data: "0x" + pa_compiled["bytecode"],
    gas: '204800000'
}, (e, contract) => {
    if (e) {
        console.log("err creating contract", e);
    } else {
        if (!contract.address) {
            console.log("Contract transaction send: TransactionHash: " + contract.transactionHash
                + " waiting to be mined...");
        } else {
            console.log("'PaymentAgent' Contract mined! Address: " + contract.address);

            fs.writeFile('pAddress', contract.address,
                err => { if (err) console.log(err); });

            fs.writeFile('../test/config/pAddress', contract.address,
                err => { if (err) console.log(err); });
        }
    }
});
