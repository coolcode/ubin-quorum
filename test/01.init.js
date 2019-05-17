import BlockService, {util} from "./BlockService";
import nodes from "./config/nodes[local].json";

async function _main(){
    const bs = new BlockService();
    await bs.deployContracts();
    const owner = bs.owner;

    for(let i=0;i<nodes.length;i++) {
        const stashName = nodes[i].stashName;
        const ethKey = nodes[i].ethKey;
        const isCentralBank = nodes[i].centralBank;
        await bs.StashFactory.createStash(stashName).send();
        util.colorLog("\tRegistering stash for " + stashName, 'a');
        await bs.Bank.registerStash(ethKey, stashName).send();
        await bs.StashFactory.markStash(stashName);
        if (isCentralBank) {
            bs.Bank.setCentralBank(stashName);
        }
    }

    console.log("DONE!");
}

_main();

