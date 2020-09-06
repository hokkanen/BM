pragma solidity >=0.4.22 <0.8.0;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";

contract BettingMarket {

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
    }

    struct Player {
      //the balance that can be used to make and take offers
      uint256 freeBalance;

      //the total balance including reservations
      uint256 totalBalance;

      //the amount locked in making and taking offers
      uint256 reservations;

      //the number of offers player has currently open
      uint256 numOffers;

      //the mapping to the latest accepted offer (as taker)
      address unsettledOfferAddress;
      uint256 unsettledOfferNumber;

      //the list of open offers (as maker)
      Offer[] offers;
    }

    event makerReceipt(address maker, string message, uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin);
    event takerReceipt(address taker, uint256 blockHeight, string message, uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin);
    event offerDeletion(address maker, string message, uint256 takerBlockHeight);
    event receipt(address player, string message, uint256 amount);

    address private OWNER; //contract owner
    mapping (address => Player) private PLAYERS; //mapping to playerdata
    uint256 private DONATION_BALANCE = 0; //donation balance
    uint256 private SEED_BLOCKS = 1; //the amount of blocks needed to form the seed for the rng
   
    modifier finalizeUnsettled(){
        finalizeSenderUnsettled();
        _; //Continue execution
    }
   
    modifier onlyOwner(){
        require(msg.sender == OWNER);
        _; //Continue execution
    }

    constructor() public{
        OWNER = msg.sender;
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
    
    //delete offer
    function deleteOffer(Offer storage offer) private {
        //store receipt info
        address makerId = offer.makerId;
        uint256 takerBlockHeight = offer.takerBlockHeight;
       
        //zero offer data
        offer.makerId = address(0);
        offer.makerBet = 0;
        offer.takerId = address(0);
        offer.takerBet = 0;
        offer.takerBlockHeight = 0;
        offer.takerOddsToWin = 0;
        
        emit receipt(makerId, "offer deleted", takerBlockHeight);
    }
    
    //finalize all accepted but unsettled offers related to the sender
    function finalizeSenderUnsettled() private {
      Player storage player = PLAYERS[msg.sender];
      
      //finalize taker case if open
      if(player.unsettledOfferAddress != address(0)){
        Offer storage makerOffer = PLAYERS[player.unsettledOfferAddress].offers[player.unsettledOfferNumber];
        if(makerOffer.takerBlockHeight != 0){
          require(makerOffer.takerBlockHeight + SEED_BLOCKS - 1 < block.number);
          settleOffer(makerOffer);
        }
      }
      //finalize maker cases if open
      for(uint256 i = 0; i < player.numOffers; i++){
        if(player.offers[i].takerBlockHeight != 0){
          if(player.offers[i].takerBlockHeight + SEED_BLOCKS - 1 < block.number){
            settleOffer(player.offers[i]);
          }
        }
      }
    }
     
    //finalize an unsettled offer that offer that has been accepted
    function settleOffer(Offer storage offer) private{
        require(offer.takerBlockHeight > 0); //check that offer is unsettled
        require(block.number > offer.takerBlockHeight + SEED_BLOCKS - 1); //check that offer was accepted at least SEED_BLOCKS block ago

        uint256 randomNumber = randomIntegerFromBlockhash(offer.takerBlockHeight, 100);
        if(randomNumber > offer.takerOddsToWin){ //maker wins
          //increase maker balance and remove reservation
          increaseBalance(offer.makerId, offer.takerBet);
          removeReservations(offer.makerId, offer.makerBet);

          //reduce taker balance and remove reservation
          reduceBalance(offer.takerId, offer.takerBet);
          removeReservations(offer.takerId, offer.takerBet);

          emit receipt(offer.makerId, "maker wins", SafeMath.add(offer.makerBet, offer.takerBet));
        }
        else{ //taker wins
          //increase taker balance and remove reservation
          increaseBalance(offer.takerId, offer.makerBet);
          removeReservations(offer.takerId, offer.takerBet);

          //reduce maker balance and remove reservation
          reduceBalance(offer.makerId, offer.makerBet);
          removeReservations(offer.makerId, offer.makerBet);

          emit receipt(offer.takerId, "taker wins", SafeMath.add(offer.makerBet, offer.takerBet));
        }
        deleteOffer(offer);
    }
    
    //generate random number from past blockhash
    function randomIntegerFromBlockhash(uint256 blockHeight, uint256 highestNumber) private view returns (uint256) {
        //use multiple (SEED_BLOCKS) seeds from separate blocks to avoid miner exploits
        uint256 randomNumber = 0;
        for(uint256 i = 0; i < SEED_BLOCKS; i++){
          uint256 blockHash = blockHeight;//uint256(blockhash(blockHeight + i)); //TEMPORARY HACK!!!!!!!
          randomNumber = SafeMath.add(randomNumber, blockHash);
        }
        return randomNumber % highestNumber;
    }

    //// OFFER INTERACTION FUNCTIONS ////
    
    //close an open offer, ie, an offer that has not been accepted
    function closeSenderOffer(uint256 offerNumber) public finalizeUnsettled {
        Offer storage offer = PLAYERS[msg.sender].offers[offerNumber];
        require(offer.makerBet > 0); //offer exists
        require(offer.takerBlockHeight == 0); //offer is open

        //remove reservation to free balance
        removeReservations(msg.sender, offer.makerBet);

        deleteOffer(offer);
        emit receipt(msg.sender, "open offer closed", offerNumber);
    }

    //finalize an accepted but unsettled offer
    function finalizeOffer(address id, uint256 offerNumber) public {
        settleOffer(PLAYERS[id].offers[offerNumber]);
    }
    
    //create an open offer
    function makeOffer(uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin) public payable finalizeUnsettled{
        require(makerBet > 0);
        require(takerOddsToWin <= 100);
        require(SafeMath.add(PLAYERS[msg.sender].freeBalance, msg.value) >= makerBet);

        increaseBalance(msg.sender, msg.value);
        addReservations(msg.sender, makerBet);

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
    function takeOffer(address offerAddress, uint256 offerNumber) public payable finalizeUnsettled{
        Player storage taker = PLAYERS[msg.sender];
        Offer storage newOffer = PLAYERS[offerAddress].offers[offerNumber];
        
        uint256 takerBet = newOffer.takerBet;
        require(SafeMath.add(taker.freeBalance, msg.value) >= takerBet);

        increaseBalance(msg.sender, msg.value);
        addReservations(msg.sender, takerBet);

        newOffer.takerId = msg.sender;
        newOffer.takerBlockHeight = block.number;
        taker.unsettledOfferAddress = offerAddress;
        taker.unsettledOfferNumber = offerNumber;

        emit takerReceipt(msg.sender, block.number,"accepted offer", newOffer.makerBet, newOffer.takerBet, newOffer.takerOddsToWin);
    }

    //// GENERAL FUNCTIONS ////

    function donation() public payable{
        require(msg.value > 0);
        DONATION_BALANCE = SafeMath.add(DONATION_BALANCE, msg.value);
        emit receipt(msg.sender, "donation received", msg.value);
    }

    function getContractBalance() public finalizeUnsettled returns (uint256){
        return address(this).balance;
    }

    function getFreeBalance() public finalizeUnsettled returns (uint256){
        return PLAYERS[msg.sender].freeBalance;
    }

    function getReservations() public finalizeUnsettled returns (uint256){
        return PLAYERS[msg.sender].reservations;
    }

    function getOffer(address offerAddress, uint256 offerNumber) public view returns (Offer memory){
        return PLAYERS[offerAddress].offers[offerNumber];
    }
    
    function getOfferOutcome(address offerAddress, uint256 offerNumber) public view returns (string memory){
        Offer memory offer = PLAYERS[offerAddress].offers[offerNumber];
        
        //check if offer already closed
        if(offer.makerBet == 0) 
          return "offer has been closed";

        //check if offer is still open
        if(offer.takerBlockHeight == 0) 
          return "offer still open";
        
        //check outcome
        require(block.number > offer.takerBlockHeight + SEED_BLOCKS - 1);
        uint256 randomNumber = randomIntegerFromBlockhash(offer.takerBlockHeight, 100);
        if(randomNumber > offer.takerOddsToWin){ //maker wins
            return "maker won";
        }
        else{ //taker wins
            return "taker won";
        }
    }
    
    function getOwner() public view returns (address){
        return OWNER;
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

    function withdrawDonations() public finalizeUnsettled onlyOwner{
        uint256 toTransfer = DONATION_BALANCE;
        require(toTransfer > 0);
        DONATION_BALANCE = 0;
        msg.sender.transfer(toTransfer);
        emit receipt(msg.sender, "withdrawed donations", toTransfer);
   }
}
