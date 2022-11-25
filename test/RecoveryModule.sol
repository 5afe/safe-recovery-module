// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/RecoveryModule.sol";
import "lib/safe-contracts/contracts/common/Enum.sol";
import "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import "lib/safe-contracts/contracts/GnosisSafe.sol";
import "lib/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

contract TestRecoveryModule is Test {

    function testConstructor() external {
        address[] memory initialDelegates = new address[](2);
        initialDelegates[0] = address(0x2);
        initialDelegates[1] = address(0x69);
        RecoveryModule testModule = new RecoveryModule(60 * 60 * 24 * 180, initialDelegates, 1);
        assertEq(testModule.recoveryPeriod(), 60 * 60 * 24 * 180);
        assertEq(testModule.recoveryDeadline(), 0);
        address[] memory delegatesFromContract = testModule.getDelegates();
        assertEq(delegatesFromContract[0], address(0x69));
        assertEq(delegatesFromContract[1], address(0x2));
    }

    function testFullCircle() external {
        address[] memory safeOwners = new address[](1);
        address safeOwner = address(0x69);
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

        // Deploy the Recovery Module
        console.log('Deploy RecoveryModule');
        address[] memory initialDelegates = new address[](2);
        initialDelegates[0] = address(0x2);
        initialDelegates[1] = address(0x69);
        vm.prank(address(deployedSafe));
        RecoveryModule testModule = new RecoveryModule(1000, initialDelegates, 2);
        console.logBytes(abi.encodePacked(address(this)));

        GnosisSafe proxyAsSafe = GnosisSafe(payable(address(deployedSafe)));
        proxyAsSafe.setup(safeOwners,
            1,
            address(0),
            bytes("0x0"),
            address(0),
            address(0),
            0,
            payable(address(0))
        );

        // Prevalidated signature
        bytes memory test = hex"0000000000000000000000000000000000000000000000000000000000000069000000000000000000000000000000000000000000000000000000000000000001";

        // Enable the module
        vm.prank(safeOwner);
        bytes memory enableModuleEncoding = abi.encodeWithSignature("enableModule(address)", address(testModule));
        proxyAsSafe.execTransaction(
            address(deployedSafe),
            0,
            enableModuleEncoding,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            test
        );

        // Check Safe modules
        console.log('Is module enabled: ', proxyAsSafe.isModuleEnabled(address(testModule)));

        vm.prank(address(initialDelegates[0]));
        testModule.startRecovery();

        // Recover Success
        vm.prank(address(initialDelegates[0]));
        vm.warp(2000);
        testModule.recover();

        // Check Safe owners
        console.log("Owners:");
        for (uint256 i = 0; i < proxyAsSafe.getOwners().length; i++) {
            console.log(proxyAsSafe.getOwners()[i]);
        }
        
        // Check Safe threshold
        console.log(proxyAsSafe.getThreshold());
    }
}
