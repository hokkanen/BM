pragma solidity >=0.4.22 <0.8.0;

contract Storage{

  struct Struct {
    mapping (address => Struct) id;
    mapping (bytes32 => Struct) byteid;
    mapping (uint256 => Struct) entry;
    mapping (string => address) _address;
    mapping (string => bool) _bool;
    mapping (string => bytes32) _bytes32;
    mapping (string => string) _string;
    mapping (string => Struct) _struct;
    mapping (string => uint256) _uint256;
  }

  mapping (string => address) internal _ADDRESS;
  mapping (string => bool) internal _BOOL;
  mapping (string => bytes32) internal _BYTES32;
  mapping (string => string) internal _STRING;
  mapping (string => Struct) internal _STRUCT;
  mapping (string => uint256) internal _UINT256;

  bool internal _INITIALIZED = false; //contract initialization status

  event makerReceipt(address maker, string message, uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin);
  event message(string message);
  event takerReceipt(address taker, uint256 blockHeight, string message, uint256 makerBet, uint256 takerBet, uint256 takerOddsToWin);
  event offerDeletion(address maker, string message, uint256 takerBlockHeight);
  event receipt(address player, string message, uint256 amount);
  
}
