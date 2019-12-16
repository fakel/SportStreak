pragma solidity 0.5.13;
//https://github.com/OpenZeppelin/
import "openzeppelin-solidity/contracts/GSN/Context.sol";
import "openzeppelin-solidity/contracts/access/Roles.sol";
import "openzeppelin-solidity/contracts/access/roles/SignerRole.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract GameAdminRole is Context {
    using Roles
    for Roles.Role;

    event GameAdminAdded(address indexed account, uint level);
    event GameAdminRemoved(address indexed account);
    event GameAdminChanged(address indexed account, uint level);

    Roles.Role private _admins;
    /**
        + Level 0: no admin
        + Level 1: game-include rights
        + Level 2: daylist-include rights+Level 1
        + Level 3: monthList-include rights+Level 2
        + Level 4: fees-wallet changes and stuck-tokens retrieve+Level 3f
     */
    mapping(address => uint) private _adminLevel;

    /**
        @dev Set the initial lvl 4 admin to the contract deployer
     */
    constructor() public {
        _addGameAdmin(_msgSender(), 4);
    }

    /**
        @dev Modifier to limit functional access to authorized wallets
     */
    modifier onlyGameAdmin(uint level) {
        require(isGameAdmin(_msgSender(), level), "GameAdminRole: caller does not have the GameAdmin role");
        _;
    }

    function isGameAdmin(address account, uint level) public view returns(bool) {
        return (_admins.has(account) && _adminLevel[account] >= level);
    }

    function addAdmin(address account, uint level) public onlyGameAdmin(4) {
        _addGameAdmin(account, level);
    }

    function changeAdmin(address account, uint level) public onlyGameAdmin(4) {
        _changeGameAdmin(account, level);
    }

    function renounceGameAdmin() public {
        _removeGameAdmin(_msgSender());
    }

    function _addGameAdmin(address account, uint level) internal {
        _admins.add(account);
        _adminLevel[account] = level;
        emit GameAdminAdded(account, level);
    }

    function _changeGameAdmin(address account, uint level) internal {
        _adminLevel[account] = level;
        emit GameAdminChanged(account, level);
    }

    function _removeGameAdmin(address account) internal {
        _admins.remove(account);
        emit GameAdminRemoved(account);
    }
}

contract SportStreak is Ownable, GameAdminRole {

    using SafeMath for uint;

    //Global Indexes
    uint public monthList;

    //Fee's wallet
    address payable public feesWallet;

    //Types definition
    struct monthListInfo {
        uint _days;
        uint games;
        uint pool;
        uint fee;
        uint entryPayment;
        uint highestStreak;
        address highestStreakOwner;
    }

    struct monthListStats {
        bool lock; //Is the user currently locked by a bet?
        uint userGame; // LastGame
        uint userDay; //Of Day
        uint userMonth; //And Month
        bool entryPaid; //Month entry paid?
        uint wins;
        uint fails;
        uint currentStreak;
        uint longestStreak;
        uint longestStreakTime; //When the longest streak occurs
    }

    struct gameInfo {
        string description;
        uint validFrom;
        uint openUntil;
        uint8 status; //waiting:0, teamAWin:1, teamBWin:2, tie:3, Null:4
    }

    // Global Mappings
    // mapping(monthList => monthListInfo) monthData;
    mapping(uint => monthListInfo) monthData;

    // mapping(monthList => mapping(dayList => uint)) dayGames;
    mapping(uint => mapping(uint => uint)) dayGames;

    // mapping(monthList => mapping(dayList => mapping(gameID => gameInfo))) gameData;
    mapping(uint => mapping(uint => mapping(uint => gameInfo))) gameData;

    // mapping(monthList => mapping(address => monthListStats)) userData;
    mapping(uint => mapping(address => monthListStats)) userData;

    // mapping(monthList => mapping(dayList => mapping(gameID => mapping(address => bool)))) predictions;
    mapping(uint => mapping(uint => mapping(uint => mapping(address => bool)))) predictions;

    //Events
    event MonthListCreated(
            uint indexed monthList,
            uint pool,
            uint fee,
            uint entryPayment
            );

    event MonthListUpdated(
            uint indexed monthList,
            uint _days,
            uint games,
            uint pool,
            uint fee,
            uint entryPayment,
            uint highestStreak,
            address highestStreakOwner
            );

    event DayListCreated(
            uint indexed _monthListID,
            uint indexed _dayListID
            );

    event GameIncluded(
            uint indexed _monthListID,
            uint indexed _dayListID,
            string _description,
            uint _validFrom,
            uint _openUntil,
            uint8 _status);

    event DaylistUpdated(
           uint indexed _monthListID,
           uint indexed _dayListID,
           uint indexed _gameID
        );

    event FeesWalletUpdated(address indexed _newWallet);

    event UserBet(
        address indexed _user,
        uint _monthList,
        uint _dayList,
        uint _gameID,
        bool _prediction);

    event UserCancelBet(
        address indexed _user,
        uint _monthList,
        uint _dayList,
        uint _gameID);

    constructor() public {
        feesWallet = msg.sender;
    }

    // User Functions

    function bet(
        uint _monthList,
        uint _dayList,
        uint _gameID,
        bool _prediction) public payable {
        //If month entry fee is not zero the user should pay it
        if(userData[_monthList][msg.sender].entryPaid == false && monthData[_monthList].entryPayment != 0) {
            require(msg.value == monthData[_monthList].entryPayment, "You need to provide the month entryFee");
        }
        //User should not be locked
        require(userData[_monthList][msg.sender].lock == false, "You are locked until other bet finish");
        //Game should not have finished
        require(gameData[_monthList][_dayList][_gameID].status == 0, "Game have finished");
        //Game should have started
        require(now >= gameData[_monthList][_dayList][_gameID].validFrom, "Game is not available yet");
        //Game entry period should not have finished
        require(now <= gameData[_monthList][_dayList][_gameID].openUntil, "Game entry period have finished");

        //Update user info
        //Lock user
        userData[_monthList][msg.sender].lock = true;
        //Set current user's game month
        userData[_monthList][msg.sender].userMonth = _monthList;
        //Set current user's game day
        userData[_monthList][msg.sender].userDay = _dayList;
        //Set current user's game id
        userData[_monthList][msg.sender].userGame = _gameID;
        //Register user prediction
        predictions[_monthList][_dayList][_gameID][msg.sender] = _prediction;
        //Log the event
        emit UserBet(msg.sender,_monthList,_dayList,_gameID,_prediction);
    }

    function cancelBet(
        uint _monthList,
        uint _dayList,
        uint _gameID) public {
        require(userData[_monthList][msg.sender].lock == true, "You are not locked, this means you have no pending bet");
        require(userData[_monthList][msg.sender].userMonth == _monthList, "Invalid Month");
        require(userData[_monthList][msg.sender].userDay == _dayList, "Invalid Day");
        require(userData[_monthList][msg.sender].userGame == _gameID, "Invalid Game");
        require(gameData[_monthList][_dayList][_gameID].status == 0, "Game have finished");
        //Unlock the user
        userData[_monthList][msg.sender].lock = false;
        //Reset user streak
        userData[_monthList][msg.sender].currentStreak = 0;
        //Emit event
        emit UserCancelBet(msg.sender,_monthList,_dayList,_gameID);
    }

    function closeBet(
        uint _monthList,
        uint _dayList,
        uint _gameID) public {
        require(userData[_monthList][msg.sender].lock == true, "You are not locked, this means you have no pending bet");
        require(gameData[_monthList][_dayList][_gameID].status != 0, "Game have not finished");
        //Unlock the user
        userData[_monthList][msg.sender].lock = false;
        if(gameData[_monthList][_dayList][_gameID].status == 3) {
        //If a tie, simply return
            return;
        } else if(gameData[_monthList][_dayList][_gameID].status == 1) {
        //If teamA wins
            if(predictions[_monthList][_dayList][_gameID][msg.sender] == true){
            //And the bet is for A, account it
            userData[_monthList][msg.sender].currentStreak = userData[_monthList][msg.sender].currentStreak.add(1);
            checkHighestStreak(_monthList,msg.sender);
            } else {
            //reset the streak
            userData[_monthList][msg.sender].currentStreak = 0;
            }
        } else if(gameData[_monthList][_dayList][_gameID].status == 2) {
        //If teamB wins
            if(predictions[_monthList][_dayList][_gameID][msg.sender] == false){
            //And the bet is for B, account it
            userData[_monthList][msg.sender].currentStreak = userData[_monthList][msg.sender].currentStreak.add(1);
            checkHighestStreak(_monthList,msg.sender);
            } else {
            //reset the streak
            userData[_monthList][msg.sender].currentStreak = 0;
            }
        } else {
            revert('Unknown error closing the bet');
        }
    }

    function checkHighestStreak(uint _monthList,address _player) private {
        uint current = userData[_monthList][_player].currentStreak;
        uint highest = userData[_monthList][_player].longestStreak;
        uint allHigh = monthData[_monthList].highestStreak;

        if(current > highest) {
            userData[_monthList][_player].longestStreak = current;
            userData[_monthList][_player].longestStreakTime = now;
            }
        if(current > allHigh) {
            monthData[_monthList].highestStreak = current;
            monthData[_monthList].highestStreakOwner = msg.sender;
        }
    }

    // Admin Funcitions
    /**
        @dev Start a new month list
        @param _pool initial pool amount
        @param _fee permille fee
        @param _entryPayment flat entryPayment for this month list
     */
    function openMonthList(
        uint _pool,
        uint _fee,
        uint _entryPayment
    ) public onlyGameAdmin(3) {
        // The current monthList is created
        monthData[monthList] = monthListInfo({
            _days: 0,
            games: 0,
            pool: _pool,
            fee: _fee,
            entryPayment: _entryPayment,
            highestStreak: 0,
            highestStreakOwner: address(0)
        });

        // The event is emited including the current monthList number
        emit MonthListCreated(
            monthList,
            _pool,
            _fee,
            _entryPayment
            );
        // The month list index is increased to show the next available index
        monthList = monthList.add(1);
    }

    /**
        @dev Start a new month list
        @param _monthListID month list where the daylist will be created
     */
    function addDayList(
        uint _monthListID) public onlyGameAdmin(2) {
        //Reflect the number of days available now on the month
        monthData[_monthListID]._days = monthData[_monthListID]._days.add(1);
        //Emit DayList creation event
        emit DayListCreated(_monthListID,monthData[_monthListID]._days);
        //Emit MonthUpdate event
        emit MonthListUpdated(
            _monthListID,
            monthData[_monthListID]._days,
            monthData[_monthListID].games,
            monthData[_monthListID].pool,
            monthData[_monthListID].fee,
            monthData[_monthListID].entryPayment,
            monthData[_monthListID].highestStreak,
            monthData[_monthListID].highestStreakOwner
            );
    }

    function addGameToDayList(
        uint _monthListID,
        uint _dayListID,
        string memory _description,
        uint _validFrom,
        uint _openUntil,
        uint8 _status) public onlyGameAdmin(1) {
        //Check if the dayList has been created
        require(monthData[_monthListID]._days >= _dayListID, "Day List doesn't exist");

        uint gameID = dayGames[_monthListID][_dayListID];

        gameData[_monthListID][_dayListID][gameID] = gameInfo({
            description: _description,
            validFrom: _validFrom,
            openUntil: _openUntil,
            status: _status
            });

        monthData[_monthListID].games = monthData[_monthListID].games.add(1);

        emit GameIncluded(
            _monthListID,
            _dayListID,
            _description,
            _validFrom,
            _openUntil,
            _status);

        emit DaylistUpdated(
            _monthListID,
            _dayListID,
            gameID
        );

        emit MonthListUpdated(
            _monthListID,
            monthData[_monthListID]._days,
            monthData[_monthListID].games,
            monthData[_monthListID].pool,
            monthData[_monthListID].fee,
            monthData[_monthListID].entryPayment,
            monthData[_monthListID].highestStreak,
            monthData[_monthListID].highestStreakOwner
            );

        dayGames[_monthListID][_dayListID] = dayGames[_monthListID][_dayListID].add(1);

    }

    function setFeesWallet(address payable _newWallet) public onlyGameAdmin(4) {
        require(_newWallet != address(0), "The wallet cannot be the zero address");
        feesWallet = _newWallet;
        emit FeesWalletUpdated(_newWallet);
    }

    function retrieveStuckTokens(IERC20 _tokenAddress) public onlyGameAdmin(4) {
        uint tokenBalance = _tokenAddress.balanceOf(address(this));
        _tokenAddress.transfer(address(this),tokenBalance);
    }

}