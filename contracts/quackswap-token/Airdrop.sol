// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IQUACK {
    function balanceOf(address account) external view returns (uint);
    function transfer(address dst, uint rawAmount) external returns (bool);
}

/**
 *  Contract for administering the Airdrop of xQUACK to QUACK holders.
 *  Arbitrary amount QUACK will be made available in the airdrop. After the
 *  Airdrop period is over, all unclaimed QUACK will be transferred to the
 *  community treasury.
 */
contract Airdrop {
    address public immutable quack;
    address public owner;
    address public whitelister;
    address public remainderDestination;

    // amount of QUACK to transfer
    mapping (address => uint) public withdrawAmount;

    uint public totalAllocated;
    uint public airdropSupply;

    bool public claimingAllowed;

    /**
     * Initializes the contract. Sets token addresses, owner, and leftover token
     * destination. Claiming period is not enabled.
     *
     * @param quack_ the QUACK token contract address
     * @param owner_ the privileged contract owner
     * @param remainderDestination_ address to transfer remaining QUACK to when
     *     claiming ends. Should be community treasury.
     */
    constructor(
        uint supply_,
        address quack_,
        address owner_,
        address remainderDestination_
    ) {
        require(owner_ != address(0), 'Airdrop::Construct: invalid new owner');
        require(quack_ != address(0), 'Airdrop::Construct: invalid quack address');

        airdropSupply = supply_;
        quack = quack_;
        owner = owner_;
        remainderDestination = remainderDestination_;
    }

    /**
     * Changes the address that receives the remaining QUACK at the end of the
     * claiming period. Can only be set by the contract owner.
     *
     * @param remainderDestination_ address to transfer remaining QUACK to when
     *     claiming ends.
     */
    function setRemainderDestination(address remainderDestination_) external {
        require(
            msg.sender == owner,
            'Airdrop::setRemainderDestination: unauthorized'
        );
        remainderDestination = remainderDestination_;
    }

    /**
     * Changes the contract owner. Can only be set by the contract owner.
     *
     * @param owner_ new contract owner address
     */
    function setOwner(address owner_) external {
        require(owner_ != address(0), 'Airdrop::setOwner: invalid new owner');
        require(msg.sender == owner, 'Airdrop::setOwner: unauthorized');
        owner = owner_;
    }

    /**
     *  Optionally set a secondary address to manage whitelisting (e.g. a bot)
     */
    function setWhitelister(address addr) external {
        require(msg.sender == owner, 'Airdrop::setWhitelister: unauthorized');
        whitelister = addr;
    }

    function setAirdropSupply(uint supply) external {
        require(msg.sender == owner, 'Airdrop::setAirdropSupply: unauthorized');
        require(
            !claimingAllowed,
            'Airdrop::setAirdropSupply: claiming in session'
        );
        require(
            supply >= totalAllocated,
            'Airdrop::setAirdropSupply: supply less than total allocated'
        );
        airdropSupply = supply;
    }

    /**
     * Enable the claiming period and allow user to claim QUACK. Before
     * activation, this contract must have a QUACK balance equal to airdropSupply
     * All claimable QUACK tokens must be whitelisted before claiming is enabled.
     * Only callable by the owner.
     */
    function allowClaiming() external {
        require(IQUACK(quack).balanceOf(
            address(this)) >= airdropSupply,
            'Airdrop::allowClaiming: incorrect QUACK supply'
        );
        require(msg.sender == owner, 'Airdrop::allowClaiming: unauthorized');
        claimingAllowed = true;
        emit ClaimingAllowed();
    }

    /**
     * End the claiming period. All unclaimed QUACK will be transferred to the address
     * specified by remainderDestination. Can only be called by the owner.
     */
    function endClaiming() external {
        require(msg.sender == owner, 'Airdrop::endClaiming: unauthorized');
        require(claimingAllowed, "Airdrop::endClaiming: Claiming not started");

        claimingAllowed = false;

        // Transfer remainder
        uint amount = IQUACK(quack).balanceOf(address(this));
        require(
            IQUACK(quack).transfer(remainderDestination, amount),
            'Airdrop::endClaiming: Transfer failed'
        );

        emit ClaimingOver();
    }

    /**
     * Withdraw your QUACK. In order to qualify for a withdrawal, the
     * caller's address must be whitelisted. All QUACK must be claimed at
     * once. Only the full amount can be claimed and only one claim is
     * allowed per user.
     */
    function claim() external {
        require(claimingAllowed, 'Airdrop::claim: Claiming is not allowed');
        require(
            withdrawAmount[msg.sender] > 0,
            'Airdrop::claim: No QUACK to claim'
        );

        uint amountToClaim = withdrawAmount[msg.sender];
        withdrawAmount[msg.sender] = 0;

        require(
            IQUACK(quack).transfer(msg.sender, amountToClaim),
            'Airdrop::claim: Transfer failed'
        );

        emit QuackClaimed(msg.sender, amountToClaim);
    }

    /**
     * Whitelist multiple addresses in one call.
     * All parameters are arrays. Each array must be the same length. Each index
     * corresponds to one (address, quack) tuple. Callable by the owner or whitelister.
     */
    function whitelistAddresses(
        address[] memory addrs,
        uint[] memory quackOuts
    ) external {
        require(
            !claimingAllowed,
            'Airdrop::whitelistAddresses: claiming in session'
        );
        require(
            msg.sender == owner || msg.sender == whitelister,
            'Airdrop::whitelistAddresses: unauthorized'
        );
        require(
            addrs.length == quackOuts.length,
            'Airdrop::whitelistAddresses: incorrect array length'
        );
        for (uint i; i < addrs.length; ++i) {
            address addr = addrs[i];
            uint quackOut = quackOuts[i];
            totalAllocated = totalAllocated + quackOut - withdrawAmount[addr];
            withdrawAmount[addr] = quackOut;
        }
        require(
            totalAllocated <= airdropSupply,
            'Airdrop::whitelistAddresses: Exceeds QUACK allocation'
        );
    }

    // Events
    event ClaimingAllowed();
    event ClaimingOver();
    event QuackClaimed(address claimer, uint amount);
}
