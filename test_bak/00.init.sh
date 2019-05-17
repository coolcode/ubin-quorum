#!/bin/bash

echo "[*] testing..."
NARGS=$#
while test $# -gt 1
do
    index=`expr $NARGS - $# + 1`
    echo "'$index', '$2'"
    #truffle exec --network cb pledge.js $index $2
    #truffle exec --network mas setShieldedBalance.js $index $2
    shift
done

echo "[*] done..."
