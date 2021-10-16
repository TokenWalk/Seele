// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./BaseTokenVoting.sol";

/// @title Compound like Linear Voting Strategy - A Seele strategy that enables compound like voting.
/// @notice This strategy differs in a few ways from compound bravo
/// @notice There are no min/max threshold checks
/// @notice There are no limits to the number of transactions that can be executed, hashes stored on proposal core
/// @notice More than one active proposal per proposer is allowed
/// @notice Only owner is allowed to cancel proposals (safety strat or governance)
/// @author Nathan Ginnever - <team@tokenwalk.org>
contract CompoundBravoVoting is BaseTokenVoting {
    /**
     * @dev Receipt structure from Compound Governor Bravo
     */
    struct Receipt {
        bool hasVoted;
        uint8 support;
        uint96 votes;
    }

    struct ProposalComp {
        mapping(address => Receipt) receipts;
        bytes32 descriptionHash;
    }

    ERC20VotesComp public immutable governanceToken;
    uint256 public proposalThreshold;

    mapping(uint256 => ProposalComp) proposalsComp;

    event ProposalThresholdUpdated(
        uint256 previousThreshold,
        uint256 newThreshold
    );

    constructor(
        uint256 _proposalThreshold,
        uint256 _votingPeriod,
        ERC20VotesComp _governanceToken,
        address _seeleModule,
        uint256 _quorumThreshold,
        uint256 _timeLockPeriod,
        address _owner,
        string memory name_
    )
        BaseTokenVoting(
            _votingPeriod,
            _seeleModule,
            _quorumThreshold,
            _timeLockPeriod,
            _owner,
            name_
        )
    {
        require(
            _governanceToken != ERC20VotesComp(address(0)),
            "invalid governance token address"
        );
        governanceToken = _governanceToken;
        proposalThreshold = _proposalThreshold;
    }

    /// @dev Updates the votes needed to create a proposal, only executor.
    /// @param _proposalThreshold the voting quorum threshold.
    function updateProposalThreshold(uint256 _proposalThreshold)
        external
        onlyOwner
    {
        uint256 previousThreshold = proposalThreshold;
        proposalThreshold = _proposalThreshold;
        emit ProposalThresholdUpdated(previousThreshold, _proposalThreshold);
    }

    /**
     * @dev See {IGovernorCompatibilityBravo-getReceipt}.
     */
    function getReceipt(uint256 proposalId, address voter)
        public
        view
        returns (Receipt memory)
    {
        return proposalsComp[proposalId].receipts[voter];
    }

    /// @dev Submits a vote for a proposal.
    /// @param proposalId the proposal to vote for.
    /// @param support against, for, or abstain.
    function vote(uint256 proposalId, uint8 support) external override {
        proposalsComp[proposalId].receipts[msg.sender].hasVoted = true;
        proposalsComp[proposalId].receipts[msg.sender].support = support;
        proposalsComp[proposalId].receipts[msg.sender].votes = SafeCast
            .toUint96(calculateWeight(msg.sender, proposalId));
        _vote(proposalId, msg.sender, support);
    }

    /// @dev Submits a vote for a proposal by ERC712 signature.
    /// @param proposalId the proposal to vote for.
    /// @param support against, for, or abstain.
    /// @param signature 712 signed vote
    function voteSignature(
        uint256 proposalId,
        uint8 support,
        bytes memory signature
    ) external override {
        address voter = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(abi.encode(VOTE_TYPEHASH, proposalId, support))
            ),
            signature
        );
        proposalsComp[proposalId].receipts[voter].hasVoted = true;
        proposalsComp[proposalId].receipts[voter].support = support;
        proposalsComp[proposalId].receipts[voter].votes = SafeCast.toUint96(
            calculateWeight(voter, proposalId)
        );
        _vote(proposalId, voter, support);
    }

    /// @dev Called by the proposal module, this notifes the strategy of a new proposal.
    /// @param data any extra data to pass to the voting strategy
    function receiveProposal(bytes memory data) external override onlySeele {
        (uint256 proposalId, address proposer, bytes32 _descriptionHash) = abi
            .decode(data, (uint256, address, bytes32));
        require(
            governanceToken.getPriorVotes(proposer, sub256(block.number, 1)) >
                proposalThreshold,
            "proposer votes below proposal threshold"
        );
        proposalsComp[proposalId].descriptionHash = _descriptionHash;
        proposals[proposalId].deadline = votingPeriod + block.timestamp;
        proposals[proposalId].startBlock = block.number;
        emit ProposalReceived(proposalId, block.timestamp);
    }

    // TODO: Check storing cast uint96 as uint256
    function calculateWeight(address delegatee, uint256 proposalId)
        public
        view
        override
        returns (uint256)
    {
        return
            governanceToken.getPriorVotes(
                delegatee,
                proposals[proposalId].startBlock
            );
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }
}
