const fs = require('fs');
const solc = require('solc');
const Web3 = require('web3');

// To do : Update host and port to read from deployment script
// const host = "3.216.212.77";
// const port = "22001";
const host = "127.0.0.1";
const port = "7545";
const web3 = new Web3(new Web3.providers.HttpProvider("http://" + host + ":" + port));


var sgdz_compiled = JSON.parse(fs.readFileSync('../build/contracts/Owned.json', 'utf8'));

var sgdzContract = web3.eth.contract(sgdz_compiled["abi"]);
console.log("contract: ", sgdz_compiled["contractName"]);

var sgdz = sgdzContract.new({
    from: web3.eth.accounts[0],
    data: sgdz_compiled["bytecode"],
    gas: 114700000
}, (e, contract) => {
    if (e) {
        console.log("err creating contract", e);
    } else {
        if (!contract.address) {
            console.log("Contract transaction send: TransactionHash: " + contract.transactionHash
                + " waiting to be mined...");
        } else {
            console.log("'Owned' Contract mined! Address: " + contract.address);
        }
    }
});


