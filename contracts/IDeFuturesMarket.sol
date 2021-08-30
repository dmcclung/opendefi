// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

abstract contract IDeFuturesMarket {
  function initialize(uint256 _endTime, string calldata _question) public payable virtual returns (bool);
  function finalize() public virtual returns (bool);  
  function distributePayout() public virtual returns (bool);
  function estimatePayout() public virtual view returns (uint256);  
  function buy(uint256 _outcome) public payable virtual returns (uint256);  
  function getOutcome() public virtual returns (uint256);
}
