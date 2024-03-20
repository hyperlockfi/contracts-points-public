// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../interfaces/INfpOps.sol";
import "../interfaces/INfpDeposits.sol";
import "../interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";

contract NfpOps is INfpOps {
    /* -------------------------------------------------------------------
       Storage 
    ------------------------------------------------------------------- */

    /// @dev NFPoisition Booster contract
    address public nfpBooster;

    /// @dev Contract the NFPoisition get deposited into (eg MasterChefV3)
    INfpDeposits public nfpDeposits;

    /// @dev Nonfungible Position Manager
    INonfungiblePositionManager public nfpManager;

    /* -------------------------------------------------------------------
      Constructor/Init 
    ------------------------------------------------------------------- */

    function _initNfpOps(
        address _nfpDeposits,
        address _nfpBooster,
        address _nfpManager
    ) internal {
        require(nfpBooster == address(0), "!init");
        nfpDeposits = INfpDeposits(_nfpDeposits);
        nfpBooster = _nfpBooster;
        nfpManager = INonfungiblePositionManager(_nfpManager);
    }

    /* -------------------------------------------------------------------
       Modifiers 
    ------------------------------------------------------------------- */

    modifier onlyBooster() {
        require(msg.sender == nfpBooster, "!booster");
        _;
    }

    /* -------------------------------------------------------------------
       Core 
    ------------------------------------------------------------------- */

    function harvestPosition(uint256 _tokenId, address _to) external override onlyBooster returns (uint256) {
        return nfpDeposits.harvest(_tokenId, _to);
    }

    function decreaseLiquidity(DecreaseLiquidityParams memory params) external override onlyBooster {
        nfpDeposits.decreaseLiquidity(params);
        // Can chain with collect
    }

    function increaseLiquidity(IncreaseLiquidityParams memory params) external payable override onlyBooster {
        (, , address token0, address token1, , , , , , , , ) = nfpManager.positions(params.tokenId);

        IERC20(token0).approve(address(nfpDeposits), params.amount0Desired);
        IERC20(token1).approve(address(nfpDeposits), params.amount1Desired);

        nfpDeposits.increaseLiquidity{ value: msg.value }(params);

        // refund tokens to V3PositionBooster
        _sweepToken(token0, nfpBooster);
        _sweepToken(token1, nfpBooster);
        _sweepETH(nfpBooster);
    }

    function collect(CollectParams memory params) external override onlyBooster returns (uint256, uint256) {
        require(params.recipient != address(0), "!recipient");
        require(params.recipient != address(this), "!recipient");
        return nfpDeposits.collect(params);
    }

    function withdrawPosition(uint256 _tokenId, address _to) external override onlyBooster {
        nfpDeposits.withdraw(_tokenId, _to);
    }

    /// @dev Warning! nfpManager NFTs will be lost if they are sent here directly
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external returns (bytes4) {
        require(msg.sender == address(nfpManager), "!manager");

        nfpManager.safeTransferFrom(address(this), address(nfpDeposits), _tokenId);

        return this.onERC721Received.selector;
    }

    /* -------------------------------------------------------------------
       Utils 
    ------------------------------------------------------------------- */

    function _sweepToken(address _token, address _to) internal {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(_token).transfer(_to, bal);
        }
    }

    function _sweepETH(address _to) internal {
        uint256 bal = address(this).balance;
        if (bal > 0) {
            (bool sent, ) = payable(_to).call{ value: bal }("");
            require(sent, "!sweep");
        }
    }
}
