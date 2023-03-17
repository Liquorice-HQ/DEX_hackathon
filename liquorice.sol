// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "hardhat/console.sol";

contract liquorice {


    address private owner;

    uint tradeFee; // fee that taker pays to maker
    uint cancelFee; // fee that maker pais for canceling orders
    uint defaultLockout; // lockout time which is stored in auction when orders are matched
    uint id; //id counter
    uint aucctionID; //Auction unqiue ID
    int maxMarkup; //defines maximum available markup/slippage defined on the platform
    int minMarkup; //defines maximum available markup/slippage defined on the platform

    struct order {
        uint id; // id of order
        address sender; // address that placed an order
        uint volume; // order volume in ETH
        bool side; // 0 is BUY, 1 is SELL
        bool TakerMaker; // 0 is taker, 1 is maker
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
    }

    struct auction {
        uint id; //id of order
        address sender; // address that placed an order
        int volume; // order volume in ETH
        bool side; // 0 is BUY, 1 is SELL
        bool TakerMaker; // 0 is taker, 1 is maker        
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
        uint takerfee; // reserved fee to be paid to maker when order is matched 
        uint makerreserve; // fee paid by maker if he cacnels an order. Should be a small amount 
        uint price; // oracle prices derived at the moment orders were matched
        uint lockout; // timeperiod when cancelation is possible
    }

    mapping(int => order[]) public orders; //orders are mapped to associated "markup" value. Example, if two makers place orders with markup 20bp, all orders are mapped to key value 20
    mapping(uint => auction[]) public auctions; //selection of orders in auction is mapped to associated auction id 

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
        aucctionID=0;
    }

    //Called by user. While orderplace is working, orddercancel should not initiate and vice versa
    function orderplace(uint _volume, bool _side, bool _TakerMaker, int _markup) external {
        require(_markup <= maxMarkup, "Invalid markup");
        id++; //we record each id in system sequantially
        if (_TakerMaker == true) {
            orders[_markup].push(order(id, msg.sender, _volume, _side, _TakerMaker, _markup));
        } else {
            matching(id, _volume, _markup, _side);
        }
    }

    //Matching function
    function matching(uint _id, uint _volume, int markup, bool _side) internal {
        uint _volumecheck;
        uint[] memory _matchedIds;
        uint _lastid;
        (_volumecheck, _matchedIds, _lastid) = precheck(_id, markup, _side, _volume);
        require(_volume <= _volumecheck, "Not enouhg matching volume");    
        
    }

    //Does initial calculations to ddefine what happens to taker order
    function precheck(uint _id, int markup, bool _side, uint _volume) internal view returns(uint checksum, uint[] memory matchedids, uint lastid) {
        uint sum = 0; //variable used to check if taker found enough maker volume
        uint lastMatchedID; //needed to find last matched id so that its volume can be reduced instead of being carried to auctions fully
        uint[] memory matchedIds;
        if (_side = true) {
            for (int i = 1; i <= markup; i++) {
                for (uint k = 0; k <= orders[i].length; k++) {
                    if (sum <= _volume) {
                        sum += orders[i][k].volume;
                        matchedIds[k] = orders[i][k].id;
                        break;
                    }
                }
            }
            
        } else {
            for (int i = 1; i >= -markup; i--) {
                for (uint k = 0; k <= orders[i].length; k++) {
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

    //Called by maker to remove trader from order book. _key means "markup" value to easily find trade 
    function ordercancel(int _key, uint _id) external {
        for (uint i = 0; i < orders[_key].length; i++) {
            if (orders[_key][i].id == _id) {
                delete orders[_key][i];
            }
        }
    }

    //Called by maker to remove order from auction book
    function auctioncancel(uint _auctionID) external {
        require(auctions[_auctionID][0].lockout > block.timestamp, "Lockout period passed");
        delete auctions[_auctionID];
    }

    //Swap function is not called by users, it activates when auction reaches lockout period
    function swap() internal {

    }

}
