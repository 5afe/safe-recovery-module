// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/RecoveryModule.sol";
import "lib/safe-contracts/contracts/common/Enum.sol";
import "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import "lib/safe-contracts/contracts/GnosisSafe.sol";
import "lib/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

contract TestRecoveryModule is Test {

    // Is there a more elegant way to access the events?
    event AddedDelegate(address delegate);
    event RemovedDelegate(address delegate);
    event SetThreshold(uint256 threshold);
    event SetRecoveryPeriod(uint256 threshold);
    event StartRecovery(uint256 recoveryDeadline);
    event CancelRecovery();
    event Recover();

    GnosisSafe proxyAsSafe;
    RecoveryModule testModule;
    address safeOwner = address(0x69);
    address[] initialDelegates = new address[](2);


    function setUp() public {
        address[] memory safeOwners = new address[](1);
        safeOwners[0] = safeOwner;
        GnosisSafe safeSingleton = new GnosisSafe();
        
        // Deploy a new Safe
        console.log('Deploy new Safe');
        bytes memory initializer = abi.encodeWithSignature(
            "function setup(address[], uint256, address, bytes, address, address, uint256, address)",
            safeOwners,
            1,
            address(0),
            bytes("0x0"),
            address(0),
            address(0),
            0,
            payable(address(0))
        );
        uint256 saltNonce = 69420;
        GnosisSafeProxyFactory proxyFactory = new GnosisSafeProxyFactory();
        GnosisSafeProxy deployedSafe = proxyFactory.createProxyWithNonce(address(safeSingleton), initializer, saltNonce);
        console.log('Deployed Safe address: ', address(deployedSafe));

        proxyAsSafe = GnosisSafe(payable(address(deployedSafe)));
        proxyAsSafe.setup(safeOwners,
            1,
            address(0),
            bytes("0x0"),
            address(0),
            address(0),
            0,
            payable(address(0))
        );

        // Deploy the Recovery Module
        console.log('Deploy RecoveryModule');
        initialDelegates[0] = address(0x2);
        initialDelegates[1] = address(0x420);
        vm.prank(address(proxyAsSafe));
        testModule = new RecoveryModule(1000, initialDelegates, 2);

        // Prevalidated signature
        bytes memory signature = hex"0000000000000000000000000000000000000000000000000000000000000069000000000000000000000000000000000000000000000000000000000000000001";

        // Enable the module
        vm.prank(safeOwner);
        bytes memory enableModuleEncoding = abi.encodeWithSignature("enableModule(address)", address(testModule));
        proxyAsSafe.execTransaction(
            address(proxyAsSafe),
            0,
            enableModuleEncoding,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
        );

        // Check Safe modules
        assertEq(proxyAsSafe.isModuleEnabled(address(testModule)), true);
    }

    function testConstructor() public {
        vm.prank(address(proxyAsSafe));
        testModule = new RecoveryModule(60 * 60 * 24 * 180, initialDelegates, 1);
        assertEq(testModule.recoveryPeriod(), 60 * 60 * 24 * 180);
        assertEq(testModule.recoveryDeadline(), 0);
        address[] memory delegatesFromContract = testModule.getDelegates();
        assertEq(delegatesFromContract[0], address(0x420));
        assertEq(delegatesFromContract[1], address(0x2));
    }

    function testCancelRecoveryProcess() public {
        vm.prank(address(initialDelegates[0]));
        vm.expectEmit(true, false, false, true);
        emit StartRecovery(1001);
        testModule.startRecovery();

        // Recover Success
        vm.prank(address(proxyAsSafe));
        vm.warp(500);
        vm.expectEmit(true, false, false, true);
        emit CancelRecovery();
        testModule.cancelRecovery();

        vm.prank(address(initialDelegates[0]));
        vm.warp(2000);
        vm.expectRevert(bytes("Recovery not started"));
        testModule.recover();
    }

    function testRecoveryAfterDeadline() public {
        vm.prank(address(initialDelegates[0]));
        vm.expectEmit(true, false, false, true);
        emit StartRecovery(1001);
        testModule.startRecovery();

        // Recover Success
        vm.prank(address(initialDelegates[0]));
        vm.warp(2000);
        vm.expectEmit(true, false, false, true);
        emit Recover();
        testModule.recover();

        // Check Safe owners
        console.log("Owners after recovery:");
        for (uint256 i = 0; i < proxyAsSafe.getOwners().length; i++) {
            console.log(proxyAsSafe.getOwners()[i]);
        }
        assertEq(proxyAsSafe.getOwners()[0], address(0x2));
        assertEq(proxyAsSafe.getOwners()[1], address(0x420));
        assertEq(proxyAsSafe.getOwners()[2], address(0x69));
        
        // Check Safe threshold
        assertEq(proxyAsSafe.getThreshold(), 2);
    }
}
