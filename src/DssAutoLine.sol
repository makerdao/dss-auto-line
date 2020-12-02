pragma solidity ^0.6.7;

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function Line() external view returns (uint256);
    function file(bytes32, uint256) external;
    function file(bytes32, bytes32, uint256) external;
}

contract DssAutoLine {
    /*** Data ***/
    struct Ilk {
        uint256   line;  // Max ceiling possible                                               [rad]
        uint256    gap;  // Max Value between current debt and line to be set                  [rad]
        uint8       on;  // Check if ilk is enabled                                            [1 if on]
        uint48     ttl;  // Min time to pass before a new increase                             [seconds]
        uint48    last;  // Last block the ceiling was updated                                 [blocks]
        uint48 lastInc;  // Last time the ceiling was increased compared to its previous value [seconds]
    }

    mapping (bytes32 => Ilk)     public ilks;
    mapping (address => uint256) public wards;

    VatLike immutable public vat;

    /*** Events ***/
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Enable(bytes32 ilk);
    event Disable(bytes32 ilk);
    event Exec(bytes32 indexed ilk, uint256 line, uint256 lineNew);

    /*** Init ***/
    constructor(address vat_) public {
        vat = VatLike(vat_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /*** Math ***/
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

    /*** Administration ***/

    // Add or update an ilk
    function enableIlk(bytes32 ilk, uint256 line, uint256 gap, uint256 ttl) external auth {
        require(ttl < uint48(-1), "DssAutoLine/invalid-ttl");
        ilks[ilk] = Ilk(line, gap, 1, uint48(ttl), 0, 0);
        emit Enable(ilk);
    }

    // Disable an ilk
    function disableIlk(bytes32 ilk) external auth {
        delete ilks[ilk];
        emit Disable(ilk);
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "DssAutoLine/not-authorized");
        _;
    }

    /*** Auto-Line Update ***/
    // @param  _ilk  The bytes32 ilk tag to adjust (ex. "ETH-A")
    // @return       The ilk line value as uint256
    function exec(bytes32 _ilk) external returns (uint256) {
        // 1 SLOAD
        uint8  ilkOn      = ilks[_ilk].on;
        uint48 ilkTtl     = ilks[_ilk].ttl;
        uint48 ilkLast    = ilks[_ilk].last;
        uint48 ilkLastInc = ilks[_ilk].lastInc;
        //

        (uint256 Art, uint256 rate,, uint256 line,) = vat.ilks(_ilk);

        // Return if the ilk is not enabled
        if (ilkOn != 1) return line;

        // Return if there was already an update in the same block
        if (ilkLast == block.number) return line;

        // Calculate collateral debt
        uint256 debt = mul(Art, rate);

        // 2 SLOADs
        uint256 ilkLine = ilks[_ilk].line;
        uint256 ilkGap  = ilks[_ilk].gap;
        //
        // Calculate new line based on the minimum between the maximum line and actual collateral debt + gap
        uint256 lineNew = min(add(debt, ilkGap), ilkLine);

        // Short-circuit if there wasn't an update or if the time since last increment has not passed
        if (lineNew == line || lineNew > line && block.timestamp < add(ilkLastInc, ilkTtl)) return line;

        // Set collateral debt ceiling
        vat.file(_ilk, "line", lineNew);
        // Set general debt ceiling
        vat.file("Line", add(sub(vat.Line(), line), lineNew));

        // Update lastInc if it is an increment in the debt ceiling
        // and update last whatever the update is
        if (lineNew > line) {
            // 1 SSTORE
            ilks[_ilk].lastInc = uint48(block.timestamp);
            ilks[_ilk].last    = uint48(block.number);
            //
        } else {
            ilks[_ilk].last    = uint48(block.number);
        }

        emit Exec(_ilk, line, lineNew);

        return lineNew;
    }
}
