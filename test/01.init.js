import BlockService, {util} from "./BlockService";

async function _main(){
    const bs = new BlockService();
    await bs.deployContracts();
    console.log("DONE!");
}

_main();

