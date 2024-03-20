// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../interfaces/INonfungiblePositionManagerStruct.sol";

interface INfpOps is INonfungiblePositionManagerStruct {
    function withdrawPosition(uint256 _tokenId, address _to) external;

    function collect(CollectParams memory params) external returns (uint256, uint256);

    function increaseLiquidity(IncreaseLiquidityParams memory params) external payable;

    function decreaseLiquidity(DecreaseLiquidityParams memory params) external;

    function harvestPosition(uint256 _tokenId, address _to) external returns (uint256);
}
