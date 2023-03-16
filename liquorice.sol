// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "hardhat/console.sol";

contract liquorice {


    address private owner;

    uint tradeFee; // fee that taker pays to maker
    uint cancelFee; // fee that maker pais for canceling orders
    uint defaultLockout; // lockout time which is stored in auction when orders are matched
    uint id; //order counter
    int maxMarkup; //defines maximum available markup/slippage defined on the platform
    int minMarkup; //defines maximum available markup/slippage defined on the platform

    struct order {
        uint id; // order id
        address sender; // address that placed an order
        uint volume; // order volume in ETH
        bool side; // 0 is BUY, 1 is SELL
        bool TakerMaker; // 0 is taker, 1 is maker
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
    }

    struct auction {
        uint id; // order id
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

    constructor(uint _tradefee, uint _defaultLockout) {
        console.log("Owner contract deployed by:", msg.sender);
        owner = msg.sender; 
        emit OwnerSet(address(0), owner);
        tradeFee = _tradefee/100;
        defaultLockout = _defaultLockout; 
        id = 0;
        minMarkup = 1;
        maxMarkup = 200;
    }


    //Called by user. While orderplace is working, orddercancel should not initiate
    function orderplace(uint _volume, bool _side, bool _TakerMaker, int _markup) public {
        require(_markup <= maxMarkup, "Invalid markup");
        id++;
        if (_TakerMaker == true) {
            orders[_markup].push(order(id, msg.sender, _volume, _side, _TakerMaker, _markup));
        } else {
            matching(_volume, _markup);
        }
    }

    //Matching function
    function matching(uint _volume, int markup) internal {

    }

    //Called by user
    function ordercancel() public {

    }

    //Swap function is not called by users, it activates when auction reaches lockout period
    function swap() internal {

    }

}
