// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

// >>>>>>>>>>>> [ IMPORTS ] <<<<<<<<<<<<

import { ERC721x } from "../lib/ERC721x/src/erc721/ERC721x.sol";
import { ERC2981 } from "../lib/solady/src/tokens/ERC2981.sol";
import { Initializable } from "../lib/solady/src/utils/Initializable.sol";
import { ReentrancyGuard } from "../lib/solady/src/utils/ReentrancyGuard.sol";

import { EnumerableSetLib } from "../lib/solady/src/utils/EnumerableSetLib.sol";
import { LibString } from "../lib/solady/src/utils/LibString.sol";
import { FixedPointMathLib as FPML } from "../lib/solady/src/utils/FixedPointMathLib.sol";
import { MerkleProofLib } from "../lib/solady/src/utils/MerkleProofLib.sol";

import { IERC20 } from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IERC721 } from "../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
//import {console2} from "../lib/forge-std/src/Console2.sol";

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

    /// @dev Input parameter doesn't satisfy a given condition.
    error Invalid();

    /// @dev Self-referral to either msg.sender or recipient is not allowed.
    error SelfReferralNotAllowed();

    /// @dev Cannot mint a token beyond maxSupply.
    error MintCap();

    /// @dev Cannot set tokenURIs or baseURI when metadata has been frozen.
    error IsPermanentURI();

    /// @dev Cannot mint when contract is paused.
    error MintClosed();

    /// @dev Cannot make an operation from a blacklisted address.
    error Blacklisted();

    /// @dev Transfer of ether to an address failed.
    error TransferFailed();

    /// @dev List is paused
    error ListPaused();

    /// @dev List is deleted
    error ListDeleted();

    /// @dev List does not exist
    error ListDoesNotExist();

    // @TODO
    error ReservedExceedsMaxSupply();

    // @TODO
    error BreaksReservedSupply();

    /// @dev msg.sender/recipient is not eligible to claim any mint allocation for a given MintList.
    error NotAllowedToClaim();

    /**
     * @dev msg.sender/recipient can't claim more than the allowed claimable supply
     * for a given MintList in a single operation.
     */
    error ExcessiveClaim();

    /// @dev Cannot set royalties when they have previously been disabled.
    error RoyaltiesDisabled();

    /// @dev Cannot mint with a msg.value lower than the price for one token.
    error InsufficientPayment();

    // >>>>>>>>>>>> [ EVENTS ] <<<<<<<<<<<<

    //@TODO consider removing indexed from some parameters, save on gas
    // as long as the contract is verified or we have access to the ABI the events will be indexed properly by default

    /**
     * @dev Emitted when a new ERC721 contract is created.
     * @param _name The name of the ERC721 contract.
     * @param _symbol The symbol of the ERC721 contract.
     * @custom:unique
     */
    event ContractCreated(string indexed _name, string indexed _symbol);

    /**
     * @dev Emitted when a permanent URI is set for a specific token ID.
     *
     * @param _value The permanent URI value.
     * @param _id The token ID for which the permanent URI is set.
     */
    event PermanentURI(string _value, uint256 indexed _id);

    /**
     * @dev Emitted when a batch of tokens have their permanent URI set.
     * This event is emitted when a range of token IDs have their permanent URI set.
     *
     * @param _fromTokenId The starting token ID of the range.
     * @param _toTokenId The ending token ID of the range.
     * @custom:unique
     */
    event BatchPermanentURI(uint256 indexed _fromTokenId, uint256 indexed _toTokenId);

    /**
     * @dev Emitted when the minting process is open.
     * @param _status The status, true means mint is open.
     */
    event MintOpen(bool indexed _status);

    /**
     * @dev Emitted when the royalty feature is disabled by setting address(0) as receiver.
     * @custom:unique
     */
    event RoyaltyDisabled();

    /**
     * @dev Emitted when the contract owner withdraws funds.
     *
     * @param to The address to which the funds are withdrawn.
     * @param amount The amount of funds withdrawn.
     */
    event Withdraw(address indexed to, uint256 indexed amount);

    /**
     * @dev Emitted when the price is updated.
     * @param price The new price.
     */
    event PriceUpdate(uint80 indexed price);

    /**
     * @dev Emitted when the supply is updated.
     * @param supply The new supply.
     */
    event SupplyUpdate(uint64 indexed supply);

    /**
     * @dev Emitted when the blacklist is updated.
     * @param blacklistedAssets The list of addresses marked for blacklist addition/removal.
     * @param status The status to which they have been updated.
     */
    event BlacklistUpdate(address[] indexed blacklistedAssets, bool indexed status);

    /**
     * @dev Emitted when a referral fee is paid.
     * @param _referral The address of the referrer.
     * @param _value The value of the referral fee.
     */
    //@TODO * @param _referred The address of the referred account.
    //@TODO * @param _amount The amount of tokens minted.
    event ReferralFeePaid(address indexed _referral, uint256 indexed _value);

    /**
     * @dev Emitted when the referral fee is updated.
     * @param _referralFee The new referral fee.
     */
    event ReferralFeeUpdate(uint16 indexed _referralFee);

    /**
     * @dev Emitted when the metadata for a single token is updated.
     * @param _tokenId The token ID for which the metadata is updated.
     */
    event MetadataUpdate(uint256 indexed _tokenId);

    /**
     * @dev Emitted when the metadata for a batch of tokens is updated.
     * @param _fromTokenId The starting token ID of the range.
     * @param _toTokenId The ending token ID of the range.
     */
    event BatchMetadataUpdate(uint256 indexed _fromTokenId, uint256 indexed _toTokenId);

    /**
     * @dev Emitted when the contract metadata is updated.
     * @param _uri The new contract metadata URI.
     */
    event ContractMetadataUpdate(string indexed _uri);

    /**
     * @dev Emitted when the royalty fee for a specific token is updated.
     * @param tokenId The ID of the token for which the royalty fee is updated.
     * @param receiver The address of the receiver of the royalty fee.
     * @param royaltyFee The updated royalty fee, represented as a 96-bit fixed-point number.
     */
    event RoyaltyUpdate(uint256 indexed tokenId, address indexed receiver, uint96 indexed royaltyFee);

    /**
     * @notice Emitted when the minting range is updated.
     * @param start_ The new start timestamp of the public mint.
     * @param end_ The new end timestamp of the public mint.
     */
    event MintRangeUpdate(uint256 indexed start_, uint256 indexed end_);

    /**
     * @dev Emitted when the maximum claimable tokens per user are updated.
     * @param claimable_ The new amount of tokens available per address.
     */
    event UserClaimableUpdate(uint256 indexed claimable_);

    /**
     * @dev Emitted when the default unit amount of tokens minted is updated.
     * @param unit_ The new amount of tokens you mint for every 1 you pay.
     */
    event UnitUpdate(uint64 indexed unit_);

    /**
     * @dev Emitted when someone mints from a list.
     * @param minter_ The address of the minter.
     * @param listId_ The ID of the custom mint list.
     * @param amount_ The amount of tokens minted.
     */
    event ListMinted(address indexed minter_, uint8 indexed listId_, uint256 indexed amount_);

    /**
     * @dev Emitted when a custom mint list is disabled.
     * @param _listId The ID of the custom mint list.
     * @param _paused The paused status of the custom mint list.
     */
    event MintListStatus(uint8 indexed _listId, bool indexed _paused);

    /**
     * @dev Emitted when a custom mint list is deleted.
     * @param _listId The ID of the custom mint list.
     * @custom:unique
     */
    event MintListDeleted(uint8 indexed _listId);

    /**
     * @dev Emitted when a custom mint list is configured.
     * @param _listId The ID of the custom mint list.
     * @param _list The configuration of the list.
     */
    //@TODO * @param _claimable The amount of tokens available per address.
    //@TODO * @param _price The price per token in wei.

    event MintListUpdate(uint8 indexed _listId, MintList _list);

    // >>>>>>>>>>>> [ STORAGE ] <<<<<<<<<<<<

    //@TODO review this
    /**
     * @dev Represents a custom mint configuration.
     *
     * This struct contains the following fields:
     * @param root The root hash of the merkle tree.
     * @param issued The number of tokens already issued.
     * @param claimed The number of tokens that can be claimed by a single address.
     * @param supply The total supply of tokens.
     * @param price The price of each token.
     */
    struct MintList {
        bytes32 root;
        uint64 userSupply;
        uint64 maxSupply;
        uint64 unit;
        uint32 start;
        uint32 end;
        uint128 price;
        bool reserved;
        bool paused;
    }
    // address tokenAddress;

    //@TODO opinionated? might consider to move it in factory
    /// @dev Maximum royalty fee in basis points.
    uint16 internal constant _MAX_ROYALTY_BPS = 1000;

    /// @dev Denominator for basis points. Equivalent to 100% with 2 decimal places.
    uint16 internal constant _DENOMINATOR_BPS = 10_000;

    /// @dev Interface ID for ERC4906. Used in supportsInterface.
    bytes4 private constant ERC4906_INTERFACE_ID = bytes4(0x49064906);

    /// @dev Enumerable set of blacklisted asset addresses.
    EnumerableSetLib.AddressSet internal _blacklist;

    /// @dev Enumerable set of custom mint list IDs.
    EnumerableSetLib.Uint256Set internal _customMintLists;

    /**
     * @dev Name of the collection.
     * e.g. "Milady Maker"
     * @custom:immutable
     */
    string internal _name;

    /**
     * @dev Symbol of the collection.
     * e.g. "MILADY"
     * @custom:immutable
     */
    string internal _symbol;

    /**
     * @dev Base URI for the collection tokenURIs.
     * e.g. "https://miladymaker.net/", "ipfs://QmXyZ/", "ar://QmXyZ/"
     */
    string internal _baseURI;

    /**
     * @dev File extension for the collection tokenURIs.
     * e.g. ".json", ".jsonc", "" (empty)
     */
    string internal _fileExtension;

    /**
     * @dev Contract URI for the collection.
     * e.g. "ipfs://QmXyZ/contract.json", "ar://QmXyZ/contract.json", or a stringified JSON object.
     * @custom:documentation https://docs.opensea.io/docs/contract-level-metadata
     */
    string internal _contractURI;

    /// @dev Maximum supply of tokens that can be minted.
    uint64 public maxSupply;

    /// @dev Total supply of tokens minted.
    uint64 internal _totalSupply;

    /// @dev Total supply of tokens reserved for the custom lists.
    uint64 internal _reservedSupply;

    /// @dev Price of minting a single token.
    uint80 public price;

    /// @dev current count of custom mint lists
    uint8 public lists;

    /**
     * @notice Percentage of the mint value that is paid to the referrer.
     * @dev Referral fee value in BPS.
     */
    uint16 public referralFee;

    /// @dev indicates that the metadata for the entire collection is frozen and cannot be updated anymore
    bool public permanentURI;

    /// @notice indicates that the minting process is open
    bool public mintOpen;

    /// @notice timestamp for the start of the minting process
    uint32 public start;

    /// @notice timestamp for the end of the minting process
    uint32 public end;

    uint64 public unit;

    uint64 public perUserSupply;

    /// @dev Mapping of token IDs to their respective tokenURIs, optional override.
    mapping(uint256 tokenId => string uri) private _tokenURIs;

    /// @dev Mapping of token IDs to their respective permanentURI state.
    mapping(uint256 tokenId => bool isPermanent) private _permanentTokenURIs;

    /// @dev Mapping of listId to MintList data.
    mapping(uint8 listId => MintList list) public mintLists;

    /// @dev Mapping of listId to minted list supply.
    mapping(uint8 listId => uint64 supply) public listSupply;

    /// @dev Mapping of user to listId to already claimed amount.
    mapping(address user => mapping(uint8 listId => uint256 claimed)) public claimedList;

    // >>>>>>>>>>>> [ MODIFIERS ] <<<<<<<<<<<<

    /**
     * @dev Checks if amount does not exceed maxSupply.
     * @param amount_ The amount to be minted.
     */
    modifier mintable(uint256 amount_) {
        if (!mintOpen) revert MintClosed();
        uint256 mulAmount = amount_ * unit;

        if (_totalSupply + mulAmount > maxSupply) revert MintCap();
        if (claimedList[msg.sender][0] + mulAmount > perUserSupply) revert ExcessiveClaim();
        if (mulAmount > maxSupply - _totalSupply - _reservedSupply) revert BreaksReservedSupply();

        if (start != 0 && block.timestamp < start) revert MintClosed();
        if (end != 0 && block.timestamp > end) revert MintClosed();
        _;
    }

    /**
     * @dev Checks if the mint does not exceed the maxSupply of its MintList.
     * @param listId_ The ID of the custom mint list.
     * @param amount_ The amount to be minted.
     */
    modifier listMintable(uint8 listId_, uint256 amount_) {
        MintList memory list = mintLists[listId_];
        if (list.paused) revert ListPaused();
        uint256 mulAmount = amount_ * list.unit;
        if (claimedList[msg.sender][listId_] + mulAmount > list.userSupply) revert ExcessiveClaim();

        if (_totalSupply + mulAmount > maxSupply) revert MintCap();
        if (listSupply[listId_] + mulAmount > list.maxSupply) revert MintCap();

        if (!list.reserved && mulAmount > maxSupply - _totalSupply - _reservedSupply) revert BreaksReservedSupply();

        if (list.start != 0 && block.timestamp < list.start) revert MintClosed();
        if (list.end != 0 && block.timestamp > list.end) revert MintClosed();
        _;
    }

    // >>>>>>>>>>>> [ CONSTRUCTION / INITIALIZATION ] <<<<<<<<<<<<

    /// @dev Constructor is kept empty in order to make the template compatible with ERC-1167 proxy factories
    constructor() payable {}

    /**
     * @dev Initializes the contract with the given basic parameters.
     * should be called immediately after deployment, ideally by factory
     * @param name_ The name of the collection. e.g. "Milady Maker"
     * @param symbol_ The symbol of the collection. e.g. "MILADY"
     * @param maxSupply_ The maximum supply of tokens that can be minted. (~1.099T max)
     * @param royalty_ The percentage of the mint value that is paid to the referrer. (420 == 420 / 10000 == 4.20%)
     * @param owner_ The owner of the collection contract.
     * @param price_ The price of minting a single token. (~1.2M ETH max)
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint64 maxSupply_,
        uint16 royalty_,
        address owner_,
        uint80 price_
    ) external payable virtual initializer {
        _initialize(name_, symbol_, maxSupply_, royalty_, owner_, price_);
    }

    /**
     * @dev Internal function to initialize the contract with the given parameters.
     * allows contracts that inherit ERC721Core to call this function in their own initializers
     * @param name_ The name of the collection. e.g. "Milady Maker"
     * @param symbol_ The symbol of the collection. e.g. "MILADY"
     * @param maxSupply_ The maximum supply of tokens that can be minted. (~1.099T max)
     * @param royalty_ The percentage of the mint value that is paid to the referrer.
     * e.g. (420 == 420 / 10000 == 4.20%) Max 10.00%
     * @param owner_ The owner of the collection contract.
     * @param price_ The price of minting a single token. (~1.2M ETH max)
     */
    function _initialize(
        string memory name_, // Collection name ("Milady")
        string memory symbol_, // Collection symbol ("MIL")
        uint64 maxSupply_, // Max supply (~1.099T max)
        uint16 royalty_, // Percentage in basis points (420 == 4.20%)
        address owner_, // Collection contract owner
        uint80 price_ // Price (~1.2M ETH max)
    ) internal virtual onlyInitializing {
        if (royalty_ > _MAX_ROYALTY_BPS) revert Invalid();
        _setTokenRoyalty(0, owner_, royalty_);
        _setDefaultRoyalty(owner_, royalty_);
        // Initialize ownership
        _initializeOwner(owner_);
        // Set all values
        _name = name_;
        _symbol = symbol_;
        maxSupply = maxSupply_;
        price = price_;

        unit = 1;
        start = 0;
        end = 0;
        perUserSupply = maxSupply;

        emit ContractCreated(name_, symbol_);
        emit RoyaltyUpdate(0, owner_, royalty_);
        emit SupplyUpdate(maxSupply_);
        emit PriceUpdate(price_);
    }

    // >>>>>>>>>>>> [ VIEW / METADATA FUNCTIONS ] <<<<<<<<<<<<

    /**
     * @notice Returns the name of the collection.
     * @return name a string representing the name of the collection.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @notice Returns the symbol of the collection.
     * @return symbol a string representing the symbol of the collection.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Returns the base URI for the collection tokenURIs.
     * @return baseURI a string representing the base URI.
     */
    function baseURI() public view virtual returns (string memory) {
        return _baseURI;
    }

    /**
     * @notice Returns the contract metadata URI for the collection.
     * @return contractURI a string representing the contract metadata URI or a stringified JSON object.
     */
    function contractURI() public view virtual returns (string memory) {
        return _contractURI;
    }

    /**
     * @notice Returns the URI for the given token ID.
     * @dev if the token has a non-empty, manually set URI, it will be returned as is,
     * otherwise it will return the concatenation of the baseURI, the token ID and, optionally,  the file extension.
     * @return tokenURI a string representing the token URI.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        string memory _tokenURI = _tokenURIs[tokenId];

        if (bytes(_tokenURI).length > 0) {
            return _tokenURI;
        }

        string memory newBaseURI = baseURI();

        return
            bytes(newBaseURI).length > 0
                ? string(abi.encodePacked(newBaseURI, tokenId.toString(), _fileExtension))
                : "";
    }

    /**
     * @notice Returns the total supply of tokens minted.
     * @return totalSupply a positive integer representing the total supply of tokens already minted.
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Override to add ERC4906 and royalty interface.
     * ERC721, ERC721Metadata, and ERC721x are present in the ERC721x override
     * @param interfaceId The ID of the standard interface you want to check for.
     * @return supported bool representing whether the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721x, ERC2981) returns (bool) {
        return
            interfaceId == ERC4906_INTERFACE_ID ||
            ERC721x.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    /**
     * @dev list of blacklisted assets, used to prevent mints to and from holders of prohibited assets
     * @return blacklist an array of blacklisted asset addresses.
     */
    function getBlacklist() public view virtual returns (address[] memory) {
        return _blacklist.values();
    }

    // >>>>>>>>>>>> [ INTERNAL FUNCTIONS ] <<<<<<<<<<<<

    /**
     * @dev Blacklist function to prevent mints to and from holders of prohibited assets,
     * applied both on minter and recipient
     * @param minter The address of the minter.
     * @param recipient The address of the recipient.
     */
    function _enforceBlacklist(address minter, address recipient) internal virtual {
        address[] memory blacklist = _blacklist.values();
        uint256 count;
        for (uint256 i = 1; i < blacklist.length; ) {
            unchecked {
                count += IAsset(blacklist[i]).balanceOf(minter);
                count += IAsset(blacklist[i]).balanceOf(recipient);
                if (count > 0) revert Blacklisted();
                ++i;
            }
        }
    }

    // >>>>>>>>>>>> [ MINT LOGIC ] <<<<<<<<<<<<

    /**
     * @notice Internal mint function that supports batch minting.
     * @dev Implements referral fee and blacklist logic.
     * @param recipient_ The address of the recipient.
     * @param amount_ The amount_ of tokens to mint.
     * @param referral_ The address of the referrer.
     */
    function _mint(address recipient_, uint256 amount_, address referral_) internal virtual {
        //@TODO if recipient is not msg.sender consider emitting another event

        _handleReferral(referral_);

        uint256 mulAmount = amount_ * unit;

        unchecked {
            claimedList[msg.sender][0] += mulAmount;
        }

        // Process ERC721 mints
        _mint(mulAmount, recipient_);
    }

    function _mint(uint256 amount_, address recipient_) internal virtual {
        // inverted parameter order to avoid overriding mint(address, uint256)

        // Prevent bad inputs
        if (recipient_ == address(0) || amount_ == 0) revert Invalid();
        // Ensure minter and recipient don't hold blacklisted assets
        _enforceBlacklist(msg.sender, recipient_);

        uint256 supply = _totalSupply;
        for (uint256 i; i < amount_; ) {
            _mint(recipient_, ++supply);
            unchecked {
                ++i;
            }
        }
        unchecked {
            _totalSupply += uint64(amount_);
        }
    }

    /**
     * @notice Mint a single token to the sender.
     * @dev Standard single-unit mint to msg.sender (implemented for max scannner compatibility)
     */
    function mint() public payable virtual mintable(1) {
        if (msg.value < price) revert InsufficientPayment();
        _mint(msg.sender, 1, address(0));
    }

    /**
     * @notice Mint the amount of tokens to the sender, provided that enough ether is sent.
     * @dev Standard multi-unit mint to msg.sender (implemented for max scanner compatibility)
     * @param amount The amount of tokens to mint.
     */
    function mint(uint256 amount) public payable virtual mintable(amount) {
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(msg.sender, amount, address(0));
    }

    /**
     * @notice Mint the amount of tokens to the recipient, provided that enough ether is sent.
     * @dev Standard mint function with recipient that supports batch minting
     * @param recipient The address of the recipient.
     * @param amount The amount of tokens to mint.
     */
    function mint(address recipient, uint256 amount) public payable virtual mintable(amount) {
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, address(0));
    }

    /**
     * @notice Mint the amount of tokens to the recipient, provided that enough ether is sent
     * Sends a percentage of the mint value to the referrer.
     * @dev Standard batch mint with referral fee support
     * @param recipient_ The address of the recipient.
     * @param amount_ The amount of tokens to mint.
     * @param referral_ The address of the referrer.
     */
    function mint(
        address recipient_,
        uint256 amount_,
        address referral_
    ) public payable virtual mintable(amount_) nonReentrant {
        if (referral_ == msg.sender || referral_ == recipient_) revert SelfReferralNotAllowed();
        if (msg.value < (price * amount_)) revert InsufficientPayment();
        _mint(recipient_, amount_, referral_);
    }

    /**
     * @notice Mint the amount of tokens to the recipient, provided that enough ether is sent
     * Sends a percentage of the mint value to the referrer.
     * @dev Standard batch mint with referral fee support
     * @param proof_ The address of the recipient.
     * @param listId_ The address of the recipient.
     * @param recipient_ The address of the recipient.
     * @param amount_ The amount of tokens to mint.
     * @param referral_ The address of the referrer.
     */
    function mint(
        bytes32[] calldata proof_,
        uint8 listId_,
        address recipient_,
        uint64 amount_,
        address referral_
    ) public payable virtual listMintable(listId_, amount_) nonReentrant {
        if (referral_ == msg.sender || referral_ == recipient_) revert SelfReferralNotAllowed();

        MintList memory list = mintLists[listId_];
        if (msg.value < amount_ * list.price) revert InsufficientPayment();

        //@TODO maybe give the choice of basing the proof verification on the sender or the recipient?
        bytes32 leaf = keccak256(bytes.concat(keccak256(bytes.concat(abi.encode(msg.sender)))));
        if (!MerkleProofLib.verifyCalldata(proof_, list.root, leaf)) revert NotAllowedToClaim();

        _handleReferral(referral_);

        uint64 mulAmount = amount_ * list.unit;

        unchecked {
            claimedList[msg.sender][listId_] += mulAmount;
            listSupply[listId_] += mulAmount;
        }

        _mint(mulAmount, recipient_);
        emit ListMinted(msg.sender, listId_, mulAmount);
    }

    function _handleReferral(address referral_) internal virtual {
        if (msg.value > 0 && referral_ != address(0)) {
            // If referral isn't address(0) and mint isn't free, process sending referral fee
            // Reentrancy is handled by applying ReentrancyGuard to referral mint function
            // [mint(address, uint256, address)]
            //@TODO stash and then withdraw might be better for gas?
            //@TODO referral discounts?
            uint256 referralAlloc = FPML.mulDivUp(referralFee, msg.value, _DENOMINATOR_BPS);
            (bool success, ) = payable(referral_).call{ value: referralAlloc }("");
            if (!success) revert TransferFailed();
            emit ReferralFeePaid(referral_, referralAlloc);
        }
    }

    // >>>>>>>>>>>> [ PERMISSIONED / OWNER FUNCTIONS ] <<<<<<<<<<<<

    // >>>> [ ROYALTY FUNCTIONS ] <<<<

    /**
     * @dev Sets the default royalty receiver and fee for the contract.
     * @param recipient The address of the recipient.
     * @param royaltyFee The royalty fee, represented as a 96-bit fixed-point number.
     */
    function setRoyalties(address recipient, uint96 royaltyFee) external virtual onlyOwner {
        if (royaltyFee > _MAX_ROYALTY_BPS) revert Invalid();
        // Revert if royalties are disabled
        (address receiver, ) = royaltyInfo(0, 0);
        if (receiver == address(0)) revert RoyaltiesDisabled();

        // Royalty recipient of nonexistent tokenId 0 is used as royalty status indicator, address(0) == disabled
        _setTokenRoyalty(0, recipient, royaltyFee);
        _setDefaultRoyalty(recipient, royaltyFee);
        emit RoyaltyUpdate(0, recipient, royaltyFee);
    }

    /**
     * @dev Sets the royalty receiver and fee for a specific token ID.
     * @param tokenId The ID of the token.
     * @param recipient The address of the recipient.
     * @param royaltyFee The royalty fee, represented as a 96-bit fixed-point number.
     */
    function setRoyaltiesForId(uint256 tokenId, address recipient, uint96 royaltyFee) external virtual onlyOwner {
        if (royaltyFee > _MAX_ROYALTY_BPS) revert Invalid();
        // Revert if royalties are disabled
        (address receiver, ) = royaltyInfo(0, 0);
        if (receiver == address(0)) revert RoyaltiesDisabled();
        // Revert if resetting tokenId 0 as it is utilized for royalty enablement status
        if (tokenId == 0) revert Invalid();

        // Reset token royalty if fee is 0, else set it
        if (royaltyFee == 0) _resetTokenRoyalty(tokenId);
        else _setTokenRoyalty(tokenId, recipient, royaltyFee);
        emit RoyaltyUpdate(tokenId, recipient, royaltyFee);
    }

    /**
     * @notice Disables royalties for the contract.
     * @dev Irreversibly disable royalties by resetting tokenId 0 royalty to (address(0), 0)
     * and deleting default royalty info
     */
    function disableRoyalties() external virtual onlyOwner {
        _deleteDefaultRoyalty();
        _resetTokenRoyalty(0);
        emit RoyaltyDisabled();
    }

    // >>>> [ CUSTOM MINT FUNCTIONS ] <<<<

    // Set arbitrary custom mint lists using merkle trees, can be reconfigured
    // NOTE: Cannot retroactively reduce mintable amount below minted supply for custom mint list

    /**
     * @notice Configures a custom mint list with a merkle root, mintable amount, and price.
     * @dev If list already exists, adjusts the configuration to the new values.
     * @param listId_ The ID of the custom mint list.
     * @param list_ The list configuration as a struct.
     */
    function setMintList(
        uint8 listId_,
        MintList calldata list_
    ) external virtual onlyOwner validateMintList(listId_, list_) {
        if (listId_ > lists) revert ListDoesNotExist();

        uint8 id = listId_ == 0 ? lists++ : listId_; // If listId_ is 0, increment listCount and create new list

        MintList memory list = mintLists[listId_];
        if (listId_ != 0 && list.userSupply == 0) revert ListDeleted();
        updateReservedSupply(listId_, list.reserved, list_.reserved, list.maxSupply, list_.maxSupply);

        mintLists[listId_] = list_;
        emit MintListUpdate(id, list_);
    }

    modifier validateMintList(uint8 listId_, MintList calldata list_) {
        if (list_.maxSupply == 0 || list_.userSupply == 0 || list_.unit == 0) revert Invalid();
        if (list_.maxSupply < listSupply[listId_]) revert Invalid();
        if (list_.end != 0 && list_.end < list_.start) revert Invalid(); // Consider using more specific errors
        _;
    }

    function updateReservedSupply(
        uint8 listId_,
        bool currentReserved_,
        bool newReserved_,
        uint64 currentMaxSupply_,
        uint64 newMaxSupply_
    ) internal {
        if (newReserved_) {
            if (newMaxSupply_ > currentMaxSupply_) {
                _reservedSupply += newMaxSupply_ - currentMaxSupply_;
                if (_reservedSupply > maxSupply) revert ReservedExceedsMaxSupply();
            } else {
                _reservedSupply -= currentMaxSupply_ - newMaxSupply_;
            }
        } else if (currentReserved_) {
            uint64 alreadyMinted = listSupply[listId_];
            _reservedSupply -= currentMaxSupply_ - alreadyMinted;
        }
    }

    /**
     * @notice Pauses or unpauses a custom mint list.
     * @dev Reduces claimable supply for custom list to 0 thus disabling it.
     * @param listId_ The ID of the custom mint list.
     */
    function toggleMintList(uint8 listId_) external virtual onlyOwner {
        if (listId_ == 0 || listId_ > lists) revert ListDoesNotExist();
        MintList storage listData = mintLists[listId_];
        if (listData.userSupply == 0) revert ListDeleted();
        listData.paused = !listData.paused;
        emit MintListUpdate(listId_, listData);
    }

    /**
     * @notice Deletes a custom mint list.
     * @param listId_ The ID of the custom mint list.
     */
    function deleteMintList(uint8 listId_) external virtual onlyOwner {
        if (listId_ == 0 || listId_ > lists) revert ListDoesNotExist();
        MintList storage listData = mintLists[listId_];
        if (listData.userSupply == 0) revert ListDeleted();
        listData.userSupply = 0;
        emit MintListDeleted(listId_);
    }

    // >>>> [ SETTER FUNCTIONS ] <<<<

    /**
     * @notice Opens the minting process.
     */
    function setMintOpen(bool open_) external virtual onlyOwner {
        mintOpen = open_;
        emit MintOpen(open_);
    }

    function setMintRange(uint32 start_, uint32 end_) external virtual onlyOwner {
        if (start_ > end_) revert Invalid();
        if (start == 0 && start != start_) mintOpen = true; // Open minting if it wasn't already
        start = start_;
        end = end_;
        emit MintRangeUpdate(start_, end_);
    }

    function setClaimableUserSupply(uint64 claimable_) external virtual onlyOwner {
        if (claimable_ == 0) revert Invalid();
        perUserSupply = claimable_;
        emit UserClaimableUpdate(claimable_);
    }

    function setUnit(uint64 unit_) external virtual onlyOwner {
        if (unit_ == 0) revert Invalid();
        unit = unit_;
        emit UnitUpdate(unit_);
    }

    // @TODO: shouldn't blacklisted also be enforced on transfer?

    /**
     * @notice Adds or removes assets to the blacklist.
     * @param blacklistedAssets The list of addresses to be blacklisted.
     * @param status The status to which they have been updated.
     */
    function setBlacklist(address[] memory blacklistedAssets, bool status) external virtual onlyOwner {
        for (uint256 i; i < blacklistedAssets.length; ++i) {
            if (status) _blacklist.add(blacklistedAssets[i]);
            else _blacklist.remove(blacklistedAssets[i]);
        }
        emit BlacklistUpdate(blacklistedAssets, status);
    }

    /**
     * @notice Sets the price for minting a single token.
     * @param newPrice The new price.
     */
    function setPrice(uint80 newPrice) external virtual onlyOwner {
        price = newPrice;
        emit PriceUpdate(newPrice);
    }

    /**
     * @notice Sets the maximum supply of tokens that can be minted.
     * @param newMaxSupply The new maximum supply.
     * If newMaxSupply is less than the current supply, the function will revert.
     * If minting has already started and newMaxSupply is greater than current maxSupply, the function will revert.
     */
    function setSupply(uint64 newMaxSupply) external virtual onlyOwner {
        if ((newMaxSupply > maxSupply && _totalSupply != 0) || newMaxSupply <= _totalSupply + _reservedSupply) {
            revert Invalid();
        }
        maxSupply = newMaxSupply;
        emit SupplyUpdate(newMaxSupply);
    }

    /**
     * @notice Sets the referral fee for minting.
     * @dev The referral fee is a percentage of the mint value that is paid to the referrer.
     * @param newReferralFee The new referral fee, must be < (_DENOMINATOR_BPS - allocation).
     */
    function setReferralFee(uint16 newReferralFee) external virtual onlyOwner {
        if (newReferralFee > _DENOMINATOR_BPS) revert Invalid();
        referralFee = newReferralFee;
        emit ReferralFeeUpdate(newReferralFee);
    }

    /**
     * @notice Sets the base URI for the collection tokenURIs.
     * @param newBaseURI The new base URI.
     * @param fileExtension The file extension for the collection tokenURIs. e.g. ".json"
     */
    function setBaseURI(string memory newBaseURI, string memory fileExtension) public virtual onlyOwner {
        if (permanentURI) revert IsPermanentURI();
        _baseURI = newBaseURI;
        _fileExtension = fileExtension;
        emit BatchMetadataUpdate(0, maxSupply);
    }

    /**
     * @notice Sets the token URI for a specific token.
     * @param tokenId The ID of the token.
     * @param _tokenURI The new token URI.
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI) external virtual onlyOwner {
        if (permanentURI || _permanentTokenURIs[tokenId]) revert IsPermanentURI();
        _tokenURIs[tokenId] = _tokenURI;
        emit MetadataUpdate(tokenId);
    }

    /**
     * @notice Sets the contract metadata URI.
     * @dev This URI is used to store contract-level metadata.
     * @param newContractURI The new contract metadata URI.
     */
    function setContractURI(string memory newContractURI) external virtual onlyOwner {
        _contractURI = newContractURI;
        emit ContractMetadataUpdate(newContractURI);
    }

    /**
     * @notice Freezes the metadata for the entire collection.
     * @dev Once the metadata is frozen, it cannot be updated anymore.
     */
    function freezeURI() external virtual onlyOwner {
        permanentURI = true;
        emit BatchPermanentURI(0, maxSupply);
    }

    /**
     * @notice Freezes the metadata for a specific token.
     * @param tokenId The ID of the token.
     */
    function freezeTokenURI(uint256 tokenId) external virtual onlyOwner {
        if (permanentURI) revert IsPermanentURI();
        string memory staticURI = tokenURI(tokenId);
        _tokenURIs[tokenId] = staticURI;
        _permanentTokenURIs[tokenId] = true;

        emit PermanentURI(staticURI, tokenId);
    }

    /**
     * @notice Withdraws funds from the contract.
     * @param recipient The address to which the funds are withdrawn.
     * @param amount The amount of funds withdrawn.
     */
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
        (bool success, ) = payable(recipient).call{ value: amount }("");
        if (!success) revert TransferFailed();
        emit Withdraw(recipient, amount);
    }

    // >>>>>>>>>>>> [ ASSET HANDLING ] <<<<<<<<<<<<

    /**
     * @dev Internal handling of ether acquired through received().
     */
    function _processPayment() internal virtual {
        if (mintOpen) {
            mint(msg.sender, (msg.value / price));
        } else {
            //@TODO handle address(0)?
            (bool success, ) = payable(owner()).call{ value: msg.value }("");
            if (!success) revert Invalid();
        }
    }

    /**
     * @dev function to retrieve erc20 from the contract
     * @param addr The address of the ERC20 token.
     * @param recipient The address to which the tokens are transferred.
     */
    function rescueERC20(address addr, address recipient) external virtual onlyOwner {
        uint256 balance = IERC20(addr).balanceOf(address(this));
        IERC20(addr).transfer(recipient, balance);
    }

    /**
     * @notice Rescue ERC721 tokens from the contract.
     * @param addr The address of the ERC721 in question.
     * @param recipient The address to which the token is transferred.
     * @param tokenId The ID of the token to be transferred.
     */
    function rescueERC721(address addr, address recipient, uint256 tokenId) external virtual onlyOwner {
        IERC721(addr).transferFrom(address(this), recipient, tokenId);
    }

    /**
     * @dev Fallback function to accept ether.
     */
    receive() external payable virtual {
        _processPayment();
    }
}
