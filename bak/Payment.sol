pragma solidity ^0.4.24;

import "./Owned.sol";
import "./SGDz.sol";
import "./StashFactory.sol";
import "./Bank.sol";

contract Payment is Owned {// Regulator node (MAS) should be the owner


    /* pseudo-public */
    function releasePmt(bytes32 _txRef) atState(AgentState.Normal) {
        /* require(pmtProved(_txRef)); */
        require(globalGridlockQueue[_txRef].state == GridlockState.Active ||
        globalGridlockQueue[_txRef].state == GridlockState.Inactive);
        delete globalGridlockQueue[_txRef];
        globalGridlockQueueDepth--;
        globalGridlockQueue[_txRef].state = GridlockState.Released;
        removeByValue('gridlockQueue', _txRef);
    }

    /* @pseudo-public */
    // need to orchestrate the adding to the global gridlockqueue
    function addToGlobalQueue(bytes32 _txRef) atState(AgentState.Normal) {
        globalGridlockQueueDepth++;
        globalGridlockQueue[_txRef].state = GridlockState.Active;
        globalGridlockQueue[_txRef].receiverVote = true;
        if (globalGridlockQueueDepth >= maxQueueDepth) nextState();
        if (isReceiver(_txRef)) enqueue(_txRef, payments[_txRef].express);
    }


    event Time(uint remainingTime);
    /* @pseudo-public
       Determine the resolve sequence, and broadcast gridlocked payments to
       receivers */
    function lineUp()
    atState(AgentState.Lineopen)
        //isStashOwner(_stashName)
    {
        if (lineOpenTime == 0) {lineOpenTime = now;}
        resolveSequence.push(msg.sender);
        done[bank.getStash(msg.sender)] = false;
        Time(lineOpenTime + timeout - now);
        if (resolveSequence.length == sf.getStashNameCount()) nextState();
    }


    function isParticipating(bytes32 _stashName) internal returns (bool) {
        for (uint i = 0; i < resolveSequence.length; i++) {
            if (bank.getStash(resolveSequence[i]) == _stashName) return true;
        }
        return false;
    }

    /* for testing */
    event Hash(bytes32 hash, bytes32 a);

    function doHash(uint256 _a) {
        bytes32 result = keccak256(_a);
        Hash(result, bytes32(_a));
    }

    function doHashBytes(bytes32 _a) {
        bytes32 result = keccak256(_a);
        Hash(result, _a);
    }

    function doHashBytes2(bytes32 _a, bytes32 _b) {
        bytes32 result = keccak256(_a, _b);
        Hash(result, _a);
    }

    event Answer(bool a);
    event Num(uint n);

    function verify() {
        bytes32 key = 'R1231';
        Answer(payments[key].txRef == bytes32(''));
        Num(uint(- 1));
    }

    event Array(bytes32[] a);

    bytes32[] array;

    function emitArray(bytes32 a, bytes32 b) {
        array.push(a);
        array.push(b);
        Array(array);
    }

    function bytesArrayInput(bytes32[] _input) {
        Array(_input);
    }

    /* @pseudo-public
       THIS METHOD WILL BREAK THE PSEUDO-PUBLIC STATES.
       However you should still make a pseudo-public call as we want to update PaymentAgent's
       state on all the nodes.
       You'll need to call syncPseudoPublicStates after calling this method to sync up
       the pseudo-public states. */
    event Sync(bytes32[] inactivatedPmtRefs, bytes32[] doneStashes, bytes32[] notDoneStashes);

    function doResolveRound()
    timedTransitions
    atState(AgentState.Resolving)
    isYourTurn
    returns (bool _didResolution)
    {
        lastResolveTime = now;
        bytes32 currentStash = bank.getStash(resolveSequence[current]);
        if (!checkOwnedStash(currentStash)) {return false;}
        if (currentStash != bank.centralBank() && isCentralBankNode()) {return false;}
        for (uint i = 0; i < gridlockQueue.length; i++) {
            Pmt inflow = payments[gridlockQueue[i]];
            GridlockedPmt g_inflow = globalGridlockQueue[inflow.txRef];
            /* to be changed */
            /* deactivate inflows from non-participant*/
            if (!isParticipating(inflow.sender) && g_inflow.state == GridlockState.Active) {
                g_inflow.state = GridlockState.Inactive;
                sf.updatePosition(inflow.receiver, inflow.sender, inflow.amount);
                //                Stash(stashRegistry[inflow.sender]).inc_position(inflow.amount);
                //                Stash(stashRegistry[inflow.receiver]).dec_position(inflow.amount);
            }
        }
        /* Bilateral EAF2 */
        inactivatedPmtRefs.length = 0;
        for (uint j = gridlockQueue.length - 1; j >= 0; j--) {// reverse chronological order
            if (sf.getPosition(currentStash) >= 0) break;
            // LSM liquidity partition
            Pmt pmt = payments[gridlockQueue[j]];
            GridlockedPmt g_pmt = globalGridlockQueue[pmt.txRef];
            /* to be changed */
            /* vote on your outflows */
            if (pmt.sender == currentStash && g_pmt.state == GridlockState.Active) {
                g_pmt.state = GridlockState.Inactive;
                inactivatedPmtRefs.push(pmt.txRef);
                sf.updatePosition(pmt.receiver, pmt.sender, pmt.amount);
                //                Stash(stashRegistry[pmt.sender]).inc_position(pmt.amount);
                //                Stash(stashRegistry[pmt.receiver]).dec_position(pmt.amount);
                done[pmt.receiver] = false;
            }
        }
        done[currentStash] = true;

        /* emit sync info */
        doneStashes.length = 0;
        notDoneStashes.length = 0;
        for (uint k = 0; k < resolveSequence.length; k++) {
            bytes32 stashName = bank.getStash(resolveSequence[k]);
            if (done[stashName]) doneStashes.push(stashName);
            else notDoneStashes.push(stashName);
        }
        Sync(inactivatedPmtRefs, doneStashes, notDoneStashes);

        committed = true;

        return true;
    }

    function allDone() internal returns (bool) {
        bool alldone = true;
        for (uint i = 0; i < resolveSequence.length; i++) {
            if (!done[bank.getStash(resolveSequence[i])]) {
                alldone = false;
                break;
            }
        }
        return alldone;
    }

    function receiverInactivate(bytes32 _txRef) private returns (bool _isReceiver) {
        for (uint i = 0; i < gridlockQueue.length; i++) {
            Pmt pmt = payments[gridlockQueue[i]];
            if (pmt.txRef == _txRef) {
                if (!checkOwnedStash(pmt.receiver)) return false;
                sf.updatePosition(pmt.receiver, pmt.sender, pmt.amount);
                return true;
            }
        }
    }

    event AllDone(bool allDone, uint current);
    /* @pseudo-public */
    function syncPseudoPublicStates(bytes32[] _inactivatedPmtRefs,
        bytes32[] _doneStashes,
        bytes32[] _notDoneStashes)
    atState(AgentState.Resolving)
    isYourTurn
    hasCommitted(_inactivatedPmtRefs, _doneStashes, _notDoneStashes)
    {
        /* syncing global queue */
        globalGridlockQueueDepth += _inactivatedPmtRefs.length;
        for (uint i = 0; i < _inactivatedPmtRefs.length; i++) {
            globalGridlockQueue[_inactivatedPmtRefs[i]].state = GridlockState.Inactive;
            receiverInactivate(_inactivatedPmtRefs[i]);
        }
        /* syncing done mapping */
        for (uint j = 0; j < _doneStashes.length; j++) {
            done[_doneStashes[j]] = true;
        }
        for (uint k = 0; k < _notDoneStashes.length; k++) {
            done[_notDoneStashes[k]] = false;
        }
        /* if everyone is done, enter netting phase, else pass on to the next participant */
        bool alldone = allDone();
        current++;
        if (current == resolveSequence.length) current = 0;
        AllDone(alldone, current);
        if (alldone == true) nextState();
    }

    /* @pseudo-public */
    //update private balance , update zcontract first then local balance, used at the end of the
    // LSM process only.
    event Deadlock();

    function settle() atState(AgentState.Settling) {
        /* netting by doing net balance movement */

        sf.netting(msg.sender);

        /* 1. confirm and dequeue active gridlocked payments
           2. reactivate inactive gridlocked payments and update position accordingly */
        uint beforeSettleGridlockCount = gridlockQueue.length;
        uint numGridlockedPmts = 0;
        for (uint j = 0; j < gridlockQueue.length; j++) {
            /* require(pmtProved(gridlockQueue[j])); */
            Pmt pmt = payments[gridlockQueue[j]];
            GridlockedPmt g_pmt = globalGridlockQueue[pmt.txRef];
            /* to be changed */
            if (g_pmt.state == GridlockState.Active) {
                g_pmt.state = GridlockState.Released;
                // Changed
                pmt.state = PmtState.Confirmed;
            } else if (g_pmt.state == GridlockState.Inactive) {// reactivate inactive pmts
                g_pmt.state = GridlockState.Active;
                sf.updatePosition(pmt.sender, pmt.receiver, pmt.amount);
                gridlockQueue[numGridlockedPmts] = pmt.txRef;
                numGridlockedPmts++;
            } else if (g_pmt.state == GridlockState.Onhold) {
                gridlockQueue[numGridlockedPmts] = pmt.txRef;
                numGridlockedPmts++;
            }
        }
        if (beforeSettleGridlockCount == numGridlockedPmts) {
            Deadlock();
            /* maxQueueDepth += 5; // prevent recursive gridlock */
        } else if (isNettingParticipant()) {
            bank.updateCurrentSalt2NettingSalt();
        }
        gridlockQueue.length = numGridlockedPmts;
        nextState();
    }

    // current resolve round leader can stop the LSM if timeout
    function moveOn() atState(AgentState.Settling) isYourTurn {
        require(now >= resolveEndTime + proofTimeout);
        nextState();
    }

    function pmtProved(bytes32 _txRef) external view returns (bool) {
        return sgdz.proofCompleted(_txRef);
    }

    /* @private for: [sender, receiver, (MAS)] */
    function confirmPmt(bytes32 _txRef) atState(AgentState.Normal) onlyReceiver(_txRef) {
        //comment out to get it to work
        /* require(pmtProved(_txRef)); */

        sf.transfer(payments[_txRef].sender,
            payments[_txRef].receiver,
            payments[_txRef].amount,
            msg.sender);
        payments[_txRef].state = PmtState.Confirmed;
        bank.updateCurrentSalt(payments[_txRef].salt);
    }

    // UBIN-61 ///////////////////////////////////////////////////
    // @pseudo-public == privateFor: [everyone]


    // ----------------------------------------------------------
    // UBIN-61	[Quorum] Cancel unsettled outgoing payment instruction - Laks
    // ----------------------------------------------------------
    function cancelPmtFromGlobalQueue(bytes32 _txRef)
    atState(AgentState.Normal)
        //onlySender(_txRef)
    {
        require(globalGridlockQueue[_txRef].state != GridlockState.Cancelled);

        if (globalGridlockQueue[_txRef].state != GridlockState.Onhold) {
            globalGridlockQueueDepth--;
            delete globalGridlockQueue[_txRef];
        }

        globalGridlockQueue[_txRef].state = GridlockState.Cancelled;
    }

    //anything other than agent state Normal will get rejected
    // @privateFor: [receiver, (optional MAS)]
    // call this after cancelPmtFromGlobalQueue
    function cancelPmt(bytes32 _txRef)
    atState(AgentState.Normal)
    onlySender(_txRef)
    {

        if (bank.isSuspended(payments[_txRef].sender)) {
            bank.emitStatusCode(600);
            return;
        }

        require((payments[_txRef].state == PmtState.Pending) ||
            (payments[_txRef].state == PmtState.Onhold));
        require(globalGridlockQueue[_txRef].state != GridlockState.Cancelled);

        bool changePosition = false;

        if (payments[_txRef].state == PmtState.Pending) changePosition = true;
        if (payments[_txRef].state == PmtState.Onhold) removeByValue('onholdPmts', _txRef);
        payments[_txRef].state = PmtState.Cancelled;
        //if high priority, decrement express count
        if (payments[_txRef].express == 1) {
            expressCount--;
        }
        //remove item from gridlock array
        removeByValue('gridlockQueue', _txRef);
        // instead of doing this, we have compress the cancelled item in settle()

        if (changePosition) updatePosition(_txRef, true);
        //	if (success) Status(_txRef,true);
        //inactivationTracker++;
        Status(_txRef, true);
    }

    // ---------------------------------------------------------------------------
    // UBIN-62 - Put unsettled outgoing payment instruction on hold - Laks
    // @pseudo-public
    // ---------------------------------------------------------------------------
    function holdPmtFromGlobalQueue(bytes32 _txRef)
    atState(AgentState.Normal)
        //onlySender(_txRef)
    {
        require((globalGridlockQueue[_txRef].state != GridlockState.Onhold) && (globalGridlockQueue[_txRef].state != GridlockState.Cancelled));
        GridlockedPmt g_pmt = globalGridlockQueue[_txRef];
        g_pmt.state = GridlockState.Onhold;
        globalGridlockQueueDepth--;
    }

    // ---------------------------------------------------------------------------
    // UBIN-62 - Put unsettled outgoing payment instruction on hold - Laks
    // @privateFor: [receiver, (optional MAS)]
    // ---------------------------------------------------------------------------
    event Status(bytes32 txRef, bool holdStatus);

    function holdPmt(bytes32 _txRef)
    atState(AgentState.Normal)
    onlySender(_txRef)
    {

        if (bank.isSuspended(payments[_txRef].sender)) {
            bank.emitStatusCode(700);
            return;
        }
        require(payments[_txRef].state == PmtState.Pending);
        require(globalGridlockQueue[_txRef].state != GridlockState.Onhold);
        payments[_txRef].state = PmtState.Onhold;
        onholdPmts.push(_txRef);
        updatePosition(_txRef, true);
        removeByValue('gridlockQueue', _txRef);
        if (payments[_txRef].state == PmtState.Onhold) {
            //inactivationTracker++;
            Status(_txRef, true);
        }
        else Status(_txRef, false);

        // Debug message - bank.getStash(msg.sender) is empty leading to onlySender to fail - Laks
    }

    // ---------------------------------------------------------------------------
    // UBIN-63 - Reactivate unsettled payment instruction that is on hold - Laks
    // @privateFor: [receiver, (optional MAS)]
    // ---------------------------------------------------------------------------
    function unholdPmt(bytes32 _txRef)
    atState(AgentState.Normal)
    onlySender(_txRef)
    {
        if (bank.isSuspended(payments[_txRef].sender)) {
            bank.emitStatusCode(800);
            return;
        }
        require(payments[_txRef].state == PmtState.Onhold);
        require(globalGridlockQueue[_txRef].state == GridlockState.Onhold);
        payments[_txRef].state = PmtState.Pending;
        removeByValue('onholdPmts', _txRef);
        enqueue(_txRef, payments[_txRef].express);
        updatePosition(_txRef, false);
        if (payments[_txRef].state == PmtState.Pending) {
            //inactivationTracker--;
            Status(_txRef, false);
        }
        else Status(_txRef, true);

    }
    // ---------------------------------------------------------------------------
    // UBIN-63 - Reactivate unsettled payment instruction that is on hold - Laks
    // @pseudo-public
    // called after unholdPmt
    // ---------------------------------------------------------------------------
    function unholdPmtFromGlobalQueue(bytes32 _txRef)
    atState(AgentState.Normal)
        //onlySender(_txRef)
    {
        //remove item from globalGridlockQueue
        require(globalGridlockQueue[_txRef].state == GridlockState.Onhold);
        GridlockedPmt g_pmt = globalGridlockQueue[_txRef];
        g_pmt.state = GridlockState.Active;
        globalGridlockQueueDepth++;
    }

    function updatePosition(bytes32 _txRef, bool reverse) internal {
        if (reverse) {
            sf.updatePosition(payments[_txRef].receiver, payments[_txRef].sender, payments[_txRef].amount);
        } else {
            sf.updatePosition(payments[_txRef].sender, payments[_txRef].receiver, payments[_txRef].amount);
        }
    }



    function getLineLength() view returns (uint) {
        return resolveSequence.length;
    }

    function getIsPaymentActive(bytes32 _txRef) external view returns (bool) {
        GridlockedPmt g_pmt = globalGridlockQueue[_txRef];
        /* to be changed */
        if (g_pmt.state == GridlockState.Active) {
            return true;
        } else {
            return false;
        }
    }


    // ----------------------------------------------------------
    // ----------------------------------------------------------
    function IndexOf(bytes32[] values, bytes32 value) returns (uint) {
        uint i;
        bool found = true;
        for (i = 0; i < values.length; i++) {
            if (values[i] == value) {
                found = true;
                break;
            }
        }
        if (found)
            return i;
        else
            return 99999999;
    }

    // ------------------------------
    // Implementation of UBIN-60 - Laks
    // ------------------------------
    function updatePriority(bytes32 _txRef, int _express) {
        var (i,found) = ArrayIndexOf(pmtIdx, _txRef);
        if (!found) {
            bank.emitStatusCode(300);
            return;
        }
        if (bank.isSuspended(payments[_txRef].sender)) {
            bank.emitStatusCode(400);
            return;
        }
        require(payments[_txRef].express != _express);
        // no update when the priority level is the same
        if (payments[_txRef].express == 0) {
            expressCount++;
        } else if (payments[_txRef].express == 1) {
            expressCount--;
        }
        payments[_txRef].express = _express;
        updateGridlockQueue(_txRef);
    }

    // -----------------------------------------------------
    // TO DO - To be refactored into a common untils - Laks
    // -----------------------------------------------------
    function ArrayIndexOf(bytes32[] values, bytes32 value) view internal returns (uint, bool) {
        bool found = false;
        uint i;
        for (i = 0; i < values.length; i++) {
            if (values[i] == value) {
                found = true;
                break;
            }
        }
        if (found)
            return (i, found);
        else
            return (0, found);
    }

    // ------------------------------------
    // Keep the gridlock queue sorted by 1. priority level 2. timestamp
    // Might need a more generic quick sort function in future
    // Assumes that the gridlockqueue is already sorted before the current txn
    // ------------------------------------
    function updateGridlockQueue(bytes32 _txRef){
        uint tstamp = payments[_txRef].timestamp;
        uint i;
        bytes32 curTxRef;
        uint curTstamp;
        int curExpress;
        var (index, found) = ArrayIndexOf(gridlockQueue, _txRef);
        uint j = index;
        if (payments[_txRef].express == 1) {
            // shift the txn to the left
            if (index == 0) return;
            for (i = index - 1; int(i) >= 0; i--) {// rather painful discovery that uint i>=0 doesn't work :(  - Jay
                curTxRef = gridlockQueue[i];
                curTstamp = payments[curTxRef].timestamp;
                curExpress = payments[curTxRef].express;
                if (curExpress == 0 || tstamp < curTstamp) {
                    gridlockQueue[i] = _txRef;
                    gridlockQueue[j] = curTxRef;
                    j--;
                }
            }
        } else {
            // shift the txn to the right
            if (index == gridlockQueue.length - 1) return;
            for (i = index + 1; i <= gridlockQueue.length - 1; i++) {
                curTxRef = gridlockQueue[i];
                curTstamp = payments[curTxRef].timestamp;
                curExpress = payments[curTxRef].express;
                if (curExpress == 1 || tstamp > curTstamp) {
                    gridlockQueue[i] = _txRef;
                    gridlockQueue[j] = curTxRef;
                    j++;
                }
            }
        }
    }
    // ------------------------------------

    // ------------------------------------
    // Removes the given value in an array
    // Refactored to use ArrayIndexOf - Laks
    // ------------------------------------
    function removeByValue(bytes32 arrayName, bytes32 value) internal returns (bool) {
        bytes32[] array;
        //TODO use a mapping?
        if (arrayName == 'onholdPmts') {
            array = onholdPmts;
        } else if (arrayName == 'gridlockQueue') {
            array = gridlockQueue;
            if (payments[value].express == 1) expressCount--;
        } else {
            return false;
        }
        var (index, found) = ArrayIndexOf(array, value);
        if (found) {
            for (uint i = index; i < array.length - 1; i++) {
                array[i] = array[i + 1];
            }
            delete array[array.length - 1];
            array.length--;
            return true;
        }
        return false;
    }

}
