pragma solidity >=0.4.22 <0.8.0;
import "./SafeMath.sol";
import "./Storage.sol";

//// TO-DO ////
// -improve comments
// -create more unit tests
// -createQuery() must check "call.value" instead of msg.value
// -think if oracleadaptor bytes32 queryId is safe?

contract BettingMarket is Storage{
   
    //finalize all accepted but unsettled offers related to the caller (msg.sender)
    modifier finalizeUnsettled(){
      Struct storage player = _STRUCT["PLAYERS"].id[msg.sender];
      finalizeTakerUnsettled(player);
      finalizeMakerUnsettled(player);
      _; //Continue execution
    }
   
    //allow only owner calls
    modifier onlyOwner(){
      require(msg.sender == _ADDRESS["OWNER"]);
      _; //Continue execution
    }

    constructor() public{
       _ADDRESS["OWNER"] = msg.sender; //contract owner
      initialize(address(0));
    }

    function initialize(address _oracle) public onlyOwner{
      require(!_INITIALIZED);
      _ADDRESS["ORACLE"] = _oracle; //oracleAdaptor contract address
      _UINT256["DONATION_BALANCE"] = 0; //donation balance
      updateNumDraws(1); //the required number of draws that use different block hashes (must be odd number)
      _INITIALIZED = true; //initialization status
    }
 
    //// INTERNAL BALANCE FUNCTIONS ////
    
    //increase / reduce player balances
    function increaseBalance(address id, uint256 amount) private{
        _STRUCT["PLAYERS"].id[id]._uint256["freeBalance"] = SafeMath.add(_STRUCT["PLAYERS"].id[id]._uint256["freeBalance"], amount);
        _STRUCT["PLAYERS"].id[id]._uint256["totalBalance"] = SafeMath.add(_STRUCT["PLAYERS"].id[id]._uint256["totalBalance"], amount);
    }
    function reduceBalance(address id, uint256 amount) private{
        _STRUCT["PLAYERS"].id[id]._uint256["freeBalance"] = SafeMath.sub(_STRUCT["PLAYERS"].id[id]._uint256["freeBalance"], amount);
        _STRUCT["PLAYERS"].id[id]._uint256["totalBalance"] = SafeMath.sub(_STRUCT["PLAYERS"].id[id]._uint256["totalBalance"], amount);
    }

    //add remove player _uint256["reservations"]
    function addReservations(address id, uint256 reservation) private{
        _STRUCT["PLAYERS"].id[id]._uint256["freeBalance"] = SafeMath.sub(_STRUCT["PLAYERS"].id[id]._uint256["freeBalance"], reservation);
        _STRUCT["PLAYERS"].id[id]._uint256["reservations"] = SafeMath.add(_STRUCT["PLAYERS"].id[id]._uint256["reservations"], reservation);
        assert(_STRUCT["PLAYERS"].id[id]._uint256["totalBalance"] == SafeMath.add(_STRUCT["PLAYERS"].id[id]._uint256["freeBalance"], _STRUCT["PLAYERS"].id[id]._uint256["reservations"]));
    }
    function removeReservations(address id, uint256 reservation) private{
        _STRUCT["PLAYERS"].id[id]._uint256["freeBalance"] = SafeMath.add(_STRUCT["PLAYERS"].id[id]._uint256["freeBalance"], reservation);
        _STRUCT["PLAYERS"].id[id]._uint256["reservations"] = SafeMath.sub(_STRUCT["PLAYERS"].id[id]._uint256["reservations"], reservation);
        assert(_STRUCT["PLAYERS"].id[id]._uint256["totalBalance"] == SafeMath.add(_STRUCT["PLAYERS"].id[id]._uint256["freeBalance"], _STRUCT["PLAYERS"].id[id]._uint256["reservations"]));
    }

    //// OTHER INTERNAL FUNCTIONS ////

    //check winner by calling the drawWinner function coresponding to the chosen seed type
    function checkWinner(Struct storage offer) private returns (string memory){
      string memory winner;
      if(strcmp(offer._string["rngSource"], "blockHash")){
        winner = drawWinner(offer._uint256["takerBlockHeight"], offer._uint256["takerOddsToWin"]);
      }
      else if(strcmp(offer._string["rngSource"], "oracleQuery")){
        (bool success, bytes memory seed) = _ADDRESS["ORACLE"].call(abi.encodePacked(bytes4(keccak256("getQueryOutcome(bytes32)")), offer._bytes32["queryId"]));
        if(success)
          winner = drawWinner(abi.decode(seed, (string)), offer._uint256["takerOddsToWin"]);
        else
          winner = "cannot determine winner";
      }
      else{
        winner = "cannot determine winner";
      }
      return winner;
    }
    
    //close offer
    function closeOffer(Struct storage offer) private {
        require(offer._uint256["makerBet"] > 0); //offer is not closed
      
        if(offer._uint256["takerBlockHeight"] == 0) //check if offer is open
          removeReservations(offer._address["makerId"], offer._uint256["makerBet"]); //remove reservation if offer is open
        else
          settleOffer(offer); //settle offer if offer accepted but unsettled
       
        //zero offer bets to indicate closed offer
        offer._uint256["makerBet"] = 0;
        offer._uint256["takerBet"] = 0;
        
        emit receipt(offer._address["makerId"], "offer closed", offer._uint256["takerBlockHeight"]);
    }

    //draws winner using the random string provided by the oracle
    function drawWinner(string memory oracleString, uint256 takerOdds) private pure returns (string memory) {
        //make sure seed is not empty
        bytes memory seed = bytes(oracleString);
        if(seed.length == 0)
          return "cannot determine winner";

        //draw winner, uint8 is between 0 and 255
        uint256 randomNumber = uint8(seed[0]);
        if(randomNumber < takerOdds)
          return "taker wins";
        else
          return "maker wins";
    } 

    //draws winner using NUM_DRAWS block hashes as seeds from consecutive blocks to mitigate miner exploits
    function drawWinner(uint256 blockHeight, uint256 takerOdds) private view returns (string memory) {
        require(_UINT256["NUM_DRAWS"] % 2 == 1);
        uint256 numWins = 0;
        for(uint256 i = 0; i < _UINT256["NUM_DRAWS"]; i++){
          uint256 blockHash = uint256(blockhash(blockHeight + i));
          uint256 randomNumber = blockHash % 256;
          if(randomNumber < takerOdds){
            numWins++;
          }
        }
        if(numWins > _UINT256["NUM_DRAWS"] / 2)
          return "taker wins";
        else
          return "maker wins";
    } 

    //finalize maker cases if unfinalized
    function finalizeMakerUnsettled(Struct storage player) private { 
      for(uint256 i = 0; i < player._uint256["numOffers"]; i++){ //loop over maker cases
        if(player._struct["offers"].entry[i]._uint256["makerBet"] != 0){ //make sure case is not already closed
          if(player._struct["offers"].entry[i]._uint256["takerBlockHeight"] != 0){ //make sure case is not open
            if(player._struct["offers"].entry[i]._uint256["takerBlockHeight"] + _UINT256["NUM_DRAWS"] - 1 < block.number){ //make sure enough block have passed so that the result can be determined
              closeOffer(player._struct["offers"].entry[i]);
            }
          }
        }
      }
    }

    //finalize taker case if unfinalized
    function finalizeTakerUnsettled(Struct storage player) private { 
      if(player._address["unsettledOfferAddress"] != address(0)){ //make sure a taker case exist
        Struct storage makerOffer = _STRUCT["PLAYERS"].id[player._address["unsettledOfferAddress"]]._struct["offers"].entry[player._uint256["unsettledOfferNumber"]];
        if(makerOffer._uint256["makerBet"] != 0){ //make sure case is not already closed
          closeOffer(makerOffer);
        }
      }
    }
     
    //finalize an unsettled offer (offer that has been accepted)
    function settleOffer(Struct storage offer) private{
        require(offer._uint256["takerBlockHeight"] > 0); //make sure offer is accepted
        require(block.number > offer._uint256["takerBlockHeight"] + _UINT256["NUM_DRAWS"] - 1); //check that offer was accepted at least NUM_DRAWS block ago

        string memory winner = checkWinner(offer);
        if(strcmp(winner, "taker wins")){ //taker wins
          //increase taker balance and remove reservation
          increaseBalance(offer._address["takerId"], offer._uint256["makerBet"]);
          removeReservations(offer._address["takerId"], offer._uint256["takerBet"]);

          //reduce maker balance and remove reservation
          reduceBalance(offer._address["makerId"], offer._uint256["makerBet"]);
          removeReservations(offer._address["makerId"], offer._uint256["makerBet"]);

          emit receipt(offer._address["takerId"], winner, SafeMath.add(offer._uint256["makerBet"], offer._uint256["takerBet"]));
        }
        else if(strcmp(winner, "maker wins")){ //maker wins
          //increase maker balance and remove reservation
          increaseBalance(offer._address["makerId"], offer._uint256["takerBet"]);
          removeReservations(offer._address["makerId"], offer._uint256["makerBet"]);

          //reduce taker balance and remove reservation
          reduceBalance(offer._address["takerId"], offer._uint256["takerBet"]);
          removeReservations(offer._address["takerId"], offer._uint256["takerBet"]);

          emit receipt(offer._address["makerId"], winner, SafeMath.add(offer._uint256["makerBet"], offer._uint256["takerBet"]));
        }
        else{
          removeReservations(offer._address["takerId"], offer._uint256["takerBet"]);
          removeReservations(offer._address["makerId"], offer._uint256["makerBet"]);
          emit message1("cannot determine winner, returning bets");
        }
    }

    //return true if two strings are equal and false otherwise
    function strcmp(string memory a, string memory b) private pure returns (bool){
      return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    //// OFFER INTERACTION FUNCTIONS ////
    
    //close or finalize offer (open offers can only be closed by the maker)
    function closeOrFinalize(address id, uint256 offerNumber) public finalizeUnsettled{
        Struct storage offer = _STRUCT["PLAYERS"].id[id]._struct["offers"].entry[offerNumber];
        if(offer._uint256["takerBlockHeight"] == 0){ //check if offer is open
          require(msg.sender == id); //allow only maker to close open offer
          closeOffer(offer);
        }
        else if(offer._uint256["makerBet"] != 0){ //close offer if not open and not finalized
          closeOffer(offer);
        }
    }
    
    //create an open offer, takerOddsToWin is between 0 and 256!!!
    function makeOffer(uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin) public payable finalizeUnsettled{
        require(makerBet > 0); //maker bet must be positive
        require(takerBet > 0); //taker bet must be positive
        require(takerOddsToWin <= 256); //odds to win cannot exceed 256 (percentage: takerOddsToWin / 256 * 100)
        require(SafeMath.add(_STRUCT["PLAYERS"].id[msg.sender]._uint256["freeBalance"], msg.value) >= makerBet); //maker has enough balance

        increaseBalance(msg.sender, msg.value);
        addReservations(msg.sender, makerBet);

        uint256 numOffers = _STRUCT["PLAYERS"].id[msg.sender]._uint256["numOffers"];
        _STRUCT["PLAYERS"].id[msg.sender]._struct["offers"].entry[numOffers]._address["makerId"] = msg.sender; 
        _STRUCT["PLAYERS"].id[msg.sender]._struct["offers"].entry[numOffers]._uint256["makerBet"] = makerBet; 
        _STRUCT["PLAYERS"].id[msg.sender]._struct["offers"].entry[numOffers]._uint256["takerBet"] = takerBet; 
        _STRUCT["PLAYERS"].id[msg.sender]._struct["offers"].entry[numOffers]._uint256["takerOddsToWin"] = takerOddsToWin;
        _STRUCT["PLAYERS"].id[msg.sender]._uint256["numOffers"] = SafeMath.add(_STRUCT["PLAYERS"].id[msg.sender]._uint256["numOffers"], 1);
        
        uint256 numMakers = _STRUCT["MAKERS"]._uint256["numMakers"];
        _STRUCT["MAKERS"].entry[numMakers]._address["makerId"] = msg.sender;
        _STRUCT["MAKERS"]._uint256["numMakers"] = SafeMath.add(_STRUCT["MAKERS"]._uint256["numMakers"], 1);

        emit longReceipt(msg.sender, block.number, "placed offer", makerBet, takerBet, takerOddsToWin);
    }

    //accept an open offer
    function takeOffer(address offerAddress, uint256 offerNumber, bool useOracle) public payable finalizeUnsettled{
        Struct storage taker = _STRUCT["PLAYERS"].id[msg.sender];
        Struct storage offer = _STRUCT["PLAYERS"].id[offerAddress]._struct["offers"].entry[offerNumber];
        
        uint256 queryPrice;
        if(useOracle){
          (bool success, bytes memory price) = _ADDRESS["ORACLE"].call(abi.encodePacked(bytes4(keccak256("getQueryPrice()"))));
          require(success);
          queryPrice = abi.decode(price, (uint256));
        }
        else{
          queryPrice= 0;
        }

        require(offer._uint256["makerBet"] > 0); //order not closed
        require(offer._uint256["takerBlockHeight"] == 0); //order still open
        require(SafeMath.add(taker._uint256["freeBalance"], msg.value) >= SafeMath.add(offer._uint256["takerBet"], queryPrice)); //taker has enough balance

        increaseBalance(msg.sender, SafeMath.sub(msg.value, queryPrice));
        addReservations(msg.sender, offer._uint256["takerBet"]);

        offer._address["takerId"] = msg.sender;
        offer._uint256["takerBlockHeight"] = block.number;
        if(useOracle){
           offer._string["rngSource"] = "oracleQuery";
           (bool success, bytes memory queryId) = _ADDRESS["ORACLE"].call.value(queryPrice)(abi.encodePacked(bytes4(keccak256("createQuery()"))));
           require(success);
           offer._bytes32["queryId"] = abi.decode(queryId, (bytes32));
        }
        else{
          offer._string["rngSource"] = "blockHash";
        }

        taker._address["unsettledOfferAddress"] = offerAddress;
        taker._uint256["unsettledOfferNumber"] = offerNumber;

        emit longReceipt(msg.sender, block.number, "accepted offer", offer._uint256["makerBet"], offer._uint256["takerBet"], offer._uint256["takerOddsToWin"]);
    }

    //// GENERAL FUNCTIONS ////

    function donation() public payable{
        require(msg.value > 0);
        _UINT256["DONATION_BALANCE"] = SafeMath.add(_UINT256["DONATION_BALANCE"], msg.value);
        emit receipt(msg.sender, "donation received", msg.value);
    }

    function getContractBalance() public view  returns (uint256){
        //after delegatecall "this" refers to the calling contract 
        return address(this).balance;
    }

    function getFreeBalance() public finalizeUnsettled returns (uint256){
        return _STRUCT["PLAYERS"].id[msg.sender]._uint256["freeBalance"];
    }

    function getReservations() public finalizeUnsettled returns (uint256){
        return _STRUCT["PLAYERS"].id[msg.sender]._uint256["reservations"];
    }

    function getMakerId(uint256 makerIndex) public view returns (address){
        return _STRUCT["MAKERS"].entry[makerIndex]._address["makerId"];
    }

    function getOffer(address offerAddress, uint256 offerNumber) public view returns (address, uint256, address, uint256, uint256, uint256, string memory){
      Struct storage offer = _STRUCT["PLAYERS"].id[offerAddress]._struct["offers"].entry[offerNumber];

      //maker id and contribution, ie, the amount offer taker can win
      address makerId = offer._address["makerId"];
      uint256 makerBet = offer._uint256["makerBet"];
      
      //taker id and contribution, ie, the amount offer maker can win
      address takerId = offer._address["takerId"];
      uint256 takerBet = offer._uint256["takerBet"];

      //the blockheight where accepted, 0 if offeris open
      uint256 takerBlockHeight = offer._uint256["takerBlockHeight"];

      //the odds for the taker to win when she accepts the offer, between 0 and 100 (100 means taker always wins)
      uint256 takerOddsToWin = offer._uint256["takerOddsToWin"];

      //seed source for the random number generator
      string memory rngSource = offer._string["rngSource"];

      return (makerId, makerBet, takerId, takerBet, takerBlockHeight, takerOddsToWin, rngSource);
    }
    
    function getOfferOutcome(address offerAddress, uint256 offerNumber) public returns (string memory){
        Struct storage offer = _STRUCT["PLAYERS"].id[offerAddress]._struct["offers"].entry[offerNumber];

        //check if offer was accepted
        if(offer._uint256["takerBlockHeight"] == 0){ 
          if(offer._uint256["makerBet"] == 0)
            return "offer not found"; //offer never existed or maker closed open offer
          else
            return "offer still open";
        }
        
        //check outcome
        require(block.number > offer._uint256["takerBlockHeight"] + _UINT256["NUM_DRAWS"] - 1);       
        return checkWinner(offer);
    }

    function getNumDraws() public view returns (uint256){
        return _UINT256["NUM_DRAWS"];
    }

    
    function getOwner() public view returns (address){
        return _ADDRESS["OWNER"];
    }

    function updateNumDraws(uint256 numDraws) public onlyOwner{
        require(numDraws % 2 == 1);
        _UINT256["NUM_DRAWS"] = numDraws;
    }

    function updateOracle(address newOracle) public onlyOwner{
        _ADDRESS["ORACLE"] = newOracle;
    }
    
    function updateOwner(address newOwner) public onlyOwner{
        _ADDRESS["OWNER"] = newOwner;
    }
    
    function withdraw() public finalizeUnsettled{
        uint256 toTransfer = _STRUCT["PLAYERS"].id[msg.sender]._uint256["freeBalance"];
        require(toTransfer > 0);
        reduceBalance(msg.sender, toTransfer);
        msg.sender.transfer(toTransfer);
        emit receipt(msg.sender, "withdrawed free balance", toTransfer);
    }

    function withdrawDonations() public onlyOwner{
        uint256 toTransfer = _UINT256["DONATION_BALANCE"];
        require(toTransfer > 0);
        _UINT256["DONATION_BALANCE"] = 0;
        msg.sender.transfer(toTransfer);
        emit receipt(msg.sender, "withdrawed donations", toTransfer);
   }
}
