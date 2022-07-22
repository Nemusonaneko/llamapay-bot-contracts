//SPDX-License-Identifier: AGPL-3.0-only

import "./ReentrancyGuard.sol";
import "./BoringBatchable.sol";

pragma solidity ^0.8.0;

interface Payer {
    function owner() external view returns (address);
    function createStream(address _vault, address _payee, uint216 _amountPerSec) external;
    function cancelStream(uint _id) external;
    function withdraw(uint _id, uint _amount) external;
    function getWithdrawable(uint _id) external view returns (uint withdrawable);
}

contract LlamaPayV2Bot is ReentrancyGuard, BoringBatchable {

    address public bot = address(0);
    address public llama = address(0);

    event CreateStreamScheduled(address indexed payer, address indexed vault, address indexed payee, uint216 amountPerSec, uint40 execution);
    event CancelStreamScheduled(address indexed payer, uint id, uint40 execution);
    event AutoWithdrawScheduled(address indexed payer, uint id, uint40 frequency);
    event AutoWithdrawCancelled(address indexed payer, uint id);
    event CreateStreamExecuted(address indexed payer, address indexed vault, address indexed payee, uint216 amountPerSec);
    event CancelStreamExecuted(address indexed payer, uint id);
    event WithdrawExecuted(address indexed payer, uint id);
    event ExecuteFailed(address indexed payer, bytes data);

    mapping(address => uint) public balances;

    function scheduleCreateStream(address _payer, address _vault, address _payee, uint216 _amountPerSec, uint40 _execution) external{
        require(msg.sender == Payer(_payer).owner(), "not owner");
        emit CreateStreamScheduled(_payer, _vault, _payee, _amountPerSec, _execution);
    }

    function scheduleCancelStream(address _payer, uint _id, uint40 _execution) external {
        require(msg.sender == Payer(_payer).owner(), "not owner");
        emit CancelStreamScheduled(_payer, _id, _execution);
    }

    function scheduleAutoWithdrawal(address _payer, uint _id, uint40 _frequency) external {
        require(msg.sender == Payer(_payer).owner(), "not owner");
        emit AutoWithdrawScheduled(_payer, _id, _frequency);
    }

    function cancelAutoWithdrawal(address _payer, uint _id) external {
        require(msg.sender == Payer(_payer).owner(), "not owner");
        emit AutoWithdrawCancelled(_payer, _id);
    }

    function executeCreateStream(address _payer, address _vault, address _payee, uint216 _amountPerSec) external {
        require(msg.sender == bot, "not bot");
        Payer(_payer).createStream(_vault, _payee, _amountPerSec);
        emit CreateStreamExecuted(_payer, _vault, _payee, _amountPerSec);
    }

    function executeCancelStream(address _payer, uint _id) external {
        require(msg.sender == bot, "not bot");
        Payer(_payer).cancelStream(_id);
        emit CancelStreamExecuted(_payer, _id);
    }

    function executeWithdraw(address _payer, uint _id) external {
        require(msg.sender == bot, "not bot");
        uint withdrawable = Payer(_payer).getWithdrawable(_id);
        Payer(_payer).withdraw(_id, withdrawable);
        emit WithdrawExecuted(_payer, _id);
    }

    function deposit(address _payer) external payable nonReentrant {
        balances[_payer] += msg.value;
    }

    function refund(address _payer) external payable {
        address owner = Payer(_payer).owner();
        require(msg.sender == owner);
        uint toSend = balances[_payer];
        balances[_payer] = 0;
        (bool sent,) = owner.call{value: toSend}("");
        require(sent, "failed to send ether");
    }

    function executeTransactions(bytes[] calldata _calls, address _owner) external {
        require(msg.sender == bot, "not bot");
        uint i;
        uint len = _calls.length;
        uint startGas = gasleft();
        for (i = 0; i < len; ++i) {
            bytes calldata call = _calls[i];
            (bool success,) = address(this).delegatecall(call);
            if (!success) {
                emit ExecuteFailed(_owner, call);
            }
        }
        uint gasUsed = (startGas - gasleft()) + 21000;
        uint totalSpent = gasUsed * tx.gasprice;
        balances[_owner] -= totalSpent;
        (bool sent, ) = bot.call{value: totalSpent}("");
        require(sent, "failed to send ether to bot");
    }

    function changeBot(address _newBot) external {
        require(msg.sender == llama, "not llama");
        bot = _newBot;
    }

}