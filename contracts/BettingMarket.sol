pragma solidity >=0.4.22 <0.8.0;
pragma experimental ABIEncoderV2;
import "./provableAPI.sol";
import "./SafeMath.sol";

//// TO-DO ////
// -improve comments

contract BettingMarket is usingProvable{

    struct Offer {
      //maker id and contribution, ie, the amount offer taker can win
      address makerId; 
      uint256 makerBet; 
      
      //taker id and contribution, ie, the amount offer maker can win
      address takerId;
      uint256 takerBet;

      //the blockheight where accepted, 0 if offeris open
      uint256 takerBlockHeight;

      //the odds for the taker to win when she accepts the offer, between 0 and 100 (100 means taker always wins)
      uint256 takerOddsToWin;

      //the source for the randomness
      string rngSource;
    }

    struct Player {
      //the balance that can be used to make and take offers
      uint256 freeBalance;

      //the total balance including reservations
      uint256 totalBalance;

      //the amount locked in making and taking offers
      uint256 reservations;

      //the number of offers player has opened
      uint256 numOffers;

      //the mapping to the latest accepted offer (as taker)
      address unsettledOfferAddress;
      uint256 unsettledOfferNumber;

      //the list of open offers (as maker)
      Offer[] offers;
    }

    event makerReceipt(address maker, string message, uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin);
    event message(string message);
    event takerReceipt(address taker, uint256 blockHeight, string message, uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin);
    event offerDeletion(address maker, string message, uint256 takerBlockHeight);
    event receipt(address player, string message, uint256 amount);

    address private OWNER; //contract owner
    address[] private MAKERS; //maker addresses
    uint256 private DONATION_BALANCE = 0; //donation balance
    uint256 private NUM_DRAWS = 3; //the required number of draws that use different block hashes
    mapping (address => Player) private PLAYERS; //mapping player addresses to player data
    mapping (bytes32 => Offer) private QUERIES; //mapping oracle queries to offer data
   
    //finalize all accepted but unsettled offers related to the caller (msg.sender)
    modifier finalizeUnsettled(){
      Player storage player = PLAYERS[msg.sender];
      finalizeTakerUnsettled(player);
      finalizeMakerUnsettled(player);
        _; //Continue execution
    }
   
    //allow only owner calls
    modifier onlyOwner(){
        require(msg.sender == OWNER);
        _; //Continue execution
    }

    constructor() public{
      require(NUM_DRAWS % 2 == 1);
      OWNER = msg.sender;
      // provable_setProof(proofType_Ledger);
    }
 
    //// INTERNAL BALANCE FUNCTIONS ////
    
    //increase / reduce player balances
    function increaseBalance(address id, uint256 amount) private{
        PLAYERS[id].freeBalance = SafeMath.add(PLAYERS[id].freeBalance, amount);
        PLAYERS[id].totalBalance = SafeMath.add(PLAYERS[id].totalBalance, amount);
    }
    function reduceBalance(address id, uint256 amount) private{
        PLAYERS[id].freeBalance = SafeMath.sub(PLAYERS[id].freeBalance, amount);
        PLAYERS[id].totalBalance = SafeMath.sub(PLAYERS[id].totalBalance, amount);
    }

    //add remove player reservations
    function addReservations(address id, uint256 reservation) private{
        PLAYERS[id].freeBalance = SafeMath.sub(PLAYERS[id].freeBalance, reservation);
        PLAYERS[id].reservations = SafeMath.add(PLAYERS[id].reservations, reservation);
        assert(PLAYERS[id].totalBalance == SafeMath.add(PLAYERS[id].freeBalance, PLAYERS[id].reservations));
    }
    function removeReservations(address id, uint256 reservation) private{
        PLAYERS[id].freeBalance = SafeMath.add(PLAYERS[id].freeBalance, reservation);
        PLAYERS[id].reservations = SafeMath.sub(PLAYERS[id].reservations, reservation);
        assert(PLAYERS[id].totalBalance == SafeMath.add(PLAYERS[id].freeBalance, PLAYERS[id].reservations));
    }

    //// OTHER INTERNAL FUNCTIONS ////
    
    //close offer
    function closeOffer(Offer storage offer) private {
        require(offer.makerBet > 0); //offer is not closed
      
        if(offer.takerBlockHeight == 0) //check if offer is open
          removeReservations(offer.makerId, offer.makerBet); //remove reservation if offer is open
        else
          settleOffer(offer); //settle offer if offer accepted but unsettled
       
        //zero offer bets to indicate closed offer
        offer.makerBet = 0;
        offer.takerBet = 0;
        
        emit receipt(offer.makerId, "offer closed", offer.takerBlockHeight);
    }

     //create query to oracle service for rng seed
     function createQuery(Offer storage offer) private returns (uint256){     
      uint256 queryExecDelay = 0;
      uint256 rngBytesRequested = 1;
      uint256 gasForCallback = 200000;
      // uint256 queryPrice = provable_getPrice("Random");
      
      uint256 balanceBeforeQuery = address(this).balance;
      bytes32 queryId = provable_newRandomDSQuery(queryExecDelay, rngBytesRequested, gasForCallback); 
      QUERIES[queryId] = offer; 
        
      uint256 queryPrice = SafeMath.sub(balanceBeforeQuery, address(this).balance);  
      emit receipt(address(this), "provable query sent, waiting for callback...", queryPrice);
      return queryPrice;
    }

    //draws winner using the random string provided by the oracle
    function drawWinner(string memory oracleString, uint256 takerOdds) private pure returns (string memory) {
        //make sure seed is not empty
        if(bytes(oracleString).length == 0)
          return "cannot determine winner";
        //draw winner
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(oracleString))) % 100; ///////////////////////////////////////////////// THIS IS NOT RELIABLE BECAUSE MAX VAL 256?????!?!?!?
        if(randomNumber < takerOdds)
          return "taker wins";
        else
          return "maker wins";
    } 

    //draws winner using NUM_DRAWS block hashes as seeds from consecutive blocks to mitigate miner exploits
    function drawWinner(uint256 blockHeight, uint256 takerOdds) private view returns (string memory) {
        require(NUM_DRAWS % 2 == 1);
        uint256 numWins = 0;
        for(uint256 i = 0; i < NUM_DRAWS; i++){
          uint256 blockHash = uint256(blockhash(blockHeight + i));
          uint256 randomNumber = blockHash % 100;
          if(randomNumber < takerOdds){
            numWins++;
          }
        }
        if(numWins > NUM_DRAWS / 2)
          return "taker wins";
        else
          return "maker wins";
    } 

    //finalize maker cases if unfinalized
    function finalizeMakerUnsettled(Player storage player) private { 
      for(uint256 i = 0; i < player.numOffers; i++){ //loop over maker cases
        if(player.offers[i].makerBet != 0){ //make sure case is not already closed
          if(player.offers[i].takerBlockHeight != 0){ //make sure case is not open
            if(player.offers[i].takerBlockHeight + NUM_DRAWS - 1 < block.number){ //make sure enough block have passed so that the result can be determined
              closeOffer(player.offers[i]);
            }
          }
        }
      }
    }

    //finalize taker case if unfinalized
    function finalizeTakerUnsettled(Player storage player) private { 
      if(player.unsettledOfferAddress != address(0)){ //make sure a taker case exist
        Offer storage makerOffer = PLAYERS[player.unsettledOfferAddress].offers[player.unsettledOfferNumber];
        if(makerOffer.makerBet != 0){ //make sure case is not already closed
          closeOffer(makerOffer);
        }
      }
    }
     
    //finalize an unsettled offer (offer that has been accepted)
    function settleOffer(Offer memory offer) private{
        require(offer.takerBlockHeight > 0); //make sure offer is accepted
        require(block.number > offer.takerBlockHeight + NUM_DRAWS - 1); //check that offer was accepted at least NUM_DRAWS block ago

        string memory winner;
        if(strcmp(offer.rngSource, "blockHash"))
          winner = drawWinner(offer.takerBlockHeight, offer.takerOddsToWin);
        else
          winner = drawWinner(offer.rngSource, offer.takerOddsToWin);

        if(strcmp(winner, "taker wins")){ //taker wins
          //increase taker balance and remove reservation
          increaseBalance(offer.takerId, offer.makerBet);
          removeReservations(offer.takerId, offer.takerBet);

          //reduce maker balance and remove reservation
          reduceBalance(offer.makerId, offer.makerBet);
          removeReservations(offer.makerId, offer.makerBet);

          emit receipt(offer.takerId, winner, SafeMath.add(offer.makerBet, offer.takerBet));
        }
        else if(strcmp(winner, "maker wins")){ //maker wins
          //increase maker balance and remove reservation
          increaseBalance(offer.makerId, offer.takerBet);
          removeReservations(offer.makerId, offer.makerBet);

          //reduce taker balance and remove reservation
          reduceBalance(offer.takerId, offer.takerBet);
          removeReservations(offer.takerId, offer.takerBet);

          emit receipt(offer.makerId, winner, SafeMath.add(offer.makerBet, offer.takerBet));
        }
        else{
          removeReservations(offer.takerId, offer.takerBet);
          removeReservations(offer.makerId, offer.makerBet);
          emit message("cannot determine winner, returning bets");
        }
    }

    //return true if two strings are equal and false otherwise
    function strcmp(string memory a, string memory b) private pure returns (bool){
      return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    //// OFFER INTERACTION FUNCTIONS ////

    function __callback(bytes32 _queryId, string memory _result, bytes memory _proof) public{
      require(msg.sender == provable_cbAddress());

      // if(provable_randomDS_proofVerify__returnCode(_queryId, _result, _proof) != 0) {
        // emit message("oracle callback proof verification failed");
      // }
      // else{
        QUERIES[_queryId].rngSource = _result;
        emit message("oracle rng source received");
      // }
    }
    
    //close or finalize offer (open offers can only be closed by the maker)
    function closeOrFinalize(address id, uint256 offerNumber) public finalizeUnsettled{
        Offer storage offer = PLAYERS[id].offers[offerNumber];
        if(offer.takerBlockHeight == 0){ //check if offer is open
          require(msg.sender == id); //allow only maker to close open offer
          closeOffer(offer);
        }
        else if(offer.makerBet != 0){ //close offer if not open and not finalized
          closeOffer(offer);
        }
    }
    
    //create an open offer
    function makeOffer(uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin) public payable finalizeUnsettled{
        require(makerBet > 0); //bet must be positive
        require(takerOddsToWin <= 100); //odds to win cannot exceed 100
        require(SafeMath.add(PLAYERS[msg.sender].freeBalance, msg.value) >= makerBet); //maker has enough balance

        increaseBalance(msg.sender, msg.value);
        addReservations(msg.sender, makerBet);

        if(PLAYERS[msg.sender].numOffers == 0)
          MAKERS.push(msg.sender);

        Offer memory newOffer;
        newOffer.makerId = msg.sender; 
        newOffer.makerBet = makerBet; 
        newOffer.takerBet = takerBet; 
        newOffer.takerOddsToWin = takerOddsToWin;

        PLAYERS[msg.sender].offers.push(newOffer);
        PLAYERS[msg.sender].numOffers = SafeMath.add(PLAYERS[msg.sender].numOffers, 1);

        emit makerReceipt(msg.sender, "placed offer", makerBet, takerBet, takerOddsToWin);
    }

    //accept an open offer
    function takeOffer(address offerAddress, uint256 offerNumber, bool useOracle) public payable finalizeUnsettled{
        Player storage taker = PLAYERS[msg.sender];
        Offer storage offer = PLAYERS[offerAddress].offers[offerNumber];
        
        uint256 queryPrice;
        if(useOracle)
          queryPrice = createQuery(offer);
        else
          queryPrice= 0;

        require(offer.makerBet > 0); //order not closed
        require(offer.takerBlockHeight == 0); //order still open
        require(SafeMath.add(taker.freeBalance, msg.value) >= SafeMath.add(offer.takerBet, queryPrice)); //taker has enough balance

        increaseBalance(msg.sender, SafeMath.sub(msg.value, queryPrice));
        addReservations(msg.sender, offer.takerBet);

        offer.takerId = msg.sender;
        offer.takerBlockHeight = block.number;
        if(useOracle == false)
          offer.rngSource = "blockHash";

        taker.unsettledOfferAddress = offerAddress;
        taker.unsettledOfferNumber = offerNumber;

        emit takerReceipt(msg.sender, block.number,"accepted offer", offer.makerBet, offer.takerBet, offer.takerOddsToWin);
    }

    //// GENERAL FUNCTIONS ////

    function donation() public payable{
        require(msg.value > 0);
        DONATION_BALANCE = SafeMath.add(DONATION_BALANCE, msg.value);
        emit receipt(msg.sender, "donation received", msg.value);
    }

    function getContractBalance() public view  returns (uint256){
        return address(this).balance;
    }

    function getFreeBalance() public finalizeUnsettled returns (uint256){
        return PLAYERS[msg.sender].freeBalance;
    }

    function getReservations() public finalizeUnsettled returns (uint256){
        return PLAYERS[msg.sender].reservations;
    }

    function getMakerId(uint256 makerIndex) public view returns (address){
        return MAKERS[makerIndex];
    }

    function getOffer(address offerAddress, uint256 offerNumber) public view returns (Offer memory){
        return PLAYERS[offerAddress].offers[offerNumber];
    }
    
    function getOfferOutcome(address offerAddress, uint256 offerNumber) public view returns (string memory){
        Offer memory offer = PLAYERS[offerAddress].offers[offerNumber];

        //check if offer was accepted
        if(offer.takerBlockHeight == 0){ 
          if(offer.makerBet == 0)
            return "maker closed the open offer";
          else
            return "offer still open";
        }
        
        //check outcome
        require(block.number > offer.takerBlockHeight + NUM_DRAWS - 1);
        return drawWinner(offer.takerBlockHeight, offer.takerOddsToWin);
    }

    function getNumDraws() public view returns (uint256){
        return NUM_DRAWS;
    }

    
    function getOwner() public view returns (address){
        return OWNER;
    }

    function updateNumDraws(uint256 numDraws) public onlyOwner{
        NUM_DRAWS = numDraws;
    }
    
    function updateOwner(address newOwner) public onlyOwner{
        OWNER = newOwner;
    }
    
    function withdraw() public finalizeUnsettled{
        uint256 toTransfer = PLAYERS[msg.sender].freeBalance;
        require(toTransfer > 0);
        reduceBalance(msg.sender, toTransfer);
        msg.sender.transfer(toTransfer);
        emit receipt(msg.sender, "withdrawed free balance", toTransfer);
    }

    function withdrawDonations() public onlyOwner{
        uint256 toTransfer = DONATION_BALANCE;
        require(toTransfer > 0);
        DONATION_BALANCE = 0;
        msg.sender.transfer(toTransfer);
        emit receipt(msg.sender, "withdrawed donations", toTransfer);
   }
}
