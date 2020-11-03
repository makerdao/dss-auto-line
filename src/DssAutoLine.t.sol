pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./DssAutoLine.sol";

interface Hevm {
    function warp(uint256) external;
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

    function file(bytes32 what, uint256 data) external {
        if (what == "Line") Line = data;
    }

    function file(bytes32 ilk, bytes32 what, uint256 data) external {
        if (what == "line") ilks[ilk].line = data;
        else if (what == "rate") ilks[ilk].rate = data;
    }

    function setDebt(bytes32 ilk, uint256 rad) external {
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

        dssAutoLine.file(bytes32("ETH"), bytes32("line"), 12600 * 10 ** 45);
        dssAutoLine.file(bytes32("ETH"), bytes32("ttl"), 3600);
        dssAutoLine.file(bytes32("ETH"), bytes32("top"), 2500 * 10 ** 45);
        dssAutoLine.file(bytes32("ETH"), bytes32("on"), 1);

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);
    }

    function testRun() public {
        vat.setDebt("ETH", 10000 * 10 ** 45); // Max debt ceiling amount
        (,,, uint256 line,) = vat.ilks("ETH");
        assertEq(line, 10000 * 10 ** 45);
        assertEq(vat.Line(), 10000 * 10 ** 45);
        hevm.warp(3600);
        dssAutoLine.run("ETH");
        (,,, line,) = vat.ilks("ETH");
        assertEq(line, 12500 * 10 ** 45);
        assertEq(vat.Line(), 12500 * 10 ** 45);
        vat.setDebt("ETH", 10200 * 10 ** 45); // New max debt ceiling amount
        hevm.warp(7200);
        dssAutoLine.run("ETH");
        (,,, line,) = vat.ilks("ETH");
        assertEq(line, 12600 * 10 ** 45); // < 127000 * 10 ** 45 (due max line)
        assertEq(vat.Line(), 12600 * 10 ** 45);
    }

    function testFailIlkNotEnabled() public {
        vat.setDebt("ETH", 10000 * 10 ** 45); // Max debt ceiling amount
        hevm.warp(3600);
        dssAutoLine.file(bytes32("ETH"), bytes32("on"), 0);
        dssAutoLine.run("ETH");
    }

    function testFailRunNotMinTime() public {
        vat.setDebt("ETH", 10000 * 10 ** 45); // Max debt ceiling amount
        hevm.warp(3599);
        dssAutoLine.run("ETH");
    }

    function testRunNoNeedTime() public {
        // As the debt ceiling will decrease
        vat.setDebt("ETH", 7000 * 10 ** 45);
        (,,, uint256 line,) = vat.ilks("ETH");
        assertEq(line, 10000 * 10 ** 45);
        assertEq(vat.Line(), 10000 * 10 ** 45);
        dssAutoLine.run("ETH");
        (,,, line,) = vat.ilks("ETH");
        assertEq(line, 9500 * 10 ** 45);
        assertEq(vat.Line(), 9500 * 10 ** 45);
    }
}
