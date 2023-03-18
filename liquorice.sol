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
        address sender; // address that placed an order
        uint volume; // order volume in ETH
        bool side; // 0 is BUY, 1 is SELL
        bool TakerMaker; // 0 is taker, 1 is maker        
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
        uint takerfee; // reserved fee to be paid to maker when order is matched 
        uint makerreserve; // fee paid by maker if he cacnels an order. Should be a small amount 
        uint price; // oracle prices derived at the moment orders were matched
        uint lockout; // timeperiod when cancelation is possible
    }

    mapping(int => mapping(uint => order)) public orders; //orders are mapped to associated "markup" value and order id. Example, if two makers place orders with markup 20bp, all orders are mapped to key value 20
    mapping(uint => mapping(uint => auction)) public auctions; //selection of orders in auction is mapped to associated auction ID


    address public constant usdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7; //pushing in USDT address. As mvp we allow to only swap UNI against USDT
    address public constant uniAddress = 0xBf5140A22578168FD562DCcF235E5D43A02ce9B1;  //pushing in UNI address. As mvp we allow to only swap UNI against USDT

    // events for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);

    // setting initial parameters at ddeploy
    constructor(uint _tradefee, uint _defaultLockout) {
        console.log("Owner contract deployed by:", msg.sender);
        owner = msg.sender; 
        emit OwnerSet(address(0), owner);
        tradeFee = _tradefee/100;
        defaultLockout = _defaultLockout; 
        minMarkup = 1;
        maxMarkup = 500;
        id=0;
        auctionID=0;
    }

    //Called by user. While orderplace is working, orddercancel should not initiate and vice versa
    function orderplace(uint _volume, bool _side, bool _TakerMaker, int _markup) external {
        require(_markup <= maxMarkup, "Invalid markup");
        id++; //we record each id in system sequantially
        if (_TakerMaker == true) {
            orders[_markup][id] = order(msg.sender, _volume, _side, _TakerMaker, _markup);
        } else {
            matching(id, _volume, _markup, _side);
        }
    }

    //Does initial calculations to define what happens to taker order
    function precheck(uint _id, int markup, bool _side, uint _volume) internal view returns(uint checksum, uint[] memory matchedids, uint lastid) {
        uint sum = 0; //variable used to check if taker found enough maker volume
        uint lastMatchedID; //needed to find last matched id so that its volume can be reduced instead of being carried to auctions fully
        uint[] memory matchedIds;
        auction[] memory auctionInsert;
        if (_side = true) {
            for (int i = 1; i <= markup; i++) {
                for (uint k = 0; k <= _id; k++) {
                    if (sum <= _volume) {
                        sum += orders[i][k].volume;
                        matchedIds[k] = orders[i][k].id;
                        break;
                    }
                }
            }
            
        } else {
            for (int i = 1; i >= -markup; i--) {
                for (uint k = 0; k <= _id; k++) {
                    if (sum <= _volume) {
                        sum += orders[i][k].volume;
                        matchedIds[k] = orders[i][k].id;
                        break;
                    }
                }   
            }
        lastMatchedID = matchedIds[matchedIds.length];
        delete matchedIds[matchedIds.length];
        matchedIds[matchedIds.length+1] = _id;
        return (sum, matchedIds, lastMatchedID);
        }
    }

    //Matching function. Transfers orders from 
    function matching(uint _takerID, uint _volume, int markup, bool _side) internal {
        uint _volumecheck;
        uint[] memory _matchedIds;
        uint _lastid;
        (_volumecheck, _matchedIds, _lastid) = precheck(_takerID, markup, _side, _volume);
        require(_volume <= _volumecheck, "Not enough matching volume");    
        for (int i = -200; i <= markup; i++) {
            for (uint k = 0; k <= orders[i].length; k++) {
                if (orders[i][k].id == _takerID){

                }    
            }
        }
    }



    //Called by maker to remove trader from order book. _key means "markup" value to easily find trade 
    function ordercancel(int _key, uint _id) external {
        delete orders[_key][_id];
    }

    //Called by maker to remove order from auction book
    function auctioncancel(uint _auctionID, uint _id) external {
        require(auctions[_auctionID][_id].lockout > block.timestamp, "Lockout period passed");
        delete auctions[_auctionID][_id];
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
}
