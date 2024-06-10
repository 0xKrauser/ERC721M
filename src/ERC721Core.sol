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


// >>>>>>>>>>>> [ INTERFACES ] <<<<<<<<<<<<

interface IAsset {
    function balanceOf(address holder) external returns (uint256);
}

/**
 * @title ERC721Core
 * @author Zodomo.eth (Farcaster/Telegram/Discord/Github: @zodomo, X: @0xZodomo, Email: zodomo@proton.me)
 * @author 0xKrauser (Discord/Github/X: @0xKrauser, Email: detroitmetalcrypto@gmail.com) 
 * @notice NFT template that contains launchpad friendly features to be inherited by other contracts
 * @custom:github https://github.com/Zodomo/ERC721M
 */
contract ERC721Core is ERC721x, ERC2981, Initializable, ReentrancyGuard {
    using LibString for uint256; // Used to convert uint256 tokenId to string for tokenURI()
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    // >>>>>>>>>>>> [ ERRORS ] <<<<<<<<<<<<

    error Invalid();
    error MintCap();
    error URILocked();
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

    uint16 internal constant _MAX_ROYALTY_BPS = 1000;
    uint16 internal constant _DENOMINATOR_BPS = 10000;

    EnumerableSetLib.AddressSet internal _blacklist;
    EnumerableSetLib.Uint256Set internal _customMintLists;
    string internal _name;
    string internal _symbol;
    string internal _baseURI;
    string internal _contractURI;
    uint40 internal _totalSupply;

    uint80 public price;
    uint40 public maxSupply;
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
        address _owner, // Collection contract owner
        uint80 _price // Price (~1.2M ETH max)
    ) public payable virtual onlyInitializing {
        if(_royalty > _MAX_ROYALTY_BPS) revert Invalid();
        _setTokenRoyalty(0, _owner, _royalty);
        _setDefaultRoyalty(_owner, _royalty);
        // Initialize ownership
        _initializeOwner(_owner);
        // Set all values
        _name = name_;
        _symbol = symbol_;
        maxSupply = _maxSupply;
        price = _price;
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

    // Solady ERC721 _mint override to implement blacklist and referral fee logic
    function _mint(address recipient, uint256 amount, address referral) internal virtual {
        // Prevent bad inputs
        if (recipient == address(0) || amount == 0) revert Invalid();
        // Ensure minter and recipient don't hold blacklisted assets
        _enforceBlacklist(msg.sender, recipient);

        if (msg.value > 0) {
            // If referral isn't address(0), process sending referral fee
            // Reentrancy is handled by applying ReentrancyGuard to referral mint function [mint(address, uint256, address)]
            //@TODO stash and then withdraw might be better for gas?
            //@TODO referral discounts? 
            if (referral != address(0) && referral != msg.sender) {
                uint256 referralAlloc = FPML.mulDivUp(referralFee, msg.value, _DENOMINATOR_BPS);
                (bool success, ) = payable(referral).call{value: referralAlloc}("");
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
        _mint(msg.sender, 1, address(0));
    }

    // Standard multi-unit mint to msg.sender (implemented for max scanner compatibility)
    function mint(uint256 amount) public payable virtual mintable(amount) {
        if (!mintOpen) revert MintClosed();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(msg.sender, amount, address(0));
    }

    // Standard mint function that supports batch minting
    function mint(address recipient, uint256 amount) public payable virtual mintable(amount) {
        if (!mintOpen) revert MintClosed();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, address(0));
    }

    // Standard batch mint with referral fee support
    function mint(address recipient, uint256 amount, address referral) public payable virtual mintable(amount) nonReentrant {
        if (!mintOpen) revert MintClosed();
        if (referral == msg.sender) revert Invalid();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, referral);
    }

    // Whitelisted mint using merkle proofs
    function customMint(bytes32[] calldata proof, uint8 listId, address recipient, uint40 amount, address referral) public payable virtual mintable(amount) nonReentrant {
        //@TODO maybe give the choice of basing the mint on the sender or the recipient?
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
        _mint(recipient, amount, referral);
        emit CustomMinted(msg.sender, listId, amount);
    }
    
    // >>>>>>>>>>>> [ PERMISSIONED / OWNER FUNCTIONS ] <<<<<<<<<<<<

    // >>>> [ ROYALTY FUNCTIONS ] <<<<

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
    function setRoyaltiesForId(
        uint256 tokenId,
        address recipient,
        uint96 royaltyFee
    ) external virtual onlyOwner {
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

    // Irreversibly disable royalties by resetting tokenId 0 royalty to (address(0), 0) and deleting default royalty info
    function disableRoyalties() external virtual onlyOwner {
        _deleteDefaultRoyalty();
        _resetTokenRoyalty(0);
        emit RoyaltyDisabled();
    }

    // >>>> [ CUSTOM MINT FUNCTIONS ] <<<<

    // Set arbitrary custom mint lists using merkle trees, can be reconfigured
    // NOTE: Cannot retroactively reduce mintable amount below minted supply for custom mint list
    function setCustomMint(bytes32 root, uint8 listId, uint40 amount, uint40 claimable, uint80 newPrice) external virtual onlyOwner {
        if (!_customMintLists.contains(listId)) _customMintLists.add(listId);
        CustomMint memory mintData = customMintData[listId];
        // Validate adjustment doesn't decrease amount below custom minted count
        if (mintData.issued != 0 && mintData.issued - mintData.supply > amount) revert Invalid();
        uint40 supply;
        unchecked {
            // Set amount as supply if new custom mint
            if (mintData.issued == 0) supply = amount;
            // Properly adjust existing supply
            else {
                supply = amount >= mintData.issued ? 
                    mintData.supply + (amount - mintData.issued) :
                    mintData.supply - (mintData.issued - amount);
            }
        }
        customMintData[listId] = CustomMint({ root: root, issued: amount, claimable: claimable, supply: supply, price: newPrice });
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

    // >>>> [ SETTER FUNCTIONS ] <<<<

    // Open mint functions
    function openMint() external virtual onlyOwner {
        mintOpen = true;
        emit MintOpen();
    }

    // @TODO: pause mint? close mint?

    // @TODO: time based mint open/close?

    // @TODO: might need to add a maximum per address?

    // Configure which assets are on blacklist
    function setBlacklist(address[] memory blacklistedAssets, bool status) external virtual onlyOwner {
        for (uint256 i; i < blacklistedAssets.length; ++i) {
            if (status) _blacklist.add(blacklistedAssets[i]);
            else _blacklist.remove(blacklistedAssets[i]);
        }
        emit BlacklistUpdate(blacklistedAssets, status);
    }

    // Update ETH mint price
    function setPrice(uint80 newPrice) external virtual onlyOwner {
        price = newPrice;
        emit PriceUpdate(newPrice);
    }

    // Update token maxSupply
    function setSupply(uint40 newMaxSupply) external virtual onlyOwner {
        uint256 currentSupply = totalSupply();
        if (newMaxSupply > maxSupply && currentSupply != 0 || newMaxSupply <= currentSupply) revert Invalid();
        maxSupply = newMaxSupply;
        emit SupplyUpdate(newMaxSupply);
    }

    // Set referral fee, must be < (_DENOMINATOR_BPS - allocation)
    function setReferralFee(uint16 newReferralFee) external virtual onlyOwner {
        if (newReferralFee > _DENOMINATOR_BPS) revert Invalid();
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

    // Withdraw non-allocated mint funds
    function withdrawFunds(address recipient, uint256 amount) external virtual nonReentrant {
        // Cache owner address to save gas
        address owner = owner();
        uint256 balance = address(this).balance;
        if (recipient == address(0)) revert Invalid();
        // If contract is owned and caller isn't them, revert.
        if (owner != address(0) && owner != msg.sender) revert Unauthorized();
        
        //@TODO maybe fallback to factory owner when address(0)?

        // Instead of reverting for overage, simply overwrite amount with balance
        if (amount > balance) amount = balance;

        // Process withdrawal
        (bool success,) = payable(recipient).call{ value: amount }("");
        if (!success) revert TransferFailed();
        emit Withdraw(recipient, amount);
    }

    // >>>>>>>>>>>> [ ASSET HANDLING ] <<<<<<<<<<<<

    // Internal handling for receive() and fallback() to reduce code length
    function _processPayment() internal virtual {
        if (mintOpen) mint(msg.sender, (msg.value / price));
        else {
            //@TODO handle address(0)?
            (bool success,) = payable(owner()).call{ value: msg.value }("");
            if (!success) revert Invalid();
        }
    }

    // Rescue tokens from contract
    function rescueERC20(address addr, address recipient) external virtual onlyOwner {
        uint256 balance = IERC20(addr).balanceOf(address(this));
        IERC20(addr).transfer(recipient, balance);
    }

    // Rescue NFTs from contract
    function rescueERC721(address addr, address recipient, uint256 tokenId) external virtual onlyOwner {
        IERC721(addr).transferFrom(address(this), recipient, tokenId);
    }

    // Process all received ETH payments
    receive() external payable virtual {
        _processPayment();
    }
}