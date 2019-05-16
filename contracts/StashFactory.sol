pragma solidity ^0.4.11;

import "./Owned.sol";
import "./Stash.sol";

contract StashFactory is Owned {

    /* stashes */
    bytes32[] public stashNames;
    // JMR stashName => stash contract address
    mapping(bytes32 => address) public stashRegistry;

    /* @pseudo-public */
    function createStash(bytes32 _stashName) onlyOwner returns (bool){
        address stash = new Stash(_stashName);
        stashRegistry[_stashName] = stash;
        stashNames.push(_stashName);
        return true;
    }

    /* @depolyment:
       privateFor = MAS and owner node */
    function markStash(bytes32 _stashName) onlyOwner {
        Stash stash = Stash(stashRegistry[_stashName]);
        stash.mark();
    }

    function updatePosition(bytes32 _sender, bytes32 _receiver, int _amount) onlyOwner {
        Stash(stashRegistry[_sender]).dec_position(_amount);
        Stash(stashRegistry[_receiver]).inc_position(_amount);
    }

    function getBalanceByOwner(bytes32 _sender) external view returns (int256){
        return Stash(stashRegistry[_sender]).getBalance();
    }

    /* @live:
       for stashes not owned by you this returns the net bilateral position */
    function getBalanceByStatshName(bytes32 _stashName)  view returns (int) {
        Stash stash = Stash(stashRegistry[_stashName]);
        return stash.getBalance();
    }

    function getPosition(bytes32 _stashName) view returns (int) {
        Stash stash = Stash(stashRegistry[_stashName]);
        return stash.getPosition();
    }

    function netting(address _sender) onlyOwner {
        for (uint i = 0; i < stashNames.length; i++) {
            Stash stash = Stash(stashRegistry[stashNames[i]]);
            int net_diff = stash.getPosition() - stash.getBalance();
            if (net_diff > 0) {
                stash.credit(net_diff);
            } else if (net_diff < 0) {
                if (checkOwnedStash(stashNames[i], _sender)) {
                    stash.safe_debit(- net_diff);
                } else {
                    stash.debit(- net_diff);
                }
            }
        }
    }

    //given a bank, check if it is the owner
    function checkOwnedStash(bytes32 _stashName, address _msg_sender) view returns (bool) {
        if (_msg_sender == owner) return true;
        // MAS does not need to mark its own stash
        Stash stash = Stash(stashRegistry[_stashName]);
        return stash.isControlled();
    }

    function getOwnedStash() view returns (bytes32) {
        for (uint i = 0; i < stashNames.length; i++) {
            Stash stash = Stash(stashRegistry[stashNames[i]]);
            if (stash.isControlled()) {
                return stashNames[i];
            }
        }
    }

    // update balance
    function transfer(bytes32 _sender, bytes32 _receiver, int _amount, address _msg_sender) external {
        Stash sender = Stash(stashRegistry[_sender]);
        Stash receiver = Stash(stashRegistry[_receiver]);
        if (checkOwnedStash(_sender, _msg_sender)) {
            sender.safe_debit(_amount);
        } else {
            sender.debit(_amount);
        }
        receiver.credit(_amount);
    }

    function credit(bytes32 _stashName, int _amount) external{
        Stash stash = Stash(stashRegistry[_stashName]);
        stash.credit(_amount);
        stash.inc_position(_amount);
    }

    function debit(bytes32 _stashName, int _amount) external{
        Stash stash = Stash(stashRegistry[_stashName]);
        stash.safe_debit(_amount);
        stash.dec_position(_amount);
    }

    // Central bank controls all the stashes
    function isCentralBankNode() view returns (bool) {
        for (uint i = 0; i < stashNames.length; i++) {
            Stash stash = Stash(stashRegistry[stashNames[i]]);
            if (!stash.isControlled()) {
                return false;
            }
        }
        return true;
    }

    function getStashNameCount() view returns(uint){
        return stashNames.length;
    }

    function getStashNames() view returns (bytes32[]) {
        return stashNames;
    }

    function clear() external{
        stashNames.length = 0;
    }
}
