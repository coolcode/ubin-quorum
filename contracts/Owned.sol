pragma solidity ^0.4.24;

contract Owned {
    address owner;

    function Owned() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        _;
        //if(msg.sender!=owner) throw; _;
    }

    function getOwner() view returns (address) {
        return owner;
    }

    function changeOwner(address _newOwner) onlyOwner {
        owner = _newOwner;
    }

    function stringToBytes32(string memory source) returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function stringToBytes16(string memory source) returns (bytes16 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 16))
        }
    }

    function bytes32ToString(bytes32 source) returns (string){
        bytes memory bytesArray = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            bytesArray[i] = source[i];
        }
        return string(bytesArray);
    }
}
