// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import { Ownable } from "@openzeppelin/contracts-0.6/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import { IPoints } from "../interfaces/IPoints.sol";

/**
 * @author  Hyperlock Finance
 */
abstract contract BasePointsDeposits is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    /// @dev The max amount of time a user can lock their token
    uint256 public constant MAX_LOCK_TIME = 8 weeks;
    /// @dev To force all locks to expire and enable withdrawals
    bool public forceExpireLocks = false;
    /// @dev The points contract
    IPoints public immutable points;
    /// @dev user => key => lock time
    mapping(address => mapping(bytes32 => uint256)) public locks;
    /// @dev lpToken => isProtected
    mapping(address => bool) public isProtectedToken;

    /* -------------------------------------------------------------------
       Events 
    ------------------------------------------------------------------- */

    event SetForceExpireLocks(bool force);

    /* -------------------------------------------------------------------
       Constructor 
    ------------------------------------------------------------------- */

    constructor(address _points) public {
        points = IPoints(_points);
    }

    /* -------------------------------------------------------------------
       Admin 
    ------------------------------------------------------------------- */

    function setForceExpireLocks(bool _force) external onlyOwner {
        forceExpireLocks = _force;
        emit SetForceExpireLocks(_force);
    }

    function transferERC20(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(!isProtectedToken[_token], "protected");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /* --------------------------------------------------------------
       Utils 
    -------------------------------------------------------------- */

    function _isLockExpired(address _sender, bytes32 _lockKey) internal view returns (bool) {
        if (forceExpireLocks) return true;
        uint256 expiresAt = locks[_sender][_lockKey];
        return block.timestamp >= expiresAt;
    }

    function _updateLockTime(
        address _sender,
        bytes32 _lockKey,
        uint256 _lock
    ) internal returns (bool lockUpdated) {
        require(_lock <= MAX_LOCK_TIME, "max lock time");
        uint256 currLock = locks[_sender][_lockKey];
        uint256 newLock = block.timestamp.add(_lock);
        if (newLock > currLock) {
            locks[_sender][_lockKey] = newLock;
            lockUpdated = true;
        }
    }
}
