// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title LoanMarket
/// @notice One collateralised ETH loan with an attached parimutuel prediction market on
///         whether the borrower repays.
/// @dev The outcome resolves entirely on-chain, so no oracle is needed: a full repayment on or
///      before `maturity` resolves to Repaid; otherwise anyone can call `markDefault` after
///      `maturity`. Uses timestamps rather than block numbers because `block.number` on
///      Arbitrum Orbit chains (such as Robinhood Chain) tracks L1 blocks, not L2 blocks.
///      All payouts are pull-based. Pro-rata division rounds down, so a few wei of dust can
///      remain in the contract.
contract LoanMarket {
    enum State {
        Funding, // borrower has posted collateral; lenders are filling the principal
        Active, // principal fully funded; loan is outstanding
        Repaid,
        Defaulted,
        Cancelled // principal not fully funded in time, or withdrawn by the borrower
    }

    enum Side {
        Repay,
        Default
    }

    address public immutable borrower;
    uint256 public immutable principal;
    uint256 public immutable interest;
    uint256 public immutable collateral;
    uint256 public immutable fundingDeadline;
    uint256 public immutable maturity;

    State public state;
    bool public drawn;
    bool public collateralWithdrawn;
    uint256 public totalLent;
    mapping(address => uint256) public lent;

    /// @notice Total ETH staked on each side of the prediction market, indexed by `Side`.
    uint256[2] public pool;
    mapping(address => uint256[2]) private _stakes;

    uint256 private _locked = 1;

    event Lent(address indexed lender, uint256 amount, uint256 totalLent);
    event Funded(uint256 timestamp);
    event Drawn(uint256 amount);
    event Repaid(address indexed payer, uint256 amount);
    event Defaulted(uint256 timestamp);
    event Cancelled(uint256 timestamp);
    event LenderClaimed(address indexed lender, uint256 amount);
    event CollateralWithdrawn(uint256 amount);
    event BetPlaced(address indexed bettor, Side indexed side, uint256 amount);
    event BetClaimed(address indexed bettor, uint256 amount);

    error InvalidParams();
    error WrongState();
    error NotBorrower();
    error ZeroAmount();
    error ExceedsPrincipal();
    error FundingClosed();
    error FundingOpen();
    error PastMaturity();
    error NotMatured();
    error NotDrawn();
    error WrongAmount();
    error NothingToClaim();
    error TransferFailed();
    error Reentrancy();

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyBorrower() {
        if (msg.sender != borrower) revert NotBorrower();
        _;
    }

    modifier inState(State s) {
        if (state != s) revert WrongState();
        _;
    }

    /// @param _borrower Address that receives the principal and owes repayment.
    /// @param _principal Amount the borrower wants to borrow, in wei.
    /// @param _interest Fixed interest owed on top of principal at repayment, in wei.
    /// @param _fundingDeadline Timestamp after which an unfilled loan can be cancelled.
    /// @param _maturity Timestamp by which the borrower must repay.
    /// @dev `msg.value` is the borrower's collateral.
    constructor(address _borrower, uint256 _principal, uint256 _interest, uint256 _fundingDeadline, uint256 _maturity)
        payable {
        if (
            _borrower == address(0) || _principal == 0 || msg.value == 0 || _fundingDeadline <= block.timestamp
                || _maturity <= _fundingDeadline
        ) revert InvalidParams();

        borrower = _borrower;
        principal = _principal;
        interest = _interest;
        collateral = msg.value;
        fundingDeadline = _fundingDeadline;
        maturity = _maturity;
    }

    // ---------------------------------------------------------------- lending

    /// @notice Contribute ETH toward the principal. Cannot exceed the amount still needed.
    function lend() external payable inState(State.Funding) {
        if (block.timestamp > fundingDeadline) revert FundingClosed();
        if (msg.value == 0) revert ZeroAmount();
        uint256 newTotal = totalLent + msg.value;
        if (newTotal > principal) revert ExceedsPrincipal();

        totalLent = newTotal;
        lent[msg.sender] += msg.value;
        emit Lent(msg.sender, msg.value, newTotal);

        if (newTotal == principal) {
            state = State.Active;
            emit Funded(block.timestamp);
        }
    }

    /// @notice Cancel an unfilled loan. The borrower can cancel any time during funding;
    ///         anyone can cancel once the funding deadline has passed.
    function cancel() external inState(State.Funding) {
        if (msg.sender != borrower && block.timestamp <= fundingDeadline) revert FundingOpen();
        state = State.Cancelled;
        emit Cancelled(block.timestamp);
    }

    /// @notice Borrower takes the principal once the loan is fully funded.
    function drawdown() external onlyBorrower inState(State.Active) nonReentrant {
        if (drawn) revert WrongState();
        drawn = true;
        emit Drawn(principal);
        _send(borrower, principal);
    }

    /// @notice Repay principal plus interest in full. Anyone may repay on the borrower's behalf.
    function repay() external payable inState(State.Active) {
        if (!drawn) revert NotDrawn();
        if (block.timestamp > maturity) revert PastMaturity();
        if (msg.value != amountDue()) revert WrongAmount();
        state = State.Repaid;
        emit Repaid(msg.sender, msg.value);
    }

    /// @notice Resolve the loan as defaulted once maturity has passed without repayment.
    function markDefault() external inState(State.Active) {
        if (block.timestamp <= maturity) revert NotMatured();
        state = State.Defaulted;
        emit Defaulted(block.timestamp);
    }

    /// @notice Lenders withdraw their share once the loan has resolved.
    function claimLender() external nonReentrant {
        uint256 payout = lenderPayout(msg.sender);
        if (payout == 0) revert NothingToClaim();
        lent[msg.sender] = 0;
        emit LenderClaimed(msg.sender, payout);
        _send(msg.sender, payout);
    }

    /// @notice Borrower reclaims collateral after repaying, or after the loan is cancelled.
    function withdrawCollateral() external onlyBorrower nonReentrant {
        if (state != State.Repaid && state != State.Cancelled) revert WrongState();
        if (collateralWithdrawn) revert NothingToClaim();
        collateralWithdrawn = true;
        emit CollateralWithdrawn(collateral);
        _send(borrower, collateral);
    }

    // ------------------------------------------------------- prediction market

    /// @notice Stake ETH on whether the loan is repaid. Open until the loan resolves.
    function bet(Side side) external payable {
        if (state != State.Funding && state != State.Active) revert WrongState();
        if (block.timestamp > maturity) revert PastMaturity();
        if (msg.value == 0) revert ZeroAmount();
        pool[uint256(side)] += msg.value;
        _stakes[msg.sender][uint256(side)] += msg.value;
        emit BetPlaced(msg.sender, side, msg.value);
    }

    /// @notice Collect winnings, or a refund if the loan was cancelled or nobody backed the
    ///         winning side.
    function claimBet() external nonReentrant {
        uint256 payout = betPayout(msg.sender);
        if (payout == 0) revert NothingToClaim();
        delete _stakes[msg.sender];
        emit BetClaimed(msg.sender, payout);
        _send(msg.sender, payout);
    }

    // ------------------------------------------------------------------ views

    function amountDue() public view returns (uint256) {
        return principal + interest;
    }

    function stakes(address bettor) external view returns (uint256 repaySide, uint256 defaultSide) {
        return (_stakes[bettor][0], _stakes[bettor][1]);
    }

    /// @notice What `lender` would receive from `claimLender` right now.
    function lenderPayout(address lender) public view returns (uint256) {
        uint256 amount = lent[lender];
        if (state == State.Repaid) return amount * amountDue() / principal;
        if (state == State.Cancelled) return amount;
        if (state == State.Defaulted) {
            // Undrawn principal is still in the contract and goes back to lenders.
            uint256 recoverable = collateral + (drawn ? 0 : principal);
            return amount * recoverable / principal;
        }
        return 0;
    }

    /// @notice What `bettor` would receive from `claimBet` right now.
    function betPayout(address bettor) public view returns (uint256) {
        uint256[2] storage s = _stakes[bettor];
        if (state == State.Cancelled) return s[0] + s[1];

        uint256 win;
        if (state == State.Repaid) win = uint256(Side.Repay);
        else if (state == State.Defaulted) win = uint256(Side.Default);
        else return 0;

        uint256 winPool = pool[win];
        if (winPool == 0) return s[0] + s[1]; // nobody to pay out to, so refund everyone
        return s[win] * (pool[0] + pool[1]) / winPool;
    }

    /// @notice Market-implied probability of repayment, in basis points (0 if no bets yet).
    function impliedRepayBps() external view returns (uint256) {
        uint256 total = pool[0] + pool[1];
        return total == 0 ? 0 : pool[uint256(Side.Repay)] * 10_000 / total;
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
