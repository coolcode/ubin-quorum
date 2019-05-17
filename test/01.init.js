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
    const currentNetwork = 'a';
    for (let i = 0; i < nodes.length; i++) {
        const stashName = nodes[i].stashName;
        const stashNameBytes = bs.string2byte(stashName);
        const ethKey = nodes[i].ethKey;
        const isCentralBank = nodes[i].centralBank;
        u.colorLog("Creating " + stashName, currentNetwork);
        await bs.StashFactory.createStash(stashNameBytes).send();
        u.colorLog("Registering stash for " + stashName, currentNetwork);
        await bs.Bank.registerStash(ethKey, stashNameBytes).send();
        await bs.StashFactory.markStash(stashNameBytes);
        if (isCentralBank) {
            bs.Bank.setCentralBank(stashNameBytes);
        }
    }

    const bals = [2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 1000, 1200, 1400, 1500];
    for (let bankIdx = 0; bankIdx < bals.length; bankIdx++) {
        let bal = bals[bankIdx];
        let saltStr = "cb06bf108dd249884188983c75186512";
        let salt = saltStr.lpad("0", 32);
        let saltInt = bal.toString(16).lpad("0", 32) + salt;
        let a = [];
        for (let i = 0; i < saltInt.length; i += 2) {
            a.push("0x" + saltInt.substr(i, 2));
        }
        // let amountHash = "0x" + sha256(a.map((i) => {
        //     return parseInt(i, 16);
        // }));

        const stashName = nodes[bankIdx + 1].stashName;
        const stashNameBytes = bs.string2byte(stashName);
        const txRefBytes = bs.string2byte('R' + Date.now());
        u.colorLog("Setting " + stashName + "'s stash balance to " + bal + "...", currentNetwork);
        await bs.Bank.pledge(txRefBytes, stashNameBytes, bal).send();
    }

    console.log("DONE!");
}

_main();

