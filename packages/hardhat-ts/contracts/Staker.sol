pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import 'hardhat/console.sol';
import './ExampleExternalContract.sol';

error DeadlineExceeded(uint256 deadline, uint256 time);
error DeadlineNotReached(uint256 timeLeft);
error NotOpenForWithdraw();
error NothingToWithdraw(address sender, uint256 balance);
error StakeHasBeenCompleted();

/// @title Staker
/// @dev A smart contract for staking ether and executing an external contract if the threshold is reached.
contract Staker {
  ExampleExternalContract public exampleExternalContract;

  mapping(address => uint256) public balances;
  uint256 public constant threshold = 1 ether;
  uint256 public immutable deadline = block.timestamp + 30 minutes;
  bool public openForWithdraw = false;

  event Stake(address indexed staker, uint256 amount);

  modifier stakeNotCompleted() {
    if (exampleExternalContract.completed()) {
      revert StakeHasBeenCompleted();
    }
    _;
  }

  modifier deadlineNotExceeded() {
    if (block.timestamp >= deadline) {
      revert DeadlineExceeded(deadline, block.timestamp);
    }
    _;
  }

  modifier deadlineReached() {
    if (block.timestamp < deadline) {
      revert DeadlineNotReached(timeLeft());
    }
    _;
  }

  /// @dev Initializes the contract with an address of the ExampleExternalContract.
  /// @param exampleExternalContractAddress The address of the ExampleExternalContract.
  constructor(address exampleExternalContractAddress) {
    exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);
  }

  /// @notice Allows users to stake ether by sending it to the contract.
  /// @dev Stakes ether sent by the user and emits a Stake event.
  function stake() public payable deadlineNotExceeded stakeNotCompleted {
    balances[msg.sender] = msg.value;
    emit Stake(msg.sender, msg.value);
  }

  /// @notice Executes the external contract if the threshold is reached, otherwise, allows users to withdraw their stake.
  /// @dev Sets the openForWithdraw flag if the threshold is not reached, otherwise calls the external contract's complete function.
  function execute() external deadlineReached stakeNotCompleted {
    if (address(this).balance < threshold) {
      openForWithdraw = true;
    } else {
      exampleExternalContract.complete{value: address(this).balance}();
    }
  }

  /// @dev Allows users to withdraw their balances if the conditions are met.
  /// @notice This function can only be called after the deadline has passed and the contract balance is below the threshold.
  ///         It reverts with appropriate error messages if any of these conditions are not met or if the user has no balance to withdraw.
  ///         Upon a successful withdrawal, the user's balance is set to 0.
  function withdraw() external deadlineReached stakeNotCompleted {
    uint256 amount = balances[msg.sender];
    if (!openForWithdraw) {
      revert NotOpenForWithdraw();
    }

    if (balances[msg.sender] == 0) {
      revert NothingToWithdraw(msg.sender, amount);
    }

    balances[msg.sender] = 0;

    (bool success, ) = msg.sender.call{value: amount}('');
    require(success, 'Wihtdrawal failed.');
  }

  /// @dev Calculates the time left until the deadline.
  /// @notice If the current block timestamp is greater than or equal to the deadline, it returns 0.
  ///         Otherwise, it returns the remaining time in seconds.
  /// @return The time left until the deadline in seconds as a uint256 value.
  function timeLeft() public view returns (uint256) {
    return block.timestamp >= deadline ? 0 : deadline - block.timestamp;
  }

  /// @notice Fallback function that allows users to stake ether by sending it directly to the contract.
  /// @dev Calls the stake() function to handle the received ether and update user balances.
  receive() external payable {
    stake();
  }
}
