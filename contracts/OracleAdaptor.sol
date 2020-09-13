pragma solidity >=0.4.22 <0.8.0;
import "./provableAPI.sol";
import "./SafeMath.sol";

contract OracleAdaptor is usingProvable{

    event message(string message);
    event outcome(address id, string message, uint256 amount);
    event query(bytes32 id, string message, uint256 amount);

    address OWNER;
    uint256 CALLBACK_GAS = 200000; //200k
    uint256 GAS_PRICE = 10000000000; //10 GWei
    uint256 QUERY_DELAY = 0; //callback delay in seconds
    uint256 RNG_BYTES = 1; //requested bytes of randomness
      
    mapping (bytes32 => string) private RNG_STRING; //is this bytes32 queryId unique and therefore safe enough!?

    constructor() public {
      OWNER = msg.sender;
      // provable_setProof(proofType_Ledger); //this only works on real network
      // provable_setCustomGasPrice(GAS_PRICE); //this only works on real network
    }

    function __callback(bytes32 _queryId, string memory _result, bytes memory _proof) public{
      require(msg.sender == provable_cbAddress());

      if(provable_randomDS_proofVerify__returnCode(_queryId, _result, _proof) != 0) {
        emit message("oracle callback proof verification failed");
      }
      else{
        RNG_STRING[_queryId] = _result;
        emit message(RNG_STRING[_queryId]);
      }
    }

    function getQueryOutcome(bytes32 queryId) public view returns (string memory){
      return RNG_STRING[queryId];
    }

    function getQueryPrice() public returns (uint256){
      uint256 gasFee = SafeMath.mul(CALLBACK_GAS, GAS_PRICE);
      uint256 queryFee = provable_getPrice("Random");
      if(queryFee == 0){
        return 0; //gasFee is also 0 in this case (first call)!
      }
      else{
        return SafeMath.add(queryFee, gasFee); //must pay queryFee and gasFee
      }
    }

    function createQuery() public payable returns (bytes32){
      uint256 queryPrice = getQueryPrice();
      require(msg.value >= queryPrice);
      uint256 balanceBeforeQuery = address(this).balance;
      bytes32 queryId = provable_newRandomDSQuery(QUERY_DELAY, RNG_BYTES, CALLBACK_GAS); 
      uint256 queryPriceRealized = SafeMath.sub(balanceBeforeQuery, address(this).balance);
      assert(queryPrice == queryPriceRealized);
      emit query(queryId, "provable query sent, waiting for callback...", queryPrice);
      return queryId;
    }

    function withdraw() public {
      require(msg.sender == OWNER);
      msg.sender.transfer(address(this).balance);
      emit outcome(msg.sender, "withdrawed", address(this).balance);
   }
}
