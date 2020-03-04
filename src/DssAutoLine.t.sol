pragma solidity ^0.5.12;

import "ds-test/test.sol";

import "./DssAutoLine.sol";

contract Hevm {
    function warp(uint256) public;
}

contract MockVat {
    struct Ilk {
        uint256 Art;   // Total Normalised Debt     [wad]
        uint256 rate;  // Accumulated Rates         [ray]
        uint256 spot;  // Price with Safety Margin  [ray]
        uint256 line;  // Debt Ceiling              [rad]
        uint256 dust;  // Urn Debt Floor            [rad]
    }
    uint256 public Line;
    mapping (bytes32 => Ilk) public ilks;

    function file(bytes32 what, uint data) external {
        if (what == "Line") Line = data;
    }

    function file(bytes32 ilk, bytes32 what, uint data) external {
        if (what == "line") ilks[ilk].line = data;
        else if (what == "rate") ilks[ilk].rate = data;
    }

    function addDebt(bytes32 ilk, uint256 rad) external {
        ilks[ilk].Art = rad / ilks[ilk].rate;
    }
}

contract DssAutoLineTest is DSTest {
    Hevm hevm;
    DssAutoLine dssAutoLine;
    MockVat vat;

    function setUp() public {
        vat = new MockVat();
        vat.file(bytes32("Line"), 10000 * 10 ** 45);
        vat.file(bytes32("ETH"), bytes32("line"), 10000 * 10 ** 45);
        vat.file(bytes32("ETH"), bytes32("rate"), 1 * 10 ** 27);
        dssAutoLine = new DssAutoLine(address(vat));

        dssAutoLine.file(bytes32("ETH"), bytes32("ttl"), 3600);
        dssAutoLine.file(bytes32("ETH"), bytes32("top"), 1.02 * 10 ** 27);
        dssAutoLine.file(bytes32("ETH"), bytes32("on"), 1);

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);
    }

    function testRun() public {
        vat.addDebt("ETH", 10000 * 10 ** 45); // Max debt ceiling amount
        (,,, uint256 line,) = vat.ilks("ETH");
        assertEq(line, 10000 * 10 ** 45);
        assertEq(vat.Line(), 10000 * 10 ** 45);
        hevm.warp(3600);
        dssAutoLine.run("ETH");
        (,,, line,) = vat.ilks("ETH");
        assertEq(line, 10000 * 10 ** 45 * 1.02);
        assertEq(vat.Line(), 10000 * 10 ** 45 * 1.02);
    }

    function testFailIlkNotEnabled() public {
        vat.addDebt("ETH", 10000 * 10 ** 45); // Max debt ceiling amount
        hevm.warp(3600);
        dssAutoLine.file(bytes32("ETH"), bytes32("on"), 0);
        dssAutoLine.run("ETH");
    }

    function testFailRunNotMinTime() public {
        vat.addDebt("ETH", 10000 * 10 ** 45); // Max debt ceiling amount
        hevm.warp(3599);
        dssAutoLine.run("ETH");
    }

    function testRunNoNeedTime() public {
        // As the debt ceiling will decrease
        vat.addDebt("ETH", 8000 * 10 ** 45);
        (,,, uint256 line,) = vat.ilks("ETH");
        assertEq(line, 10000 * 10 ** 45);
        assertEq(vat.Line(), 10000 * 10 ** 45);
        dssAutoLine.run("ETH");
        (,,, line,) = vat.ilks("ETH");
        assertEq(line, 8000 * 10 ** 45 * 1.02);
        assertEq(vat.Line(), 8000 * 10 ** 45 * 1.02);
    }
}
