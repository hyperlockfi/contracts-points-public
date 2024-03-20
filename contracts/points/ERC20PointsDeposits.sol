// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import { IERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts-0.6/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import { IPoints } from "../interfaces/IPoints.sol";
import { BasePointsDeposits } from "./BasePointsDeposits.sol";

/**
 * @author  Hyperlock Finance
 */
contract ERC20PointsDeposits is BasePointsDeposits, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    /// @dev user => lptoken => amount
    mapping(address => mapping(address => uint256)) public staked;

    /* -------------------------------------------------------------------
       Events 
    ------------------------------------------------------------------- */

    event LockedERC20(address sender, bytes32 lockKey, address lptoken);
    event Stake(address lpToken, address sender, uint256 amount);
    event Unstake(address lpToken, address sender, uint256 amount);

    /* -------------------------------------------------------------------
       Constructor 
    ------------------------------------------------------------------- */

    constructor(address _points) public BasePointsDeposits(_points) {}

    /* -------------------------------------------------------------------
       ERC20 LP Tokens 
    ------------------------------------------------------------------- */

    function stake(
        address _lpToken,
        uint256 _amount,
        uint256 _lock
    ) external nonReentrant {
        require(points.pools(_lpToken), "invalid lp token");
        bytes32 lockKey = keccak256(abi.encode("erc20", _lpToken));
        bool lockUpdated = _updateLockTime(msg.sender, lockKey, _lock);

        if (_amount > 0) {
            staked[msg.sender][_lpToken] = staked[msg.sender][_lpToken].add(_amount);
            if (!isProtectedToken[_lpToken]) {
                isProtectedToken[_lpToken] = true;
            }
            IERC20(_lpToken).safeTransferFrom(msg.sender, address(this), _amount);
            emit Stake(_lpToken, msg.sender, _amount);
        }

        if (_lock > 0 && lockUpdated) {
            emit LockedERC20(msg.sender, lockKey, _lpToken);
        }
    }

    function unstake(address _lpToken, uint256 _amount) external nonReentrant {
        require(_isLockExpired(msg.sender, keccak256(abi.encode("erc20", _lpToken))), "!expired");
        staked[msg.sender][_lpToken] = staked[msg.sender][_lpToken].sub(_amount);
        IERC20(_lpToken).transfer(msg.sender, _amount);
        emit Unstake(_lpToken, msg.sender, _amount);
    }
}
