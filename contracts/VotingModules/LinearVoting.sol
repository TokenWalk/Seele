// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../common/Enum.sol";

contract LinearVoting {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Delegation {
        mapping(address => uint256) votes;
        uint256 lastBlock;
        uint256 total;
        uint256 proposalCount;
    }

    address private _governanceToken;
    address private _proposalModule;

    mapping(address => Delegation) public delegations;

    modifier onlyProposalModule() {
        require(msg.sender == _proposalModule, "TW023");
        _;
    }

    event VotesDelegated(uint256 number);
    event VotesUndelegated(uint256 number);

    constructor(address governanceToken_, address proposalModule_) {
        _governanceToken = governanceToken_;
        _proposalModule = proposalModule_;
    }

    function governanceToken() public view virtual returns (address) {
        return _governanceToken;
    }

    function delegateVotes(address delegatee, uint256 amount) external {
        IERC20(_governanceToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        delegations[delegatee].votes[msg.sender] = amount;
        delegations[delegatee].lastBlock = block.number;
        // can make the total 1-1 here
        delegations[delegatee].total = delegations[delegatee].total.add(amount);
    }

    function undelegateVotes(address delegatee, uint256 amount) external {
        require(delegations[delegatee].proposalCount == 0, "TW024");
        require(delegations[delegatee].votes[msg.sender] >= amount, "TW020");
        IERC20(_governanceToken).safeTransfer(msg.sender, amount);
        delegations[delegatee].votes[msg.sender] = delegations[delegatee]
            .votes[msg.sender]
            .sub(amount);
        delegations[delegatee].total = delegations[delegatee].total.sub(amount);
    }

    function startVoting(address delegatee) external onlyProposalModule {
        delegations[delegatee].proposalCount = delegations[delegatee]
            .proposalCount
            .add(1);
    }

    function endVoting(address delegatee) external onlyProposalModule {
        delegations[delegatee].proposalCount = delegations[delegatee]
            .proposalCount
            .sub(1);
    }

    function calculateWeight(address delegatee)
        external
        view
        returns (uint256)
    {
        require(delegations[delegatee].lastBlock < block.number, "TW021"); // todo move this to a check function
        // can return quadtric here
        return delegations[delegatee].total;
    }
}
