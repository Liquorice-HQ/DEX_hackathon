// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.5/contracts/token/ERC20/IERC20.sol";

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
        bool side; // 0 is BUY, 1 is SELL
        bool TakerMaker; // 0 is taker, 1 is maker
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
    }

    struct auction {
        uint id; //ID of the order
        address sender; // address that placed an order
        uint volume; // order volume in ETH
        bool side; // 0 is BUY, 1 is SELL
        bool TakerMaker; // 0 is taker, 1 is maker        
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
        uint price; // oracle prices derived at the moment orders were matched
        uint lockout; // timeperiod when cancelation is possible
    }

    auction[] public tempAuction; //used to assist with forming an auction

    mapping(int => mapping(uint => order)) public orders; //orders are mapped to associated "markup" value and order id. Example, if two makers place orders with markup 20bp, all orders are mapped to key value 20
    mapping(uint => auction[]) public auctions; //selection of orders in auction is mapped to associated auction ID


    address public constant usdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7; //pushing in USDT address. As mvp we allow to only swap UNI against USDT
    address public constant uniAddress = 0xBf5140A22578168FD562DCcF235E5D43A02ce9B1;  //pushing in UNI address. As mvp we allow to only swap UNI against USDT

    // events for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);

    // setting initial parameters at ddeploy
    constructor(uint _defaultLockout) {
        console.log("Owner contract deployed by:", msg.sender);
        owner = msg.sender; 
        emit OwnerSet(address(0), owner);
        defaultLockout = _defaultLockout; 
        minMarkup = 1;
        maxMarkup = 500;
        id=0;
        auctionID=0;
    }

    //Called by user. While orderplace is working, orddercancel should not initiate and vice versa
    function orderplace(uint _volume, bool _side, bool _TakerMaker, int _markup) external {
        require(_markup <= maxMarkup, "Invalid markup");
        if (_TakerMaker == true) {
            if (_markup > 0) {
                _side = true;
            } else {
                _side = false;
            }
            orders[_markup][id] = order(msg.sender, _volume, _side, _TakerMaker, _markup);
            id++; //we record each id in system sequantially
        } else {
            matching(id, msg.sender, _TakerMaker, _markup,  _side, _volume);
            id++; //we record each id in system sequantially
        }
    }

    //Does initial calculations to define what happens to taker order
    function precheck(uint _id, address _sender, bool _takerMaker, int _markup, bool _side, uint _volume) internal returns(uint checksum) {
        uint sum = 0; //variable used to check if taker found enough maker volume
        uint lastMatchedID; //needed to find last matched id so that its volume can be reduced instead of being carried to auctions fully
        uint _price = 1500;
        auction memory tempStruct = auction(_id, _sender, _volume, _side, _takerMaker, _markup, _price, defaultLockout);
        tempAuction.push(tempStruct);
        if (_side = false) {
            for (int i = 1; i <= _markup; i++) {
                for (uint k = 0; k <= _id+1; k++) {
                    if (sum <= _volume) {
                        sum += orders[i][k].volume;
                        auction memory tempStruct1 = auction(k, orders[i][k].sender, orders[i][k].volume, orders[i][k].side, orders[i][k].TakerMaker, orders[i][k].markup, _price, defaultLockout);
                        tempAuction.push(tempStruct1);
                    } else {
                        break;
                    }
                }
            }
            
        } else {
            for (int i = 1; i >= -_markup; i--) {
                for (uint k = 0; k <= _id; k++) {
                    if (sum <= _volume) {
                        sum += orders[i][k].volume;
                        auction memory tempStruct2 = auction(k, orders[i][k].sender, orders[i][k].volume, orders[i][k].side, orders[i][k].TakerMaker, orders[i][k].markup, _price, defaultLockout);
                        tempAuction.push(tempStruct2);                        
                    } else {
                        break;
                    }
                }   
            }
        return (sum);
        }
    }

    //Matching function. Transfers orders from 
    function matching(uint _id, address _sender, bool _takerMaker, int _markup, bool _side, uint _volume) internal {
        uint _volumecheck;
        _volumecheck = precheck(_id, _sender, _takerMaker, _markup, _side, _volume);
        require(_volume <= _volumecheck, "Not enough matching volume");   
        auctionID++;
        auctions[auctionID] = tempAuction;

        for (uint i = 0; i <= tempAuction.length; i++) {
            _id = tempAuction[i].id;
            _markup = tempAuction[i].markup;
            delete orders[_markup][_id];
        }   
        delete tempAuction;
    }



    //Called by maker to remove trader from order book. _key means "markup" value to easily find trade 
    function ordercancel(int _key, uint _id) external {
        delete orders[_key][_id];
    }

    //Called by maker to remove order from auction book
    function auctioncancel(uint _auctionID) external {
        require(auctions[_auctionID][0].lockout > block.timestamp, "Lockout period passed");
        delete auctions[_auctionID];
    }

    //Ideally this function needs to be activated automatically. But in first iteration we can use make it as a manual activation by auction participants
    function claim(uint _auctionID) external payable {
        require(auctions[_auctionID][0].lockout < block.timestamp, "Auction is still ongoing");
        IERC20 usdt = IERC20(usdtAddress);
        IERC20 uni = IERC20(uniAddress);
        address takerAdr;
        address makerAdr;
        uint takerAmount;
        uint makerAmount;

        for (uint i = 0; i <= auctions[_auctionID].length; i++) {
            if (auctions[_auctionID][i].TakerMaker = false) {
                takerAdr = auctions[_auctionID][i].sender;
                takerAmount = auctions[_auctionID][i].volume;
                if (auctions[_auctionID][i].side = false){
                    takerAmount = auctions[_auctionID][i].price * takerAmount;
                    require(usdt.balanceOf(address(takerAdr)) >= takerAmount, "Insufficient USDT balance in contract");
                } else {
                    require(uni.balanceOf(address(takerAdr)) >= takerAmount, "Insufficient UNI balance in contract");
                }
            }
        }

        for (uint i = 0; i <= auctions[_auctionID].length; i++) {
            if (auctions[_auctionID][i].TakerMaker = true) {
                makerAdr = auctions[_auctionID][i].sender;
                makerAmount = auctions[_auctionID][i].volume;
                if (auctions[_auctionID][i].side = false){
                    makerAmount = auctions[_auctionID][i].price * makerAmount;
                    require(usdt.balanceOf(address(makerAdr)) >= makerAmount, "Insufficient USDT balance");
                    IERC20(usdt).transferFrom(makerAdr, takerAdr, makerAmount);
                    IERC20(uni).transferFrom(takerAdr, makerAdr, takerAmount);
                } else {
                    require(uni.balanceOf(address(makerAdr)) >= makerAmount, "Insufficient UNI balance");
                    IERC20(uni).transferFrom(makerAdr, takerAdr, makerAmount);
                    IERC20(usdt).transferFrom(takerAdr, makerAdr, takerAmount);
                }
            }
        }
    }

    function viewOrder(int _key, uint256 _id) public view returns (order memory) {
        return orders[_key][_id];
    }

    function viewAuction(uint256 _key) public view returns (auction[] memory) {
        return auctions[_key];
    }
}

