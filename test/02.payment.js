import BlockService, {util} from "./BlockService";
import u from "./u";
import nodes from "./config/nodes.json";//[local]

String.prototype.lpad = function (padString, length) {
    let str = this;
    while (str.length < length)
        str = padString + str;
    return str;
};

async function _main() {
    const bs = new BlockService();
    await bs.deployContracts();
    const owner = bs.owner;
    let currentNetwork = 'a';
    for (let i = 0; i < nodes.length; i++) {
        const stashName = nodes[i].stashName;
        const stashNameBytes = bs.string2byte(stashName);
        const ethKey = nodes[i].ethKey;
        const isCentralBank = nodes[i].centralBank;
        u.colorLog("Creating " + stashName, currentNetwork);
        await bs.StashFactory.createStash(stashName).send();
        u.colorLog("Registering stash for " + stashName, currentNetwork);
        await bs.Bank.registerStash(ethKey, stashName).send();
        await bs.StashFactory.markStash(stashName);
        if (isCentralBank) {
            bs.Bank.setCentralBank(stashNameBytes);
        }
    }

    let saltStr = "cb06bf108dd249884188983c75186512";
    let salt = saltStr.lpad("0", 32);
    const bals = [2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 1000, 1200, 1400, 1500];
    for (let bankIdx = 0; bankIdx < bals.length; bankIdx++) {
        let bal = bals[bankIdx];
        // let a = [];
        // let saltInt = bal.toString(16).lpad("0", 32) + salt;
        // for (let i = 0; i < saltInt.length; i += 2) {
        //     a.push("0x" + saltInt.substr(i, 2));
        // }

        const stashName = nodes[bankIdx + 1].stashName;
        const stashNameBytes = bs.string2byte(stashName);
        const txRefBytes = bs.string2byte('R' + Date.now());
        u.colorLog("Setting " + stashName + "'s stash balance to " + bal + "...", currentNetwork);
        await bs.Bank.pledge(txRefBytes, stashNameBytes, bal).send();

        let bal_act = await bs.StashFactory.getBalanceByStatshName(stashNameBytes).call();
        u.colorLog(stashName + ' bal: ' + bal_act, currentNetwork);
    }

    currentNetwork = 'b';

    var GridlockState = ['Inactive', 'Active', 'Onhold', 'Cancelled'];//from enum in sol
    var PmtState = [ 'Pending', 'Confirmed', 'Onhold', 'Cancelled' ];
    const threshold = 4;
    await bs.GridlockQueue.setThreshold(threshold).send();
    u.colorLog("Setting GridlockQueue's threshold to " + threshold + "...", currentNetwork);

    const submitPmt = async (_txRef, s_index, r_index, amount, express, directQueue_index) => {
        const txRef = bs.string2byte(_txRef);
        const sender = bs.string2byte(nodes[s_index].stashName);
        const receiver = bs.string2byte(nodes[r_index].stashName);
        const directQueue = directQueue_index === 1 ? true : false;
        await bs.GridlockQueue.submitPmt(txRef, sender, receiver, amount, express, directQueue, "0x" + salt).send();

        u.colorLog(`${_txRef}: ${nodes[s_index].stashName}->${nodes[r_index].stashName}: ${amount}`, currentNetwork);
    }

    await submitPmt('R00001', 2, 3, 8000, 0, 0);
    await submitPmt('R00002', 3, 4, 70, 0, 0);
    await submitPmt('R00003', 4, 2, 90, 0, 0);
    await submitPmt('R00004', 2, 3, 200, 0, 0);

    let depth = await bs.GridlockQueue.getGridlockQueueDepth().call();
    u.colorLog('depth: ' + depth, currentNetwork);
    for (let i = 0; i < depth; i++) {
        let q_pmt = await bs.GridlockQueue.gridlockQueue(i).call();
        u.colorLog('------ txRef: ' + u.hex2a(q_pmt) + " --------", currentNetwork);
        let pmt = await bs.GridlockQueue.payments(q_pmt).call();
        u.colorLog('Sender: ' + u.hex2a(pmt[1]), currentNetwork);
        u.colorLog('Receiver: ' + u.hex2a(pmt[2]), currentNetwork);
        u.colorLog('Amount: ' + pmt[3], currentNetwork);
        u.colorLog('Priority: ' + pmt[5], currentNetwork);
        u.colorLog('Payment State: ' + PmtState[pmt[4]], currentNetwork);
        u.colorLog('Timestamp: ' + [pmt[7]], currentNetwork);
        u.colorLog('', currentNetwork);
    }

    console.log("DONE!");
}

_main();

