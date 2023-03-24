pragma solidity ^0.8.0;

//import "hardhat/console.sol";
//import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface UsdcToken {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract liquorice {

    int weiconv;
    address private owner;

    uint tradeFee; // fee that taker pays to maker
    uint cancelFee; // fee that maker pais for canceling orders
    uint defaultLockout; // lockout time which is stored in auction when orders are matched
    uint id; //id counter
    uint auctionID; //Auction unqiue ID
    int maxMarkup; //defines maximum available markup/slippage defined on the platform
    int minMarkup; //defines maximum available markup/slippage defined on the platform

    struct order {
        address sender; // address that placed an order
        int volume; // order volume in MATIC
        bool TakerMaker; // 0 is taker, 1 is maker
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
    }

    struct auction {
        uint id; //ID of the order
        address sender; // address that placed an order
        int volume; // order volume in MATIC
        bool TakerMaker; // 0 is taker, 1 is maker        
        int markup; // markup of maker order
        int price; // oracle price derived at the moment orders were matched + maker markup
        uint lockout; // timeperiod when cancelation by maker is possible
    }

    //Used purely to help front operate data 
    struct orderbookView {
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
        int volume; // sum of volume on a particular level 
    }

    //Used to display auctions in front
    struct auctionView {
        uint auctionid;
        address sender; // address that placed an order
        int volume; // order volume in MATIC      
        int markup; // markup of maker order
        int price; // oracle price derived at the moment orders were matched + maker markup
    }

    struct ordersView {
        uint id; //ID of the order
        address sender; // address that placed an order
        int volume; // order volume in MATIC
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
    }

    //IERC20 public dai;

    AggregatorV3Interface internal priceFeed;

    mapping(int => mapping(uint => order)) public orders; //orders are mapped to associated "markup" value and order id. Example, if two makers place orders with markup 20bp, all orders are mapped to key value 20
    mapping(uint => auction[]) public auctions; //selection of orders in auction is mapped to associated auction ID

    mapping(address => uint256) public maticBalances;
    mapping(address => uint256) public usdcBalances;

    UsdcToken public usdcToken;

    // events for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    event OrderBookChanged(uint when);
    event AuctionBookChanged(uint when);

    // setting initial parameters at ddeploy
    constructor() {
        //console.log("Owner contract deployed by:", msg.sender);
        owner = msg.sender; 
        emit OwnerSet(address(0), owner);
        defaultLockout = 2; 
        minMarkup = -20;
        maxMarkup = 20;
        id=0;
        auctionID=0;
        priceFeed = AggregatorV3Interface(0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada);
        weiconv = 1000000000000000000;
        usdcToken = UsdcToken(0xe9DcE89B076BA6107Bb64EF30678efec11939234);
    }
    
    //fetches Matic/USD price
    function getLatestPrice() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return price;
    }

    //Main function to place orders
    function orderplace(int _volume,  bool _TakerMaker, int _markup) public payable {
        require(_markup <= maxMarkup, "Invalid markup");
        if (_TakerMaker == true) {
            require(msg.value >= uint(_volume*weiconv), "not enough matic to place maker order"); 
            maticBalances[msg.sender] += msg.value*uint(weiconv);
            id++; //we record each id in system sequantially
            orders[_markup][id] = order(msg.sender, _volume, _TakerMaker, _markup); 

            emit OrderBookChanged(block.timestamp);
            emit AuctionBookChanged(block.timestamp);
        } else {
            id++; //we record each id in system sequantially
            int _volumecheck;
            uint _makerID;
            int _makerMarkup;
            (_volumecheck, _makerID, _makerMarkup) = precheck(_markup, _volume);
            int _price = getLatestPrice() * (1+_makerMarkup/10000);
            require(_volume <= _volumecheck, "Not enough matching volume");   
            auctionID++;
            auctions[auctionID].push(auction(id, msg.sender, _volume, false, _makerMarkup, _price, defaultLockout));
            auctions[auctionID].push(auction(_makerID, orders[_makerMarkup][_makerID].sender, _volume, true, _makerMarkup, _price, defaultLockout));
            order storage myStruct = orders[_makerMarkup][_makerID];
            myStruct.volume = _volumecheck - _volume;
            orders[_makerMarkup][_makerID] = myStruct;

            emit OrderBookChanged(block.timestamp);
            emit AuctionBookChanged(block.timestamp);
        }
    }

    //Does initial calculations to check whether there is enough matching volume to fill taker order
    function precheck(int _maxMarkup, int _volume) public view returns(int checksum, uint makerID ,int _makerMarkup) {
        int sum = 0; //variable used to check if taker found enough maker volume
        uint _makerID;
        for (int i = 1; i <= _maxMarkup; i++) {
            if (sum >= _volume) {
                    break;
            }  else {
                for (uint k = 0; k <= id; k++) {
                    sum = orders[i][k].volume;
                    if (sum >= _volume) {
                        _makerID = k;
                        _makerMarkup = i;
                        break;
                    }   
                }
             }
        }
        return (sum, _makerID, _makerMarkup);
    }

    //Called by maker to remove order from order book. _key means "markup" value to easily find trade 
    function ordercancel(int _key, uint _id) external {
        require(address(msg.sender) == address(orders[_key][_id].sender), "you can not cancel this order");
        maticBalances[msg.sender] -= uint(orders[_key][_id].volume*weiconv);
        payable(msg.sender).transfer(uint(orders[_key][_id].volume*weiconv));
        delete orders[_key][_id];

        emit OrderBookChanged(block.timestamp);
    }

    //Called by maker to remove order from auction book
    function auctioncancel(uint _auctionID) external {
        require(address(msg.sender) == address(auctions[_auctionID][1].sender), "you can not cancel this order");
        require(auctions[_auctionID][0].lockout > block.timestamp, "Lockout period passed");
        payable(msg.sender).transfer(uint(auctions[_auctionID][1].volume*weiconv));
        maticBalances[msg.sender] -= uint(auctions[_auctionID][1].volume*weiconv);
        delete auctions[_auctionID];

        emit AuctionBookChanged(block.timestamp);
    }

    //Ideally this function needs to be activated automatically. But in first iteration we can make it as a manual activation by taker
    function claim(uint _auctionID) external payable {
        require(auctions[_auctionID][0].lockout < block.timestamp, "Auction is still ongoing");
        require(auctions[_auctionID][0].sender == msg.sender, "You can not claim this auction");
        uint usdcAmount = uint(auctions[_auctionID][0].volume*(auctions[_auctionID][0].price/100000000)*10**6);
        usdcToken.approve(address(this), usdcAmount);
        usdcToken.transferFrom(msg.sender, address(this), usdcAmount);

        usdcToken.transfer(auctions[_auctionID][1].sender, usdcAmount);
        maticBalances[auctions[_auctionID][1].sender] -= uint(auctions[_auctionID][0].volume*weiconv);
        payable(msg.sender).transfer(uint(auctions[_auctionID][0].volume*weiconv));

        delete auctions[_auctionID];
        emit AuctionBookChanged(block.timestamp);
    }

    function volumeSum(int _key) public view returns (int levelSum) {
        int _levelSum;
        for (uint i = 1; i <= id; i++) {
            _levelSum += orders[_key][i].volume;
        }
        return(_levelSum);
    }

    //Used to display order book in front
    function priceLadder() public view returns (orderbookView[] memory) {
        orderbookView[] memory temp = new orderbookView[](20);
        uint k;
        for (int i = -10; i <= 10; i++) {
            if (i != 0) {
                temp[k].markup = i;
                temp[k].volume = volumeSum(i);
                k++;
            }
        }
        return (temp);
    }

    //Used to display auction data on frontend. Returns top 5 pending auctions for a specific maker
    function displayAuctions(address _sender) public view returns (auctionView[] memory) {
        auctionView[] memory temp = new auctionView[](5);
        uint k;
        for (uint i = 1; i <= auctionID; i++) {
            if (auctions[i][1].sender == _sender) {
                temp[k].auctionid = i;
                temp[k].sender = auctions[i][1].sender;
                temp[k].volume = auctions[i][1].volume;
                temp[k].markup = auctions[i][1].markup;
                temp[k].price = auctions[i][1].price;
                k++;
            }
        }
        return (temp);
    }

    //Used to display order data on frontend. Returns top 5 pending auctions for a specific maker
    function displayOrders(address _sender) public view returns (ordersView[] memory) {
        ordersView[] memory temp = new ordersView[](5);
        uint k;
        for (int i = -20; i <= 20; i++) {
            for (uint d = 0; d <= id; d++) {
                if (orders[i][d].sender == _sender) {
                    temp[k].id = d;
                    temp[k].sender = _sender;
                    temp[k].volume = orders[i][d].volume;
                    temp[k].markup = orders[i][d].markup;
                    k++;
                }
            }
        }
        return (temp);
    }

    //used for testing
    function withdraw(uint _auctionID) public payable {
        payable(msg.sender).transfer(uint(auctions[_auctionID][0].volume*weiconv));
    }

    //used for testing
    function viewOrder(int _key, uint256 _id) public view returns (order memory) {
        return orders[_key][_id];
    }

    //used for testing
    function viewAuction(uint256 _key) public view returns (auction[] memory) {
        return auctions[_key];
    }
}


