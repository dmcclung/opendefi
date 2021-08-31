// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

abstract contract IDeFuturesMarket {
  function initialize(uint256 _endTime, string calldata _question, uint256 _collateralRequired, address _borrowerAddress) external virtual returns (bool);
  function fund() external virtual payable returns (bool);
  function finalize() public virtual returns (bool);  
  function distributePayout() public virtual returns (bool);
  function estimatePayout() public virtual view returns (uint256);  
  function buy(uint256 _outcome) public payable virtual returns (uint256);  
  function getOutcome() external view virtual returns (uint256);
}
