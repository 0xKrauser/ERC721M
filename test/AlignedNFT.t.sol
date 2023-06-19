// SPDX-License-Identifier: VPL
pragma solidity ^0.8.20;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import "forge-std/console.sol";
import "solady/utils/FixedPointMathLib.sol";
import "openzeppelin/token/ERC721/IERC721.sol";
import "./RevertingReceiver.sol";
import "./TestingAlignedNFT.sol";

contract AlignedNFTTest is DSTestPlus {

    TestingAlignedNFT alignedNFT_LA;
    TestingAlignedNFT alignedNFT_HA;

    function setUp() public {
        // Low alignment / high dev cut
        alignedNFT_LA = new TestingAlignedNFT(
            420, // 42.0% cut
            0x5Af0D9827E0c53E4799BB226655A1de152A425a5, // Milady NFT
            address(42), // Mint funds recipient when in push mode
            true // Push mode enabled
        );
        // High alignment / low dev cut
        alignedNFT_HA = new TestingAlignedNFT(
            150, // 15.0% cut
            0x5Af0D9827E0c53E4799BB226655A1de152A425a5, // Milady NFT
            address(42), // Mint funds recipient when in push mode
            false // Push mode not enabled
        );
        hevm.deal(address(this), 100 ether);
    }

    // Generic tests for coverage
    function testName() public view {
        require(keccak256(abi.encodePacked(alignedNFT_HA.name())) == 
            keccak256(abi.encodePacked("AlignedNFT Test")));
    }
    function testSymbol() public view {
        require(keccak256(abi.encodePacked(alignedNFT_HA.symbol())) == 
            keccak256(abi.encodePacked("ANFTTest")));
    }
    function testTokenURI(uint256 _tokenId) public view {
        bytes memory tokenIdString = bytes(alignedNFT_HA.tokenURI(_tokenId));
        uint tokenId = 0;
        for (uint256 i = 0; i < tokenIdString.length; i++) {
            uint256 c = uint256(uint8(tokenIdString[i]));
            if (c >= 48 && c <= 57) {
                tokenId = tokenId * 10 + (c - 48);
            }
        }
        require(_tokenId == tokenId);
    }

    function testVaultBalance(uint256 _tokenId, uint256 _amount) public {
        hevm.assume(_tokenId <= 1000000);
        hevm.assume(_amount > 1 gwei);
        hevm.assume(_amount < 0.01 ether);
        alignedNFT_HA.execute_mint{ value: _amount }(address(this), _tokenId);
        uint256 tithe = (_amount * 850) / 1000;
        require(alignedNFT_HA.vaultBalance() == tithe);
    }

    function test_changePushRecipient(address _to) public {
        hevm.assume(_to != address(0));
        alignedNFT_HA.execute_changePushRecipient(_to);
        require(alignedNFT_HA.pushRecipient() == _to);
    }
    function test_changePushRecipient_ZeroAddress() public {
        hevm.expectRevert(AlignedNFT.ZeroAddress.selector);
        alignedNFT_HA.execute_changePushRecipient(address(0));
    }
    function test_setPushStatus(bool _pushStatus) public {
        alignedNFT_HA.execute_setPushStatus(_pushStatus);
        require(alignedNFT_HA.pushStatus() == _pushStatus);
    }

    function test_mint_ownership(address _to, uint256 _tokenId) public {
        hevm.assume(_to != address(0));
        hevm.assume(_tokenId <= 1000000);
        alignedNFT_HA.execute_mint(_to, _tokenId);
        require(IERC721(address(alignedNFT_HA)).ownerOf(_tokenId) == _to);
    }
    function test_mint_tithe(uint256 _tokenId, uint256 _amount) public {
        hevm.assume(_tokenId <= 1000000);
        hevm.assume(_amount > 1 gwei);
        hevm.assume(_amount < 0.01 ether);
        alignedNFT_HA.execute_mint{ value: _amount }(address(this), _tokenId);
        uint256 tithe = (_amount * 850) / 1000;
        require(alignedNFT_HA.vaultBalance() == tithe);
    }
    function test_mint_pushAllocation(uint256 _tokenId, uint256 _amount) public {
        uint256 dust = address(42).balance;
        hevm.assume(_tokenId <= 1000000);
        hevm.assume(_amount > 1 gwei);
        hevm.assume(_amount < 0.01 ether);
        alignedNFT_LA.execute_mint{ value: _amount }(address(this), _tokenId);
        uint256 allocation = FixedPointMathLib.fullMulDivUp(420, _amount, 1000);
        require((address(42).balance - dust) == allocation);
    }
    function test_mint_poolAllocation(uint256 _tokenId, uint256 _amount) public {
        hevm.assume(_tokenId <= 1000000);
        hevm.assume(_amount > 1 gwei);
        hevm.assume(_amount < 0.01 ether);
        alignedNFT_HA.execute_mint{ value: _amount }(address(this), _tokenId);
        uint256 allocation = FixedPointMathLib.fullMulDivUp(150, _amount, 1000);
        require(address(alignedNFT_HA).balance == allocation);
    }
    function test_mint_TransferFailed_push() public {
        RevertingReceiver rr = new RevertingReceiver();
        alignedNFT_LA.execute_changePushRecipient(address(rr));
        hevm.expectRevert(AlignedNFT.TransferFailed.selector);
        alignedNFT_LA.execute_mint{ value: 100 gwei }(address(this), 69);
    }

    function test_withdrawAllocation_max(uint256 _tokenId, uint256 _amount) public {
        uint256 dust = address(42).balance;
        hevm.assume(_tokenId <= 1000000);
        hevm.assume(_amount > 1 gwei);
        hevm.assume(_amount < 0.01 ether);
        alignedNFT_HA.execute_mint{ value: _amount }(address(this), _tokenId);
        uint256 allocation = FixedPointMathLib.fullMulDivUp(150, _amount, 1000);
        alignedNFT_HA.execute_withdrawAllocation(address(42), type(uint256).max);
        require((address(42).balance - dust) == allocation);
    }
    function test_withdrawAllocation_exact(uint256 _tokenId, uint256 _amount) public {
        uint256 dust = address(42).balance;
        hevm.assume(_tokenId <= 1000000);
        hevm.assume(_amount > 1 gwei);
        hevm.assume(_amount < 0.01 ether);
        alignedNFT_HA.execute_mint{ value: _amount }(address(this), _tokenId);
        alignedNFT_HA.execute_withdrawAllocation(address(42), 100000);
        require((address(42).balance - dust) == 100000);
    }
    function test_withdrawAllocation_ZeroAddress() public {
        alignedNFT_HA.execute_mint{ value: 100 gwei }(address(this), 69);
        hevm.expectRevert(AlignedNFT.ZeroAddress.selector);
        alignedNFT_HA.execute_withdrawAllocation(address(0), 100000);
    }
    function test_withdrawAllocation_Overdraft() public {
        alignedNFT_HA.execute_mint{ value: 100 gwei }(address(this), 69);
        hevm.expectRevert(AlignedNFT.Overdraft.selector);
        alignedNFT_HA.execute_withdrawAllocation(address(42), 101 gwei);
    }
    function test_withdrawAllocation_TransferFailed() public {
        RevertingReceiver rr = new RevertingReceiver();
        alignedNFT_HA.execute_mint{ value: 100 gwei }(address(this), 69);
        hevm.expectRevert(AlignedNFT.TransferFailed.selector);
        alignedNFT_HA.execute_withdrawAllocation(address(rr), 15 gwei);
    }
}