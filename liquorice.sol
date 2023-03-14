// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "hardhat/console.sol";

contract liquorice {

    address private owner;

    // event for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);

    uint defaultFee; // fee that maker pais for canceling orders
    uint defaultLockout; // lockout time which is stored in auction when orders are matched

    struct order {
        address sender; // address that placed an order
        uint volume; // order volume in ETH
        bool side; // 0 is BUY, 1 is SELL
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
    }

    struct auction {
        address sender; // address that placed an order
        int volume; // order volume in ETH
        bool side; // 0 is BUY, 1 is SELL
        int markup; // positive means maker order, negative means taker order. Range 0 to 100 
        uint takerfee; // reserved fee to be paid to maker when order is matched 
        uint makerreserve; // fee paid by maker if he cacnels an order. Should be a small amount 
        uint price; // oracle prices derived at the moment orders were matched
        uint lockout; // timeperiod when cancelation is possible
    }

    order[] public orders;
    
    mapping(uint => auction) public auctions;

    constructor() {
        console.log("Owner contract deployed by:", msg.sender);
        owner = msg.sender; // 'msg.sender' is sender of current call, contract deployer for a constructor
        emit OwnerSet(address(0), owner);
        defaultFee = 0.0001 ether;
        defaultLockout = 3; 
    }

    function orderplace(int _volume, bool _side, int _markup) public {
        
    }

    function ordercancel() public {

    }

    //swap function is not called by users, it activates when auction reaches lockout period
    function swap() internal {

    }

}
