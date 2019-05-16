const fs = require('fs');
const solc = require('solc');
const Web3 = require('web3');

const config = JSON.parse(fs.readFileSync(`config/config.json`, 'utf8'));
const url = config.networks[config.env].url;

const web3 = new Web3(new Web3.providers.HttpProvider(url));
const owner = web3.eth.accounts[0];
const defaultGas = 204800000;

const deploy_contract = async (contract_name) => {

    const sgdz_compiled = JSON.parse(fs.readFileSync(`../build/contracts/${contract_name}.json`, 'utf8'));
    const sgdzContract = web3.eth.contract(sgdz_compiled["abi"]);

    const contract = await sgdzContract.new({
        from: owner,
        data: sgdz_compiled["bytecode"],
        gas: 204800000
    });

    console.log(contract);
    console.log(`"${sgdz_compiled["contractName"]}": "${contract.address}",`);

    fs.writeFile('config/' + contract_name + '_Address', contract.address,
        err => {
            if (err) console.log(err);
        });

    return contract;
};

const _main = async () => {
    const SGDz = await  deploy_contract('SGDz');
    const StashFactory = await deploy_contract('StashFactory');
    const PledgeAgent = await deploy_contract('PledgeAgent');
    const RedeemAgent = await deploy_contract('RedeemAgent');
    const Bank = await deploy_contract('Bank');
    //const GridlockQueue = await deploy_contract('GridlockQueue');
    await Bank.functions.setExternalContracts(StashFactory.address, PledgeAgent.address, RedeemAgent.address).send({from: owner, gas:defaultGas});

}

_main();

