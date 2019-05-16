pragma solidity ^0.4.14;

contract PledgeAgent {

    /* pledge | redeem */
    struct Pledge {
        bytes32 txRef;
        bytes32 stashName;
        int amount;
        uint timestamp;
    }


    bytes32[] public pledgeIdx;
    mapping(bytes32 => Pledge) public pledges;

    function getPledgeHistoryLength() view returns (uint) {
        return pledgeIdx.length;
    }


    /* @live:
       privateFor = MAS and owner node */
    function pledge(bytes32 _txRef, bytes32 _stashName, int _amount) external{
        pledgeIdx.push(_txRef);
        pledges[_txRef].txRef = _txRef;
        pledges[_txRef].stashName = _stashName;
        pledges[_txRef].amount = _amount;
        pledges[_txRef].timestamp = now;
    }
}
