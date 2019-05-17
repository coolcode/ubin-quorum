pragma solidity ^0.4.11;

import "./Owned.sol";
import "./Stash.sol";
import "./StashFactory.sol";
import "./RedeemAgent.sol";
import "./PledgeAgent.sol";

contract Bank is Owned {// Regulator node (MAS) should be the owner

    function Bank() {
        owner = msg.sender;
    }

    StashFactory public sf;
    RedeemAgent public redeemAgent;
    PledgeAgent public pledgeAgent;

    function setExternalContracts(address _sf, address _pa, address _ra) onlyOwner {
        sf = StashFactory(_sf);
        pledgeAgent = PledgeAgent(_pa);
        redeemAgent = RedeemAgent(_ra);
    }

    /* salt tracking */
    bytes16 public currentSalt; // used to retrieve shielded balance
    bytes16 public nettingSalt; // used to cache result salt after LSM calculation

    mapping(address => bytes32) public acc2stash; // @pseudo-public
    function registerStash(address _acc, bytes32 _stashName) onlyOwner {
        acc2stash[_acc] = _stashName;
    }

    function getStash(address _acc) view returns(bytes32){
        return acc2stash[_acc];
    }

    /* @pseudo-public
         during LSM / confirming pmt: banks and cb will call this to set their current salt
       @private for: [pledger]
         during pledge / redeem: MAS-regulator / cb will invoke this function
     */
    function setCurrentSalt(bytes16 _salt) {
        bytes32 _stashName = acc2stash[msg.sender];
        require(checkOwnedStash(_stashName), "not owned stash");
        // non-owner will not update salt
        if (acc2stash[msg.sender] != centralBank) {// when banks are setting salt, cb should not update its salt
            require(msg.sender == owner || !isCentralBankNode());
            // unless it invoked by MAS-regulator
        } else {
            require(isCentralBankNode());
            // when cb are setting salt, banks should not update its salt
        }
        currentSalt = _salt;
    }

    /* @pseudo-public */
    function setNettingSalt(bytes16 _salt) {
        bytes32 _stashName = acc2stash[msg.sender];
        require(checkOwnedStash(_stashName), "not owned stash");
        // non-owner will not update salt
        if (acc2stash[msg.sender] != centralBank) {// when banks are setting salt, cb should not update its salt
            require(msg.sender == owner || !isCentralBankNode());
            // unless it invoked by MAS-regulator
        } else {
            require(isCentralBankNode());
            // when cb are setting salt, banks should not update its salt
        }
        nettingSalt = _salt;
    }

    function updateCurrentSalt2NettingSalt() external{
        currentSalt = nettingSalt;
    }

    function updateCurrentSalt(bytes16 salt) external{
        currentSalt = salt;
    }

    // @pseudo-public, all the banks besides cb will not execute this action
    function setCentralBankCurrentSalt(bytes16 _salt) onlyCentralBank {
        if (isCentralBankNode()) {
            currentSalt = _salt;
        }
    }

    function getCurrentSalt() view returns (bytes16) {
        require(msg.sender == owner || checkOwnedStash(acc2stash[msg.sender]));
        return currentSalt;
    }

        /* set up central bank */
    bytes32 public centralBank;

    function setCentralBank(bytes32 _stashName) onlyOwner {
        centralBank = _stashName;
    }

    modifier onlyCentralBank() {require(acc2stash[msg.sender] == centralBank);
        _;}

    /* Suspend bank / stash */
    mapping(bytes32 => bool) public suspended;

    function suspendStash(bytes32 _stashName) onlyOwner {
        suspended[_stashName] = true;
    }

    function unSuspendStash(bytes32 _stashName) onlyOwner {
        suspended[_stashName] = false;
    }

    function isSuspended(bytes32 _stashName) external returns(bool){
        return suspended[_stashName];
    }

    //modifier notSuspended(bytes32 _stashName) { require(suspended[_stashName] == false); _; }

    event statusCode(int errorCode); // statusCode added to handle returns upon exceptions - Laks

    function emitStatusCode(int errorCode){
        emit statusCode(errorCode);
    }

    // workaround to handle exception as require/throw do not return errors - need to refactor - Laks
    modifier notSuspended(bytes32 _stashName) {
        if (suspended[_stashName]) {
            emitStatusCode(100);
            return;
        }
        _;
    }

    /* @live:
       privateFor == MAS and owner node

       This method is set to onlyonwer as pledge include off-chain process
    */
    function pledge(bytes32 _txRef, bytes32 _stashName, int _amount)
        // onlyCentralBank
    notSuspended(_stashName)
    {
        if (_stashName != centralBank || isCentralBankNode()) {
            sf.credit(_stashName, _amount);

            pledgeAgent.pledge(_txRef, _stashName, _amount);
        }
    }

    /* @live:
       privateFor = MAS and owner node */
    function redeem(bytes32 _txRef, bytes32 _stashName, int _amount)
        //onlyCentralBank
    notSuspended(_stashName)
    {
        if (_stashName != centralBank || isCentralBankNode()) {
            sf.debit(_stashName, _amount);

            redeemAgent.redeem(_txRef, _stashName, _amount);
        }
    }

    function checkOwnedStash(bytes32 _stashName) view private returns(bool){
        return sf.checkOwnedStash(_stashName, msg.sender);
    }

    function getOwnedStash() view returns (bytes32) {
        if (isCentralBankNode()) return centralBank;
        return sf.getOwnedStash();
    }

    // Central bank controls all the stashes
    function isCentralBankNode() view returns (bool) {
        return sf.isCentralBankNode();
    }

    function clear() external{

    }
}
