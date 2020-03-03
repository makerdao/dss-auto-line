pragma solidity ^0.5.12;

import "ds-test/test.sol";

import "./DssAutoLine.sol";

contract DssAutoLineTest is DSTest {
    DssAutoLine line;
    address vat;

    function setUp() public {
        line = new DssAutoLine(vat);
    }
}
