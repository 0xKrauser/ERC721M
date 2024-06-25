// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "./_Test.sol";

import "../lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "../lib/solady/test/utils/mocks/MockERC20.sol";
import "../lib/solady/test/utils/mocks/MockERC721.sol";
import { ERC721Core } from "../src/core/ERC721Core.sol";
import { IAlignmentVaultMinimal, ERC721M } from "../src/ERC721M.sol";
import "../src/IERC721M.sol";
import { IERC721M as IERC721MC } from "../src/core/IERC721M.sol";
import { Core, ICore, Ownable, Pausable, ReentrancyGuard } from "../src/core/Core.sol";
import "../src/core/royalty/CoreRoyalty.sol";
import "../src/core/metadata/CoreMetadata721.sol";

import "../lib/solady/src/auth/Ownable.sol";

contract AlphaERC721MTest is TestWithHelpers, ERC721Holder {
    using LibString for uint256;

    ERC721M public template;
    ERC721M public manualInit;
    IERC721 public nft = IERC721(0xeA9aF8dBDdE2A8d3515C3B4E446eCd41afEdB1C6); // Milady NFT
    MockERC20 public testToken;
    MockERC721 public testNFT;

    function setUp() public {
        vm.createSelectFork("sepolia");
        template = new ERC721M();
        template.initialize(
            "ERC721M Test",
            "ERC721M",
            100,
            500,
            2000,
            address(this),
            address(nft),
            0.01 ether,
            21,
            bytes32("")
        );
        template.setBaseURI("https://miya.wtf/api/", "");
        template.setContractURI("https://miya.wtf/api/contract.json");
        vm.deal(address(this), 1000 ether);
        testToken = new MockERC20("Test Token", "TEST", 18);
        testToken.mint(address(this), 100 ether);
        testNFT = new MockERC721();
        testNFT.safeMint(address(this), 1);
        testNFT.safeMint(address(this), 2);
        testNFT.safeMint(address(this), 3);
    }

    function testInitialize() public {
        manualInit = new ERC721M();
        manualInit.initialize(
            "ERC721M Test",
            "ERC721M",
            100,
            500,
            2000,
            address(this),
            address(nft),
            0.01 ether,
            21,
            bytes32("")
        );
        manualInit.setBaseURI("https://miya.wtf/api/", "");
        manualInit.setContractURI("https://miya.wtf/api/contract.json");
        assertEq(manualInit.minAllocation(), 2000);
        (address recipient, uint256 royalty) = manualInit.royaltyInfo(0, 1 ether);
        assertEq(recipient, address(this));
        assertEq(royalty, 0.05 ether);
        assertEq(IAlignmentVaultMinimal(manualInit.alignmentVault()).alignedNft(), address(nft));
        require(manualInit.owner() == address(this));
        require(keccak256(abi.encodePacked(manualInit.name())) == keccak256(abi.encodePacked("ERC721M Test")));
        require(keccak256(abi.encodePacked(manualInit.symbol())) == keccak256(abi.encodePacked("ERC721M")));
        require(
            keccak256(abi.encodePacked(manualInit.baseURI())) == keccak256(abi.encodePacked("https://miya.wtf/api/"))
        );
        require(
            keccak256(abi.encodePacked(manualInit.contractURI())) ==
                keccak256(abi.encodePacked("https://miya.wtf/api/contract.json"))
        );
        require(manualInit.maxSupply() == 100);
        require(manualInit.price() == 0.01 ether);
    }

    function testInitializeRevertNotAligned() public {
        manualInit = new ERC721M();
        vm.expectRevert(IERC721MC.AllocationOutOfBounds.selector);
        manualInit.initialize(
            "ERC721M Test",
            "ERC721M",
            100,
            500,
            250,
            address(this),
            address(nft),
            0.01 ether,
            21,
            bytes32("")
        );
    }

    function testInitializeRevertInvalid() public {
        manualInit = new ERC721M();
        vm.expectRevert(IERC721MC.AllocationOutOfBounds.selector);
        manualInit.initialize(
            "ERC721M Test",
            "ERC721M",
            100,
            500,
            10_001,
            address(this),
            address(nft),
            0.01 ether,
            21,
            bytes32("")
        );
        vm.expectRevert(ICoreRoyalty.MaxRoyalties.selector);
        manualInit.initialize(
            "ERC721M Test",
            "ERC721M",
            100,
            10_001,
            2000,
            address(this),
            address(nft),
            0.01 ether,
            21,
            bytes32("")
        );
    }

    function testName() public view {
        require(keccak256(abi.encodePacked(template.name())) == keccak256(abi.encodePacked("ERC721M Test")));
    }

    function testSymbol() public view {
        require(keccak256(abi.encodePacked(template.symbol())) == keccak256(abi.encodePacked("ERC721M")));
    }

    function testBaseUri() public view {
        require(
            keccak256(abi.encodePacked(template.baseURI())) == keccak256(abi.encodePacked("https://miya.wtf/api/"))
        );
    }

    function testContractURI() public view {
        require(
            keccak256(abi.encodePacked(template.contractURI())) ==
                keccak256(abi.encodePacked("https://miya.wtf/api/contract.json"))
        );
    }

    function testTokenURI() public {
        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);

        string memory uri = template.tokenURI(1);
        console2.log("URI: ", uri);
        console2.log(template.totalSupply());
        assertEq(
            keccak256(abi.encodePacked(template.tokenURI(1))),
            keccak256(
                abi.encodePacked(string.concat("https://miya.wtf/api/", uint256(template.totalSupply()).toString()))
            )
        );
    }

    function testTokenURIRevertTokenDoesNotExist() public {
        vm.expectRevert(ERC721.TokenDoesNotExist.selector);
        template.tokenURI(1);
    }

    function testSetPrice(uint256 _price) public {
        vm.assume(_price >= 10 gwei);
        vm.assume(_price <= 1 ether);
        template.setPrice(_price);
        require(template.price() == _price);
    }

    function testOpenMint() public {
        require(template.paused() == true);
        template.unpause();
        require(template.paused() == false);
    }

    function testSetBaseURI() public {
        template.setBaseURI("ipfs://miyahash/", "");
        require(keccak256(abi.encodePacked(template.baseURI())) == keccak256(abi.encodePacked("ipfs://miyahash/")));
    }

    function testSetBaseURIRevertPermanentURI() public {
        template.freezeURI();
        vm.expectRevert(ICoreMetadata.URIPermanent.selector);
        template.setBaseURI("ipfs://miyahash/", "");
    }

    function testFreezeURI() public {
        template.freezeURI();
        require(template.permanentURI() == true);
    }

    function testTransferOwnership(address _newOwner) public {
        vm.assume(_newOwner != address(0));
        template.transferOwnership(_newOwner);
        require(template.owner() == _newOwner, "ownership transfer error");
    }

    function testMint(address _to, uint32 _amount) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= 100);
        vm.assume(_to != address(0));
        template.unpause();
        uint256 eth = 0.01 ether;
        uint256 value = _amount * eth;
        template.mint{ value: value }(_to, _amount, 2000);
    }

    function testMintRevertInsufficientPayment() public {
        template.unpause();
        vm.expectRevert(ICore.InsufficientPayment.selector);
        template.mint{ value: 0.001 ether }(address(this), 1, 2000);
    }

    function testMintRevertMintClosed() public {
        vm.expectRevert(Pausable.EnforcedPause.selector);
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
    }

    function testMintRevertMintCapReached() public {
        template.unpause();
        template.mint{ value: 0.01 ether * 100 }(address(this), 100, address(0), 2000);
        vm.expectRevert(ICore.MaxSupply.selector);
        template.mint{ value: 0.01 ether }(address(this), 1, address(0), 2000);
    }

    function testMintRevertMintCapExceeded() public {
        template.unpause();
        vm.expectRevert(ICore.MaxSupply.selector);
        template.mint{ value: 0.01 ether * 101 }(address(this), 101, 2000);
    }

    function testRescueERC20() public {
        testToken.transfer(address(template), 1 ether);
        template.rescueERC20(address(testToken), address(42));
        require(testToken.balanceOf(address(42)) >= 1 ether);
    }

    function testRescueERC721() public {
        testNFT.transferFrom(address(this), address(template), 1);
        template.rescueERC721(address(testNFT), address(42), 1);
        require(testNFT.ownerOf(1) == address(42));
    }

    function testRescueERC721AlignedAsset() public {
        vm.startPrank(nft.ownerOf(42));
        nft.approve(address(this), 42);
        nft.transferFrom(nft.ownerOf(42), address(template), 42);
        vm.stopPrank();
        template.rescueERC721(address(nft), address(42), 42);
        require(nft.ownerOf(42) == address(template.alignmentVault()));
    }

    function testWithdrawFunds() public {
        template.unpause();
        template.mint{ value: 0.01 ether }(address(42), 1, 2000);
        uint256 dust = address(42).balance;
        template.withdraw(address(42), 0.002 ether);
        require((address(42).balance - dust) == 0.002 ether);
    }

    function testWithdrawFundsRenounced() public {
        template.unpause();
        template.mint{ value: 0.01 ether }(address(42), 1, 2000);
        template.renounceOwnership();
        template.withdraw(address(69), 0.0000001 ether);
        require(address(template.alignmentVault()).balance == 0.01 ether);
    }

    function testWithdrawFundsRevertUnauthorized() public {
        template.unpause();
        template.mint{ value: 0.01 ether }(address(42), 1, 2000);
        vm.prank(address(42));
        vm.expectRevert(Ownable.Unauthorized.selector);
        template.withdraw(address(42), 0.002 ether);
    }

    function testReceive() public {
        (bool success, ) = payable(address(template)).call{ value: 1 ether }("");
        require(success);
        require(address(template.alignmentVault()).balance == 1 ether);
    }

    function testOnERC721Received() public {
        vm.startPrank(nft.ownerOf(42));
        nft.approve(address(this), 42);
        nft.safeTransferFrom(nft.ownerOf(42), address(template), 42);
        vm.stopPrank();
        require(nft.ownerOf(42) == address(template.alignmentVault()), "NFT redirection failed");
    }

    function testOnERC721ReceivedRevertNotAligned() public {
        vm.expectRevert(IERC721MC.NotAligned.selector);
        testNFT.safeTransferFrom(address(this), address(template), 1);
    }

    function testProcessPayment() public {
        template.unpause();
        address(template).call{ value: 1 ether }("");
        require(template.balanceOf(address(this)) > 0);
    }

    function testTransferFromUnlocked() public {
        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.transferFrom(address(this), address(42), 1);
        require(template.ownerOf(1) == address(42));
    }

    //@TODO: Fix this test
    /*
    function testTransferFromLocked() public {
        address[] memory approved = new address[](1);
        approved[0] = address(this);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721x.Locked.selector, 1));
        template.transferFrom(address(this), address(42), 1);
    }
     */

    function testSafeTransferFromUnlocked() public {
        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.safeTransferFrom(address(this), address(42), 1, bytes("milady"));
        require(template.ownerOf(1) == address(42));
    }
    /*
    function testSafeTransferFromLocked() public {
        address[] memory approved = new address[](1);
        approved[0] = address(this);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721x.Locked.selector, 1));
        template.safeTransferFrom(address(this), address(42), 1, bytes("milady"));
    }

    function testLockId() public {
        address[] memory approved = new address[](1);
        approved[0] = address(this);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);
        require(!template.isUnlocked(1));
    }

    function testLockIdRevertTokenDoesNotExist() public {
        vm.expectRevert(ERC721.TokenDoesNotExist.selector);
        template.lockId(1);
    }

    function testLockIdRevertNotApprovedContract() public {
        address[] memory approved = new address[](1);
        approved[0] = address(42);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        vm.expectRevert(IERC721x.NotApprovedContract.selector);
        template.lockId(1);
    }

    function testLockIdRevertAlreadyLocked() public {
        address[] memory approved = new address[](1);
        approved[0] = address(this);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);
        vm.expectRevert(IERC721x.AlreadyLocked.selector);
        template.lockId(1);
    }

    function testUnlockId() public {
        address[] memory approved = new address[](1);
        approved[0] = address(this);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);
        template.unlockId(1);
        require(template.isUnlocked(1));
    }

    function testUnlockIdNotLastLocker() public {
        address[] memory approved = new address[](2);
        approved[0] = address(this);
        approved[1] = address(333);
        bool[] memory status = new bool[](2);
        status[0] = true;
        status[1] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);

        vm.prank(address(333));
        template.lockId(1);

        template.unlockId(1);
        require(!template.isUnlocked(1));
    }

    function testUnlockIdRevertTokenDoesNotExist() public {
        vm.expectRevert(ERC721.TokenDoesNotExist.selector);
        template.unlockId(1);
    }

    function testUnlockIdRevertNotApprovedContract() public {
        address[] memory approved = new address[](1);
        approved[0] = address(42);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        vm.expectRevert(IERC721x.NotApprovedContract.selector);
        template.unlockId(1);
    }

    function testUnlockIdRevertTokenNotLocked() public {
        address[] memory approved = new address[](1);
        approved[0] = address(this);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        vm.expectRevert(IERC721x.NotLocked.selector);
        template.unlockId(1);
    }

    function testFreeId() public {
        address[] memory approved = new address[](1);
        approved[0] = address(this);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);
        status[0] = false;
        template.updateApprovedContracts(approved, status);
        template.freeId(1, address(this));
        require(template.isUnlocked(1));
    }

    function testFreeIdNotLastLocker() public {
        address[] memory approved = new address[](2);
        approved[0] = address(this);
        approved[1] = address(333);
        bool[] memory status = new bool[](2);
        status[0] = true;
        status[1] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);

        vm.prank(address(333));
        template.lockId(1);

        approved = new address[](1);
        approved[0] = address(this);
        status = new bool[](1);
        status[0] = false;
        template.updateApprovedContracts(approved, status);

        template.freeId(1, address(this));
        require(!template.isUnlocked(1));
    }

    function testFreeIdRevertTokenDoesNotExist() public {
        vm.expectRevert(ERC721.TokenDoesNotExist.selector);
        template.freeId(1, address(this));
    }

    function testFreeIdRevertApprovedContract() public {
        address[] memory approved = new address[](1);
        approved[0] = address(this);
        bool[] memory status = new bool[](1);
        status[0] = true;
        template.updateApprovedContracts(approved, status);

        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        template.lockId(1);
        vm.expectRevert(IERC721x.ApprovedContract.selector);
        template.freeId(1, address(this));
    }

    function testFreeIdRevertNotLocked() public {
        template.unpause();
        template.mint{ value: 0.01 ether }(address(this), 1, 2000);
        vm.expectRevert(IERC721x.NotLocked.selector);
        template.freeId(1, address(this));
    }
    function testUpdateApprovedContractsRevertArrayLengthMismatch() public {
        address[] memory contracts = new address[](2);
        contracts[0] = address(1);
        contracts[1] = address(2);
        bool[] memory values = new bool[](1);
        values[0] = true;

        vm.expectRevert(IERC721x.ArrayLengthMismatch.selector);
        template.updateApprovedContracts(contracts, values);
    }
    */

    function testWithdrawFundsBeta(bytes32 callerSalt, bytes32 recipientSalt, uint256 amount) public {
        vm.assume(callerSalt != recipientSalt);
        vm.assume(callerSalt != bytes32(""));
        vm.assume(recipientSalt != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address recipient = _bytesToAddress(recipientSalt);
        amount = bound(amount, 1, 100);
        vm.deal(caller, 0.01 ether * amount);

        template.unpause();

        vm.prank(caller);
        template.mint{ value: 0.01 ether * amount }(recipient, amount, 2000);

        vm.expectRevert(NotZero.selector);
        template.withdraw(address(0), type(uint256).max);

        vm.prank(recipient);
        vm.expectRevert(Ownable.Unauthorized.selector);
        template.withdraw(caller, type(uint256).max);

        template.withdraw(recipient, 0.001 ether);
        assertEq(address(recipient).balance, 0.001 ether, "partial recipient balance error");
        template.withdraw(recipient, type(uint256).max);
        assertEq(address(recipient).balance, 0.008 ether * amount, "full recipient balance error");
    }
}
