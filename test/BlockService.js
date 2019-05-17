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
        this.owner = this.getFirstAccount();
        this.contracts = {};
        //this.loadContracts();
        this.defaultGas = "204800000";
        this.log_level = "info";
    }

    loadOption() {
        const env = config.env;
        return config.networks[env];
    }

    getDefaultAccounts() {
        return this.opt.accounts;
        //return await this.web3.eth.getAccounts();
    }

    getFirstAccount() {
        return this.getDefaultAccounts()[0];
    }

    async deployContracts() {
        this.log(`names: ${ this.names}`);
        for (let i = 0; i < this.names.length; i++) {
            await this.deployContract(this.names[i]);
        }

        const r = await this.Bank.setExternalContracts(this.StashFactory.address, this.PledgeAgent.address, this.RedeemAgent.address).send({from: this.owner, gas: this.defaultGas});
        this.log(`set bank's external contracts. tx hash: ${r.transactionHash}`);
    }


    async deployContract(name) {
        this.log(`deploying "${name}"...` , 'debug');
        const sgdz_compiled = JSON.parse(fs.readFileSync(`../build/contracts/${name}.json`, 'utf8'));

        const receipt = await this.deployAgent({
            abi: sgdz_compiled["abi"],
            data: sgdz_compiled["bytecode"],
            from: this.owner,
            gas: this.defaultGas
        });

        const contractAddress = receipt.contractAddress;
        this.log(`addr: ${contractAddress}` , 'debug');
        const contract = this.loadContract(name, sgdz_compiled["abi"], contractAddress);
        this.log(`"${name}": "${contract.address}",`);
        // fs.writeFile('config/' + name + '_Address', contract.address,
        //     err => {
        //         if (err) console.log(err);
        //     });

        //return contract;
        return true;
    }

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
                self.log(`tx hash: ${hash}` , 'debug');
                await self.confirmTx(hash);
                //resolve(hash);
                self.log(`confirmed: ${hash}` , 'debug');
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
        //this.log(`load '${event}' event data!. items:`, items);
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
                this.log('Transaction with hash ' + txHash + ' has been successfully confirmed', 'debug');
                const trx = await this.web3.eth.getTransaction(txHash);
                return trx;
            }
            this.log(`waiting confirmation: ${i * 2}s`, 'debug');
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
            //this.log("trx.blockNumber",trx.blockNumber);
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

    string2byte(value) {
        return this.web3.utils.fromAscii(value);
    }

    byte2string(value) {
        return this.web3.utils.toAscii(value);
    }

    log(str, level){
       if(!level || level == this.log_level){
           console.log(str);
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
        if (p === undefined) {
            p = {from: self.bs.owner, gas: self.bs.defaultGas};
        }
        return new Promise(function (resolve, reject) {
            self.web3method(...self.methodArguments).send(p, async (error, hash) => {
                if (error) {
                    console.error(error);
                    reject(error);
                    return;
                }
                self.bs.log(`tx hash: ${hash}` , 'debug');
                await self.bs.confirmTx(hash);
                //resolve(hash);
                self.bs.log(`confirmed: ${hash}` , 'debug');
                const receipt = await self.bs.getReceipt(hash);
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

                //this.log(`ContractProxy target: ${target}, name: ${name}`);
                function ContractMethod() {
                    let methodArguments = [...arguments];
                    //this.log(methodArguments);
                    return new MethodProxy(bs, this.web3methods[name], methodArguments);
                }

                return ContractMethod;
            }
        });
    }
}


export const util = {
    sleep: function (ms) {
        return new Promise((resolve, reject) => setTimeout(resolve, ms));
    },

    wei2eth: function (value, digits) {
        let _15x = new BN("1000000000000000", 10);
        let _r3 = util.bn(value).div(_15x).toString(10);
        let r = parseInt(_r3) / 1000;

        return r.toFixed(digits || 2);
    },

    eth2wei: function (value) {
        let _18x = new BN("1000000000000000000", 10);
        let r = util.bn(value).mul(_18x).toString(10);
        return r;
    },

    wei2token: function (value) {
        let _18x = new BN("1000000000000000000", 10);
        let r = util.bn(value).div(_18x).toString(10);
        return parseFloat(r).toFixed();
    },

    bn2string: function (value) {
        return util.bn(value).toString(10);
    },

    bn2int: function (value) {
        return parseInt(util.bn2string(value));
    },

    bn2float: function (value) {
        return parseFloat(util.bn2string(value));
    },

    bn2time(v) {
        return new Date(util.bn2float(v) * 1000);
    },

    bn: function (value) {
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
    },

    array: function (value) {
        return Object.values(value);
    },

}
