pragma solidity 0.5.12;

import "./commonFunctions.sol";

contract VatLike {
    function ilks(bytes32) external returns (
        uint256 Art,   // wad
        uint256 rate   // ray
    );
    function fold(bytes32,address,int) external;
}

contract Jug is LogEmitter {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address usr) external emitLog onlyOwners { authorizedAccounts[usr] = 1; }
    function removeAuthorization(address usr) external emitLog onlyOwners { authorizedAccounts[usr] = 0; }
    modifier onlyOwners {
        require(authorizedAccounts[msg.sender] == 1, "Jug/not-onlyOwnersorized");
        _;
    }

    // --- Data ---
    struct Ilk {
        uint256 duty;
        uint256  timeOfLastCollectionRate;
    }

    mapping (bytes32 => Ilk) public ilks;
    VatLike                  public CDPEngine;
    address                  public debtEngine;
    uint256                  public base;

    // --- Init ---
    constructor(address CDPEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        CDPEngine = VatLike(CDPEngine_);
    }

    // --- Math ---
    function rpow(uint x, uint n, uint b) internal pure returns (uint z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }
    uint256 constant ONE = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function diff(uint x, uint y) internal pure returns (int z) {
        z = int(x) - int(y);
        require(int(x) >= 0 && int(y) >= 0);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / ONE;
    }

    // --- Administration ---
    function init(bytes32 ilk) external emitLog onlyOwners {
        Ilk storage i = ilks[ilk];
        require(i.duty == 0, "Jug/ilk-already-init");
        i.duty = ONE;
        i.timeOfLastCollectionRate  = now;
    }
    function file(bytes32 ilk, bytes32 what, uint data) external emitLog onlyOwners {
        require(now == ilks[ilk].timeOfLastCollectionRate, "Jug/timeOfLastCollectionRate-not-updated");
        if (what == "duty") ilks[ilk].duty = data;
        else revert("Jug/file-unrecognized-param");
    }
    function file(bytes32 what, uint data) external emitLog onlyOwners {
        if (what == "base") base = data;
        else revert("Jug/file-unrecognized-param");
    }
    function file(bytes32 what, address data) external emitLog onlyOwners {
        if (what == "debtEngine") debtEngine = data;
        else revert("Jug/file-unrecognized-param");
    }

    // --- Stability Fee Collection ---
    function collectRate(bytes32 ilk) external emitLog returns (uint rate) {
        require(now >= ilks[ilk].timeOfLastCollectionRate, "Jug/invalid-now");
        (, uint prev) = CDPEngine.ilks(ilk);
        rate = rmul(rpow(add(base, ilks[ilk].duty), now - ilks[ilk].timeOfLastCollectionRate, ONE), prev);
        CDPEngine.fold(ilk, debtEngine, diff(rate, prev));
        ilks[ilk].timeOfLastCollectionRate = now;
    }
}
