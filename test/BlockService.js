import Web3 from "web3";
import BN from "../node_modules/bn.js/lib/bn";
import fs from 'fs';

import config from "./config/config.json";
import Bank from "../build/contracts/Bank.json"
import SGDz from "../build/contracts/SGDz.json"

export default class BlockService {
    constructor(opt) {
        this.opt = opt || this.loadOption();
        this.modules = {
            "Bank": Bank.abi,
            "SGDz": SGDz.abi,
        };
        this.names = ["SGDz", "StashFactory", "PledgeAgent", "RedeemAgent", "Bank"];//, "StashFactory", "PledgeAgent", "RedeemAgent", "Bank"
        this.web3 = new Web3(this.opt.url);
        this.owner = this.getDefaultAccounts()[0];
        this.contracts = {};
        //this.loadContracts();
        this.defaultGas = "204800000";
    }

    loadOption() {
        const env = config.env;
        return config.networks[env];
    }

    getDefaultAccounts() {
        return this.opt.accounts;
        //return await this.web3.eth.getAccounts();
    }

    async deployContracts() {
        console.log("names:", this.names);
        for (let i = 0; i < this.names.length; i++) {
            await this.deployContract(this.names[i]);
        }

        const r = await this.Bank.setExternalContracts(this.StashFactory.address, this.PledgeAgent.address, this.RedeemAgent.address).send({from: this.owner, gas: this.defaultGas});
        console.log(`set bank's external contracts. tx hash: `, r.transactionHash);
    }


    async deployContract(name) {
        console.log(`deploying "${name}"...`);
        const sgdz_compiled = JSON.parse(fs.readFileSync(`../build/contracts/${name}.json`, 'utf8'));
        //const web3Contract = new this.web3.eth.Contract(sgdz_compiled["abi"]);
        /*, null, {
            data: sgdz_compiled["bytecode"],
            from: this.owner,
            gas: this.defaultGas
        }*/
        //const deployAgent = new MethodProxy(this, web3Contract.deploy, );
        //const self = this;

        const receipt = await this.deployAgent({
            abi: sgdz_compiled["abi"],
            data: sgdz_compiled["bytecode"],
            from: this.owner,
            gas: this.defaultGas
        });

        //const receipt = await this.getReceipt(transactionHash);
        const contractAddress = receipt.contractAddress;
        console.log(`addr:`, contractAddress);
        const contract = this.loadContract(name, sgdz_compiled["abi"], contractAddress);
        console.log(`"${name}": "${contract.address}",`);
        // fs.writeFile('config/' + name + '_Address', contract.address,
        //     err => {
        //         if (err) console.log(err);
        //     });

        //return contract;
        return true;
    };

    deployAgent(opt) {
        const {abi, data, from, gas} = opt;
        const self = this;
        return new Promise(function (resolve, reject) {
            const web3Contract = new self.web3.eth.Contract(abi);
            web3Contract.deploy({data: data}).send({from: from, gas: gas}, async (error, hash) => {
                if (error) {
                    console.error(error);
                    reject(error);
                    return;
                }
                console.log("tx hash: ", hash);
                await self.confirmTx(hash);
                //resolve(hash);
                console.log("confirmed: ", hash);
                const receipt = await self.getReceipt(hash);
                //console.log("receipt: ", receipt);
                resolve(receipt);
            });
        });
    }

    loadContracts() {
        for (let name in this.modules) {
            this.loadContract(name, this.modules[name], this.opt.contracts[name]);
        }
    }

    loadContract(name, abi, address) {
        let contract = new this.web3.eth.Contract(abi, address, {gas: this.defaultGas});
        this.contracts[name] = contract;
        this[name] = new ContractProxy(this, contract.methods);
        this[name].address = contract.address;
        //console.log("methods:", contract.methods);

        this[name].events = contract.events;
        this[name].raw = contract;
        this[name].loadEventData = async (event, param, limit) => await this.loadEventData(contract, event, param, limit);
        return this[name];
    }

    getContract(name, address) {
        let contract = new this.web3.eth.Contract(this.modules[name], address, {gas: this.defaultGas});
        return new ContractProxy(this, contract.methods);
    }

    async loadEventData(contract, event, param, limit) {
        let filter;
        if (!param) {
            filter = {
                fromBlock: 0,
                toBlock: 'latest'
            };
        } else {
            //DO NOT use param as filter directly because the web3 will modify it in 'getPastEvents'
            filter = Object.assign({}, param);
        }
        if (!limit) {
            limit = 10;
        }

        let events = await contract.getPastEvents(event, filter);
        //console.log("limit: ", limit);
        //console.log(`load '${event}' event data! total: ${events.length}`);
        let items = [];
        let num = 0;
        for (let i = events.length - 1; i >= 0; i--) {
            items.push(events[i].returnValues);
            if (++num >= limit) {
                break;
            }
        }
        //console.log(`load '${event}' event data!. items:`, items);
        return items;
    }

    async unlockAccounts() {
        const accounts = this.getDefaultAccounts();
        for (let i = 0; i < accounts.length; i++) {
            await this.web3.eth.personal.unlockAccount(accounts[i], "", 360000);
        }
    }

    async confirmTx(txHash, confirmations = 0) {
        if (!txHash) {
            console.error("empty hash");
            return;
        }
        let i = 0;
        while (i++ < 100) {
            const trxConfirmations = await this.getConfirmations(txHash);
            if (trxConfirmations >= confirmations) {
                console.log('Transaction with hash ' + txHash + ' has been successfully confirmed');
                const trx = await this.web3.eth.getTransaction(txHash);
                return trx;
            }
            console.log(`waiting confirmation: ${i * 2}s`);
            await util.sleep(2 * 1000);
        }
    }

    async getConfirmations(txHash) {
        try {
            const trx = await this.web3.eth.getTransaction(txHash);
            if (trx == null) {
                return -2;
            }
            const currentBlock = await this.web3.eth.getBlockNumber();
            //console.log("trx.blockNumber",trx.blockNumber);
            return trx.blockNumber === null ? -1 : (currentBlock - trx.blockNumber) + 1
        }
        catch (error) {
            console.error(error);
        }
    }

    async getReceipt(txHash) {
        try {
            const receipt = await this.web3.eth.getTransactionReceipt(txHash);
            return receipt;
        }
        catch (error) {
            console.error(error);
        }
    }
}

export class MethodProxy {
    constructor(bs, web3method, methodArguments) {
        this.bs = bs;
        this.web3method = web3method;
        this.methodArguments = methodArguments;
    }

    send(p) {
        let self = this;
        return new Promise(function (resolve, reject) {
            self.web3method(...self.methodArguments).send(p, async (error, hash) => {
                if (error) {
                    console.error(error);
                    reject(error);
                    return;
                }
                console.log("hash: ", hash);
                await self.bs.confirmTx(hash);
                console.log("confirmed: ", hash);
                const receipt = await self.bs.getReceipt(hash);
                //console.log("receipt: ", receipt);
                resolve(receipt);
            });
        });
    }

    call(p) {
        let self = this;
        return new Promise(function (resolve, reject) {
            self.web3method(...self.methodArguments).call(p, async (error, res) => {
                if (error) {
                    console.error(error);
                    reject(error);
                    return;
                }
                resolve(res);
            });
        });
    }
}

export class ContractProxy {
    constructor(bs, web3methods) {
        this.bs = bs;
        this.web3methods = web3methods;

        return new Proxy(this, {
            get: (target, name) => {
                if (this[name]) {
                    return this[name];
                }

                //console.log(`ContractProxy target: ${target}, name: ${name}`);
                function ContractMethod() {
                    let methodArguments = [...arguments];
                    //console.log(methodArguments);
                    return new MethodProxy(bs, this.web3methods[name], methodArguments);
                }

                return ContractMethod;
            }
        });
    }
}


export class util {
    static sleep(ms) {
        return new Promise((resolve, reject) => setTimeout(resolve, ms));
    }

    static wei2eth(value, digits) {
        let _15x = new BN("1000000000000000", 10);
        let _r3 = util.bn(value).div(_15x).toString(10);
        let r = parseInt(_r3) / 1000;

        return r.toFixed(digits || 2);
    }

    static eth2wei(value) {
        let _18x = new BN("1000000000000000000", 10);
        let r = util.bn(value).mul(_18x).toString(10);
        return r;
    }

    static wei2token(value) {
        let _18x = new BN("1000000000000000000", 10);
        let r = util.bn(value).div(_18x).toString(10);
        return parseFloat(r).toFixed();
    }

    static bn2string(value) {
        return util.bn(value).toString(10);
    }

    static bn2int(value) {
        return parseInt(util.bn2string(value));
    }

    static bn2float(value) {
        return parseFloat(util.bn2string(value));
    }

    static bn2time(v) {
        return new Date(util.bn2float(v) * 1000);
    }

    static bn(value) {
        if (!value) {
            return new BN(0, 10);
        }
        if (BN.isBN(value)) {
            return value;
        } else if (typeof value === "string") {
            return new BN(value, 10);
        } else if (typeof value === "object") {
            return new BN(value.toString(), 10);
        }
        return new BN(value);
    }

    static array(v) {
        return Object.values(v);
    }
}
