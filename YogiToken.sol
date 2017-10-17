pragma solidity ^0.4.11;

library SafeMath {
    function mul(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal constant returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal constant returns (uint256) {
        assert(b <= a);
        return a - b;
    } 

    function add(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract IERC20 {
    function totalSupply() public constant returns (uint256);
    function balanceOf(address _to) public constant returns (uint256);
    function transfer(address to, uint256 value) public;
    function transferFrom(address from, address to, uint256 value);
    function approve(address spender, uint256 value) public;
    function allowance(address owner, address spender) public constant returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract YogiToken is IERC20 {

    using SafeMath for uint256;

    enum Stage {PREICO, ICO, SUCCESS, FAILURE, REFUNDING }

    // Token properties
    string public name = "YOGI Token";
    string public symbol = "YOG";
    uint public decimals = 18;

    uint public _totalSupply = 70000000e18;

    uint public _icoSupply = 35000000e18;

    uint public _founders = 21000000e18;

    uint public _marketAllocation = 14000000e18;

    uint public softCap = 15 ether;

    bool public isGoalReached = false;

    //total sold token
    uint public totaldistribution = 0;

    // Balances for each account
    mapping (address => uint256) balances;

    // Owner of account approves the transfer of an amount to another account
    mapping (address => mapping(address => uint256)) allowed;

    // How much ETH each address has invested to this crowdsale
    mapping (address => uint256) public investedAmountOf;

    // How many distinct addresses have invested
    uint public investorCount;

    // start and end timestamps where investments are allowed (both inclusive)
    uint256 public startTime;
    uint256 public endTime;

    //stage preICO or ICO
    Stage public stage;

    // Owner of Token
    address public owner;

    // Wallet Address of Token
    address public multisig;

    // how many token units a buyer gets per wei
    uint public PRICE = 1000;

    uint public minContribAmount = 0.1 ether; // 0.1 ether

    // amount of raised money in wei
    uint256 public fundRaised = 0;

    // How much wei we have returned back to the contract after a failed crowdfund.
    uint public loadedRefund = 0;

    // How much wei we have given back to investors.
    uint public weiRefunded = 0;

    bool public crowdsale = true;

    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    event BurnToken(uint256 value);

    // Refund was processed for a contributor
    event Refund(address investor, uint weiAmount);

    event ResumeCrowdsale();
    event PausedCrowdsale();

    event MinimumGoalReached();

    // modifier to allow only owner has full control on the function
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    modifier isCrowdsale() {
        require(crowdsale);
        _;
    }

    // Constructor
    // @notice YogiToken Contract
    // @return the transaction address
    function YogiToken(uint256 _startTime, uint256 _endTime, address _multisig) public payable{
      require(_startTime >= getNow() &&_endTime >= _startTime &&_multisig!=0x0);

        startTime = _startTime;
        endTime = _endTime;
        multisig = _multisig;
        balances[multisig] = _totalSupply;
        stage = Stage.PREICO;
        owner=msg.sender;
    }


    // Payable method
    // @notice Anyone can buy the tokens on tokensale by paying ether
    function () public payable isCrowdsale {
        tokensale(msg.sender);
    }

    // @notice tokensale
    // @param recipient The address of the recipient
    // @return the transaction address and send the event as Transfer
    function tokensale(address _to) public payable isCrowdsale {
        require(_to != 0x0);
        require(validPurchase());

        uint256 weiAmount = msg.value;
        uint tokens = weiAmount.mul(getPrice());

        uint timebasedBonus = tokens.mul(getTimebasedBonusRate()).div(100);

        tokens = tokens.add(timebasedBonus);

        require (tokens < _icoSupply);

        if(investedAmountOf[_to] == 0) {
           // A new investor
           investorCount++;
        }

        // Update investor
        investedAmountOf[_to] = investedAmountOf[_to].add(weiAmount);
        balances[_to] = balances[_to].add(tokens);

        // Update totals
        fundRaised = fundRaised.add(weiAmount);
        totaldistribution = totaldistribution.add(tokens);

        balances[multisig] = balances[multisig].sub(tokens);
        _icoSupply = _icoSupply.sub(tokens);

        TokenPurchase(msg.sender, _to, weiAmount, tokens);

        forwardFunds();

        if (!isGoalReached && fundRaised >= softCap) {
            isGoalReached = true;
            MinimumGoalReached();
        }
    }

    // send ether to the fund collection wallet
    // override to create custom fund forwarding mechanisms
    function forwardFunds() internal {
        multisig.transfer(msg.value);
    }

    // @return true if the transaction can buy tokens
    function validPurchase() internal constant returns (bool) {
        bool withinPeriod = getNow() >= startTime && getNow() <= endTime;
        bool nonZeroPurchase = msg.value != 0;
        bool minContribution = minContribAmount <= msg.value;
        if (stage == Stage.PREICO) {
            uint nowTime = getNow();
            uint days10 = startTime + (10 days * 1000);
            if (nowTime > days10) {
                stage = Stage.ICO;
            }
        }
        return withinPeriod && nonZeroPurchase && minContribution;
    }

    // @return true if the crowdsale has raised enough money to be successful.
    function isMinimumGoalReached() public constant returns (bool reached) {
        return fundRaised >= softCap;
    }

    function updateICOStatus() public onlyOwner {
        if (hasEnded() && fundRaised >= softCap) {
            stage = Stage.SUCCESS;
        } else if (hasEnded()) {
            stage = Stage.FAILURE;
        }
    }

    modifier isFailure {
        require (stage == Stage.FAILURE);
        _;
    }

    modifier isRefunding {
        require (stage == Stage.REFUNDING);
        _;
    }

    //  Allow load refunds back on the contract for the refunding. The team can transfer the funds back on the smart contract in the case the minimum goal was not reached.
    function loadRefund() public payable isFailure {
        require(msg.value != 0);
        loadedRefund = loadedRefund.add(msg.value);
        if (loadedRefund >= fundRaised) {
            stage = Stage.REFUNDING;
        }
    }

    // Investors can claim refund.
    // Note that any refunds from indirect buyers should be handled separately, and not through this contract.
    function refund() public isRefunding {
        uint256 weiValue = investedAmountOf[msg.sender];
        require (weiValue != 0);

        msg.sender.transfer(weiValue);
        investedAmountOf[msg.sender] = 0;
        balances[msg.sender] = 0;
        weiRefunded = weiRefunded.add(weiValue);
        Refund(msg.sender, weiValue);
    }

    // Get the time-based bonus rate
    function getTimebasedBonusRate() internal constant returns (uint256) {
        uint256 bonusRate = 0;
        uint nowTime = getNow();
        uint days10 = startTime + (10 days * 1000);
        if (nowTime <= days10) {
            bonusRate = 10;
        }

        return bonusRate;
    }

    function changeStartTime(uint256 _startTime) public onlyOwner {
        require(startTime > getNow());
    	startTime = _startTime;
    }

    function changeEndTime(uint256 _endTime) public onlyOwner {
        require(startTime > getNow());
    	endTime = _endTime;
    }

    // Halt or Resume Crowd Sale / ICO
    function pauseResumeCrowdsale(bool _crowdsale) public onlyOwner {
        crowdsale = _crowdsale;
        if (crowdsale)
            ResumeCrowdsale();
        else
           PausedCrowdsale();
    }

    function burnToken() public onlyOwner {
        require(_icoSupply >= 0 && endTime < getNow());

        balances[multisig] = balances[multisig].sub(_icoSupply);

        _totalSupply = _totalSupply.sub(_icoSupply);

        BurnToken(_icoSupply);

        _icoSupply = 0;
     }

    // @return total tokens supplied
    function totalSupply() public constant returns (uint256) {
        return _totalSupply;
    }

    // What is the balance of a particular account?
    // @param who The address of the particular account
    // @return the balanace the particular account
    function balanceOf(address _to) public constant returns (uint256) {
        return balances[_to];
    }

    // @notice send `value` token to `to` from `msg.sender`
    // @param to The address of the recipient
    // @param value The amount of token to be transferred
    // @return the transaction address and send the event as Transfer
    function transfer(address to, uint256 value) public {
        require (
            balances[msg.sender] >= value && value > 0
        );
        balances[msg.sender] = balances[msg.sender].sub(value);
        balances[to] = balances[to].add(value);
        Transfer(msg.sender, to, value);
    }


    // @notice send `value` token to `to` from `from`
    // @param from The address of the sender
    // @param to The address of the recipient
    // @param value The amount of token to be transferred
    // @return the transaction address and send the event as Transfer
    function transferFrom(address from, address to, uint256 value) public {
        require (
            allowed[from][msg.sender] >= value && balances[from] >= value && value > 0
        );
        balances[from] = balances[from].sub(value);
        balances[to] = balances[to].add(value);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(value);
        Transfer(from, to, value);
    }

    // Allow spender to withdraw from your account, multiple times, up to the value amount.
    // If this function is called again it overwrites the current allowance with value.
    // @param spender The address of the sender
    // @param value The amount to be approved
    // @return the transaction address and send the event as Approval
    function approve(address spender, uint256 value) public {
        require (
            balances[msg.sender] >= value && value > 0
        );
        allowed[msg.sender][spender] = value;
        Approval(msg.sender, spender, value);
    }

    // Check the allowed value for the spender to withdraw from owner
    // @param owner The address of the owner
    // @param spender The address of the spender
    // @return the amount which spender is still allowed to withdraw from owner
    function allowance(address _owner, address spender) public constant returns (uint256) {
        return allowed[_owner][spender];
    }

    // Get current price of a Token
    // @return the price or token value for a ether
    function getPrice() public constant returns (uint result) {
        return PRICE;
    }

    // @return true if crowdsale current lot event has ended
    function hasEnded() public constant returns (bool) {
        return getNow() > endTime;
    }

    // @return  current time
    function getNow() public constant returns (uint) {
        return (now * 1000);
    }

    function FoundersToken(address to, uint256 value) onlyOwner {
         require (
            to != 0x0 && value > 0 && _founders >= value
         );
         balances[multisig] = balances[multisig].sub(value);

         balances[to] = balances[to].add(value);

         _founders = _founders.sub(value);
	       Transfer(msg.sender, to, value);
     }

     function marketallocationTokens(address to, uint256 value) onlyOwner {
         require (
            to != 0x0 && value > 0 && _marketAllocation >= value
         );
         balances[multisig] = balances[multisig].sub(value);

         balances[to] = balances[to].add(value);

         _marketAllocation = _marketAllocation.sub(value);
	       Transfer(msg.sender, to, value);
     }
}
