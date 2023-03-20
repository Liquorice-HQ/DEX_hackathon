// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.5/contracts/token/ERC20/IERC20.sol";

interface DaiToken {
    function transfer(address dst, uint wad) external returns (bool);
    function transferFrom(address src, address dst, uint wad) external returns (bool);
    function balanceOf(address guy) external view returns (uint);
}

contract liquorice {


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
        uint volume; // order volume in ETH
        bool TakerMaker; // 0 is taker, 1 is maker
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
    }

    struct auction {
        uint id; //ID of the order
        address sender; // address that placed an order
        uint volume; // order volume in ETH
        bool TakerMaker; // 0 is taker, 1 is maker        
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
        uint price; // oracle prices derived at the moment orders were matched
        uint lockout; // timeperiod when cancelation is possible
    }

    mapping(int => mapping(uint => order)) public orders; //orders are mapped to associated "markup" value and order id. Example, if two makers place orders with markup 20bp, all orders are mapped to key value 20
    mapping(uint => auction[]) public auctions; //selection of orders in auction is mapped to associated auction ID

    mapping(address => uint256) public ethBalances;
    mapping(address => uint256) public usdcBalances;

    IERC20 public dai;

    // events for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    event OrderBookChanged(uint when);
    event AuctionBookChanged(uint when);

    // setting initial parameters at ddeploy
    constructor() {
        console.log("Owner contract deployed by:", msg.sender);
        owner = msg.sender; 
        dai = IERC20(0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa);
        emit OwnerSet(address(0), owner);
        defaultLockout = 2; 
        minMarkup = 1;
        maxMarkup = 500;
        id=0;
        auctionID=0;
    }

    //Called by user. While orderplace is working, orddercancel should not initiate and vice versa
    function orderplace(uint _volume,  bool _TakerMaker, int _markup) public payable {
        require(_markup <= maxMarkup, "Invalid markup");
        if (_TakerMaker == true) {
            require(msg.value >= _volume*1e18, "not enough eth to place maker order"); 
            ethBalances[msg.sender] += msg.value*1e18;
            id++; //we record each id in system sequantially
            orders[_markup][id] = order(msg.sender, _volume, _TakerMaker, _markup); 

            emit OrderBookChanged(block.timestamp);
            emit AuctionBookChanged(block.timestamp);
        } else {
            id++; //we record each id in system sequantially
            uint _volumecheck;
            uint _makerID;
            int _makerMarkup;
            uint _price = 1500;
            (_volumecheck, _makerID, _makerMarkup) = precheck(_markup, _volume);
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

    //Does initial calculations to define what happens to taker order
    function precheck(int _maxMarkup, uint _volume) public view returns(uint checksum, uint makerID ,int _makerMarkup) {
        uint sum = 0; //variable used to check if taker found enough maker volume
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

    //Called by maker to remove trader from order book. _key means "markup" value to easily find trade 
    function ordercancel(int _key, uint _id) external {
        require(address(msg.sender) == address(orders[_key][_id].sender), "you can not cancel this order");
        payable(msg.sender).transfer(orders[_key][_id].volume*1e18);
        ethBalances[msg.sender] -= orders[_key][_id].volume*1e18;
        delete orders[_key][_id];

        emit OrderBookChanged(block.timestamp);
    }

    //Called by maker to remove order from auction book
    function auctioncancel(uint _auctionID) external {
        require(address(msg.sender) == address(auctions[_auctionID][1].sender), "you can not cancel this order");
        require(auctions[_auctionID][0].lockout > block.timestamp, "Lockout period passed");
        ethBalances[msg.sender] -= auctions[_auctionID][0].volume*1e18;
        payable(msg.sender).transfer(auctions[_auctionID][0].volume*1e18);
        delete auctions[_auctionID];

        emit AuctionBookChanged(block.timestamp);
    }

    //Ideally this function needs to be activated automatically. But in first iteration we can use make it as a manual activation by auction participants
    function claim(uint _auctionID) external payable {
        require(auctions[_auctionID][0].lockout < block.timestamp, "Auction is still ongoing");
        require(auctions[_auctionID][0].sender == msg.sender, "You can not cancel this auction");
        dai.transferFrom(msg.sender, address(auctions[_auctionID][1].sender), auctions[_auctionID][1].volume*auctions[_auctionID][1].price);
        payable(msg.sender).transfer(auctions[_auctionID][0].volume*1e18);
        ethBalances[auctions[_auctionID][1].sender] -= auctions[_auctionID][0].volume*1e18;

        emit AuctionBookChanged(block.timestamp);
    }

    function viewOrder(int _key, uint256 _id) public view returns (order memory) {
        return orders[_key][_id];
    }

    function viewAuction(uint256 _key) public view returns (auction[] memory) {
        return auctions[_key];
    }
}


