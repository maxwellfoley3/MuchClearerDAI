/// CDPEngine.sol -- Dai CDP database

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
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

pragma solidity 0.5.12;

contract CDPEngineInstance is Permissioned {
    // --- Auth ---
    function addAuthorization(address usr) external emitLog onlyOwners {
      require(DSRisActive, "CDPEngineInstance/not-DSRisActive");
      authorizedAccounts[usr] = true;
    }
    function removeAuthorization(address usr) external emitLog onlyOwners {
      require(DSRisActive, "CDPEngineInstance/not-DSRisActive");
      authorizedAccounts[usr] = false;
    }

    mapping(address => mapping (address => uint)) public can;
    function hope(address usr) external emitLog { can[msg.sender][usr] = 1; }
    function nope(address usr) external emitLog { can[msg.sender][usr] = 0; }
    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }

    // --- Data ---
    struct Ilk {
        uint256 debtAmount;   // Total Normalised Debt     [amount]
        uint256 accumulatedRates ;  // Accumulated Rates         [ray]
        uint256 spot;  // Price with Safety Margin  [ray]
        uint256 line;  // Debt Ceiling              [rad]
        uint256 dust;  // Urn Debt Floor            [rad]
    }
    struct Urn {
        uint256 ink;   // Locked Collateral  [amount]
        uint256 art;   // Normalised Debt    [amount]
    }

    mapping (bytes32 => Ilk)                       public ilks;
    mapping (bytes32 => mapping (address => Urn )) public urns;
    mapping (bytes32 => mapping (address => uint)) public tokenCollateral;  // [amount]
    mapping (address => uint256)                   public dai;  // [rad]
    mapping (address => uint256)                   public sin;  // [rad]

    uint256 public debt;  // Total Dai Issued    [rad]
    uint256 public vice;  // Total Unbacked Dai  [rad]
    uint256 public Line;  // Total Debt Ceiling  [rad]
    bool public DSRisActive;  // Access Flag

    // --- Logs ---
    event LogNote(
        bytes4   indexed  sig,
        bytes32  indexed  arg1,
        bytes32  indexed  arg2,
        bytes32  indexed  arg3,
        bytes             data
    ) anonymous;

    modifier emitLog {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: the selector and the first three args
            let mark := msize                         // end of memory ensures zero
            mstore(0x40, add(mark, 288))              // update free memory pointer
            mstore(mark, 0x20)                        // bytes type data offset
            mstore(add(mark, 0x20), 224)              // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)     // bytes payload
            log4(mark, 288,                           // calldata
                 shl(224, shr(224, calldataload(0))), // msg.sig
                 calldataload(4),                     // arg1
                 calldataload(36),                    // arg2
                 calldataload(68)                     // arg3
                )
        }
    }

    // --- Init ---
    constructor() public {
        authorizedAccounts[msg.sender] = true;
        DSRisActive = true;
    }

    // --- Math ---
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function sub(uint x, int y) internal pure returns (uint z) {
        z = x - uint(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function mul(uint x, int y) internal pure returns (int z) {
        z = int(x) * y;
        require(int(x) >= 0);
        require(y == 0 || z / y == int(x));
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function init(bytes32 ilk) external emitLog onlyOwners {
        require(ilks[ilk].accumulatedRates  == 0, "CDPEngineInstance/ilk-already-init");
        ilks[ilk].accumulatedRates  = 10 ** 27;
    }
    function file(bytes32 what, uint data) external emitLog onlyOwners {
        require(DSRisActive, "CDPEngineInstance/not-DSRisActive");
        if (what == "Line") Line = data;
        else revert("CDPEngineInstance/file-unrecognized-param");
    }
    function file(bytes32 ilk, bytes32 what, uint data) external emitLog onlyOwners {
        require(DSRisActive, "CDPEngineInstance/not-DSRisActive");
        if (what == "spot") ilks[ilk].spot = data;
        else if (what == "line") ilks[ilk].line = data;
        else if (what == "dust") ilks[ilk].dust = data;
        else revert("CDPEngineInstance/file-unrecognized-param");
    }
    function cage() external emitLog onlyOwners {
        DSRisActive = false;
    }

    // --- Fungibility ---
    function slip(bytes32 ilk, address usr, int256 amount) external emitLog onlyOwners {
        tokenCollateral[ilk][usr] = add(tokenCollateral[ilk][usr], amount);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 amount) external emitLog {
        require(wish(src, msg.sender), "CDPEngineInstance/not-allowed");
        tokenCollateral[ilk][src] = sub(tokenCollateral[ilk][src], amount);
        tokenCollateral[ilk][dst] = add(tokenCollateral[ilk][dst], amount);
    }
    function move(address src, address dst, uint256 rad) external emitLog {
        require(wish(src, msg.sender), "CDPEngineInstance/not-allowed");
        dai[src] = sub(dai[src], rad);
        dai[dst] = add(dai[dst], rad);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- CDP Manipulation ---
    function frob(bytes32 i, address u, address v, address w, int dink, int dart) external emitLog {
        // system is DSRisActive
        require(DSRisActive, "CDPEngineInstance/not-DSRisActive");

        Urn memory urn = urns[i][u];
        Ilk memory ilk = ilks[i];
        // ilk has been initialised
        require(ilk.accumulatedRates  != 0, "CDPEngineInstance/ilk-not-init");

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.debtAmount = add(ilk.debtAmount, dart);

        int dtab = mul(ilk.accumulatedRates , dart);
        uint tab = mul(ilk.accumulatedRates , urn.art);
        debt     = add(debt, dtab);

        // either debt has decreased, or debt ceilings are not exceeded
        require(either(dart <= 0, both(mul(ilk.debtAmount, ilk.accumulatedRates ) <= ilk.line, debt <= Line)), "CDPEngineInstance/ceiling-exceeded");
        // urn is either less risky than before, or it is safe
        require(either(both(dart <= 0, dink >= 0), tab <= mul(urn.ink, ilk.spot)), "CDPEngineInstance/not-safe");

        // urn is either more safe, or the owner consents
        require(either(both(dart <= 0, dink >= 0), wish(u, msg.sender)), "CDPEngineInstance/not-allowed-u");
        // collateral src consents
        require(either(dink <= 0, wish(v, msg.sender)), "CDPEngineInstance/not-allowed-v");
        // debt dst consents
        require(either(dart >= 0, wish(w, msg.sender)), "CDPEngineInstance/not-allowed-w");

        // urn has no debt, or a non-dusty amount
        require(either(urn.art == 0, tab >= ilk.dust), "CDPEngineInstance/dust");

        tokenCollateral[i][v] = sub(tokenCollateral[i][v], dink);
        dai[w]    = add(dai[w],    dtab);

        urns[i][u] = urn;
        ilks[i]    = ilk;
    }
    // --- CDP Fungibility ---
    function fork(bytes32 ilk, address src, address dst, int dink, int dart) external emitLog {
        Urn storage u = urns[ilk][src];
        Urn storage v = urns[ilk][dst];
        Ilk storage i = ilks[ilk];

        u.ink = sub(u.ink, dink);
        u.art = sub(u.art, dart);
        v.ink = add(v.ink, dink);
        v.art = add(v.art, dart);

        uint utab = mul(u.art, i.accumulatedRates );
        uint vtab = mul(v.art, i.accumulatedRates );

        // both sides consent
        require(both(wish(src, msg.sender), wish(dst, msg.sender)), "CDPEngineInstance/not-allowed");

        // both sides safe
        require(utab <= mul(u.ink, i.spot), "CDPEngineInstance/not-safe-src");
        require(vtab <= mul(v.ink, i.spot), "CDPEngineInstance/not-safe-dst");

        // both sides non-dusty
        require(either(utab >= i.dust, u.art == 0), "CDPEngineInstance/dust-src");
        require(either(vtab >= i.dust, v.art == 0), "CDPEngineInstance/dust-dst");
    }
    // --- CDP Confiscation ---
    function grab(bytes32 i, address u, address v, address w, int dink, int dart) external emitLog onlyOwners {
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.debtAmount = add(ilk.debtAmount, dart);

        int dtab = mul(ilk.accumulatedRates , dart);

        tokenCollateral[i][v] = sub(tokenCollateral[i][v], dink);
        sin[w]    = sub(sin[w],    dtab);
        vice      = sub(vice,      dtab);
    }

    // --- Settlement ---
    function heal(uint rad) external emitLog {
        address u = msg.sender;
        sin[u] = sub(sin[u], rad);
        dai[u] = sub(dai[u], rad);
        vice   = sub(vice,   rad);
        debt   = sub(debt,   rad);
    }
    function suck(address u, address v, uint rad) external emitLog onlyOwners {
        sin[u] = add(sin[u], rad);
        dai[v] = add(dai[v], rad);
        vice   = add(vice,   rad);
        debt   = add(debt,   rad);
    }

    // --- Rates ---
    function fold(bytes32 i, address u, int accumulatedRates ) external emitLog onlyOwners {
        require(DSRisActive, "CDPEngineInstance/not-DSRisActive");
        Ilk storage ilk = ilks[i];
        ilk.accumulatedRates  = add(ilk.accumulatedRates , accumulatedRates );
        int rad  = mul(ilk.debtAmount, accumulatedRates );
        dai[u]   = add(dai[u], rad);
        debt     = add(debt,   rad);
    }
}