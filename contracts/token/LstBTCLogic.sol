// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./interfaces/ILstBTC.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title LstBTCLogic
 * @dev Main lstBTC token contract implementing ERC20 with role-based access control
 *
 * This contract manages the lstBTC token with features including:
 * - Minting and burning by authorized addresses (minters, burners)
 * - Role-based access control for different operations
 * - Blacklisting functionality for security and compliance
 * - Upgradeable design using UUPS pattern
 * - Integration with bridge contract for cross-chain operations
 *
 * The contract follows OpenZeppelin patterns and integrates with the lstBTC
 * bridge protocol for Bitcoin cross-chain functionality.
 */
contract LstBTCLogic is ILstBTC, ERC20Upgradeable,
    Ownable2StepUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    modifier onlyBlackLister() {
        require(isBlackLister(_msgSender()), "LstBTC: only blacklisters");
        _;
    }

    modifier notBlackListed(address _account) {
        require(!isBlackListed(_account), "LstBTC: blacklisted");
        _;
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "LstBTC: only minters can mint");
        _;
    }

    modifier onlyBurner() {
        require(isBurner(_msgSender()), "LstBTC: only burners can burn");
        _;
    }

    modifier nonZeroValue(uint _value) {
        require(_value > 0, "LstBTC: value is zero");
        _;
    }

    // Mapping of address to minter role status
    mapping(address => bool) public minters;

    // Mapping of address to burner role status
    mapping(address => bool) public burners;

    // Mapping of address to blacklister role status
    mapping(address => bool) public blacklisters;

    // Mapping of address to blacklisted status
    mapping(address => bool) internal blacklisted;

    // Address of the bridge contract
    address public override bridge;

    // Maximum amount of tokens that can be minted
    uint public override maxMintLimit;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the lstBTC token contract
    /// @dev Sets up the ERC20 token with name and symbol, initializes all upgradeable contracts,
    ///      and sets the maximum mint limit. Can only be called once during deployment.
    /// @param _name Token name (e.g., "Liquid Staked Bitcoin")
    /// @param _symbol Token symbol (e.g., "lstBTC")
    function initialize(
        string memory _name,
        string memory _symbol
    ) public initializer {
        ERC20Upgradeable.__ERC20_init(
            _name,
            _symbol
        );
        Ownable2StepUpgradeable.__Ownable2Step_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        UUPSUpgradeable.__UUPSUpgradeable_init();

        maxMintLimit = 10 ** 8;
    }

    /// @notice Disabled ownership renouncement for security
    /// @dev Overrides the default renounceOwnership function to prevent accidental
    ///      loss of control over the token contract
    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice Authorizes contract upgrades
    /// @dev Only owner can upgrade the contract implementation using UUPS pattern
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice	Returns the number of decimals used for token amounts
    /// @return	Number of decimals (8 for lstBTC)
    function decimals() public view virtual override(ERC20Upgradeable, ILstBTC) returns (uint8) {
        return 8;
    }

    /// @notice	Updates the bridge contract address
    /// @dev	Only owner can call this function
    /// @param	_bridge	New bridge contract address
    function setBridge(address _bridge) external override onlyOwner {
        require(_bridge != address(0), "LstBTC: zero address");

        if (_bridge != bridge) {
            emit NewBridge(bridge, _bridge);
            bridge = _bridge;
        }
    }

    /// @notice	Changes the maximum mint limit per epoch
    /// @dev	Only owner can call this function
    /// @param	_mintLimit	New maximum mint limit
    function setMaxMintLimit(uint _mintLimit) public override onlyOwner {
        emit NewMintLimit(maxMintLimit, _mintLimit);
        maxMintLimit = _mintLimit;
    }

    /// @notice	Checks if an account is a blacklister
    /// @param	account	The account to check
    /// @return	bool	Whether the account is a blacklister
    function isBlackLister(address account) internal view returns (bool) {
        require(account != address(0), "LstBTC: zero address");
        return blacklisters[account];
    }

    /// @notice	Checks if an account is blacklisted
    /// @param	account	The account to check
    /// @return	bool	Whether the account is blacklisted
    function isBlackListed(address account) public view returns (bool) {
        // require(account != address(0), "LstBTC: zero address");
        return blacklisted[account];
    }

    /// @notice	Checks if an account is a minter
    /// @param	account	The account to check
    /// @return	bool	Whether the account is a minter
    function isMinter(address account) internal view returns (bool) {
        require(account != address(0), "LstBTC: zero address");
        return minters[account];
    }

    /// @notice	Check if an account is burner
    /// @param	account	The account which intended to be checked
    /// @return	bool
    function isBurner(address account) internal view returns (bool) {
        require(account != address(0), "LstBTC: zero address");
        return burners[account];
    }

    /// @notice	Adds a blacklister
    /// @dev	Only owner can call this function
    /// @param	account	The account which intended to be added to blacklisters
    function addBlackLister(address account) external override onlyOwner {
        require(!isBlackLister(account), "LstBTC: already has role");
        blacklisters[account] = true;
        emit BlackListerAdded(account);
    }

    /// @notice	Removes a blacklister
    /// @dev	Only owner can call this function
    /// @param	account	The account which intended to be removed from blacklisters
    function removeBlackLister(address account) external override onlyOwner {
        require(isBlackLister(account), "LstBTC: does not have role");
        blacklisters[account] = false;
        emit BlackListerRemoved(account);
    }

    /// @notice	Adds a minter
    /// @dev	Only owner can call this function
    /// @param	account	The account which intended to be added to minters
    function addMinter(address account) external override onlyOwner {
        require(!isMinter(account), "LstBTC: already has role");
        minters[account] = true;
        emit MinterAdded(account);
    }

    /// @notice	Removes a minter
    /// @dev	Only owner can call this function
    /// @param	account	The account which intended to be removed from minters
    function removeMinter(address account) external override onlyOwner {
        require(isMinter(account), "LstBTC: does not have role");
        minters[account] = false;
        emit MinterRemoved(account);
    }

    /// @notice	Adds a burner
    /// @dev	Only owner can call this function
    /// @param	account	The account which intended to be added to burners
    function addBurner(address account) external override onlyOwner {
        require(!isBurner(account), "LstBTC: already has role");
        burners[account] = true;
        emit BurnerAdded(account);
    }

    /// @notice	Removes a burner
    /// @dev	Only owner can call this function
    /// @param	account	The account which intended to be removed from burners
    function removeBurner(address account) external override onlyOwner {
        require(isBurner(account), "LstBTC: does not have role");
        burners[account] = false;
        emit BurnerRemoved(account);
    }

    /// @notice	Burns LstBTC tokens of msg.sender
    /// @dev	Only burners can call this
    /// @param	_amount	Amount of burnt tokens
    function burn(uint _amount) external nonReentrant onlyBurner override returns (bool) {
        _burn(_msgSender(), _amount);
        emit Burn(_msgSender(), _msgSender(), _amount);
        return true;
    }

    /// @notice	Burns LstBTC tokens of user
    /// @dev	Only owner can call this
    /// @param	_user	Address of user whose lstBTC is burnt
    /// @param	_amount	Amount of burnt tokens
    function ownerBurn(
        address _user,
        uint _amount
    ) external nonReentrant onlyOwner override returns (bool) {

        if (isBlackListed(_user)) {
            blacklisted[_user] = false;
            _burn(_user, _amount);
            blacklisted[_user] = true;
        } else {
            _burn(_user, _amount);
        }

        emit Burn(owner(), _user, _amount);
        return true;
    }

    /// @notice	Mints LstBTC tokens for _receiver
    /// @dev	Only minters can call this
    /// @param	_receiver	Address of token's receiver
    /// @param	_amount	Amount of minted tokens
    function mint(
        address _receiver,
        uint _amount
    ) external nonReentrant onlyMinter override returns (bool) {
        require(totalSupply() + _amount <= maxMintLimit, "LstBTC: reached maximum mint limit");

        _mint(_receiver, _amount);
        emit Mint(_msgSender(), _receiver, _amount);
        return true;
    }

    /// @notice	Blacklist an account
    /// @dev	Only Blacklisters can call this
    /// @param	_account	Account blacklisted
    function blacklist(address _account) external override nonReentrant onlyBlackLister {
        blacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    /// @notice	UnBlacklist an account
    /// @dev	Only Blacklisters can call this
    /// @param	_account	Account unblacklisted
    function unBlacklist(address _account) external override nonReentrant onlyBlackLister {
        blacklisted[_account] = false;
        emit UnBlacklisted(_account);
    }

    /// @notice	Hook called before token transfer
    /// @dev	Prevents transfers to/from blacklisted addresses
    /// @param	from	Address sending tokens
    /// @param	to	Address receiving tokens
    /// @param	/*amount*/	Amount being transferred (unused)
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 /*amount*/
    ) internal view override {
        require(!isBlackListed(from), "LstBTC: from is blacklisted");
        require(!isBlackListed(to), "LstBTC: to is blacklisted");
    }

    /// @notice	Hook called after token transfer
    /// @dev	Notifies bridge contract of transfer and validates amount
    /// @param	from	Address that sent tokens
    /// @param	to	Address that received tokens
    /// @param	amount	Amount that was transferred
    function _afterTokenTransfer(
        address from,
        address to,
        uint amount
    ) internal override {
        if (from == address(0) || to == address(0) || amount == 0) { return; }

        require(amount <= type(uint64).max, "LstBTC: exceeds uint64 limit");
        Address.functionCall(
            bridge,
            abi.encodeWithSignature(
                "onLstBTCTransfer(address,address,uint64)",
                from,
                to,
                amount
            )
        );
    }
}