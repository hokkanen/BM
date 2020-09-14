pragma solidity >=0.4.22 <0.8.0;

contract usingProvable {

    uint256 GAS_PRICE = 2 * 1e10;
    uint256 QUERY_FEE = 0.004 ether;
    byte constant proofType_Ledger = 0x30;

    function __callback(bytes32 _myid, string memory _result, bytes memory _proof) public {
        return;
    }

    function provable_setProof(byte _proofP) internal {
        return;
    }

    function provable_setCustomGasPrice(uint _gasPrice) internal {
        GAS_PRICE = _gasPrice;
        return;
    }

    function provable_cbAddress() internal returns (address) {
        return msg.sender;
    }

    function provable_randomDS_proofVerify__returnCode(bytes32 _queryId, string memory _result, bytes memory _proof) internal returns (uint8) {
        return 0;
    }

    function provable_getPrice(string memory _datasource) internal returns (uint) {
        return QUERY_FEE;
    }

    function provable_newRandomDSQuery(uint _delay, uint _nbytes, uint _customGasLimit) internal returns (bytes32) {
        address(0).transfer(QUERY_FEE + GAS_PRICE * _customGasLimit);
        bytes32 queryId = 0x0;
        string memory seed = string(abi.encodePacked(blockhash(block.number)));
        __callback(queryId, seed, bytes("proofString"));
        return queryId;
    }
}
