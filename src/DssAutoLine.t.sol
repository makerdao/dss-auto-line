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

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    bytes32 constant ilk = "gold";

    function setUp() public {
        vat = new MockVat();
        vat.file("Line", 10000 * RAD);
        vat.file(ilk, "line", 10000 * RAD);
        vat.file(ilk, "rate", 1 * RAY);
        dssAutoLine = new DssAutoLine(address(vat));

        dssAutoLine.file(ilk, "line", 12600 * RAD);
        dssAutoLine.file(ilk, "ttl", 3600);
        dssAutoLine.file(ilk, "gap", 2500 * RAD);
        dssAutoLine.file(ilk, "on", 1);

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);
    }

    function try_exec(bytes32 _ilk) internal returns (bool ok) {
        string memory sig = "exec(bytes32)";
        (ok,) = address(dssAutoLine).call(abi.encodeWithSignature(sig, _ilk));
    }

    function test_exec() public {
        vat.setDebt(ilk, 10000 * RAD); // Max debt ceiling amount
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
        assertEq(Art,  10000 * WAD);
        assertEq(line, 10000 * RAD);
        assertEq(vat.Line(), 10000 * RAD);

        hevm.warp(3600);

        dssAutoLine.exec(ilk);
        (,,,line,) = vat.ilks(ilk);
        assertEq(line, 12500 * RAD);
        assertEq(vat.Line(), 12500 * RAD);
        (,,,,uint256 last) = dssAutoLine.ilks(ilk);
        assertEq(last, 3600);
        vat.setDebt(ilk, 10200 * RAD); // New max debt ceiling amount

        hevm.warp(7200);

        dssAutoLine.exec(ilk);
        (,,,line,) = vat.ilks(ilk);
        assertEq(line, 12600 * RAD); // < 127000 * RAD (due max line: 10200 + gap)
        assertEq(vat.Line(), 12600 * RAD);
        (,,,,last) = dssAutoLine.ilks(ilk);
        assertEq(last, 7200);
    }

    function test_exec_multiple_ilks() public {
        vat.file("gold",         "line", 5000 * RAD);
        dssAutoLine.file("gold", "line", 7600 * RAD);

        vat.file("silver", "line", 5000 * RAD);
        vat.file("silver", "rate", 1 * RAY);

        dssAutoLine.file("silver", "line", 7600 * RAD);
        dssAutoLine.file("silver", "ttl", 7200);       // Different than gold
        dssAutoLine.file("silver", "gap", 1000 * RAD); // Different than gold
        dssAutoLine.file("silver", "on", 1);

        vat.setDebt("gold", 5000 * RAD); // Max gold debt ceiling amount
        (uint256 goldArt,,, uint256 goldLine,) = vat.ilks("gold");
        assertEq(goldArt,  5000 * WAD);
        assertEq(goldLine, 5000 * RAD);
        assertEq(vat.Line(), 10000 * RAD);

        vat.setDebt("silver", 5000 * RAD); // Max silver debt ceiling amount
        (uint256 silverArt,,, uint256 silverLine,) = vat.ilks("silver");
        assertEq(silverArt,  5000 * WAD);
        assertEq(silverLine, 5000 * RAD);
        assertEq(vat.Line(), 10000 * RAD);

        assertTrue(!try_exec("gold"));
        assertTrue(!try_exec("silver"));
        hevm.warp(3600);
        assertTrue( try_exec("gold"));
        assertTrue(!try_exec("silver"));

        (,,, goldLine,) = vat.ilks("gold");
        assertEq(goldLine, 7500 * RAD);
        assertEq(vat.Line(), 12500 * RAD);
        (,,,,uint256 goldLast) = dssAutoLine.ilks("gold");
        assertEq(goldLast, 3600);

        assertTrue(!try_exec("silver")); // Don't need to check gold since no debt increase
        hevm.warp(7200);
        assertTrue( try_exec("gold"));   // Gold line does not increase
        assertTrue( try_exec("silver")); // Silver line increases

        (,,, goldLine,) = vat.ilks("gold");
        assertEq(goldLine, 7500 * RAD);
        (,,, silverLine,) = vat.ilks("silver");
        assertEq(silverLine, 6000 * RAD);
        assertEq(vat.Line(), 13500 * RAD);
        assertTrue(vat.Line() == goldLine + silverLine);

        (,,,,goldLast) = dssAutoLine.ilks("gold");
        assertEq(goldLast, 3600);
        (,,,,uint256 silverLast) = dssAutoLine.ilks("silver");
        assertEq(silverLast, 7200);

        vat.setDebt("gold",   7500 * RAD); // Will use max line
        vat.setDebt("silver", 6000 * RAD); // Will use `gap`

        hevm.warp(14400); // Both will be able to increase
        assertTrue(try_exec("gold"));
        assertTrue(try_exec("silver"));

        (,,,goldLine,) = vat.ilks("gold");
        assertEq(goldLine, 7600 * RAD);
        (,,,silverLine,) = vat.ilks("silver");
        assertEq(silverLine, 7000 * RAD);
        assertEq(vat.Line(), 14600 * RAD);
        assertTrue(vat.Line() == goldLine + silverLine);

        (,,,,goldLast) = dssAutoLine.ilks("gold");
        assertEq(goldLast, 14400);
        (,,,,silverLast) = dssAutoLine.ilks("silver");
        assertEq(silverLast, 14400);
    }

    function test_ilk_not_enabled() public {
        vat.setDebt(ilk, 10000 * RAD); // Max debt ceiling amount
        hevm.warp(3600);

        assertTrue( try_exec(ilk));
        dssAutoLine.file(ilk, "on", 0);
        assertTrue(!try_exec(ilk));
    }

    function test_exec_not_enough_time_passed() public {
        vat.setDebt(ilk, 10000 * RAD); // Max debt ceiling amount
        hevm.warp(3599);
        assertTrue(!try_exec(ilk));
        hevm.warp(3600);
        assertTrue( try_exec(ilk));
    }

    function test_exec_line_decrease_under_min_time() public {
        // As the debt ceiling will decrease
        vat.setDebt(ilk, 10000 * RAD);
        (,,, uint256 line,) = vat.ilks(ilk);
        assertEq(line, 10000 * RAD);
        assertEq(vat.Line(), 10000 * RAD);

        assertTrue(!try_exec(ilk));
        vat.setDebt(ilk, 7000 * RAD); // debt + gap = 7000 + 2500 = 9500 < 10000
        assertTrue( try_exec(ilk));

        (,,, line,) = vat.ilks(ilk);
        assertEq(line, 9500 * RAD);
        assertEq(vat.Line(), 9500 * RAD);
    }

    function test_invalid_exec_ilk() public {
        hevm.warp(3600);
        assertTrue(!try_exec("FAIL-A"));
    }

    function test_exec_twice_failure() public {
        vat.setDebt(ilk, 100 * RAD); // Max debt ceiling amount
        vat.file(ilk,         "line", 100 * RAD);
        dssAutoLine.file(ilk, "line", 20000 * RAD);

        hevm.warp(3600);

        assertTrue( try_exec(ilk));
        (,,,uint256 line,) = vat.ilks(ilk);
        assertEq(line, 2600 * RAD);
        assertEq(vat.Line(), 12500 * RAD);

        vat.setDebt(ilk, 2500 * RAD);

        assertTrue(!try_exec(ilk)); // This should fail

        hevm.warp(7200);

        assertTrue( try_exec(ilk));
        (,,,line,) = vat.ilks(ilk);
        assertEq(line, 5000 * RAD);
        assertEq(vat.Line(), 14900 * RAD);
    }
}
