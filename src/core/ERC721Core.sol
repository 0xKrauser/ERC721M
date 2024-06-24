// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

// >>>>>>>>>>>> [ IMPORTS ] <<<<<<<<<<<<

import { Core } from "./Core.sol";
import { CoreBlacklist } from "./blacklist/CoreBlacklist.sol";
import { MintList, CoreList } from "./lists/CoreList.sol";
import { CoreLockable } from "./lockable/CoreLockable.sol";
import { CoreMetadata721, ICoreMetadata } from "./metadata/CoreMetadata721.sol";
import { CoreReferral } from "./referral/CoreReferral.sol";
import { CoreRoyalty } from "./royalty/CoreRoyalty.sol";

import { NotZero } from "./ICore.sol";

import { Initializable } from "../../lib/solady/src/utils/Initializable.sol";

import { FixedPointMathLib as FPML } from "../../lib/solady/src/utils/FixedPointMathLib.sol";

// import {console2} from "../../lib/forge-std/src/Console2.sol";

/**
 * @title ERC721Core
 * @author Zodomo.eth (Farcaster/Telegram/Discord/Github: @zodomo, X: @0xZodomo, Email: zodomo@proton.me)
 * @author 0xKrauser (Discord/Github/X: @0xKrauser, Email: detroitmetalcrypto@gmail.com)
 * @notice NFT template that contains launchpad friendly features to be inherited by other contracts
 * @custom:github https://github.com/Zodomo/ERC721M
 */

// REMEMBER TO ADD BACK ERC721x capabilities
contract ERC721Core is Core, CoreBlacklist, CoreList, CoreMetadata721, CoreReferral, CoreRoyalty, Initializable {
    function _canMint(uint256 amount_) internal view override returns (uint256 tokenAmount_) {
        tokenAmount_ = Core._canMint(amount_);
        _requireUnreservedSupply(tokenAmount_, _totalSupply, maxSupply);
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
        uint32 maxSupply_,
        uint16 royalty_,
        address owner_,
        uint256 price_
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
        uint32 maxSupply_, // Max supply (~1.099T max)
        uint16 royalty_, // Percentage in basis points (420 == 4.20%)
        address owner_, // Collection contract owner
        uint256 price_ // Price (~1.2M ETH max)
    ) internal virtual onlyInitializing {
        _initializeOwner(owner_);
        _setRoyalties(owner_, royalty_);

        _name = name_;
        _symbol = symbol_;

        price = price_;
        maxSupply = maxSupply_;
        userSupply = maxSupply_;

        unit = 1;
        start = 0;
        end = 0;

        emit ContractCreated(name_, symbol_);
        emit SupplyUpdate(maxSupply_);
        emit PriceUpdate(price_);
    }

    // >>>>>>>>>>>> [ VIEW / METADATA FUNCTIONS ] <<<<<<<<<<<<

    /// @inheritdoc CoreMetadata721
    function tokenURI(
        uint256 tokenId_
    ) public view virtual override(CoreMetadata721) returns (string memory tokenURI_) {
        if (_exists(tokenId_)) return _tokenURI(tokenId_);
        revert TokenDoesNotExist();
    }

    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(CoreRoyalty, CoreMetadata721) returns (bool supported_) {
        return CoreRoyalty.supportsInterface(interfaceId_) || CoreMetadata721.supportsInterface(interfaceId_);
    }

    // >>>>>>>>>>>> [ INTERNAL FUNCTIONS ] <<<<<<<<<<<<

    /**
     * @notice Internal mint function that supports batch minting.
     * @dev Implements blacklist logic.
     * @param recipient_ The address of the recipient.
     * @param amount_ The amount of tokens to mint.
     */
    function _mint(address recipient_, uint32 amount_) internal virtual {
        //@TODO if recipient is not msg.sender consider emitting another event
        // Prevent bad inputs
        if (recipient_ == address(0) || amount_ == 0) revert NotZero();

        // Ensure minter and recipient don't hold blacklisted assets
        _enforceBlacklist(recipient_);

        unchecked {
            uint256 supply = _totalSupply;
            for (uint256 i; i < amount_; ) {
                super._mint(recipient_, ++supply);
                ++i;
            }
            _totalSupply += amount_;
        }
    }

    /**
     * @notice Internal mint function for mints that do not require list logic.
     * @dev Implements referral logic.
     * @param recipient_ The address of the recipient.
     * @param amount_ The amount_ of tokens to mint.
     * @param referral_ The address of the referrer.
     */
    function _handleMint(address recipient_, uint256 amount_, address referral_) internal virtual {
        uint256 tokenAmount = _canMint(amount_);

        _handleReferral(referral_, recipient_);

        unchecked {
            _claimed[msg.sender] += tokenAmount;
        }

        // Process ERC721 mints
        _mint(recipient_, tokenAmount);
    }

    /**
     * @notice Internal mint function for mints that do not require list logic.
     * @dev Implements referral fee logic.
     * @param recipient_ The address of the recipient.
     * @param amount_ The amount_ of tokens to mint.
     * @param referral_ The address of the referrer.
     */
    function _handleMintWithList(
        bytes32[] calldata proof_,
        uint8 listId_,
        address recipient_,
        uint32 amount_,
        address referral_
    ) internal virtual {
        _handleReferral(referral_, recipient_);

        (uint256 tokenAmount, uint256 cost, bool reserved) = _canMintList(proof_, listId_, amount_);

        if (msg.value < cost) revert InsufficientPayment();

        if (_totalSupply + tokenAmount > maxSupply) revert MaxSupply();

        if (!reserved) _requireUnreservedSupply(tokenAmount, _totalSupply, maxSupply);

        _mint(recipient_, tokenAmount);
        emit ListMinted(msg.sender, listId_, tokenAmount);
    }

    /**
     * @notice Mint a single token to the sender.
     * @dev Standard single-unit mint to msg.sender (implemented for max scannner compatibility)
     */
    function mint() public payable virtual {
        _handleMint(msg.sender, 1, address(0));
    }

    /**
     * @notice Mint the amount of tokens to the sender, provided that enough ether is sent.
     * @dev Standard multi-unit mint to msg.sender (implemented for max scanner compatibility)
     * @param amount_ The amount of tokens to mint.
     */
    function mint(uint256 amount_) public payable virtual {
        _handleMint(msg.sender, amount_, address(0));
    }

    /**
     * @notice Mint the amount of tokens to the recipient, provided that enough ether is sent.
     * @dev Standard mint function with recipient that supports batch minting
     * @param recipient_ The address of the recipient.
     * @param amount_ The amount of tokens to mint.
     */
    function mint(address recipient_, uint256 amount_) public payable virtual {
        _handleMint(recipient_, amount_, address(0));
    }

    /**
     * @notice Mint the amount of tokens to the recipient, provided that enough ether is sent
     * Sends a percentage of the mint value to the referrer.
     * @dev Standard batch mint with referral fee support
     * @param recipient_ The address of the recipient.
     * @param amount_ The amount of tokens to mint.
     * @param referral_ The address of the referrer.
     */
    function mint(address recipient_, uint256 amount_, address referral_) public payable virtual nonReentrant {
        _handleMint(recipient_, amount_, referral_);
    }

    /**
     * @notice Mint the amount of tokens to the recipient, provided that enough ether is sent
     * @dev Batch mint with referral fee support and list merkle proof support.
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
        uint32 amount_,
        address referral_
    ) public payable virtual nonReentrant {
        _handleMintWithList(proof_, listId_, recipient_, amount_, referral_);
    }

    // >>>>>>>>>>>> [ PERMISSIONED / OWNER FUNCTIONS ] <<<<<<<<<<<<

    /// @dev Override to account for the lists reserved supply.
    /// @inheritdoc Core
    function setSupply(uint32 maxSupply_) external virtual override onlyOwner {
        if (maxSupply_ < _totalSupply + _reservedSupply) revert UnderSupply();
        _setMaxSupply(maxSupply_);
    }

    // >>>>>>>>>>>> [ Metadata ] <<<<<<<<<<<<

    function setContractURI(string memory contractURI_) external virtual onlyOwner {
        _setContractURI(contractURI_);
    }

    function setBaseURI(string memory baseURI_, string memory fileExtension_) external virtual onlyOwner {
        _setBaseURI(baseURI_, fileExtension_, maxSupply);
    }

    function setTokenURI(uint256 tokenId_, string memory tokenURI_) external virtual onlyOwner {
        _setTokenURI(tokenId_, tokenURI_);
    }

    function freezeURI() external virtual onlyOwner {
        _freezeURI(maxSupply);
    }

    function freezeTokenURI(uint256 tokenId_) external virtual onlyOwner {
        _freezeTokenURI(tokenId_);
    }

    // >>>>>>>>>>>> [ Lists ] <<<<<<<<<<<<

    function setList(
        uint256 price_,
        uint8 listId_,
        bytes32 root_,
        uint32 userSupply_,
        uint32 maxSupply_,
        uint32 start_,
        uint32 end_,
        uint32 unit_,
        bool reserved_,
        bool paused_
    ) external virtual onlyOwner {
        _setList(listId_, root_, price_, userSupply_, maxSupply_, start_, end_, unit_, reserved_, paused_, maxSupply);
    }

    function pauseList(uint8 listId_) external virtual onlyOwner {
        _pauseList(listId_, true);
    }

    function unpauseList(uint8 listId_) external virtual onlyOwner {
        _pauseList(listId_, false);
    }

    function deleteList(uint8 listId_) external virtual onlyOwner {
        _deleteList(listId_);
    }

    // >>>>>>>>>>>> [ Royalty ] <<<<<<<<<<<<

    function setRoyalties(address recipient_, uint96 bps_) external virtual onlyOwner {
        _requireRoyaltiesEnabled();
        _setRoyalties(recipient_, bps_);
    }

    function setTokenRoyalties(uint256 tokenId_, address recipient_, uint96 bps_) external virtual onlyOwner {
        _requireRoyaltiesEnabled();
        _setTokenRoyalties(tokenId_, recipient_, bps_);
    }

    function disableRoyalties() external virtual onlyOwner {
        _disableRoyalties();
    }

    // >>>>>>>>>>>> [ Blacklist ] <<<<<<<<<<<<

    function setBlacklist(address[] calldata assets_, bool status_) external virtual onlyOwner {
        _setBlacklist(assets_, status_);
    }

    // >>>>>>>>>>>> [ Referral ] <<<<<<<<<<<<

    function setReferralFee(uint16 bps_) external virtual onlyOwner {
        _setReferralFee(bps_);
    }

    // >>>>>>>>>>>> [ ASSET HANDLING ] <<<<<<<<<<<<

    /// @inheritdoc Core
    function _processPayment() internal virtual override {
        if (!paused()) {
            mint(msg.sender, (msg.value / price));
        } else {
            _processPayment();
        }
    }
}