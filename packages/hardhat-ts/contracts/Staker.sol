pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import 'hardhat/console.sol';
import './ExampleExternalContract.sol';

error NoStakeIncluded();
error DeadlineExceeded(uint256 deadline, uint256 time);
error DeadlineNotReached(uint256 secondsLeft);
error NotOpenForWithdrawals();
error NothingToWithdraw(address sender, uint256 balance);
error WithdrawalFailed();
error StakeHasBeenCompleted();
error ExternalContractCallFailed();

/// @title Staker smart contract
/// @dev A smart contract for staking ether and executing an external contract if the threshold is reached.
contract Staker {
  ExampleExternalContract public exampleExternalContract;

  mapping(address => uint256) public balances;
  uint256 public constant threshold = 1 ether;
  uint256 public immutable deadline = block.timestamp + 30 seconds;
  bool public openForWithdraw = false;

  event Stake(address indexed staker, uint256 amount);

  modifier stakeNotCompleted() {
    if (exampleExternalContract.completed()) {
      revert StakeHasBeenCompleted();
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

  /// @notice Allows a user to stake Ether by sending it to the contract.
  /// @dev Increments the user's balance by the amount of Ether sent with the transaction.
  ///      Emits a Stake event upon successful staking.
  ///      Reverts if the deadline has passed or if no Ether is sent with the transaction.
  ///      This function can only be called if the stake has not been completed.
  function stake() public payable stakeNotCompleted {
    uint256 amount = msg.value;

    if (amount == 0) {
      revert NoStakeIncluded();
    }
    if (block.timestamp >= deadline) {
      revert DeadlineExceeded(deadline, block.timestamp);
    }

    balances[msg.sender] += amount;
    emit Stake(msg.sender, amount);
  }

  /// @notice Executes the external contract if the threshold is reached, otherwise, allows users to withdraw their stake.
  /// @dev Sets the openForWithdraw flag if the threshold is not reached, otherwise calls the external contract's complete function.
  function execute() external deadlineReached stakeNotCompleted {
    uint256 contractBalance = address(this).balance;

    if (contractBalance < threshold) {
      openForWithdraw = true;
    } else {
      try exampleExternalContract.complete{value: contractBalance}() {
        // External call succeeded
      } catch {
        revert ExternalContractCallFailed();
      }
    }
  }

  /// @dev Allows users to withdraw their balances if the conditions are met.
  /// @notice This function can only be called after the deadline has passed and the contract balance is below the threshold.
  ///         It reverts with appropriate error messages if any of these conditions are not met or if the user has no balance to withdraw.
  ///         Upon a successful withdrawal, the user's balance is set to 0.
  function withdraw() external deadlineReached stakeNotCompleted {
    uint256 amount = balances[msg.sender];

    if (amount == 0) {
      revert NothingToWithdraw(msg.sender, amount);
    }
    if (!openForWithdraw) {
      revert NotOpenForWithdrawals();
    }

    balances[msg.sender] = 0;

    (bool success, ) = msg.sender.call{value: amount}('');
    if (!success) {
      revert WithdrawalFailed();
    }
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
