const fs = require('fs');

var nodes = JSON.parse(fs.readFileSync('./config/nodes.json', 'utf8'));

var nettingConfig = [];

var stashNames = {
  "01" : "MASREGULATOR",
  "02" : "MASGSGSG",
  "03" : "BOFASG2X",
  "04" : "CHASSGSG",
  "05" : "CITISGSG",
  "06" : "CSFBSGSX",
  "07" : "DBSSSGSG",
  "08" : "HSBCSGSG",
  "09" : "MTBCSGSG",
  "10" : "OCBCSGSG",
  "11" : "SCBLSGSG",
  "12" : "UOBVSGSG",
  "13" : "XSIMSGSG"
};


var counter = 0;

nodes.forEach( enode => {
  let nodeId = enode.nodeName.slice(2,4);
  let centralBank = false;
  let regulator = false;
  let stashName = stashNames[nodeId];
  if (stashName === "MASGSGSG") centralBank = true;
  if (stashName === "MASREGULATOR") regulator = true;
  let nodeConfig = {
    "nodeId" : parseInt(nodeId),
    "host" : "3.216.212.77",
    "port": enode.rpcPort,
    "accountNumber" : 0,
    "ethKey" : enode.address,
    "constKey" : enode.constellationPublicKey,
    "stashName" : stashName,
    "enode" : enode.nodePubKey,
    "centralBank" : centralBank,
    "regulator" : regulator,
    "localport" : 3000
  };
  nettingConfig.push(nodeConfig);

  counter++;

});

nettingConfig.sort((a,b) => { return a.nodeId - b.nodeId; });

fs.writeFile('test/config/config.json', JSON.stringify(nettingConfig),
             err => { if(err) console.log(err); });

var testnet = { "nodes" : nettingConfig.map(i => i.constKey) };

fs.writeFile('testnet.json', JSON.stringify(testnet),
             err => { if(err) console.log(err); });


fs.writeFile('server/config/network.json', JSON.stringify(nettingConfig),
            err => { if(err) console.log(err); });
