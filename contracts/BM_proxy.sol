pragma solidity >=0.4.22 <0.8.0;
import "./Storage.sol";

contract Proxy is Storage {

  address private CONTRACT;

  constructor(address _currentAddress) public {
    _ADDRESS["OWNER"] = msg.sender;
    CONTRACT = _currentAddress;
  }

  //get current contract
  function getContract() public view returns (address){
    return CONTRACT;
  }

  //upgrade contract
  function upgradeContract(address _newAddress) public {
    require(msg.sender == _ADDRESS["OWNER"]);
    CONTRACT = _newAddress;
  }

  //fallback function
  function () payable external {
    address implementation = CONTRACT;
    require(CONTRACT != address(0));
    bytes memory data = msg.data;

    //delegate all calls to BettingMarket contract
    assembly {
      let result := delegatecall(gas, implementation, add(data, 0x20), mload(data), 0, 0)
      let size := returndatasize
      let ptr := mload(0x40)
      returndatacopy(ptr, 0, size)
      switch result
      case 0 {revert(ptr, size)}
      default {return(ptr, size)}
    }
  }
}