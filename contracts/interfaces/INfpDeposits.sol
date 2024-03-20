// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import "../interfaces/INonfungiblePositionManagerStruct.sol";

interface INfpDeposits is INonfungiblePositionManagerStruct {
    struct UserPositionInfo {
        uint128 liquidity;
        uint128 boostLiquidity;
        int24 tickLower;
        int24 tickUpper;
        uint256 rewardGrowthInside;
        uint256 reward;
        address user;
        uint256 pid;
        uint256 boostMultiplier;
    }

    function userPositionInfos(uint256 tokenId) external view returns (UserPositionInfo memory);

    function withdraw(uint256 _tokenId, address _to) external returns (uint256 reward);

    function harvest(uint256 _tokenId, address _to) external returns (uint256 reward);

    function collect(CollectParams memory params) external returns (uint256 amount0, uint256 amount1);

    function decreaseLiquidity(DecreaseLiquidityParams memory params)
        external
        returns (uint256 amount0, uint256 amount1);

    function increaseLiquidity(IncreaseLiquidityParams memory params)
        external
        payable
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function pendingCake(uint256 _tokenId) external view returns (uint256 reward);

    function updateLiquidity(uint256 _tokenId) external;

    function updatePools(uint256[] calldata pids) external;

    function owner() external view returns (address);

    function receiver() external view returns (address);

    function upkeep(
        uint256 _amount,
        uint256 _duration,
        bool _withUpdate
    ) external;

    function getLatestPeriodInfo(address) external returns (uint256 rewardPerSecond, uint256 endTime);

    function nonfungiblePositionManager() external returns (address);
}
