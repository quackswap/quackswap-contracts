pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath.sol";

contract QUACK {
    /// @notice EIP-20 token name for this token
    string public name;

    /// @notice EIP-20 token symbol for this token
    string public symbol;

    /// @notice Contract administrator (e.g. governance)
    address public admin;

    /// @notice Only address that can mint (e.g. vesting contract)
    address public minter;

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @notice Maximum number of tokens that can be in circulation
    uint public maxSupply;

    /// @notice Total number of tokens in circulation
    uint public totalSupply;

    /// @notice Total number of tokens that has been burned
    uint public burnedSupply;

    /// @notice Disables changing max supply when true
    bool public hardcapped;

    /// @notice Allowance amounts on behalf of others
    mapping (address => mapping (address => uint256)) internal allowances;

    /// @notice Official record of token balances for each account
    mapping (address => uint256) internal balances;

    /// @notice A record of each accounts delegate
    mapping (address => address) public delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /// @notice An event thats emitted when the minter address changes
    event MinterChanged(address indexed oldMinter, address indexed newMinter);

    /// @notice An event thats emitted when the admin address changes
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    /// @notice An event thats emitted when the maxSupply changed
    event MaxSupplyChanged(uint oldMaxSupply, uint newMaxSupply);

    /// @notice An event thats emitted when maxSupply becomes immutable
    event HardcapEnabled();

    /// @notice The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice The standard EIP-20 approval event
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /**
     * @notice Construct a new QUACK token
     * @param _maxSupply Maximum number of tokens that can be in circulation
     * @param initialSupply Number of tokens to mint to the message sender
     * @param _symbol EIP-20 token symbol for this token
     * @param _name EIP-20 token name for this token
     */
    constructor(uint _maxSupply, uint256 initialSupply, string memory _symbol, string memory _name) public {
        maxSupply = _maxSupply;
        admin = msg.sender;
        _mintTokens(admin, initialSupply);
        symbol = _symbol;
        name = _name;
    }

    /**
     * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param account The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(address account, address spender) external view returns (uint) {
        return allowances[account][spender];
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Triggers an approval from owner to spends
     * @param owner The address to approve from
     * @param spender The address to be approved
     * @param amount The number of tokens that are approved (2^256-1 means infinite)
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(address owner, address spender, uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "QUACK::permit: invalid signature");
        require(signatory == owner, "QUACK::permit: unauthorized");
        require(now <= deadline, "QUACK::permit: signature expired");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view returns (uint) {
        return balances[account];
    }

    /**
     * @notice Mint `amount` tokens to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to mint
     * @return Whether or not the transfer succeeded
     */
    function mint(address dst, uint256 amount) external returns (bool) {
        require(msg.sender == minter && minter != address(0), "QUACK::mint: unauthorized");
        _mintTokens(dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 amount) external returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint256 amount) external returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowances[src][spender];

        if (spender != src && spenderAllowance != uint256(-1)) {
            uint256 newAllowance = sub256(spenderAllowance, amount, "QUACK::transferFrom: transfer amount exceeds spender allowance");
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    /**
     * @notice Burn `amount` tokens of `msg.sender`
     * @param amount The number of tokens to burn
     * @return Whether or not the burn succeeded
     */
    function burn(uint256 amount) external returns (bool) {
        _burnTokens(msg.sender, amount);
        return true;
    }

    /**
     * @notice Burn `amount` tokens of `src`
     * @param src The address of the source account
     * @param amount The number of tokens to burn
     * @return Whether or not the transfer succeeded
     */
    function burnFrom(address src, uint256 amount) external returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowances[src][spender];

        if (spender != src && spenderAllowance != uint256(-1)) {
            uint256 newAllowance = sub256(spenderAllowance, amount, "QUACK::burnFrom: burn amount exceeds spender allowance");
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _burnTokens(src, amount);
        return true;
    }

    /**
     * @notice Make `newMinter` the only address that can mint this token
     * @param newMinter The address that will have sole minting privileges
     * @return Whether or not the minter was set successfully
     */
    function setMinter(address newMinter) external returns (bool) {
        require(msg.sender == admin, "QUACK::setMinter: unauthorized");
        emit MinterChanged(minter, newMinter);
        minter = newMinter;
        return true;
    }

    /**
     * @notice Change the administrator of the contract
     * @param newAdmin The address that will be the new administrator
     * @return Whether or not the admin was set successfully
     */
    function setAdmin(address newAdmin) external returns (bool) {
        require(msg.sender == admin, "QUACK::setAdmin: unauthorized");
        require(newAdmin != address(0), "QUACK::setAdmin: cannot make zero address the admin");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
        return true;
    }

    /**
     * @notice Change the maximum supply
     * @param newMaxSupply The maximum number of tokens that can exist
     * @return Whether or not the maximum supply was changed
     */
    function setMaxSupply(uint newMaxSupply) external returns (bool) {
        require(!hardcapped, "QUACK::setMaxSupply: function was disabled");
        require(msg.sender == admin, "QUACK::setMaxSupply: unauthorized");
        require(newMaxSupply >= totalSupply, "QUACK::setMaxSupply: circulating supply exceeds new max supply");
        emit MaxSupplyChanged(maxSupply, newMaxSupply);
        maxSupply = newMaxSupply;
        return true;
    }

    /**
     * @notice Make the token hardcapped by irreversibly disabling setMaxSupply
     * @return Whether or not the hardcap was enabled
     */
    function disableSetMaxSupply() external returns (bool) {
        require(msg.sender == admin, "QUACK::disableSetMaxSupply: unauthorized");
        hardcapped = true;
        emit HardcapEnabled();
        return true;
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "QUACK::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "QUACK::delegateBySig: invalid nonce");
        require(now <= expiry, "QUACK::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "QUACK::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _transferTokens(address src, address dst, uint256 amount) internal {
        require(src != address(0), "QUACK::_transferTokens: cannot transfer from the zero address");
        require(dst != address(0), "QUACK::_transferTokens: cannot transfer to the zero address");

        balances[src] = sub256(balances[src], amount, "QUACK::_transferTokens: transfer amount exceeds balance");
        balances[dst] = add256(balances[dst], amount, "QUACK::_transferTokens: transfer amount overflows");
        emit Transfer(src, dst, amount);

        _moveDelegates(delegates[src], delegates[dst], amount);
    }

    function _burnTokens(address src, uint256 amount) internal {
        require(src != address(0), "QUACK::_burnTokens: cannot burn from the zero address");

        balances[src] = sub256(balances[src], amount, "QUACK::_burnTokens: burn amount exceeds balance");
        totalSupply = SafeMath.sub(totalSupply, uint(amount));
        burnedSupply = SafeMath.add(burnedSupply, uint(amount));
        emit Transfer(src, address(0), amount);

        _moveDelegates(delegates[src], address(0), amount);
    }

    function _mintTokens(address dst, uint256 amount) internal {
        require(dst != address(0), "QUACK::_mintTokens: cannot mint to the zero address");

        totalSupply = SafeMath.add(totalSupply, uint(amount));
        balances[dst] = add256(balances[dst], amount, "QUACK::_mintTokens: mint amount overflows");
        emit Transfer(address(0), dst, amount);

        require(totalSupply <= maxSupply, "QUACK::_mintTokens: mint result exceeds max supply");

        delegates[dst] = dst;
        _moveDelegates(address(0), delegates[dst], amount);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = sub256(srcRepOld, amount, "QUACK::_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = add256(dstRepOld, amount, "QUACK::_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint256 oldVotes, uint256 newVotes) internal {
      uint32 blockNumber = safe32(block.number, "QUACK::_writeCheckpoint: block number exceeds 32 bits");

      if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
          checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
      } else {
          checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          numCheckpoints[delegatee] = nCheckpoints + 1;
      }

      emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function add256(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub256(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}
