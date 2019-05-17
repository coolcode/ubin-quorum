import BlockService, {util} from "./BlockService";
import u from "./u";
import nodes from "./config/nodes[local].json";

async function _main(){
    const bs = new BlockService();
    await bs.deployContracts();
    const owner = bs.owner;

    for(let i=0;i<nodes.length;i++) {
        const stashName = nodes[i].stashName;
        const stashNameBytes = bs.string2byte(stashName);
        const ethKey = nodes[i].ethKey;
        const isCentralBank = nodes[i].centralBank;
        u.colorLog("Creating " + stashName, 'a');
        await bs.StashFactory.createStash(stashNameBytes).send();
        u.colorLog("Registering stash for " + stashName, 'a');
        await bs.Bank.registerStash(ethKey, stashNameBytes).send();
        await bs.StashFactory.markStash(stashNameBytes);
        if (isCentralBank) {
            bs.Bank.setCentralBank(stashNameBytes);
        }
    }

    console.log("DONE!");
}

_main();

