// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

// >>>>>>>>>>>> [ IMPORTS ] <<<<<<<<<<<<

import {ERC721x} from "../lib/ERC721x/src/erc721/ERC721x.sol";
import {ERC2981} from "../lib/solady/src/tokens/ERC2981.sol";
import {Initializable} from "../lib/solady/src/utils/Initializable.sol";
import {ReentrancyGuard} from "../lib/solady/src/utils/ReentrancyGuard.sol";

import {EnumerableSetLib} from "../lib/solady/src/utils/EnumerableSetLib.sol";
import {LibString} from "../lib/solady/src/utils/LibString.sol";
import {FixedPointMathLib as FPML} from "../lib/solady/src/utils/FixedPointMathLib.sol";
import {MerkleProofLib} from "../lib/solady/src/utils/MerkleProofLib.sol";

import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC721} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";

//import {console2} from "../lib/forge-std/src/console2.sol";

// >>>>>>>>>>>> [ INTERFACES ] <<<<<<<<<<<<

interface IAsset {
    function balanceOf(address holder) external returns (uint256);
}

interface IAlignmentVaultMinimal {
    function vault() external view returns (address);
    function alignedNft() external view returns (address);
}

interface IFactory {
    function deploy(address vaultOwner, address alignedNft, uint96 vaultId) external returns (address);
    function deployDeterministic(
        address vaultOwner,
        address alignedNft,
        uint96 vaultId,
        bytes32 salt
    ) external returns (address);
}

/**
 * @title ERC721M
 * @author Zodomo.eth (Farcaster/Telegram/Discord/Github: @zodomo, X: @0xZodomo, Email: zodomo@proton.me)
 * @notice A NFT template that can be configured to automatically send a portion of mint funds to an AlignmentVault
 * @custom:github https://github.com/Zodomo/ERC721M
 */
contract ERC721M is ERC721x, ERC2981, Initializable, ReentrancyGuard {
    using LibString for uint256; // Used to convert uint256 tokenId to string for tokenURI()
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    // >>>>>>>>>>>> [ ERRORS ] <<<<<<<<<<<<

    error Invalid();
    error MintCap();
    error URILocked();
    error NotAligned();
    error MintClosed();
    error Blacklisted();
    error TransferFailed();
    error NothingToClaim();
    error ExcessiveClaim();
    error RoyaltiesDisabled();
    error InsufficientPayment();

    // >>>>>>>>>>>> [ EVENTS ] <<<<<<<<<<<<

    event URILock();
    event MintOpen();
    event RoyaltyDisabled();
    event Withdraw(address indexed to, uint256 indexed amount);
    event PriceUpdate(uint80 indexed price);
    event SupplyUpdate(uint40 indexed supply);
    event AlignmentUpdate(uint16 indexed minAllocation, uint16 indexed maxAllocation);
    event BlacklistUpdate(address[] indexed blacklistedAssets, bool indexed status);
    event ReferralFeePaid(address indexed referral, uint256 indexed amount);
    event ReferralFeeUpdate(uint16 indexed referralFee);
    event BatchMetadataUpdate(uint256 indexed fromTokenId, uint256 indexed toTokenId);
    event ContractMetadataUpdate(string indexed uri);
    event RoyaltyUpdate(uint256 indexed tokenId, address indexed receiver, uint96 indexed royaltyFee);
    event CustomMinted(address indexed minter, uint8 indexed listId, uint40 indexed amount);
    event CustomMintDeleted(uint8 indexed listId);
    event CustomMintDisabled(uint8 indexed listId);
    event CustomMintRepriced(uint8 indexed listId, uint80 indexed price);
    event CustomMintReenabled(uint8 indexed listId, uint40 indexed claimable);
    event CustomMintConfigured(bytes32 indexed merkleRoot, uint8 indexed listId, uint40 indexed amount);

    // >>>>>>>>>>>> [ STORAGE ] <<<<<<<<<<<<

    struct CustomMint {
        bytes32 root;
        uint40 issued;
        uint40 claimable;
        uint40 supply;
        uint80 price;
    }

    // Address of AlignmentVaultFactory, used when deploying AlignmentVault
    address public constant vaultFactory = 0x7c1A6B4B373E70730c52dfCB2e0A67E7591d4AAa;
    uint16 internal constant _MAX_ROYALTY_BPS = 1000;
    uint16 internal constant _DENOMINATOR_BPS = 10_000;

    EnumerableSetLib.AddressSet internal _blacklist;
    EnumerableSetLib.Uint256Set internal _customMintLists;
    string internal _name;
    string internal _symbol;
    string internal _baseURI;
    string internal _contractURI;
    uint40 internal _totalSupply;

    uint80 public price;
    uint40 public maxSupply;
    uint16 public minAllocation;
    uint16 public maxAllocation;
    uint16 public referralFee;
    bool public uriLocked;
    bool public mintOpen;
    address public alignmentVault;
    mapping(uint8 listId => CustomMint) public customMintData;
    mapping(address user => mapping(uint8 listId => uint256 claimed)) public customClaims;

    // >>>>>>>>>>>> [ MODIFIERS ] <<<<<<<<<<<<

    modifier mintable(uint256 amount) {
        if (_totalSupply + amount > maxSupply) revert MintCap();
        _;
    }

    // >>>>>>>>>>>> [ CONSTRUCTION / INITIALIZATION ] <<<<<<<<<<<<

    // Constructor is kept empty in order to make the template compatible with ERC-1167 proxy factories
    constructor() payable {}

    // Initialize contract, should be called immediately after deployment, ideally by factory
    function initialize(
        string memory name_, // Collection name ("Milady")
        string memory symbol_, // Collection symbol ("MIL")
        uint40 _maxSupply, // Max supply (~1.099T max)
        uint16 _royalty, // Percentage in basis points (420 == 4.20%)
        uint16 _allocation, // Minimum Percentage of mint funds to AlignmentVault in basis points, minimum of 5% (777 == 7.77%)
        address _owner, // Collection contract owner
        address _alignedNft, // Address of NFT to configure AlignmentVault for, must have NFTX vault!
        uint80 _price, // Price (~1.2M ETH max)
        uint96 _vaultId, // NFTX Vault ID, please check!
        bytes32 _salt // AV Deployment salt
    ) external payable virtual initializer {
        // Confirm mint alignment allocation is within valid range
        if (_allocation < 500) revert NotAligned(); // Require allocation be >= 5%
        if (_allocation > _DENOMINATOR_BPS || _royalty > _MAX_ROYALTY_BPS) revert Invalid(); // Require allocation and royalty be <= 100%
        minAllocation = _allocation;
        maxAllocation = _allocation;
        _setTokenRoyalty(0, _owner, _royalty);
        _setDefaultRoyalty(_owner, _royalty);
        // Initialize ownership
        _initializeOwner(_owner);
        // Set all values
        _name = name_;
        _symbol = symbol_;
        maxSupply = _maxSupply;
        price = _price;
        // Deploy AlignmentVault
        address deployedAV;
        if (_salt == bytes32("")) deployedAV = IFactory(vaultFactory).deploy(_owner, _alignedNft, _vaultId);
        else deployedAV = IFactory(vaultFactory).deployDeterministic(_owner, _alignedNft, _vaultId, _salt);
        alignmentVault = deployedAV;
        // Send initialize payment (if any) to vault
        if (msg.value > 0) {
            (bool success,) = payable(deployedAV).call{value: msg.value}("");
            if (!success) revert TransferFailed();
        }
        emit AlignmentUpdate(_allocation, _allocation);
    }

    // >>>>>>>>>>>> [ VIEW / METADATA FUNCTIONS ] <<<<<<<<<<<<

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function baseURI() public view virtual returns (string memory) {
        return _baseURI;
    }

    function contractURI() public view virtual returns (string memory) {
        return _contractURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        string memory newBaseURI = baseURI();
        return (bytes(newBaseURI).length > 0 ? string(abi.encodePacked(newBaseURI, tokenId.toString())) : "");
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    // Override to add royalty interface. ERC721, ERC721Metadata, and ERC721x are present in the ERC721x override
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721x, ERC2981) returns (bool) {
        return ERC721x.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    function getBlacklist() public view virtual returns (address[] memory) {
        return _blacklist.values();
    }

    function getCustomMintListIds() external view virtual returns (uint256[] memory) {
        return _customMintLists.values();
    }

    // >>>>>>>>>>>> [ INTERNAL FUNCTIONS ] <<<<<<<<<<<<

    // Blacklist function to prevent mints to and from holders of prohibited assets, applied even if recipient isn't minter
    function _enforceBlacklist(address minter, address recipient) internal virtual {
        address[] memory blacklist = _blacklist.values();
        uint256 count;
        for (uint256 i = 1; i < blacklist.length;) {
            unchecked {
                count += IAsset(blacklist[i]).balanceOf(minter);
                count += IAsset(blacklist[i]).balanceOf(recipient);
                if (count > 0) revert Blacklisted();
                ++i;
            }
        }
    }

    // >>>>>>>>>>>> [ MINT LOGIC ] <<<<<<<<<<<<

    // Solady ERC721 _mint override to implement mint funds alignment and blacklist
    function _mint(address recipient, uint256 amount, address referral, uint16 allocation) internal {
        // Prevent bad inputs
        if (recipient == address(0) || amount == 0) revert Invalid();
        // Ensure minter and recipient don't hold blacklisted assets
        _enforceBlacklist(msg.sender, recipient);
        // Ensure allocation set by the user is in the range between minAllocation and maxAllocation
        if (allocation < minAllocation || allocation > maxAllocation) revert Invalid();
        // Calculate allocation
        uint256 mintAlloc = FPML.fullMulDivUp(allocation, msg.value, _DENOMINATOR_BPS);

        if (msg.value > 0) {
            // Send aligned amount to AlignmentVault (success is intentionally not read to save gas as it cannot fail)
            payable(alignmentVault).call{value: mintAlloc}("");
            // If referral isn't address(0), process sending referral fee
            // Reentrancy is handled by applying ReentrancyGuard to referral mint function [mint(address, uint256, address)]
            if (referral != address(0) && referral != msg.sender) {
                uint256 referralAlloc = FPML.mulDivUp(referralFee, msg.value, _DENOMINATOR_BPS);
                (bool success,) = payable(referral).call{value: referralAlloc}("");
                if (!success) revert TransferFailed();
                emit ReferralFeePaid(referral, referralAlloc);
            }
        }

        // Process ERC721 mints
        // totalSupply is read once externally from loop to reduce SLOADs to save gas
        uint256 supply = _totalSupply;
        for (uint256 i; i < amount;) {
            _mint(recipient, ++supply);
            unchecked {
                ++i;
            }
        }
        unchecked {
            _totalSupply += uint40(amount);
        }
    }

    // Standard single-unit mint to msg.sender (implemented for max scannner compatibility)
    function mint() public payable virtual mintable(1) {
        if (!mintOpen) revert MintClosed();
        if (msg.value < price) revert InsufficientPayment();
        _mint(msg.sender, 1, address(0), minAllocation);
    }

    // Standard multi-unit mint to msg.sender (implemented for max scanner compatibility)
    function mint(uint256 amount) public payable virtual mintable(amount) {
        if (!mintOpen) revert MintClosed();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(msg.sender, amount, address(0), minAllocation);
    }

    // Standard mint function that supports batch minting
    function mint(address recipient, uint256 amount) public payable virtual mintable(amount) {
        if (!mintOpen) revert MintClosed();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, address(0), minAllocation);
    }

    // Standard batch mint with referral fee support
    function mint(
        address recipient,
        uint256 amount,
        address referral
    ) public payable virtual mintable(amount) nonReentrant {
        if (!mintOpen) revert MintClosed();
        if (referral == msg.sender) revert Invalid();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, referral, minAllocation);
    }

    // Standard mint function that supports batch minting and custom allocation
    function mint(address recipient, uint256 amount, uint16 allocation) public payable virtual mintable(amount) {
        if (!mintOpen) revert MintClosed();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, address(0), allocation);
    }

    // Standard batch mint with custom allocation support and referral fee support
    function mint(
        address recipient,
        uint256 amount,
        address referral,
        uint16 allocation
    ) public payable virtual mintable(amount) nonReentrant {
        if (!mintOpen) revert MintClosed();
        if (referral == msg.sender) revert Invalid();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, referral, allocation);
    }

    // Whitelisted mint using merkle proofs
    function customMint(
        bytes32[] calldata proof,
        uint8 listId,
        address recipient,
        uint40 amount,
        address referral
    ) public payable virtual mintable(amount) nonReentrant {
        CustomMint memory mintData = customMintData[listId];
        if (mintData.root == bytes32("")) revert Invalid();
        if (amount > mintData.supply) revert MintCap();
        if (customClaims[msg.sender][listId] + amount > mintData.claimable) revert ExcessiveClaim();
        if (msg.value < amount * mintData.price) revert InsufficientPayment();

        bytes32 leaf = keccak256(bytes.concat(keccak256(bytes.concat(abi.encode(msg.sender)))));
        if (!MerkleProofLib.verifyCalldata(proof, mintData.root, leaf)) revert NothingToClaim();

        unchecked {
            customClaims[msg.sender][listId] += amount;
            customMintData[listId].supply -= amount;
        }
        _mint(recipient, amount, referral, minAllocation);
        emit CustomMinted(msg.sender, listId, amount);
    }

    // >>>>>>>>>>>> [ PERMISSIONED / OWNER FUNCTIONS ] <<<<<<<<<<<<

    // Set referral fee, must be < (_DENOMINATOR_BPS - allocation)
    function setReferralFee(uint16 newReferralFee) external virtual onlyOwner {
        if (newReferralFee > (_DENOMINATOR_BPS - maxAllocation)) revert Invalid();
        referralFee = newReferralFee;
        emit ReferralFeeUpdate(newReferralFee);
    }

    // Update baseURI and/or contractURI for the entire collection
    function setMetadata(string memory newBaseURI, string memory newContractURI) external virtual onlyOwner {
        if (uriLocked) revert URILocked();
        if (bytes(newBaseURI).length > 0) {
            _baseURI = newBaseURI;
            emit BatchMetadataUpdate(0, maxSupply);
        }
        if (bytes(newContractURI).length > 0) {
            _contractURI = newContractURI;
            emit ContractMetadataUpdate(newContractURI);
        }
    }

    // Permanently lock collection URI
    function lockURI() external virtual onlyOwner {
        uriLocked = true;
        emit URILock();
    }

    // Update ETH mint price
    function setPrice(uint80 newPrice) external virtual onlyOwner {
        price = newPrice;
        emit PriceUpdate(newPrice);
    }

    // Set default royalty receiver and royalty fee
    function setRoyalties(address recipient, uint96 royaltyFee) external virtual onlyOwner {
        if (royaltyFee > _MAX_ROYALTY_BPS) revert Invalid();
        // Revert if royalties are disabled
        (address receiver,) = royaltyInfo(0, 0);
        if (receiver == address(0)) revert RoyaltiesDisabled();

        // Royalty recipient of nonexistent tokenId 0 is used as royalty status indicator, address(0) == disabled
        _setTokenRoyalty(0, recipient, royaltyFee);
        _setDefaultRoyalty(recipient, royaltyFee);
        emit RoyaltyUpdate(0, recipient, royaltyFee);
    }

    // Set royalty receiver and royalty fee for a specific tokenId
    function setRoyaltiesForId(uint256 tokenId, address recipient, uint96 royaltyFee) external virtual onlyOwner {
        if (royaltyFee > _MAX_ROYALTY_BPS) revert Invalid();
        // Revert if royalties are disabled
        (address receiver,) = royaltyInfo(0, 0);
        if (receiver == address(0)) revert RoyaltiesDisabled();
        // Revert if resetting tokenId 0 as it is utilized for royalty enablement status
        if (tokenId == 0) revert Invalid();

        // Reset token royalty if fee is 0, else set it
        if (royaltyFee == 0) _resetTokenRoyalty(tokenId);
        else _setTokenRoyalty(tokenId, recipient, royaltyFee);
        emit RoyaltyUpdate(tokenId, recipient, royaltyFee);
    }

    // Set arbitrary custom mint lists using merkle trees, can be reconfigured
    // NOTE: Cannot retroactively reduce mintable amount below minted supply for custom mint list
    function setCustomMint(
        bytes32 root,
        uint8 listId,
        uint40 amount,
        uint40 claimable,
        uint80 newPrice
    ) external virtual onlyOwner {
        if (!_customMintLists.contains(listId)) _customMintLists.add(listId);
        CustomMint memory mintData = customMintData[listId];
        // Validate adjustment doesn't decrease amount below custom minted count
        if (mintData.issued != 0 && mintData.issued - mintData.supply > amount) revert Invalid();
        uint40 supply;
        unchecked {
            // Set amount as supply if new custom mint
            if (mintData.issued == 0) {
                supply = amount;
            }
            // Properly adjust existing supply
            else {
                supply = amount >= mintData.issued
                    ? mintData.supply + (amount - mintData.issued)
                    : mintData.supply - (mintData.issued - amount);
            }
        }
        customMintData[listId] =
            CustomMint({root: root, issued: amount, claimable: claimable, supply: supply, price: newPrice});
        emit CustomMintConfigured(root, listId, amount);
    }

    // Reduces claimable supply for custom list to 0
    function disableCustomMint(uint8 listId) external virtual onlyOwner {
        if (!_customMintLists.contains(listId)) revert Invalid();
        customMintData[listId].claimable = 0;
        emit CustomMintDisabled(listId);
    }

    // Reenables custom mint by setting claimable amount
    function reenableCustomMint(uint8 listId, uint40 claimable) external virtual onlyOwner {
        if (!_customMintLists.contains(listId)) revert Invalid();
        uint40 issued = customMintData[listId].issued;
        claimable = claimable <= issued ? claimable : issued;
        customMintData[listId].claimable = claimable;
        emit CustomMintReenabled(listId, claimable);
    }

    // Reprice custom mint
    function repriceCustomMint(uint8 listId, uint80 newPrice) external virtual onlyOwner {
        if (!_customMintLists.contains(listId)) revert Invalid();
        customMintData[listId].price = newPrice;
        emit CustomMintRepriced(listId, newPrice);
    }

    // Completely nukes a custom mint list to minimal state
    function nukeCustomMint(uint8 listId) external virtual onlyOwner {
        CustomMint memory mintData = customMintData[listId];
        if (mintData.issued == mintData.supply) {
            if (_customMintLists.contains(listId)) _customMintLists.remove(listId);
            delete customMintData[listId];
            emit CustomMintDeleted(listId);
        } else {
            customMintData[listId] = CustomMint({
                root: bytes32(""),
                issued: mintData.issued - mintData.supply,
                claimable: 0,
                supply: 0,
                price: 0
            });
            emit CustomMintConfigured(bytes32(""), listId, 0);
        }
    }

    // Irreversibly disable royalties by resetting tokenId 0 royalty to (address(0), 0) and deleting default royalty info
    function disableRoyalties() external virtual onlyOwner {
        _deleteDefaultRoyalty();
        _resetTokenRoyalty(0);
        emit RoyaltyDisabled();
    }

    // Configure which assets are on blacklist
    function setBlacklist(address[] memory blacklistedAssets, bool status) external virtual onlyOwner {
        for (uint256 i; i < blacklistedAssets.length; ++i) {
            if (status) _blacklist.add(blacklistedAssets[i]);
            else _blacklist.remove(blacklistedAssets[i]);
        }
        emit BlacklistUpdate(blacklistedAssets, status);
    }

    // Open mint functions
    function openMint() external virtual onlyOwner {
        mintOpen = true;
        emit MintOpen();
    }

    // Increase mint alignment allocation
    // NOTE: There will be no function to decrease this value. This operation is one-way only.
    function increaseAlignment(uint16 newMinAllocation, uint16 newMaxAllocation) external virtual onlyOwner {
        uint16 _minAllocation = minAllocation;
        if (newMaxAllocation < _minAllocation) revert Invalid();
        // Prevent oversetting alignment (keeping maxAllocation in mind)
        if (newMaxAllocation + referralFee > _DENOMINATOR_BPS) revert Invalid();
        // Prevent alignment deception (changing it last mint) by locking minAllocation in at 50% minted
        if (totalSupply() < maxSupply / 2) {
            if (newMinAllocation < _minAllocation || newMinAllocation > newMaxAllocation) revert Invalid();
            minAllocation = newMinAllocation;
        } else {
            newMinAllocation = _minAllocation;
        }
        maxAllocation = newMaxAllocation;
        emit AlignmentUpdate(newMinAllocation, newMaxAllocation);
    }

    // Decrease token maxSupply
    // NOTE: There is and will be no function to increase supply. This operation is one-way only.
    function decreaseSupply(uint40 newMaxSupply) external virtual onlyOwner {
        if (newMaxSupply >= maxSupply || newMaxSupply < totalSupply()) revert Invalid();
        maxSupply = newMaxSupply;
        emit SupplyUpdate(newMaxSupply);
    }

    // Withdraw non-allocated mint funds
    function withdrawFunds(address recipient, uint256 amount) external virtual nonReentrant {
        // Cache owner address to save gas
        address owner = owner();
        uint256 balance = address(this).balance;
        if (recipient == address(0)) revert Invalid();
        // If contract is owned and caller isn't them, revert.
        if (owner != address(0) && owner != msg.sender) revert Unauthorized();
        // If contract is renounced, convert recipient to vault and withdraw all funds to it
        if (owner == address(0)) {
            recipient = alignmentVault;
            amount = balance;
        }
        // Instead of reverting for overage, simply overwrite amount with balance
        if (amount > balance) amount = balance;

        // Process withdrawal
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();
        emit Withdraw(recipient, amount);
    }

    // >>>>>>>>>>>> [ ASSET HANDLING ] <<<<<<<<<<<<

    // Internal handling for receive() and fallback() to reduce code length
    function _processPayment() internal {
        if (mintOpen) {
            mint(msg.sender, (msg.value / price));
        } else {
            // Calculate allocation and split paymeent accordingly
            uint256 mintAlloc = FPML.fullMulDivUp(minAllocation, msg.value, _DENOMINATOR_BPS);
            // Success when transferring to vault isn't checked because transfers to vault cant fail
            payable(alignmentVault).call{value: mintAlloc}("");
            // Reentrancy risk is ignored here because if owner wants to withdraw that way that's their prerogative
            // But if transfer to owner fails for any reason, it will be sent to the vault
            (bool success,) = payable(owner()).call{value: msg.value - mintAlloc}("");
            if (!success) payable(alignmentVault).call{value: msg.value - mintAlloc}("");
        }
    }

    // Rescue non-aligned tokens from contract, else send aligned tokens to vault
    function rescueERC20(address addr, address recipient) external virtual onlyOwner {
        uint256 balance = IERC20(addr).balanceOf(address(this));
        if (addr == IAlignmentVaultMinimal(alignmentVault).vault()) {
            IERC20(addr).transfer(alignmentVault, balance);
        } else {
            IERC20(addr).transfer(recipient, balance);
        }
    }

    // Rescue non-aligned NFTs from contract, else send aligned NFTs to vault
    function rescueERC721(address addr, address recipient, uint256 tokenId) external virtual onlyOwner {
        if (addr == IAlignmentVaultMinimal(alignmentVault).alignedNft()) {
            IERC721(addr).safeTransferFrom(address(this), alignmentVault, tokenId);
        } else {
            IERC721(addr).transferFrom(address(this), recipient, tokenId);
        }
    }

    // Forward aligned NFTs to vault, revert if sent other NFTs
    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external virtual returns (bytes4) {
        address nft = IAlignmentVaultMinimal(alignmentVault).alignedNft();
        if (msg.sender == nft) IERC721(nft).safeTransferFrom(address(this), alignmentVault, tokenId);
        else revert NotAligned();
        return ERC721M.onERC721Received.selector;
    }

    // Process all received ETH payments
    receive() external payable virtual {
        _processPayment();
    }

    // Forward calldata and payment to AlignmentVault. Used if ERC721M is AlignmentVault owner.
    // Calling this contract using the IAlignmentVaultMinimal interface will trigger this fallback.
    fallback() external payable virtual onlyOwner {
        assembly {
            // Store the target contract address from the storage variable
            let target := sload(alignmentVault.slot)
            // Store the calldata size in memory
            let calldataSize := calldatasize()
            // Copy the calldata to memory
            calldatacopy(0x0, 0x0, calldataSize)
            // Forward the calldata and msg.value to the target contract
            let result := call(gas(), target, callvalue(), 0x0, calldataSize, 0x0, 0x0)
            // Revert with the returned data if the call failed
            if iszero(result) {
                returndatacopy(0x0, 0x0, returndatasize())
                revert(0x0, returndatasize())
            }
            // Return the returned data if the call succeeded
            returndatacopy(0x0, 0x0, returndatasize())
            return(0x0, returndatasize())
        }
    }
}
