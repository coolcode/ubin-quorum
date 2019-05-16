pragma solidity ^0.4.14;

contract RedeemAgent {

    struct Redeem {
        bytes32 txRef;
        bytes32 stashName;
        int amount;
        uint timestamp;
    }


    bytes32[] public redeemIdx;
    mapping (bytes32 => Redeem) public redeems;

    function getRedeemHistoryLength() view returns (uint) {
        return redeemIdx.length;
    }

    /* @live:
       privateFor = MAS and owner node */
    function redeem(bytes32 _txRef, bytes32 _stashName, int _amount) external{
        redeemIdx.push(_txRef);
        redeems[_txRef].txRef = _txRef;
        redeems[_txRef].stashName = _stashName;
        redeems[_txRef].amount = _amount;
        redeems[_txRef].timestamp = now;
    }
}
