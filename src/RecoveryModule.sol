// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/safe-contracts/contracts/GnosisSafe.sol";
import "lib/safe-contracts/contracts/common/Enum.sol";

/// @title RecoveryModule - A module to recover ownership of a Safe.
/// @author Aaron Cook - <aaron@safe.global>
/// @author Germán Martínez - <german@safe.global>
/// @author Manuel Gelfart - <manu@safe.global>
contract RecoveryModule {
    address payable immutable private owner;

    address internal constant SENTINEL_DELEGATES = address(0x1);
    mapping(address => address) internal delegates;
    uint256 internal delegateCount;

    uint256 public threshold;

    uint256 public recoveryPeriod;

    uint256 internal constant NO_DEADLINE = 0;
    uint256 public recoveryDeadline;

    constructor(uint256 _recoveryPeriod, address[] memory _delegates, uint256 _threshold) {
        owner = payable(msg.sender);

        setRecoveryPeriod(_recoveryPeriod);

        delegates[SENTINEL_DELEGATES] = SENTINEL_DELEGATES;
        for (uint256 i = 0; i < _delegates.length; i++) {
            addDelegate(_delegates[i]);
        }

        setThreshold(_threshold);
    }

    event AddedDelegate(address delegate);
    event RemovedDelegate(address delegate);
    event SetThreshold(uint256 threshold);
    event SetRecoveryPeriod(uint256 threshold);
    event StartRecovery(uint256 recoveryDeadline);
    event CancelRecovery();
    event Recover();

    modifier onlyOwner() {
        require(owner == msg.sender, "Caller is not the owner");
        _;
    }

    modifier onlyDelegate () {
        require(isDelegate(msg.sender), "You are not a recovery delegate");
        _;
    }

    // OWNER

    function getOwner() public view returns (address) {
        return owner;
    }

    /// DELEGATES

    /// @dev Adds a new delegate.
    /// @param delegate Address of the delegate.
    function addDelegate(address delegate) public onlyOwner {
        require(delegate != address(0) && delegate != SENTINEL_DELEGATES && delegate != address(this), "Invalid delegate address");
        require(delegates[delegate] == address(0), "Delegate already exists");

        delegates[delegate] = delegates[SENTINEL_DELEGATES];
        delegates[SENTINEL_DELEGATES] = delegate;
        delegateCount++;

        emit AddedDelegate(delegate);
    }

    /// @dev Removes an existing delegate.
    /// @param delegate Address of the delegate.
    function removeDelegate(
        address prevDelegate,
        address delegate
    ) public onlyOwner {
        require(delegate != address(0) && delegate != SENTINEL_DELEGATES, "Invalid delegate address");
        require(delegates[prevDelegate] == delegate, "Invalid previous delegate");

        delegates[prevDelegate] = delegates[delegate];
        delegates[delegate] = address(0);
        delegateCount--;

        if (delegateCount > threshold) {
            setThreshold(delegateCount);
        }

        emit RemovedDelegate(delegate);
    }
    
    /// @dev Returns the list of delegates.
    /// @return List of delegates.
    function getDelegates() public view returns (address[] memory) {
        address[] memory array = new address[](delegateCount);

        uint256 i = 0;
        address currentDelegate = delegates[SENTINEL_DELEGATES];

        while (currentDelegate != SENTINEL_DELEGATES) {
            array[i] = currentDelegate;
            currentDelegate = delegates[currentDelegate];
            i++;
        }

        return array;
    }
    
    function isDelegate(address delegate) public view returns(bool) {
        return delegate != SENTINEL_DELEGATES && delegates[delegate] != address(0);
    }
    
    /// @dev Sets the threshold of the Safe post-recovery.
    /// @param _threshold Threshold of the Safe post-recovery.
    function setThreshold(uint256 _threshold) public onlyOwner {
        require(_threshold > 0, "Threshold cannot be 0");
        require(_threshold <= delegateCount, "Threshold cannot be greater than the number of delegates");

        threshold = _threshold;

        emit SetThreshold(threshold);
    }
    
    /// RECOVERY

    /// @dev Sets the recovery request period.
    /// @param _recoveryPeriod Recovery request period in milliseconds.
    function setRecoveryPeriod(uint256 _recoveryPeriod) public onlyOwner {
        recoveryPeriod = _recoveryPeriod;

        emit SetRecoveryPeriod(recoveryPeriod);
    }

    function getRecoveryPeriod() public view returns (uint256) {
        return recoveryPeriod;
    }

    /// @dev Starts a recovery request.
    function startRecovery() external onlyDelegate {
        require(recoveryDeadline == NO_DEADLINE, "Recovery already started");
        
        recoveryDeadline = block.timestamp + recoveryPeriod;

        emit SetRecoveryPeriod(recoveryDeadline);
    }

    function getRecoveryDeadline() public view returns (uint256) {
        return recoveryDeadline;
    }

    /// @dev Cancels a recovery request.
    function cancelRecovery() external onlyOwner {
        require(recoveryDeadline != NO_DEADLINE, "Recovery not started");

        recoveryDeadline = NO_DEADLINE;

        emit CancelRecovery();
    }

    /// @dev Recovers the Safe by adding delegates as owners with the specified threshold.
    function recover() external onlyDelegate {
        require(recoveryDeadline != NO_DEADLINE, "Recovery not started");
        require(block.timestamp > recoveryDeadline, "Recovery deadline not met");

        GnosisSafe safe = GnosisSafe(owner);

        address[] memory _delegates = getDelegates();
        
        for (uint256 i = 0; i < _delegates.length; i++) {
            bool isLastDelegate = i == delegateCount - 1;
            
            bytes memory changeOwnerData = abi.encodeWithSignature(
                "addOwnerWithThreshold(address,uint256)",
                _delegates[i],
                isLastDelegate ? threshold : 1
            );

            safe.execTransactionFromModule(owner, 0, changeOwnerData, Enum.Operation.Call);
        }

        recoveryDeadline = NO_DEADLINE;
        
        require(safe.getThreshold() == threshold, "Threshold not correctly set");

        emit Recover();
    }
}
