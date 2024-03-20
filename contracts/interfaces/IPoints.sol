// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface IPoints {
    function pools(address _pool) external view returns (bool);
}
