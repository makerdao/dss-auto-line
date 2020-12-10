// SPDX-License-Identifier: AGPL-3.0-or-later

/// DssAutoLine.t.sol

// Copyright (C) 2018-2020 Maker Ecosystem Growth Holdings, INC.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.6.11;

import "ds-test/test.sol";

import "./DssAutoLine.sol";

interface Hevm {
    function roll(uint256) external;
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

        dssAutoLine.setIlk(ilk, 12600 * RAD, 2500 * RAD, 1 hours);

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        _warp(0);
    }

    function _warp(uint256 time) internal {
        hevm.roll(time / 15); // 1 block each 15 seconds
        hevm.warp(time);
    }

    function test_exec() public {
        vat.setDebt(ilk, 10000 * RAD); // Max debt ceiling amount
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
        assertEq(Art,  10000 * WAD);
        assertEq(line, 10000 * RAD);
        assertEq(vat.Line(), 10000 * RAD);

        _warp(1 hours);

        dssAutoLine.exec(ilk);
        (,,,line,) = vat.ilks(ilk);
        assertEq(line, 12500 * RAD);
        assertEq(vat.Line(), 12500 * RAD);
        (,,, uint256 last, uint256 lastInc) = dssAutoLine.ilks(ilk);
        assertEq(last   , 1 hours / 15);
        assertEq(lastInc, 1 hours);
        vat.setDebt(ilk, 10200 * RAD); // New max debt ceiling amount

        _warp(2 hours);

        dssAutoLine.exec(ilk);
        (,,,line,) = vat.ilks(ilk);
        assertEq(line, 12600 * RAD); // < 12700 * RAD (due max line: 10200 + gap)
        assertEq(vat.Line(), 12600 * RAD);
        (,,, last, lastInc) = dssAutoLine.ilks(ilk);
        assertEq(last   , 2 hours / 15);
        assertEq(lastInc, 2 hours);
    }

    function test_exec_multiple_ilks() public {
        vat.file("gold",         "line", 5000 * RAD);
        dssAutoLine.setIlk("gold", 7600 * RAD, 2500 * RAD, 1 hours);

        vat.file("silver", "line", 5000 * RAD);
        vat.file("silver", "rate", 1 * RAY);

        dssAutoLine.setIlk("silver", 7600 * RAD, 1000 * RAD, 2 hours);

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

        assertEq(dssAutoLine.exec("gold"), 5000 * RAD);
        assertEq(dssAutoLine.exec("silver"), 5000 * RAD);
        _warp(1 hours);
        assertEq(dssAutoLine.exec("gold"), 7500 * RAD);
        assertEq(dssAutoLine.exec("silver"), 5000 * RAD);

        (,,, goldLine,) = vat.ilks("gold");
        assertEq(goldLine, 7500 * RAD);
        assertEq(vat.Line(), 12500 * RAD);
        (,,, uint256 goldLast, uint256 goldLastInc) = dssAutoLine.ilks("gold");
        assertEq(goldLast   , 1 hours / 15);
        assertEq(goldLastInc, 1 hours);

        assertEq(dssAutoLine.exec("silver"), 5000 * RAD);  // Don't need to check gold since no debt increase

        _warp(2 hours);
        assertEq(dssAutoLine.exec("gold"), 7500 * RAD);  // Gold line does not increase
        assertEq(dssAutoLine.exec("silver"), 6000 * RAD);   // Silver line increases

        (,,, goldLine,) = vat.ilks("gold");
        assertEq(goldLine, 7500 * RAD);
        (,,, silverLine,) = vat.ilks("silver");
        assertEq(silverLine, 6000 * RAD);
        assertEq(vat.Line(), 13500 * RAD);
        assertTrue(vat.Line() == goldLine + silverLine);

        (,,, goldLast, goldLastInc) = dssAutoLine.ilks("gold");
        assertEq(goldLast   , 1 hours / 15);
        assertEq(goldLastInc, 1 hours);
        (,,, uint256 silverLast, uint256 silverLastInc) = dssAutoLine.ilks("silver");
        assertEq(silverLast   , 2 hours / 15);
        assertEq(silverLastInc, 2 hours);

        vat.setDebt("gold",   7500 * RAD); // Will use max line
        vat.setDebt("silver", 6000 * RAD); // Will use `gap`

        _warp(4 hours); // Both will be able to increase

        assertEq(dssAutoLine.exec("gold"), 7600 * RAD);
        assertEq(dssAutoLine.exec("silver"), 7000 * RAD);

        (,,,goldLine,) = vat.ilks("gold");
        assertEq(goldLine, 7600 * RAD);
        (,,,silverLine,) = vat.ilks("silver");
        assertEq(silverLine, 7000 * RAD);
        assertEq(vat.Line(), 14600 * RAD);
        assertTrue(vat.Line() == goldLine + silverLine);

        (,,, goldLast, goldLastInc) = dssAutoLine.ilks("gold");
        assertEq(goldLast   , 4 hours / 15);
        assertEq(goldLastInc, 4 hours);
        (,,, silverLast, silverLastInc) = dssAutoLine.ilks("silver");
        assertEq(silverLast   , 4 hours / 15);
        assertEq(silverLastInc, 4 hours);
    }

    function test_ilk_not_enabled() public {
        vat.setDebt(ilk, 10000 * RAD); // Max debt ceiling amount
        _warp(1 hours);

        dssAutoLine.remIlk(ilk);
        assertEq(dssAutoLine.exec(ilk), 10000 * RAD); // The line from the vat
    }

    function test_exec_not_enough_time_passed() public {
        vat.setDebt(ilk, 10000 * RAD); // Max debt ceiling amount
        _warp(3575);
        assertEq(dssAutoLine.exec(ilk), 10000 * RAD);  // No change
        _warp(1 hours);
        assertEq(dssAutoLine.exec(ilk), 12500 * RAD);  // + gap
    }

    function test_exec_line_decrease_under_min_time() public {
        // As the debt ceiling will decrease
        vat.setDebt(ilk, 10000 * RAD);
        (,,, uint256 line,) = vat.ilks(ilk);
        assertEq(line, 10000 * RAD);
        assertEq(vat.Line(), 10000 * RAD);
        (,,, uint256 last, uint256 lastInc) = dssAutoLine.ilks(ilk);
        assertEq(last   , 0);
        assertEq(lastInc, 0);

        _warp(15); // To block number 1

        assertEq(dssAutoLine.exec(ilk), 10000 * RAD);
        (,,, line,) = vat.ilks(ilk);
        assertEq(line, 10000 * RAD);
        assertEq(vat.Line(), 10000 * RAD);
        (,,, last, lastInc) = dssAutoLine.ilks(ilk);
        assertEq(last   , 0); // no update
        assertEq(lastInc, 0); // no increment

        vat.setDebt(ilk, 7000 * RAD); // debt + gap = 7000 + 2500 = 9500 < 10000
        (uint256 Art,,,,) = vat.ilks(ilk);
        assertEq(Art, 7000 * WAD);

        _warp(30); // To block number 2

        assertEq(dssAutoLine.exec(ilk), 9500 * RAD);
        (,,, line,) = vat.ilks(ilk);
        assertEq(line, 9500 * RAD);
        assertEq(vat.Line(), 9500 * RAD);
        (,,, last, lastInc) = dssAutoLine.ilks(ilk);
        assertEq(last   , 2); // update
        assertEq(lastInc, 0); // no increment

        vat.setDebt(ilk, 6000 * RAD); // debt + gap = 6000 + 2500 = 8500 < 9500
        (Art,,,,) = vat.ilks(ilk);
        assertEq(Art, 6000 * WAD);

        assertEq(dssAutoLine.exec(ilk), 9500 * RAD); // Same value as it was executed on same block than previous exec
        (,,, line,) = vat.ilks(ilk);
        assertEq(line, 9500 * RAD);
        assertEq(vat.Line(), 9500 * RAD);
        (,,, last, lastInc) = dssAutoLine.ilks(ilk);
        assertEq(last   , 2); // no update
        assertEq(lastInc, 0); // no increment

        _warp(45); // To block number 3

        assertEq(dssAutoLine.exec(ilk), 8500 * RAD);
        (,,, line,) = vat.ilks(ilk);
        assertEq(line, 8500 * RAD);
        assertEq(vat.Line(), 8500 * RAD);
        (,,, last, lastInc) = dssAutoLine.ilks(ilk);
        assertEq(last   , 3); // update
        assertEq(lastInc, 0); // no increment
    }

    function test_invalid_exec_ilk() public {
        _warp(1 hours);
        assertEq(dssAutoLine.exec("FAIL-A"), 0);
    }

    function test_exec_twice_failure() public {
        vat.setDebt(ilk, 100 * RAD); // Max debt ceiling amount
        vat.file(ilk,         "line", 100 * RAD);
        dssAutoLine.setIlk(ilk, 20000 * RAD, 2500 * RAD, 1 hours);

        _warp(1 hours);

        assertEq(dssAutoLine.exec(ilk), 2600 * RAD);
        (,,,uint256 line,) = vat.ilks(ilk);
        assertEq(line, 2600 * RAD);
        assertEq(vat.Line(), 12500 * RAD);

        vat.setDebt(ilk, 2500 * RAD);

        assertEq(dssAutoLine.exec(ilk), 2600 * RAD); // This should short-circuit

        _warp(2 hours);

        assertEq(dssAutoLine.exec(ilk), 5000 * RAD);
        (,,,line,) = vat.ilks(ilk);
        assertEq(line, 5000 * RAD);
        assertEq(vat.Line(), 14900 * RAD);
    }
}
