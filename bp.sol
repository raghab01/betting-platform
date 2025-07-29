// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SportsBettingPlatform
 * @dev A decentralized sports betting platform for event prediction markets
 * @author Your Name
 */
contract SportsBettingPlatform {
    
    // Struct to represent a betting event
    struct BettingEvent {
        uint256 eventId;
        string description;
        string teamA;
        string teamB;
        uint256 endTime;
        uint256 totalBetsA;
        uint256 totalBetsB;
        uint256 winningTeam; // 1 for teamA, 2 for teamB, 0 for not decided
        bool isActive;
        bool isResolved;
    }
    
    // Struct to represent a bet
    struct Bet {
        address bettor;
        uint256 eventId;
        uint256 team; // 1 for teamA, 2 for teamB
        uint256 amount;
        bool claimed;
    }
    
    // State variables
    address public owner;
    uint256 public eventCounter;
    uint256 public betCounter;
    uint256 public platformFeePercentage = 5; // 5% platform fee
    
    // Mappings
    mapping(uint256 => BettingEvent) public events;
    mapping(uint256 => Bet) public bets;
    mapping(address => uint256[]) public userBets;
    mapping(uint256 => uint256[]) public eventBets;
    
    // Events
    event EventCreated(uint256 indexed eventId, string description, string teamA, string teamB, uint256 endTime);
    event BetPlaced(uint256 indexed betId, address indexed bettor, uint256 indexed eventId, uint256 team, uint256 amount);
    event EventResolved(uint256 indexed eventId, uint256 winningTeam);
    event WinningsClaimed(uint256 indexed betId, address indexed bettor, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier eventExists(uint256 _eventId) {
        require(_eventId < eventCounter, "Event does not exist");
        _;
    }
    
    modifier eventActive(uint256 _eventId) {
        require(events[_eventId].isActive, "Event is not active");
        require(block.timestamp < events[_eventId].endTime, "Betting period has ended");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        eventCounter = 0;
        betCounter = 0;
    }
    
    /**
     * @dev Creates a new betting event
     * @param _description Description of the event
     * @param _teamA Name of team A
     * @param _teamB Name of team B
     * @param _duration Duration in seconds from now when betting ends
     */
    function createEvent(
        string memory _description,
        string memory _teamA,
        string memory _teamB,
        uint256 _duration
    ) external onlyOwner {
        require(_duration > 0, "Duration must be greater than 0");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(bytes(_teamA).length > 0, "Team A name cannot be empty");
        require(bytes(_teamB).length > 0, "Team B name cannot be empty");
        
        uint256 endTime = block.timestamp + _duration;
        
        events[eventCounter] = BettingEvent({
            eventId: eventCounter,
            description: _description,
            teamA: _teamA,
            teamB: _teamB,
            endTime: endTime,
            totalBetsA: 0,
            totalBetsB: 0,
            winningTeam: 0,
            isActive: true,
            isResolved: false
        });
        
        emit EventCreated(eventCounter, _description, _teamA, _teamB, endTime);
        eventCounter++;
    }
    
    /**
     * @dev Places a bet on a specific team for an event
     * @param _eventId ID of the event to bet on
     * @param _team Team to bet on (1 for teamA, 2 for teamB)
     */
    function placeBet(uint256 _eventId, uint256 _team) 
        external 
        payable 
        eventExists(_eventId) 
        eventActive(_eventId) 
    {
        require(_team == 1 || _team == 2, "Team must be 1 or 2");
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(!events[_eventId].isResolved, "Event already resolved");
        
        // Create new bet
        bets[betCounter] = Bet({
            bettor: msg.sender,
            eventId: _eventId,
            team: _team,
            amount: msg.value,
            claimed: false
        });
        
        // Update event totals
        if (_team == 1) {
            events[_eventId].totalBetsA += msg.value;
        } else {
            events[_eventId].totalBetsB += msg.value;
        }
        
        // Update mappings
        userBets[msg.sender].push(betCounter);
        eventBets[_eventId].push(betCounter);
        
        emit BetPlaced(betCounter, msg.sender, _eventId, _team, msg.value);
        betCounter++;
    }
    
    /**
     * @dev Resolves an event by declaring the winning team
     * @param _eventId ID of the event to resolve
     * @param _winningTeam Winning team (1 for teamA, 2 for teamB)
     */
    function resolveEvent(uint256 _eventId, uint256 _winningTeam) 
        external 
        onlyOwner 
        eventExists(_eventId) 
    {
        require(_winningTeam == 1 || _winningTeam == 2, "Winning team must be 1 or 2");
        require(!events[_eventId].isResolved, "Event already resolved");
        require(block.timestamp >= events[_eventId].endTime, "Event has not ended yet");
        
        events[_eventId].winningTeam = _winningTeam;
        events[_eventId].isResolved = true;
        events[_eventId].isActive = false;
        
        emit EventResolved(_eventId, _winningTeam);
    }
    
    /**
     * @dev Claims winnings for a specific bet
     * @param _betId ID of the bet to claim winnings for
     */
    function claimWinnings(uint256 _betId) external {
        require(_betId < betCounter, "Bet does not exist");
        
        Bet storage bet = bets[_betId];
        require(bet.bettor == msg.sender, "You are not the bettor");
        require(!bet.claimed, "Winnings already claimed");
        
        BettingEvent storage bettingEvent = events[bet.eventId];
        require(bettingEvent.isResolved, "Event not resolved yet");
        require(bet.team == bettingEvent.winningTeam, "Your team did not win");
        
        // Calculate winnings
        uint256 totalPool = bettingEvent.totalBetsA + bettingEvent.totalBetsB;
        uint256 winningPool = (bet.team == 1) ? bettingEvent.totalBetsA : bettingEvent.totalBetsB;
        
        // Calculate user's share of the losing pool
        uint256 userShare = (bet.amount * totalPool) / winningPool;
        
        // Deduct platform fee
        uint256 platformFee = (userShare * platformFeePercentage) / 100;
        uint256 payout = userShare - platformFee;
        
        bet.claimed = true;
        
        // Transfer winnings
        payable(msg.sender).transfer(payout);
        
        emit WinningsClaimed(_betId, msg.sender, payout);
    }
    
    /**
     * @dev Gets event details
     * @param _eventId ID of the event
     */
    function getEvent(uint256 _eventId) 
        external 
        view 
        eventExists(_eventId) 
        returns (BettingEvent memory) 
    {
        return events[_eventId];
    }
    
    // Additional utility functions
    
    /**
     * @dev Gets all bet IDs for a user
     * @param _user Address of the user
     */
    function getUserBets(address _user) external view returns (uint256[] memory) {
        return userBets[_user];
    }
    
    /**
     * @dev Gets all bet IDs for an event
     * @param _eventId ID of the event
     */
    function getEventBets(uint256 _eventId) external view returns (uint256[] memory) {
        return eventBets[_eventId];
    }
    
    /**
     * @dev Calculates potential winnings for a bet amount
     * @param _eventId ID of the event
     * @param _team Team to bet on
     * @param _amount Amount to bet
     */
    function calculatePotentialWinnings(uint256 _eventId, uint256 _team, uint256 _amount) 
        external 
        view 
        eventExists(_eventId) 
        returns (uint256) 
    {
        BettingEvent memory bettingEvent = events[_eventId];
        uint256 totalPool = bettingEvent.totalBetsA + bettingEvent.totalBetsB + _amount;
        uint256 teamPool = (_team == 1) ? bettingEvent.totalBetsA + _amount : bettingEvent.totalBetsB + _amount;
        
        if (teamPool == 0) return 0;
        
        uint256 userShare = (_amount * totalPool) / teamPool;
        uint256 platformFee = (userShare * platformFeePercentage) / 100;
        
        return userShare - platformFee;
    }
    
    /**
     * @dev Withdraws platform fees (only owner)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner).transfer(balance);
    }
    
    /**
     * @dev Transfers ownership of the contract
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    /**
     * @dev Updates platform fee percentage
     * @param _newFeePercentage New fee percentage (max 10%)
     */
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
}
