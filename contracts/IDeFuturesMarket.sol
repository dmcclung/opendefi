// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

abstract contract IDeFuturesMarket {
  function initialize() public payable virtual returns (bool);
  function getEndTime() public virtual view returns (uint256);
  function getFinalizationTime() public virtual view returns (uint256);
  function finalize() public virtual returns (bool);
  function isFinalized() public virtual view returns (bool);
  function distributePayout() public virtual returns (bool);
  function estimatePayout() public virtual view returns (uint256);  
  function buy(uint256 _outcome) public payable virtual returns (uint256);
  function getQuestion() public virtual returns (string memory);
  function getOutcome() public virtual returns (uint256);
}
