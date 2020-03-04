pragma solidity ^0.5.12;

import { DssDeployTestBase } from "dss-deploy/DssDeploy.t.base.sol";

import "./DssAutoLine.sol";

contract DssAutoLineTest is DssDeployTestBase {
    DssAutoLine dssAutoLine;

    function rely(address who, address to) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("rely(address,address)", who, to);
        uint256      eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function setUp() public {
        super.setUp();
        deploy();

        dssAutoLine = new DssAutoLine(address(vat));
        dssAutoLine.rely(address(pause.proxy()));
        dssAutoLine.deny(address(this));

        this.rely(address(vat), address(dssAutoLine));

        this.file(address(dssAutoLine), bytes32("ETH"), bytes32("ttl"), 3600);
        this.file(address(dssAutoLine), bytes32("ETH"), bytes32("top"), 1.02 * 10 ** 27);
        this.file(address(dssAutoLine), bytes32("ETH"), bytes32("on"), 1);

        weth.deposit.value(1000 ether)();
        weth.approve(address(ethJoin), uint(-1));
        ethJoin.join(address(this), 1000 ether);
        vat.frob("ETH", address(this), address(this), address(this), 1000 ether, 0);
    }

    function generateDAI(uint256 amount) public {
        vat.frob("ETH", address(this), address(this), address(this), 0, int256(amount));
    }

    function testRun() public {
        generateDAI(10000 ether); // Max debt ceiling amount
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
        generateDAI(10000 ether); // Max debt ceiling amount
        hevm.warp(3600);
        this.file(address(dssAutoLine), bytes32("ETH"), bytes32("on"), 0);
        dssAutoLine.run("ETH");
    }

    function testFailRunNotMinTime() public {
        generateDAI(10000 ether); // Max debt ceiling amount
        hevm.warp(3599);
        dssAutoLine.run("ETH");
    }

    function testRunNoNeedTime() public {
        // As the debt ceiling will decrease
        generateDAI(8000 ether); // Max debt ceiling amount
        (,,, uint256 line,) = vat.ilks("ETH");
        assertEq(line, 10000 * 10 ** 45);
        assertEq(vat.Line(), 10000 * 10 ** 45);
        dssAutoLine.run("ETH");
        (,,, line,) = vat.ilks("ETH");
        assertEq(line, 8000 * 10 ** 45 * 1.02);
        assertEq(vat.Line(), 8000 * 10 ** 45 * 1.02);
    }
}
