// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import { Ownable } from "@openzeppelin/contracts-0.6/access/Ownable.sol";
import { MerkleProof } from "@openzeppelin/contracts-0.6/cryptography/MerkleProof.sol";
import { Multicall } from "../nfp/Multicall.sol";

/**
 * @author  Hyperlock Finance
 * @notice  - Claim point
 *          - Track points balances
 *          - Allocate points to pools
 *          - Manage roots
 */
contract Points is Ownable, Multicall {
    using SafeMath for uint256;

    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    /// @dev The length of a claim/allocate epoch
    uint256 public constant EPOCH_LENGTH = 1 weeks;

    /// @dev user => balance
    mapping(address => uint256) public balanceOf;

    /// @dev pool => balance
    mapping(address => uint256) public allocOf;

    /// @dev user => epoch => balance
    mapping(address => mapping(uint256 => uint256)) public balanceOfAt;

    /// @dev user => epoch => allocated
    mapping(address => mapping(uint256 => uint256)) public allocatedOfAt;

    /// @dev pool => epoch => weight
    mapping(address => mapping(uint256 => uint256)) public allocOfAt;

    /// @dev pool => isActive
    mapping(address => bool) public pools;

    /// @dev epoch => root
    mapping(uint256 => bytes32) public roots;

    /// @dev user => salt => claimed
    mapping(address => mapping(bytes32 => bool)) public isClaimedZero;

    /* -------------------------------------------------------------------
       Events 
    ------------------------------------------------------------------- */

    event PoolAdded(address pool, bool isActive);
    event RootAdded(uint256 epoch, bytes32 root);
    event Claimed(address sender, uint256 epoch, uint256 amount);
    event Allocated(address sender, uint256 epoch, address pool, uint256 amount);

    /* -------------------------------------------------------------------
       Owner 
    ------------------------------------------------------------------- */

    /**
     * @notice Add new merkle root
     * @dev Only callable by the contract owner
     * @param _epoch The epoch to add the root for
     * @param _root The merkle root to add
     */
    function addRoot(uint256 _epoch, bytes32 _root) external onlyOwner {
        roots[_epoch] = _root;
        emit RootAdded(_epoch, _root);
    }

    /**
     * @notice Add a pool
     * @dev Only callable by the contract owner
     * @param _pool The pool address
     * @param _isActive If the pool is active
     */
    function addPool(address _pool, bool _isActive) external onlyOwner {
        pools[_pool] = _isActive;
        emit PoolAdded(_pool, _isActive);
    }

    /* -------------------------------------------------------------------
       Core 
    ------------------------------------------------------------------- */

    /**
     * @notice  Claim points for ZERO epoch (points airdrop)
     * @dev     - Can only claim once
     *
     * @param _proof The merkle root proof
     * @param _amount The amount of points to claim
     */
    function claimZero(
        bytes32[] calldata _proof,
        bytes32 _salt,
        uint256 _amount
    ) external {
        require(!isClaimedZero[msg.sender][_salt], "already claimed");
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _salt, _amount));
        require(MerkleProof.verify(_proof, roots[0], leaf), "invalid proof");

        isClaimedZero[msg.sender][_salt] = true;
        balanceOf[msg.sender] = balanceOf[msg.sender].add(_amount);

        emit Allocated(msg.sender, 0, address(0), _amount);
    }

    /**
     * @notice  Claim points
     * @dev     - Can only claim once per epoch
     *
     * @param _proof The merkle root proof
     * @param _amount The amount of points to claim
     */
    function claim(bytes32[] calldata _proof, uint256 _amount) external {
        uint256 epoch = _getCurrentEpoch();
        _claim(msg.sender, epoch, _proof, _amount);
    }

    /**
     * @notice  Claim points
     * @param _sender The account to send points to
     * @param _epoch The epoch to claim points for
     * @param _proof The merkle root proof
     * @param _amount The amount of points to claim
     */
    function _claim(
        address _sender,
        uint256 _epoch,
        bytes32[] calldata _proof,
        uint256 _amount
    ) internal {
        bytes32 leaf = keccak256(abi.encodePacked(_sender, _epoch, _amount));

        require(balanceOfAt[_sender][_epoch] == 0, "already claimed");
        require(MerkleProof.verify(_proof, roots[_epoch], leaf), "invalid proof");

        balanceOfAt[_sender][_epoch] = _amount;

        emit Claimed(_sender, _epoch, _amount);
    }

    /**
     * @notice  Allocate points to a pool
     * @dev     - Can only allocate points for the current epoch
     *          - Can only allocate to a valid pool
     *          - Can only allocate up to their epoch balance
     *          - Allocated balance gets assigned to their total balance
     *
     * @param _pool The pool to allocate points to
     * @param _amount The amount of points to allocate
     */
    function allocate(address _pool, uint256 _amount) external {
        uint256 epoch = _getCurrentEpoch();
        uint256 bal = balanceOfAt[msg.sender][epoch];
        require(bal >= _amount, "not enough balance for this epoch");

        uint256 allocated = allocatedOfAt[msg.sender][epoch];
        uint256 remaining = bal.sub(allocated);
        require(pools[_pool], "invalid pool");
        require(remaining >= _amount, "not enough remaining balance");

        allocOf[_pool] = allocOf[_pool].add(_amount);
        allocOfAt[_pool][epoch] = allocOfAt[_pool][epoch].add(_amount);

        balanceOf[msg.sender] = balanceOf[msg.sender].add(_amount);
        allocatedOfAt[msg.sender][epoch] = allocatedOfAt[msg.sender][epoch].add(_amount);

        emit Allocated(msg.sender, epoch, _pool, _amount);
    }

    /* -------------------------------------------------------------------
       Utils 
    ------------------------------------------------------------------- */

    function getCurrentEpoch() external view returns (uint256) {
        return _getCurrentEpoch();
    }

    function _getCurrentEpoch() internal view returns (uint256) {
        return block.timestamp.div(EPOCH_LENGTH);
    }
}
