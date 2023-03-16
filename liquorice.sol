// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "hardhat/console.sol";

contract liquorice {


    address private owner;

    uint tradeFee; // fee that taker pays to maker
    uint cancelFee; // fee that maker pais for canceling orders
    uint defaultLockout; // lockout time which is stored in auction when orders are matched
    uint id; //id counter
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

    mapping(int => order[]) public orders;
    mapping(uint => auction[]) public auctions;

    // event for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);

    // setting initial parameters at ddeploy
    constructor(uint _tradefee, uint _defaultLockout) {
        console.log("Owner contract deployed by:", msg.sender);
        owner = msg.sender; 
        emit OwnerSet(address(0), owner);
        tradeFee = _tradefee/100;
        defaultLockout = _defaultLockout; 
        minMarkup = 1;
        maxMarkup = 200;
        id=0;
    }

    //Called by user. While orderplace is working, orddercancel should not initiate
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
        uint volumecheck;
        uint[] memory matchedIds;
        (volumecheck, ) = precheck(_volume, markup, _side);
        (, matchedIds) = precheck(_volume, markup, _side);
        require(_volume <= volumecheck, "Not enouhg matching volume");    
        
    }

    function precheck(uint _volume, int markup, bool _side) internal view returns(uint checksum, uint[] memory) {
        uint sum = 0; //variable used to check if taker found enough maker volume
        uint[] memory matchedIds;
        if (_side = true) {
            for (int i = 0; i <= markup; i++) {
                for (uint k = 0; k <= orders[i].length; k++) {
                    sum += orders[i][k].volume;
                    matchedIds[k] = orders[i][k].id;
                }
            }
            
        } else {
            for (int i = 0; i >= -markup; i--) {
                for (uint k = 0; k <= orders[i].length; k++) {
                    sum += orders[i][k].volume;
                    matchedIds[k] = orders[i][k].id;
                }
            }
        }
        return (sum, matchedIds);
    }

    //Called by user
    function ordercancel() public {

    }

    //Swap function is not called by users, it activates when auction reaches lockout period
    function swap() internal {

    }

}
