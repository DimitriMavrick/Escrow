// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title MultiEscrow
 * @dev A contract for managing multi-party escrow with whitelisting, blacklisting, and ETH distribution.
 */
contract MultiEscrow {
    address public owner;
    address public firstOwner;
    uint256 public totalEth;

    mapping(address => bool) public whiteListAccounts;
    mapping(address => bool) public blackListAccounts;
    mapping(address => uint256) public allocations;
    
    address[] public whiteList;
    
    struct Transaction {
        address user;
        uint256 amount;
        uint256 timestamp;
        string transactionType;
    }
    
    Transaction[] public transactionHistory;

    event Deposit(address indexed from, uint256 amount);
    event Whitelisted(address indexed beneficiary);
    event Blacklisted(address indexed beneficiary);
    event Allocated(address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed beneficiary, uint256 amount);
    event Recovered(address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FirstOwnerChanged(address indexed previousFirstOwner, address indexed newFirstOwner);

    /**
     * @dev Constructor to set up the initial owner and first owner.
     * @param _firstOwner The address of the first owner (Bob).
     */
    constructor(address _firstOwner) {
        owner = msg.sender;
        firstOwner = _firstOwner;
    }

    /**
     * @dev Allows the contract to receive ETH.
     */
    receive() external payable {
        totalEth += msg.value;
        emit Deposit(msg.sender, msg.value);
        recordTransaction(msg.sender, msg.value, "Deposit");
    }

    /**
     * @dev Fallback function to revert direct payments.
     */
    fallback() external payable {
        revert("Direct payments not allowed");
    }

    /**
     * @dev Modifier to restrict access to the contract owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    /**
     * @dev Modifier to restrict access to the first owner.
     */
    modifier onlyFirstOwner() {
        require(msg.sender == firstOwner, "Only firstOwner can call this function");
        _;
    }

    /**
     * @dev Modifier to check if an address is not blacklisted.
     */
    modifier notBlacklisted(address _beneficiary) {
        require(!blackListAccounts[_beneficiary], "Beneficiary is blacklisted");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new address.
     * @param newOwner The address of the new owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Changes the first owner of the contract.
     * @param newFirstOwner The address of the new first owner.
     */
    function changeFirstOwner(address newFirstOwner) public onlyOwner {
        require(newFirstOwner != address(0), "New firstOwner is the zero address");
        emit FirstOwnerChanged(firstOwner, newFirstOwner);
        firstOwner = newFirstOwner;
    }

    /**
     * @dev Allows the first owner to deposit ETH and distribute it.
     * @param _benefAccounts An array of beneficiary addresses.
     */
    function depositEth(address[] memory _benefAccounts) external payable onlyFirstOwner {
        require(msg.value > 0, "amount > 0");
        totalEth += msg.value;
        
        distribute(_benefAccounts);
        emit Deposit(msg.sender, msg.value);
        recordTransaction(msg.sender, msg.value, "Deposit");
    }

    /**
     * @dev Adds multiple addresses to the whitelist.
     * @param _benefAccounts An array of addresses to be whitelisted.
     */
    function whitelistAccounts(address[] memory _benefAccounts) external onlyFirstOwner {
        for (uint256 i = 0; i < _benefAccounts.length; i++) {
            require(_benefAccounts[i] != address(0), "Cannot whitelist the zero address");
            if (!whiteListAccounts[_benefAccounts[i]]) {
                whiteListAccounts[_benefAccounts[i]] = true;
                whiteList.push(_benefAccounts[i]);
                emit Whitelisted(_benefAccounts[i]);
            }
        }
    }

    /**
     * @dev Removes an address from the whitelist.
     * @param _account The address to be removed from the whitelist.
     */
    function removeFromWhitelist(address _account) external onlyFirstOwner {
        require(whiteListAccounts[_account], "Address is not whitelisted");
        whiteListAccounts[_account] = false;
        for (uint256 i = 0; i < whiteList.length; i++) {
            if (whiteList[i] == _account) {
                whiteList[i] = whiteList[whiteList.length - 1];
                whiteList.pop();
                break;
            }
        }
    }

    /**
     * @dev Internal function to distribute ETH equally among beneficiaries.
     * @param _benefAccounts An array of beneficiary addresses.
     */
    function distribute(address[] memory _benefAccounts) internal {
        require(_benefAccounts.length > 0, "No beneficiaries to distribute");

        uint256 share = totalEth / _benefAccounts.length;

        for (uint256 i = 0; i < _benefAccounts.length; i++) {
            if (whiteListAccounts[_benefAccounts[i]] && !blackListAccounts[_benefAccounts[i]]) {
                allocations[_benefAccounts[i]] = share;
                emit Allocated(_benefAccounts[i], share);
                recordTransaction(_benefAccounts[i], share, "Allocation");
            }
        }
    }

    /**
     * @dev Allows custom allocation of ETH to whitelisted addresses.
     * @param _amount An array of amounts to be allocated to each whitelisted address.
     */
    function customAllocation(uint256[] memory _amount) external onlyFirstOwner {
        require(whiteList.length == _amount.length, "Amounts must match whitelist length");
        uint256 totalAmount;
        for (uint256 i = 0; i < whiteList.length; i++) {
            allocations[whiteList[i]] = _amount[i];
            totalAmount += _amount[i];
            emit Allocated(whiteList[i], _amount[i]);
            recordTransaction(whiteList[i], _amount[i], "CustomAllocation");
        }
        require(totalAmount == totalEth, "invalid _amount");
    }

    /**
     * @dev Allows a beneficiary to withdraw their allocated ETH.
     */
    function withdraw() external notBlacklisted(msg.sender) {
        uint256 amount = allocations[msg.sender];
        require(amount > 0, "No allocation for this address");
        require(address(this).balance >= amount, "Insufficient contract balance");
        allocations[msg.sender] = 0;
        totalEth -= amount;

        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
        recordTransaction(msg.sender, amount, "Withdrawal");
    }

    /**
     * @dev Blacklists a whitelisted address.
     * @param _beneficiary The address to be blacklisted.
     */
    function blacklistAddress(address _beneficiary) external onlyFirstOwner {
        require(whiteListAccounts[_beneficiary], "Address not whitelisted");
        require(_beneficiary != address(0), "Cannot blacklist the zero address");
        blackListAccounts[_beneficiary] = true;
        emit Blacklisted(_beneficiary);
    }

    /**
     * @dev Recovers funds from blacklisted addresses.
     * @param _beneficiary An array of blacklisted addresses.
     */
    function recoverBlacklistedFunds(address[] memory _beneficiary) external onlyFirstOwner {
        uint256 amount;
        for(uint i = 0; i < _beneficiary.length; i++){
            require(blackListAccounts[_beneficiary[i]], "Address is not blacklisted");
            amount += allocations[_beneficiary[i]];
            allocations[_beneficiary[i]] = 0;
        }
        require(amount > 0, "No allocated funds to recover");
        totalEth -= amount;
        payable(msg.sender).transfer(amount);
        emit Recovered(msg.sender, amount);
        recordTransaction(msg.sender, amount, "BlacklistRecovery");
    }

    /**
     * @dev Returns the current balance of the contract.
     * @return The balance of the contract in wei.
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Returns the status of an account (whitelisted and blacklisted).
     * @param _account The address to check.
     * @return isWhitelisted Whether the address is whitelisted.
     * @return isBlacklisted Whether the address is blacklisted.
     */
    function getStatus(address _account) external view returns (bool isWhitelisted, bool isBlacklisted) {
        return (whiteListAccounts[_account], blackListAccounts[_account]);
    }

    /**
     * @dev Returns the full transaction history.
     * @return An array of Transaction structs.
     */
    function getTransactionHistory() external view returns (Transaction[] memory) {
        return transactionHistory;
    }

    /**
     * @dev Internal function to record a transaction in the history.
     * @param _user The address involved in the transaction.
     * @param _amount The amount of ETH involved.
     * @param _type The type of transaction.
     */
    function recordTransaction(address _user, uint256 _amount, string memory _type) internal {
        transactionHistory.push(Transaction(_user, _amount, block.timestamp, _type));
    }
}