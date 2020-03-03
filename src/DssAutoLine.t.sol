pragma solidity ^0.5.15;

import "ds-test/test.sol";

import "./DssAutoLine.sol";

contract DssAutoLineTest is DSTest {
    DssAutoLine line;

    function setUp() public {
        line = new DssAutoLine();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
