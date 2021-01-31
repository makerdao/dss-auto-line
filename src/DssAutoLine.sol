// SPDX-License-Identifier: AGPL-3.0-or-later

/// DssAutoLine.sol

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

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function Line() external view returns (uint256);
    function file(bytes32, uint256) external;
    function file(bytes32, bytes32, uint256) external;
}

contract DssAutoLine {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr);}
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr);}
    modifier auth { require(wards[msg.sender] == 1, "DssAutoLine/not-authorized"); _;}

    // --- Can ---
    mapping (address => uint256) public keepers;
    function relyKeeper(address usr) external auth { keepers[usr] = 1; emit RelyKeeper(usr);}
    function denyKeeper(address usr) external auth { keepers[usr] = 0; emit DenyKeeper(usr);}
    modifier keeper { require(keepers[msg.sender] == 1, "DssAutoLine/not-authorized");_;}

    // --- Data ---
    struct Ilk {
        uint256   line;  // Max ceiling possible                                               [rad]
        uint256    gap;  // Max Value between current debt and line to be set                  [rad]
        uint48     ttl;  // Min block to pass before a new increase                            [blocks]
        uint48     ctl;  // Min block to pass before a new decrease                            [blocks]
        uint48     atl;  // Min block to pass before a new decrease for keeper                 [blocks]
        uint48    last;  // Last block the ceiling was updated                                 [blocks]
    }

    mapping (bytes32 => Ilk)     public ilks;

    VatLike immutable public vat;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event RelyKeeper(address indexed usr);
    event DenyKeeper(address indexed usr);
    event Setup(bytes32 indexed ilk, uint256 line, uint256 gap, uint256 ttl, uint256 ctl);
    event Remove(bytes32 indexed ilk);
    event Exec(bytes32 indexed ilk, uint256 line, uint256 lineNew);

    // --- Init ---
    constructor(address vat_) public {
        vat = VatLike(vat_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Math ---
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    // --- Administration ---

    /**
        @dev Add or update an ilk
        @param ilk    Collateral type (ex. ETH-A)
        @param line   Collateral maximum debt ceiling that can be configured [RAD]
        @param gap    Amount of collateral to step [RAD]
        @param ttl    Minimum blocks between increase [blocks]
        @param atl    Minimum blocks between decrease for keeper [blocks]
    */
    function setIlk(bytes32 ilk, uint256 line, uint256 gap, uint256 ttl, uint256 atl) external auth {
        require(ttl  < uint48(-1), "DssAutoLine/invalid-ttl");
        require(line > 0,          "DssAutoLine/invalid-line");
        ilks[ilk] = Ilk(line, gap, uint48(ttl), 0, uint48(atl), 0);
        emit Setup(ilk, line, gap, ttl, atl);
    }

    /**
        @dev Remove an ilk
        @param ilk    Collateral type (ex. ETH-A)
    */
    function remIlk(bytes32 ilk) external auth {
        delete ilks[ilk];
        emit Remove(ilk);
    }


    // --- Keeper ---
    // @param  _ilk  The bytes32 ilk tag to adjust (ex. "ETH-A")
    // @return       The ilk line value as uint256
    function execKeeper(bytes32 _ilk) external keeper returns (uint256) {
        uint256 ilkLine   = ilks[_ilk].line;
        require(ilkLine != 0, "DssAutoLine/no-autoline");

        uint48  ilkTtl     = ilks[_ilk].ttl;
        uint48  ilkAtl     = ilks[_ilk].atl;
        uint48  ilkCtl     = ilks[_ilk].ctl;
        uint48  ilkLast    = ilks[_ilk].last;
        uint256 ilkGap     = ilks[_ilk].gap;

        (uint256 line, uint256 lineNew) = _exec(_ilk, ilkLine, ilkTtl/2, ilkCtl, ilkLast, ilkGap);

        ilks[_ilk].ctl     = ilkAtl;
        ilks[_ilk].last    = uint48(block.number);

        emit Exec(_ilk, line, lineNew);

        vat.file(_ilk, "line", lineNew);
        vat.file("Line", add(sub(vat.Line(), line), lineNew));

    }

    // --- Primary Functions ---
    // @param  _ilk  The bytes32 ilk tag to adjust (ex. "ETH-A")
    // @return       The ilk line value as uint256
    function exec(bytes32 _ilk) external returns (uint256) {
        uint256 ilkLine = ilks[_ilk].line;
        require(ilkLine != 0, "DssAutoLine/no-autoline");

        uint48  ilkTtl     = ilks[_ilk].ttl;
        uint48  ilkCtl     = ilks[_ilk].ctl;
        uint48  ilkLast    = ilks[_ilk].last;
        uint256 ilkGap     = ilks[_ilk].gap;

        (uint256 line, uint256 lineNew) = _exec(_ilk, ilkLine, ilkTtl, ilkCtl, ilkLast, ilkGap);

        ilks[_ilk].ctl     = 0;
        ilks[_ilk].last    = uint48(block.number);

        emit Exec(_ilk, line, lineNew);

        vat.file(_ilk, "line", lineNew);
        vat.file("Line", add(sub(vat.Line(), line), lineNew));

    }

    function _exec(bytes32 ilk, uint256 ilkLine, uint48  ilkTtl, uint48  ilkCtl, uint48  ilkLast, uint256 ilkGap) private returns (uint256, uint256 lineNew) {

        (uint256 Art, uint256 rate,, uint256 line,) = vat.ilks(ilk);

        // Calculate collateral debt
        uint256 debt = mul(Art, rate);
        // Calculate new line based on the minimum between the maximum line and actual collateral debt + gap
        lineNew = min(add(debt, ilkGap), ilkLine);

        // Short-circuit if there wasn't an update or if the time since last increment has not passed
        require(lineNew != line, "DssAutoLine/no-update");
        require(lineNew <= line || block.number >= add(ilkLast, ilkTtl), "DssAutoLine/not-authorized");
        require(lineNew >= line || block.number >= add(ilkLast, ilkCtl), "DssAutoLine/not-authorized");
    }
}
