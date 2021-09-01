// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./IDeFuturesMarket.sol";

contract DeFuturesMarket is IDeFuturesMarket {
    // Temporary: replace with market metadata
    string public question;

    // Block height when loan ends and outcome can be finalized
    uint256 public endTime;

    // Block height when market is finalized
    uint256 public finalizationTime;

    // Is market finalized ready to distribute payout and outcome determined?
    bool public isFinal;

    // What happened at the end
    uint256 public finalOutcome;

    // Market must be initialized before it can be funded
    bool public isInitialized = false;

    // Market must be funded with collateral before it can be started
    bool public isFunded = false;

    // Temporary: owner is set to what address deployed the market contract
    address private owner;

    // Borrower provides collateral
    address private borrowerAddress;

    // Collateral required
    uint256 private collateralRequired;

    // Collateral received
    uint256 private collateralReceived;

    // Start time on market
    uint256 private startTime;

    // Map of address to outcome shares
    // buyer address => outcome => shares
    // i.e. my address => yes => 100
    //      my address => no => 20
    // Each outcome is identified by a number, 0...x
    // TODO: May need to have the reverse mapping for other use cases
    mapping(address => mapping(uint256 => uint256)) public ownerShares;
    
    // Interest per block  
    uint256 private interestPerBlock;

    // How many blocks accrue interest?
    uint256 private blockTerm;

    constructor() {
        owner = msg.sender;        
    }

    function initialize(uint256 _endTime, string calldata _question, uint256 _collateralRequired, address _borrowerAddress, uint256 _interestPerBlock, uint256 _blockTerm) external override returns (bool) {
        require(owner == msg.sender, "Only the contract owner can initialize");
        require(owner != _borrowerAddress, "Owner cannot be borrower");
        require(_endTime > block.number, "End time must be a block height greater than the current height");
        require(_collateralRequired > 0, "Collateral required must be greater than 0");
        require(_interestPerBlock > 0, "Interest is required");
        require(_blockTerm > 0, "Block term must be greater than 0");

        endTime = _endTime;
        question = _question;
        blockTerm = _blockTerm;
        borrowerAddress = _borrowerAddress;
        interestPerBlock = _interestPerBlock;
        collateralRequired = _collateralRequired;        

        isInitialized = true;
        return true;
    }

    function fund() external override payable returns (bool) {
        require(borrowerAddress == msg.sender, "Only the borrower can fund collateral");
        require(msg.value > collateralRequired, "Insufficient value");
        require(isInitialized, "Market must be initialized before funding");

        // Track what we received
        // TODO: Configure how we denominate collateral in initialize
        collateralReceived = msg.value;

        isFunded = true;
        return true;
    }

    function finalize() public override returns (bool) {
        require(block.number > endTime, "Market not finalizable");

        finalizationTime = block.number;
        isFinal = true;

        // TODO: Determine how to set the final outcome

        return true;
    }

    // TODO: This functions like withdrawal, msg.sender gets their payout
    // transfered to their address or whatever address they specify
    function distributePayout() public override returns (bool) {
        return true;
    }

    // TODO: This could estimate their payout
    function estimatePayout() public view override returns (uint256) {
        return 100000;
    }    

    // Total interest accrued on the contract, borrower must pay this interest
    // back on or before settling the outcome of the market
    function totalInterestAccrued() public view override returns (uint256) {
        uint256 blocksAccrued = block.number - startTime;
        if (blocksAccrued > blockTerm) {
            blocksAccrued = blockTerm;
        }
        return blocksAccrued * interestPerBlock;
    }

    // Returns the number of shares purchased for the specified outcome
    // dependent on what the price of each share is
    function buy(uint256 _outcome) public payable override returns (uint256) {
        require(msg.value > 0, "Value required");
        require(msg.sender != owner, "Invalid msg sender");
        require(msg.sender != borrowerAddress, "Invalid msg sender");
        require(isFunded, "Market must be funded");

        // TODO: log events for all of these state transitions and 
        // buy etc

        uint256 shares = msg.value;
        ownerShares[msg.sender][_outcome] = shares;
        return shares;
    }

    function getOutcome() external view override returns (uint256) {
        require(isFinal, "Market is not final");
        return finalOutcome;
    }
}
