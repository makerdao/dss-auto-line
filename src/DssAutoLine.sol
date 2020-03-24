pragma solidity ^0.5.12;

contract VatLike {
    function ilks(bytes32) public view returns (uint256, uint256, uint256, uint256, uint256);
    function Line() public view returns (uint256);
    function file(bytes32, uint256) public;
    function file(bytes32, bytes32, uint256) public;
}

contract DssAutoLine {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "DssAutoLine/not-authorized");
        _;
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

    struct Ilk {
        uint256 line; // Max ceiling possible
        uint256 on;   // Check if ilk is enabled
        uint256 ttl;  // Min time to pass before a new increase
        uint256 top;  // Defensive percentage margin to set the ceiling over actual ilk debt
        uint256 last; // Last time the ceiling was increased compared to its previous value
    }

    VatLike                     public vat;
    mapping (bytes32 => Ilk)    public ilks;

    constructor(address vat_) public {
        vat = VatLike(vat_);
        wards[msg.sender] = 1;
    }

    function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
        if (what == "line") ilks[ilk].line = data;
        else if (what == "ttl") ilks[ilk].ttl = data;
        else if (what == "top") ilks[ilk].top = data;
        else if (what == "on") ilks[ilk].on = data;
        else revert("DssAutoLine/file-unrecognized-param");
    }

    function run(bytes32 ilk) public {
        // Check the ilk ins enabled
        require(ilks[ilk].on == 1, "DssAutoLine/ilk-not-enabled");

        (uint256 Art, uint rate,, uint256 line,) = vat.ilks(ilk);
        // Calculate collateral debt
        uint debt = mul(Art, rate);

        // Calculate new line based on the minimum between the maximum line and actual collateral debt + defensive percentage margin
        uint lineNew = min(
            mul(debt, ilks[ilk].top) / 10 ** 27,
            ilks[ilk].line
        );

        // Check the ceiling is not increasing or enough time has passed since last increase
        require(lineNew <= line || now >= add(ilks[ilk].last, ilks[ilk].ttl), "DssAutoLine/no-min-time-passed");

        // Set collateral debt ceiling
        vat.file(ilk, "line", lineNew);
        // Set general debt ceiling
        vat.file("Line", add(sub(vat.Line(), line), lineNew));

        // Update last if it was an increase in the debt ceiling
        if (lineNew > line) ilks[ilk].last = now;
    }
}
