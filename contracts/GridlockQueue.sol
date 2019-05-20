pragma solidity ^0.4.24;

import "./Owned.sol";
import "./SGDz.sol";
import "./StashFactory.sol";
import "./Bank.sol";

contract GridlockQueue is Owned {// Regulator node (MAS) should be the owner

    function GridlockQueue() {
        owner = msg.sender;
        agentState = AgentState.Normal;
        /* default config */
        maxQueueDepth = 100;
        timeout = 10 * 1000000000;
        /* seconds */
        proofTimeout = 20 * 1000000000;
        /* seconds */
    }


    StashFactory public sf;
    SGDz public sgdz;
    Bank public bank;

    function setExternalContracts(address _sf, address _sgdz, address _bank) onlyOwner {
        sf = StashFactory(_sf);
        sgdz = SGDz(_sgdz);
        bank = Bank(_bank);
    }

    /* payments */
    modifier isPositive(int _amount) {if (_amount <= 0) throw;
        _;}
    modifier isInvoled(bytes32 _sender, bytes32 _receiver) {
        if (!checkOwnedStash(_sender) && !checkOwnedStash(_receiver)) throw;
        _;
    }
    // Pending: waiting for value transfer in z-contract, or waiting as receiver, or waiting
    // for gridlock resolution procecss to finished
    // Confirmed: value transfer in z-contract is completed
    // Gridlocked: gridlocked payments
    //UBIN-61 : added Canceled state, UBIN-63/64 - put on hold status- Laks
    enum PmtState {Pending, Confirmed, Onhold, Cancelled}
    struct Pmt {
        bytes32 txRef;
        bytes32 sender;
        bytes32 receiver;
        int amount; // > 0
        PmtState state;
        int express;
        bool putInQueue;
        uint timestamp; // added to include sorting in API layer - Laks
        bytes16 salt;
    }

    uint public expressCount;
    bytes32[] public pmtIdx;                  // @private (list of all-trans)
    mapping(bytes32 => Pmt) public payments; // @private

    function getSalt(bytes32 _txRef) view returns (bytes16) {
        return payments[_txRef].salt;
    }

    function getOutgoingQueueDepth(bytes32 _sender) view returns (uint) {
        uint result = 0;
        for (uint i = 0; i < gridlockQueue.length; ++i) {
            if (payments[gridlockQueue[i]].sender == bank._getStash(_sender)) {
                result++;
            }
        }
        return result;
    }

    //uint public inactivationTracker; //RH - omit cancel and hold from queue

    bytes32[] public onholdPmts;

    function getOnholdCount() view returns (uint) {
        return onholdPmts.length;
    }

    function getOnholdPmtDetails(uint index) view returns (bytes32, bytes32, bytes32, int, PmtState, int, bool, uint){
        bytes32 txRef = onholdPmts[index];
        return (txRef, payments[txRef].sender, payments[txRef].receiver, payments[txRef].amount, payments[txRef].state, payments[txRef].express, payments[txRef].putInQueue, payments[txRef].timestamp);
    }

    function getPaymentAmount(bytes32 _txRef) view returns (int) {
        require(checkOwnedStash(payments[_txRef].sender) || checkOwnedStash(payments[_txRef].receiver));
        return payments[_txRef].amount;
    }

    bytes32[] public gridlockQueue;           // @private

    /* gridlock resolution facilities */
    enum GridlockState {Cancelled, Inactive, Active, Onhold, Released}
    struct GridlockedPmt {
        GridlockState state;
        bool receiverVote;  // for receiver to indicate whether inactivation is acceptable
    }
    // key should be pmt sha3 hash. But currently txRef is used
    // to globaqueue after checking queue.
    uint public globalGridlockQueueDepth;
    mapping(bytes32 => GridlockedPmt) public globalGridlockQueue;

    uint public maxQueueDepth;                 // queue depth trigger

    /* resolve sequence */
    address[] public resolveSequence;          // order of banks for round-robin in resolution steps

    uint public current;                       // current resolving bank

    modifier onlySender(bytes32 _txRef) {require(bank._getStash(tx.origin) == payments[_txRef].sender);
        _;}
    modifier onlyTxParties(bytes32 _txRef) {require(bank._getStash(tx.origin) == payments[_txRef].sender || bank._getStash(tx.origin) == payments[_txRef].receiver);
        _;}
    modifier onlyReceiver(bytes32 _txRef) {require(bank._getStash(tx.origin) == payments[_txRef].receiver);
        _;}

    modifier isYourTurn() {if (resolveSequence[current] != msg.sender) throw;
        _;}

    /* state machine */
    uint lineOpenTime;                     // time when the first participant is in line
    uint public lastResolveTime;                  // time when the last participant did the resolve round
    uint public timeout;                          // wait time for participants to line up
    uint public proofTimeout;
    uint resolveEndTime;                  // time when the current the resolve round finishes

    function setTimeout(uint _timeout) onlyOwner {
        timeout = _timeout;
    }

    enum AgentState {Normal, Lineopen, Resolving, Settling}
    AgentState public agentState;
    modifier atState(AgentState _state) {if (agentState != _state) throw;
        _;}

    event AgentStateChange(AgentState state);

    function nextState() internal {
        if (agentState == AgentState.Normal) globalGridlockQueueDepth = 0;
        if (agentState == AgentState.Lineopen) {lineOpenTime = 0;
            lastResolveTime = now;}
        if (agentState == AgentState.Resolving) {current = 0;
            resolveEndTime = now;}
        if (agentState == AgentState.Settling) resolveSequence.length = 0;
        agentState = AgentState((uint(agentState) + 1) % 4);
        AgentStateChange(agentState);
    }
    // Note that this modifier is only added to resolution method, so if nobody
    // has started to resolve then one can still join even if time's up.
    mapping(address => uint) lastPingTime;

    event Ping(uint delta, uint _timeout);

    function ping() {
        lastPingTime[msg.sender] = now;
        Ping(now - lastResolveTime, timeout);
    }

    modifier timedTransitions() {
        if (agentState == AgentState.Lineopen) {
            if (resolveSequence.length == sf.getStashNameCount() || now >= lineOpenTime + timeout) {
                nextState();
            }
        }

        /* Non-lenient timeout kick-out rule */

        int delta = getMyResolveSequenceId() - int(current);
        uint resolveTimeout;
        if (delta >= 0) {
            resolveTimeout = timeout * uint(delta);
        } else {
            resolveTimeout = timeout * (uint(delta) + resolveSequence.length);
        }
        if (lastResolveTime == 0) lastResolveTime = now;
        if (agentState == AgentState.Resolving &&
        lastResolveTime + resolveTimeout <= lastPingTime[msg.sender] &&
        lastPingTime[msg.sender] > lastPingTime[resolveSequence[current]]) {
            for (uint i = current; i < resolveSequence.length - 1; i++) {
                resolveSequence[i] = resolveSequence[i + 1];
            }
            delete resolveSequence[resolveSequence.length - 1];
            resolveSequence.length--;
        }
        _;


        /* if (agentState == AgentState.Resolving && */
        /*     lastResolveTime + timeout <= now) { */
        /*   for (uint i = current; i < resolveSequence.length-1; i++) { */
        /*     resolveSequence[i] = resolveSequence[i+1]; */
        /*   } */
        /*   delete resolveSequence[resolveSequence.length-1]; */
        /*   resolveSequence.length--; */
        /* } */
        /* _; */

    }

    /* Sync Messaging */
    mapping(bytes32 => bool) public done;
    bytes32[] inactivatedPmtRefs;
    bytes32[] doneStashes;
    bytes32[] notDoneStashes;
    bool committed;

    function arrayEqual(bytes32[] a, bytes32[] b) returns (bool) {
        if (a.length != b.length) return false;
        for (uint i = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }
    modifier hasCommitted(bytes32[] _inactivatedPmtRefs,
        bytes32[] _doneStashes,
        bytes32[] _notDoneStashes)
    {
        if (checkOwnedStash(bank._getStash(resolveSequence[current])) &&
            !(bank._getStash(resolveSequence[current]) != bank.centralBank() && isCentralBankNode())) {
            if (!committed) throw;
            else committed = false;
            if (checkOwnedStash(bank._getStash(resolveSequence[current]))) {
                if (!arrayEqual(_inactivatedPmtRefs, inactivatedPmtRefs)) throw;
                if (!arrayEqual(_doneStashes, doneStashes)) throw;
                if (!arrayEqual(_notDoneStashes, notDoneStashes)) throw;
            }
        }
        _;
    }



    /* @live:
       privateFor = MAS and participating node

       In sender node, if the account has enough liquidity the payment would
       be in status pending until the corresponding payment is made in the z-contract,
       else the payment is copyed into the gridlock */
    // timestamp is created onchain now - Zekun
    event Payment(bytes32 txRef, bool gridlocked, bool confirmPmt);

    function submitPmt(bytes32 _txRef, bytes32 _sender, bytes32 _receiver, int _amount,
        int _express, bool _putInQueue, bytes16 _salt)
    isPositive(_amount)
    isInvoled(_sender, _receiver)
//    notSuspended(_sender)
//    notSuspended(_receiver)
    {
        //JMR
        Pmt memory pmt = Pmt(_txRef,
            _sender,
            _receiver,
            _amount,
            PmtState.Pending,
            _express,
            _putInQueue,
            now,
            _salt);
        pmtIdx.push(_txRef);
        payments[_txRef] = pmt;

        //update positions
        sf.updatePosition(_sender, _receiver, _amount);

        if (_putInQueue) {
            if (checkOwnedStash(_sender)) {
                enqueue(_txRef, _express);
            }
            Payment(_txRef, true, false);
        } else {
            // enough balance (with LSM liquidity partition)
            if (checkOwnedStash(_sender) && sf.getBalanceByOwner(_sender) >= _amount) {
                if (getOutgoingQueueDepth(_sender) < 1 ||
                    (_express == 1 && expressCount < 1)) {//no queue //express and no express queue
                    Payment(_txRef, false, false);
                } else {//queue but enough balance
                    enqueue(_txRef, _express);
                    // put in end of queue
                    Payment(_txRef, true, false);
                }
            } else if (checkOwnedStash(_sender)) {// if not enough balance all goes to queue
                enqueue(_txRef, _express);
                Payment(_txRef, true, false);
            }
        }
    }
    ///////////////////////////////////////////////////////////////////

    /* UBIN-153 insert into queue based on priority level */
    function enqueue(bytes32 _txRef, int _express) internal {
        if (_express == 0) {
            gridlockQueue.push(_txRef);
        } else if (_express == 1) {
            // todo: can potentially use the updateGridlockQueue func
            if (gridlockQueue.length == expressCount) {// all express payment
                gridlockQueue.push(_txRef);
            } else {
                gridlockQueue.push(gridlockQueue[gridlockQueue.length - 1]);
                for (uint i = gridlockQueue.length - 1; i > expressCount; i--) {
                    gridlockQueue[i] = gridlockQueue[i - 1];
                }
                gridlockQueue[expressCount] = _txRef;
            }
            expressCount++;
        }
    }

    function isReceiver(bytes32 txRef) private returns (bool) {
        for (uint i = 0; i < pmtIdx.length; i++) {
            //find matching payment index.
            if (pmtIdx[i] == txRef) {
                // N.B. only MAS will control both sender and receiver stash
                if (checkOwnedStash(payments[pmtIdx[i]].receiver) &&
                    !checkOwnedStash(payments[pmtIdx[i]].sender)) {
                    return true;
                }
            }
        }
        return false;
    }


    function isNettingParticipant() view returns (bool) {
        bytes32 myStashName = getOwnedStash();
        for (uint i = 0; i < resolveSequence.length; ++i) {
            if (myStashName == bank._getStash(resolveSequence[i])) return true;
        }
        return false;
    }


    function checkOwnedStash(bytes32 _stashName) view private returns(bool){
        return sf.checkOwnedStash(_stashName, msg.sender);
    }


    function getOwnedStash() view returns (bytes32) {
        if (isCentralBankNode()) return bank.centralBank();
        return sf.getOwnedStash();
    }

    // Central bank controls all the stashes
    function isCentralBankNode() view returns (bool) {
        return sf.isCentralBankNode();
    }

    function getThreshold() view returns (uint) {
        return maxQueueDepth;
    }

    function setThreshold(uint _threshold) onlyOwner {
        maxQueueDepth = _threshold;
    }

    function getAgentState() view returns (uint) {
        if (agentState == AgentState.Normal) {
            return 0;
        } else if (agentState == AgentState.Lineopen) {
            return 1;
        } else if (agentState == AgentState.Resolving) {
            return 2;
        } else if (agentState == AgentState.Settling) {
            return 3;
        }
    }

    function getResolveSequence() view returns (address[]) {
        return resolveSequence;
    }

    function getResolveSequenceLength() view returns (uint) {
        return resolveSequence.length;
    }

    function getCurrentStash() view returns (bytes32) {
        return bank._getStash(resolveSequence[current]);
    }

    function getMyResolveSequenceId() view returns (int) {
        for (uint i = 0; i < resolveSequence.length; i++) {
            if (resolveSequence[i] == tx.origin) return int(i);
        }
        return - 1;
    }

    function getActiveGridlockCount() view returns (uint) {
        uint result = 0;
        for (uint i = 0; i < gridlockQueue.length - 1; i++) {
            Pmt pmt = payments[gridlockQueue[i]];
            GridlockedPmt g_pmt = globalGridlockQueue[pmt.txRef];
            /* to be changed */
            if (g_pmt.state == GridlockState.Active) result++;
        }
        return result;
    }

    function getHistoryLength() view returns (uint) {
        return pmtIdx.length;
    }

    function getGridlockQueueDepth() view returns (uint) {
        return gridlockQueue.length;
    }

    function getGlobalGridlockQueueDepth() view returns (uint) {
        return globalGridlockQueueDepth;
    }

    //util functions- added for debug and testing///
    //not to be used by app. //////////////////////
    //Only use from debug and testing scripts///////
    function clearQueue() {
        for (uint i = 0; i < gridlockQueue.length; i++) {
            delete globalGridlockQueue[gridlockQueue[i]];
        }
        globalGridlockQueueDepth = 0;
        gridlockQueue.length = 0;
        onholdPmts.length = 0;
        expressCount = 0;
    }

    function wipeout() {
        clearQueue();
        for (uint i = 0; i < pmtIdx.length; i++) {
            delete payments[pmtIdx[i]];
        }
        pmtIdx.length = 0;
        agentState = AgentState.Normal;
        sf.clear();
        bank.clear();
        resolveSequence.length = 0;
        current = 0;
    }
}
