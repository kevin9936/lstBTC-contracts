// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deployer} from "./utils/Deployer.sol";
import {LstBTCLogic} from "contracts/token/LstBTCLogic.sol";
import {LstBTCProxy} from "contracts/token/LstBTCProxy.sol";
import {AccessControlBase} from "contracts/access/AccessControlBase.sol";

contract LstBTCLogicTest is Deployer {
    address public user1;
    address public user2;
    address public user3;
    address public notOwner;
    address public notMinter;
    address public notBurner;
    address public notBlackLister;
    address public minter1;
    address public initMinter2;
    address public burner1;
    address public blacklister1;
    address public bridge;
    address public owner;
    uint256 public mintAmount;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        mintAmount = 100000;
        user1 = address(2000);
        user2 = address(2001);
        user3 = address(2002);
        notOwner = address(3000);
        notMinter = address(3001);
        notBurner = address(3002);
        notBlackLister = address(3003);
        initMinter2 = address(7000);
        minter1 = address(7001);
        burner1 = address(4001);
        blacklister1 = address(4002);
        owner = address(6000);
        lstBTC.addMinter(initMinter2);
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(notOwner, "NotOwner");
        vm.label(notMinter, "NotMinter");
        vm.label(notBurner, "NotBurner");
        vm.label(notBlackLister, "NotBlackLister");
        vm.label(minter1, "Minter1");
        vm.label(initMinter2, "initMinter2");
        vm.label(burner1, "Burner1");
        vm.label(blacklister1, "BlackLister1");
        vm.label(bridge, "Bridge");
        vm.label(owner, "Owner");
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public {
        assertEq(lstBTC.name(), "Liquid Staked BTC");
        assertEq(lstBTC.symbol(), "lstBTC");
        assertEq(lstBTC.maxMintLimit(), 10 ** 8);
        assertEq(lstBTC.owner(), address(this));
    }

    function test_RevertWhen_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        lstBTC.initialize("Liquid Staked BTC", "lstBTC");
    }

    // ============ Owner Permission Tests ============

    function test_RevertWhen_SetBridge_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.setBridge(address(0x123));
    }

    function test_RevertWhen_SetMaxMintLimit_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.setMaxMintLimit(2 * 10 ** 8);
    }

    function test_RevertWhen_AddBlackLister_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.addBlackLister(user1);
    }

    function test_RevertWhen_RemoveBlackLister_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.removeBlackLister(user1);
    }

    function test_RevertWhen_AddMinter_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.addMinter(user1);
    }

    function test_RevertWhen_RemoveMinter_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.removeMinter(user1);
    }

    function test_RevertWhen_AddBurner_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.addBurner(user1);
    }

    function test_RevertWhen_RemoveBurner_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.removeBurner(user1);
    }

    function test_RevertWhen_OwnerBurn_NotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lstBTC.ownerBurn(user1, 100);
    }

    function test_RevertWhen_Mint_NotMinter() public {
        vm.prank(notMinter);
        vm.expectRevert("LstBTC: only minters can mint");
        lstBTC.mint(user1, 1000);
    }

    function test_RevertWhen_Burn_NotBurner() public {
        vm.prank(notBurner);
        vm.expectRevert("LstBTC: only burners can burn");
        lstBTC.burn(100);
    }

    function test_RevertWhen_Blacklist_NotBlackLister() public {
        vm.prank(notBlackLister);
        vm.expectRevert("LstBTC: only blacklisters");
        lstBTC.blacklist(user1);
    }

    function test_RevertWhen_UnBlacklist_NotBlackLister() public {
        vm.prank(notBlackLister);
        vm.expectRevert("LstBTC: only blacklisters");
        lstBTC.unBlacklist(user1);
    }

    // ============ Owner Function Implementation Tests ============
    // setBridge
    function test_SetBridge_Success() public {
        address newBridge = address(10001);
        address oldBridge = lstBTC.bridge();

        vm.expectEmit(true, true, false, true);
        emit NewBridge(oldBridge, newBridge);

        lstBTC.setBridge(newBridge);
        assertEq(lstBTC.bridge(), newBridge);
    }

    function test_RevertWhen_SetBridge_ZeroAddress() public {
        vm.expectRevert("LstBTC: zero address");
        lstBTC.setBridge(address(0));
    }

    function test_SetBridge_SameAddress() public {
        lstBTC.setBridge(address(10001));

        vm.recordLogs();
        lstBTC.setBridge(address(10001));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }
    // setMaxMintLimit
    function test_SetMaxMintLimit_Success() public {
        uint256 oldLimit = lstBTC.maxMintLimit();
        uint256 newLimit = 2 * 10 ** 8;

        vm.expectEmit(true, true, false, true);
        emit NewMintLimit(oldLimit, newLimit);

        lstBTC.setMaxMintLimit(newLimit);
        assertEq(lstBTC.maxMintLimit(), newLimit);
    }
    // addBlackLister
    function test_AddBlackLister_Success() public {
        assertFalse(lstBTC.blacklisters(blacklister1));

        vm.expectEmit(true, false, false, true);
        emit BlackListerAdded(blacklister1);

        lstBTC.addBlackLister(blacklister1);
        assertTrue(lstBTC.blacklisters(blacklister1));
    }

    function test_RevertWhen_AddBlackLister_AlreadyHasRole() public {
        lstBTC.addBlackLister(blacklister1);

        vm.expectRevert("LstBTC: already has role");
        lstBTC.addBlackLister(blacklister1);
    }
    // removeBlackLister
    function test_RemoveBlackLister_Success() public {
        lstBTC.addBlackLister(blacklister1);
        assertTrue(lstBTC.blacklisters(blacklister1));

        vm.expectEmit(true, false, false, true);
        emit BlackListerRemoved(blacklister1);

        lstBTC.removeBlackLister(blacklister1);
        assertFalse(lstBTC.blacklisters(blacklister1));
    }

    function test_RevertWhen_RemoveBlackLister_DoesNotHaveRole() public {
        vm.expectRevert("LstBTC: does not have role");
        lstBTC.removeBlackLister(blacklister1);
    }
    // addMinter
    function test_AddMinter_Success() public {
        assertFalse(lstBTC.minters(minter1));

        vm.expectEmit(true, false, false, true);
        emit MinterAdded(minter1);

        lstBTC.addMinter(minter1);
        assertTrue(lstBTC.minters(minter1));
    }

    function test_RevertWhen_AddMinter_AlreadyHasRole() public {
        lstBTC.addMinter(minter1);

        vm.expectRevert("LstBTC: already has role");
        lstBTC.addMinter(minter1);
    }
    // removeMinter
    function test_RemoveMinter_Success() public {
        lstBTC.addMinter(minter1);
        assertTrue(lstBTC.minters(minter1));

        vm.expectEmit(true, false, false, true);
        emit MinterRemoved(minter1);

        lstBTC.removeMinter(minter1);
        assertFalse(lstBTC.minters(minter1));
    }

    function test_RevertWhen_RemoveMinter_DoesNotHaveRole() public {
        vm.expectRevert("LstBTC: does not have role");
        lstBTC.removeMinter(minter1);
    }
    // addBurner
    function test_AddBurner_Success() public {
        assertFalse(lstBTC.burners(burner1));

        vm.expectEmit(true, false, false, true);
        emit BurnerAdded(burner1);

        lstBTC.addBurner(burner1);
        assertTrue(lstBTC.burners(burner1));
    }

    function test_RevertWhen_AddBurner_AlreadyHasRole() public {
        lstBTC.addBurner(burner1);

        vm.expectRevert("LstBTC: already has role");
        lstBTC.addBurner(burner1);
    }
    // removeBurner
    function test_RemoveBurner_Success() public {
        lstBTC.addBurner(burner1);
        assertTrue(lstBTC.burners(burner1));

        vm.expectEmit(true, false, false, true);
        emit BurnerRemoved(burner1);

        lstBTC.removeBurner(burner1);
        assertFalse(lstBTC.burners(burner1));
    }

    function test_RevertWhen_RemoveBurner_DoesNotHaveRole() public {
        vm.expectRevert("LstBTC: does not have role");
        lstBTC.removeBurner(burner1);
    }
    // burn
    function test_Burn_Success() public {
        vm.prank(initMinter2);
        lstBTC.mint(burner1, mintAmount);
        lstBTC.addBurner(burner1);
        uint256 burnAmount = 400;
        uint256 initialBalance = lstBTC.balanceOf(burner1);
        vm.expectEmit(true, true, false, true);
        emit Burn(burner1, burner1, burnAmount);
        vm.prank(burner1);
        bool result = lstBTC.burn(burnAmount);
        assertTrue(result);
        assertEq(lstBTC.balanceOf(burner1), initialBalance - burnAmount);
        assertEq(lstBTC.totalSupply(), initialBalance - burnAmount);
    }

    function test_Burn_ZeroAmount() public {
        vm.prank(initMinter2);
        lstBTC.mint(burner1, mintAmount);
        lstBTC.addBurner(burner1);
        vm.prank(burner1);
        bool result = lstBTC.burn(0);
        assertTrue(result);
        assertEq(lstBTC.balanceOf(burner1), mintAmount);
    }

    function test_Burn_AllBalance() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(burner1, 1000);

        lstBTC.addBurner(burner1);
        uint256 balance = lstBTC.balanceOf(burner1);

        vm.prank(burner1);
        bool result = lstBTC.burn(balance);

        assertTrue(result);
        assertEq(lstBTC.balanceOf(burner1), 0);
        assertEq(lstBTC.totalSupply(), 0);
    }

    function test_MultipleBurnsAndMints() public {
        lstBTC.addBurner(burner1);
        lstBTC.addBurner(user1);
        lstBTC.addBurner(user2);

        vm.startPrank(initMinter2);
        lstBTC.mint(burner1, 1000);
        lstBTC.mint(user1, 2000);
        lstBTC.mint(user2, 3000);
        assertEq(lstBTC.totalSupply(), 6000);
        vm.stopPrank();

        vm.prank(burner1);
        lstBTC.burn(500);
        vm.prank(user1);
        lstBTC.burn(1000);
        vm.prank(user2);
        lstBTC.burn(1500);
        assertEq(lstBTC.totalSupply(), 3000);

        vm.startPrank(initMinter2);
        lstBTC.mint(burner1, 4000);
        lstBTC.mint(user1, 5000);
        lstBTC.mint(user2, 6000);
        vm.stopPrank();
        assertEq(lstBTC.totalSupply(), 18000);

        assertEq(lstBTC.balanceOf(burner1), 4500);
        assertEq(lstBTC.balanceOf(user1), 6000);
        assertEq(lstBTC.balanceOf(user2), 7500);

        vm.prank(burner1);
        lstBTC.burn(1500);
        vm.prank(user1);
        lstBTC.burn(2000);
        vm.prank(user2);
        lstBTC.burn(2500);

        assertEq(lstBTC.balanceOf(burner1), 3000);
        assertEq(lstBTC.balanceOf(user1), 4000);
        assertEq(lstBTC.balanceOf(user2), 5000);
        assertEq(lstBTC.totalSupply(), 12000);
    }

    function test_RevertWhen_Burn_BlacklistedUser() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, 1000);

        lstBTC.addBlackLister(blacklister1);
        vm.prank(blacklister1);
        lstBTC.blacklist(user1);
        assertTrue(lstBTC.isBlackListed(user1));

        lstBTC.addBurner(user1);

        vm.prank(user1);
        vm.expectRevert("LstBTC: from is blacklisted");
        lstBTC.burn(500);
        assertEq(lstBTC.balanceOf(user1), 1000);
    }

    function test_Burn_BlacklistedUser_NotBurner() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, 1000);

        lstBTC.addBlackLister(blacklister1);
        vm.prank(blacklister1);
        lstBTC.blacklist(user1);
        assertTrue(lstBTC.isBlackListed(user1));

        vm.prank(user1);
        vm.expectRevert("LstBTC: only burners can burn");
        lstBTC.burn(500);
    }

    // ownerBurn
    function test_OwnerBurn_Success() public {
        lstBTC.transferOwnership(owner);
        vm.prank(owner);
        lstBTC.acceptOwnership();
        assertEq(lstBTC.owner(), owner);

        vm.prank(initMinter2);
        lstBTC.mint(user1, 1000);
        uint256 initialBalance = lstBTC.balanceOf(user1);
        assertEq(initialBalance, 1000);
        assertEq(lstBTC.totalSupply(), 1000);
        uint256 burnAmount = 500;
        vm.expectEmit(true, true, false, true);
        emit Burn(lstBTC.owner(), user1, burnAmount);
        vm.prank(owner);
        lstBTC.ownerBurn(user1, burnAmount);
        assertEq(lstBTC.balanceOf(user1), initialBalance - burnAmount);
    }

    function test_OwnerBurn_BlacklistedUser_Success() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, 1000);

        lstBTC.addBlackLister(blacklister1);
        vm.prank(blacklister1);
        lstBTC.blacklist(user1);
        assertTrue(lstBTC.isBlackListed(user1));

        uint256 initialBalance = lstBTC.balanceOf(user1);
        uint256 burnAmount = 500;
        vm.expectEmit(true, true, false, true);
        emit Burn(lstBTC.owner(), user1, burnAmount);
        lstBTC.ownerBurn(user1, burnAmount);
        assertEq(lstBTC.balanceOf(user1), initialBalance - burnAmount);
        assertTrue(lstBTC.isBlackListed(user1));
    }

    function test_OwnerBurn_MultipleUsers_Success() public {
        lstBTC.transferOwnership(owner);
        vm.prank(owner);
        lstBTC.acceptOwnership();
        assertEq(lstBTC.owner(), owner);

        vm.startPrank(initMinter2);
        lstBTC.mint(user1, 1000);
        lstBTC.mint(user2, 2000);
        lstBTC.mint(user3, 3000);
        vm.stopPrank();

        assertEq(lstBTC.balanceOf(user1), 1000);
        assertEq(lstBTC.balanceOf(user2), 2000);
        assertEq(lstBTC.balanceOf(user3), 3000);
        assertEq(lstBTC.totalSupply(), 6000);

        vm.startPrank(owner);
        lstBTC.ownerBurn(user1, 500);
        lstBTC.ownerBurn(user2, 1000);
        lstBTC.ownerBurn(user3, 1500);
        vm.stopPrank();

        assertEq(lstBTC.balanceOf(user1), 500);
        assertEq(lstBTC.balanceOf(user2), 1000);
        assertEq(lstBTC.balanceOf(user3), 1500);
        assertEq(lstBTC.totalSupply(), 3000);
    }

    function test_OwnerBurn_BlacklistedUser_AllTokens() public {
        lstBTC.transferOwnership(owner);
        vm.prank(owner);
        lstBTC.acceptOwnership();
        assertEq(lstBTC.owner(), owner);

        vm.prank(initMinter2);
        lstBTC.mint(user1, 1000);
        assertEq(lstBTC.balanceOf(user1), 1000);
        vm.prank(owner);

        lstBTC.addBlackLister(blacklister1);
        vm.prank(blacklister1);
        lstBTC.blacklist(user1);
        assertTrue(lstBTC.isBlackListed(user1));

        vm.prank(owner);
        bool result = lstBTC.ownerBurn(user1, 1000);

        assertTrue(result);
        assertEq(lstBTC.balanceOf(user1), 0);
        assertTrue(lstBTC.isBlackListed(user1));
        assertEq(lstBTC.totalSupply(), 0);
    }

    // mint
    function test_Mint_Success() public {
        vm.expectEmit(true, true, false, true);
        emit Mint(initMinter2, user1, mintAmount);
        vm.prank(initMinter2);
        bool result = lstBTC.mint(user1, mintAmount);
        assertTrue(result);
        assertEq(lstBTC.balanceOf(user1), mintAmount);
        assertEq(lstBTC.totalSupply(), mintAmount);
    }

    function test_RevertWhen_Mint_ExceedsMaxLimit() public {
        uint256 maxLimit = lstBTC.maxMintLimit();
        vm.prank(initMinter2);
        vm.expectRevert("LstBTC: reached maximum mint limit");
        lstBTC.mint(user1, maxLimit + 1);
    }

    function test_RevertWhen_Mint_ExceedsMaxLimit_AfterMultipleMints() public {
        uint256 maxLimit = lstBTC.maxMintLimit();

        vm.prank(initMinter2);
        lstBTC.mint(user1, maxLimit - 1000);

        vm.prank(initMinter2);
        lstBTC.mint(user2, 500);

        vm.prank(initMinter2);
        vm.expectRevert("LstBTC: reached maximum mint limit");
        lstBTC.mint(user3, 600);
        assertEq(lstBTC.balanceOf(user1), maxLimit - 1000);
        assertEq(lstBTC.balanceOf(user2), 500);
        assertEq(lstBTC.balanceOf(user3), 0);
        assertEq(lstBTC.totalSupply(), maxLimit - 1000 + 500);
    }

    function test_RevertWhen_Mint_BlacklistedUser() public {
        lstBTC.addBlackLister(blacklister1);
        vm.prank(blacklister1);
        lstBTC.blacklist(user1);

        assertTrue(lstBTC.isBlackListed(user1));

        vm.prank(initMinter2);
        vm.expectRevert("LstBTC: to is blacklisted");
        lstBTC.mint(user1, 1000);
    }

    function test_Mint_AtMaxLimit() public {
        uint256 maxLimit = lstBTC.maxMintLimit();
        vm.prank(initMinter2);
        bool result = lstBTC.mint(user1, maxLimit);

        assertTrue(result);
        assertEq(lstBTC.balanceOf(user1), maxLimit);
        assertEq(lstBTC.totalSupply(), maxLimit);
    }

    function test_Mint_ZeroAmount() public {
        lstBTC.addMinter(minter1);

        vm.prank(minter1);
        bool result = lstBTC.mint(user1, 0);

        assertTrue(result);
        assertEq(lstBTC.balanceOf(user1), 0);
    }

    function test_Mint_MultipleMints_Success() public {
        vm.startPrank(initMinter2);
        lstBTC.mint(user1, 1000);
        lstBTC.mint(user2, 2000);
        lstBTC.mint(user3, 3000);
        lstBTC.mint(user3, 3000);
        assertEq(lstBTC.balanceOf(user1), 1000);
        assertEq(lstBTC.balanceOf(user2), 2000);
        assertEq(lstBTC.balanceOf(user3), 6000);
        assertEq(lstBTC.totalSupply(), 9000);
        vm.stopPrank();
    }

    // blacklist
    function test_Blacklist_Success() public {
        lstBTC.addBlackLister(blacklister1);
        assertFalse(lstBTC.isBlackListed(user1));

        vm.expectEmit(true, false, false, true);
        emit Blacklisted(user1);

        vm.prank(blacklister1);
        lstBTC.blacklist(user1);

        assertTrue(lstBTC.isBlackListed(user1));
    }

    function test_Blacklist_AlreadyBlacklisted() public {
        lstBTC.addBlackLister(blacklister1);

        vm.prank(blacklister1);
        lstBTC.blacklist(user1);

        vm.prank(blacklister1);
        lstBTC.blacklist(user1);

        assertTrue(lstBTC.isBlackListed(user1));
    }
    // unBlacklist
    function test_UnBlacklist_Success() public {
        lstBTC.addBlackLister(blacklister1);

        vm.prank(blacklister1);
        lstBTC.blacklist(user1);
        assertTrue(lstBTC.isBlackListed(user1));

        vm.expectEmit(true, false, false, true);
        emit UnBlacklisted(user1);

        vm.prank(blacklister1);
        lstBTC.unBlacklist(user1);

        assertFalse(lstBTC.isBlackListed(user1));
    }

    function test_UnBlacklist_NotBlacklisted() public {
        lstBTC.addBlackLister(blacklister1);

        vm.prank(blacklister1);
        lstBTC.unBlacklist(user1);

        assertFalse(lstBTC.isBlackListed(user1));
    }

    // transfer
    function test_Transfer_Success() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, 1000);

        uint256 transferAmount = 500;
        vm.prank(user1);
        vm.mockCall(
            bridge,
            abi.encodeWithSignature(
                "onLstBTCTransfer(address,address,uint64)",
                user1,
                user2,
                transferAmount
            ),
            abi.encode(true)
        );
        bool result = lstBTC.transfer(user2, transferAmount);

        assertTrue(result);
        assertEq(lstBTC.balanceOf(user1), 500);
        assertEq(lstBTC.balanceOf(user2), 500);
    }

    function test_RevertWhen_TransferFromBlacklistedUser() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, 1000);

        lstBTC.addBlackLister(blacklister1);
        vm.prank(blacklister1);
        lstBTC.blacklist(user1);

        vm.prank(user1);
        vm.expectRevert("LstBTC: from is blacklisted");
        lstBTC.transfer(user2, 100);
    }

    function test_RevertWhen_TransferToBlacklistedUser() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, 1000);

        lstBTC.addBlackLister(blacklister1);
        vm.prank(blacklister1);
        lstBTC.blacklist(user2);

        vm.prank(user1);
        vm.expectRevert("LstBTC: to is blacklisted");
        lstBTC.transfer(user2, 100);
    }

    function test_RevertWhen_Transfer_FromZeroAddress() public {
        vm.prank(address(0));
        vm.expectRevert("ERC20: transfer from the zero address");
        lstBTC.transfer(user1, 100);
    }

    function test_RevertWhen_Transfer_ToZeroAddress() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, 1000);

        vm.prank(user1);
        vm.expectRevert("ERC20: transfer to the zero address");
        lstBTC.transfer(address(0), 100);
    }

    function test_Transfer_Success_ZeroAmount() public {
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, 1000);

        uint256 initialBalance = lstBTC.balanceOf(user1);

        vm.prank(user1);
        bool result = lstBTC.transfer(user2, 0);

        assertTrue(result);
        assertEq(lstBTC.balanceOf(user1), initialBalance);
        assertEq(lstBTC.balanceOf(user2), 0);
    }

    function test_RevertWhen_Transfer_AmountExceedsUint64Max() public {
        lstBTC.setMaxMintLimit(type(uint256).max);
        lstBTC.addMinter(minter1);
        vm.prank(minter1);
        lstBTC.mint(user1, type(uint256).max);

        vm.prank(user1);
        vm.expectRevert("LstBTC: exceeds uint64 limit");
        uint256 amount = uint256(type(uint64).max) + 1;
        lstBTC.transfer(user2, amount);
    }

    // ============ View Functions Tests ============

    function test_IsBlackListed_View() public {
        assertFalse(lstBTC.isBlackListed(user1));

        lstBTC.addBlackLister(blacklister1);
        vm.prank(blacklister1);
        lstBTC.blacklist(user1);

        assertTrue(lstBTC.isBlackListed(user1));
    }

    function test_Decimals_View() public {
        assertEq(lstBTC.decimals(), 8);
    }

    function test_RoleStatus_View() public {
        assertFalse(lstBTC.minters(minter1));
        assertFalse(lstBTC.burners(burner1));
        assertFalse(lstBTC.blacklisters(blacklister1));

        lstBTC.addMinter(minter1);
        lstBTC.addBurner(burner1);
        lstBTC.addBlackLister(blacklister1);

        assertTrue(lstBTC.minters(minter1));
        assertTrue(lstBTC.burners(burner1));
        assertTrue(lstBTC.blacklisters(blacklister1));
    }

    // ============ Events Declaration for Tests ============

    event NewBridge(address indexed oldBridge, address indexed newBridge);
    event NewMintLimit(uint256 oldLimit, uint256 newLimit);
    event BlackListerAdded(address indexed account);
    event BlackListerRemoved(address indexed account);
    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event BurnerAdded(address indexed account);
    event BurnerRemoved(address indexed account);
    event Burn(address indexed burner, address indexed from, uint256 amount);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
}
