// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts-0.6/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManager.sol";
import { INonfungiblePositionManagerStruct } from "../interfaces/INonfungiblePositionManagerStruct.sol";
import { PoolAddress } from "../thruster/PoolAddress.sol";
import { IPoints } from "../interfaces/IPoints.sol";
import { BasePointsDeposits } from "./BasePointsDeposits.sol";

/**
 * @author  Hyperlock Finance
 */
contract ERC721PointsDeposits is BasePointsDeposits, INonfungiblePositionManagerStruct, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    /// @dev The nonfungible position manager contract
    INonfungiblePositionManager public immutable nfpManager;
    /// @dev user => tokenId => staked
    mapping(address => mapping(uint256 => bool)) public nfps;

    /* -------------------------------------------------------------------
       Events 
    ------------------------------------------------------------------- */

    event LockedERC721(address sender, bytes32 lockKey, uint256 tokenId);
    event Deposit(address pool, address sender, uint256 tokenId);
    event Withdraw(address pool, address sender, uint256 tokenId);

    /* -------------------------------------------------------------------
       Constructor 
    ------------------------------------------------------------------- */

    constructor(address _nfpManager, address _points) public BasePointsDeposits(_points) {
        nfpManager = INonfungiblePositionManager(_nfpManager);
    }

    /* -------------------------------------------------------------------
       Modifiers 
    ------------------------------------------------------------------- */

    modifier onlyPositionOwner(uint256 _tokenId) {
        require(nfps[msg.sender][_tokenId], "not position owner");
        _;
    }

    /* -------------------------------------------------------------------
       NFT LP Tokens 
    ------------------------------------------------------------------- */

    function onERC721Received(
        address,
        address _from,
        uint256 _tokenId,
        bytes calldata
    ) external returns (bytes4) {
        require(msg.sender == address(nfpManager), "!manager");
        address pool = _poolFromTokenId(_tokenId);
        require(points.pools(pool), "invalid pool");

        if (_from != address(0)) {
            nfps[_from][_tokenId] = true;
            emit Deposit(pool, _from, _tokenId);
        }
        return this.onERC721Received.selector;
    }

    function lock(uint256 _tokenId, uint256 _lock) external onlyPositionOwner(_tokenId) {
        bytes32 lockKey = keccak256(abi.encode("erc721", _tokenId));
        bool lockUpdated = _updateLockTime(msg.sender, lockKey, _lock);
        if (lockUpdated) {
            emit LockedERC721(msg.sender, lockKey, _tokenId);
        }
    }

    function withdraw(uint256 _tokenId) external nonReentrant onlyPositionOwner(_tokenId) {
        bytes32 lockKey = keccak256(abi.encode("erc721", _tokenId));
        require(_isLockExpired(msg.sender, lockKey), "!expired");

        address pool = _poolFromTokenId(_tokenId);
        nfps[msg.sender][_tokenId] = false;

        nfpManager.safeTransferFrom(address(this), msg.sender, _tokenId);
        emit Withdraw(pool, msg.sender, _tokenId);
    }

    /* --------------------------------------------------------------
       NFT LP Tokens: Manage Liquidity 
    -------------------------------------------------------------- */

    function decreaseLiquidity(DecreaseLiquidityParams memory params)
        external
        nonReentrant
        onlyPositionOwner(params.tokenId)
    {
        nfpManager.decreaseLiquidity(params);
    }

    function collect(CollectParams memory params)
        external
        nonReentrant
        onlyPositionOwner(params.tokenId)
        returns (uint256, uint256)
    {
        require(params.recipient != address(0), "!recipient");
        nfpManager.collect(params);
    }

    function rebalance(
        uint256 token0In,
        uint256 token1In,
        DecreaseLiquidityParams memory decreaseParams,
        CollectParams memory collectParams,
        MintParams memory mintParams
    ) external nonReentrant onlyPositionOwner(collectParams.tokenId) {
        require(decreaseParams.tokenId == collectParams.tokenId, "!tokenId");
        require(collectParams.recipient != address(0), "!collectRecipient");
        require(mintParams.recipient == address(this), "!mintRecipient");

        address token0;
        address token1;
        uint256 liquidityBefore;
        uint256 tokenIdBefore = collectParams.tokenId;

        {
            uint24 fee;
            (, , token0, token1, fee, , , liquidityBefore, , , , ) = nfpManager.positions(tokenIdBefore);
            // Validate we are minting for the same pool
            require(mintParams.token0 == token0 && mintParams.token1 == token1 && mintParams.fee == fee, "!mintParams");
        }

        uint256 token0BalBefore = IERC20(token0).balanceOf(address(this));
        uint256 token1BalBefore = IERC20(token1).balanceOf(address(this));

        // Close the current position
        nfpManager.decreaseLiquidity(decreaseParams);
        nfpManager.collect(collectParams);
        nfpManager.burn(tokenIdBefore);

        // Mint the new position
        if (token0In > 0) IERC20(token0).safeTransferFrom(msg.sender, address(this), token0In);
        if (token1In > 0) IERC20(token1).safeTransferFrom(msg.sender, address(this), token1In);

        IERC20(token0).approve(address(nfpManager), mintParams.amount0Desired);
        IERC20(token1).approve(address(nfpManager), mintParams.amount1Desired);

        (uint256 tokenIdAfter, uint128 liquidityAfter, , ) = nfpManager.mint(mintParams);

        // Update state and move locks from the old ID to the newly minted one
        bytes32 lockKeyBefore = keccak256(abi.encode("erc721", tokenIdBefore));
        bytes32 lockKeyAfter = keccak256(abi.encode("erc721", tokenIdAfter));
        locks[msg.sender][lockKeyAfter] = locks[msg.sender][lockKeyBefore];
        locks[msg.sender][lockKeyBefore] = 0;
        nfps[msg.sender][tokenIdBefore] = false;
        nfps[msg.sender][tokenIdAfter] = true;

        require(liquidityAfter >= liquidityBefore, "!liquidity");

        uint256 token0BalAfter = IERC20(token0).balanceOf(address(this));
        uint256 token1BalAfter = IERC20(token1).balanceOf(address(this));

        // refund tokens
        _sweepToken(token0, msg.sender, token0BalAfter.sub(token0BalBefore));
        _sweepToken(token1, msg.sender, token1BalAfter.sub(token1BalBefore));
        _sweepETH(msg.sender);

        // emit events
        address pool = _poolFromTokenId(tokenIdAfter);
        emit Withdraw(pool, msg.sender, tokenIdBefore);
        emit Deposit(pool, msg.sender, tokenIdAfter);
        emit LockedERC721(msg.sender, lockKeyAfter, tokenIdAfter);
    }

    /* --------------------------------------------------------------
       Utils 
    -------------------------------------------------------------- */

    function _poolFromTokenId(uint256 _tokenId) internal view returns (address) {
        (, , address token0, address token1, uint24 fee, , , , , , , ) = nfpManager.positions(_tokenId);
        return PoolAddress.computeAddress(nfpManager.factory(), PoolAddress.PoolKey(token0, token1, fee));
    }

    function _sweepToken(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        if (_amount > 0) {
            IERC20(_token).transfer(_to, _amount);
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
