// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSC Engine
 * @author @Jakub-Kliment
 * 
 * System designed to be as minimal as possible, to maintain a 1 token == $1 peg.
 * Properties:
 *      - Collateral: Exogenous (ETH & BTC)
 *      - Minting: Algorithmic
 *      - Relative Stability: Pegged to USD
 * 
 * Similar to DAI without governance, without fees and backed by wETH and wBTC.
 * 
 * Our system should always be "overcollateralized".
 * At no point, should the value of all collateral be less than 
 * the dollar backed value of the DSC.
 * 
 * @notice This contract is the core of the DSC system.
 * It handles all the logic or mining and redeeming DSC, as well as deposing
 * and withdrawing collateral
 * @notice This contract is very loosly based on the MakerDAO (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    //    Errors    //
    //////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    /////////////////////////
    //   State variables   //
    /////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////
    //   Events      //
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed tokenAddress, uint256 indexed amount);

    ////////////////////
    //   Modifiers   //
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }
    //////////////////////
    //   Constructor   //
    /////////////////////
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////
    //   External Functions   //
    ////////////////////////////
    /**
     * Main function of the contract to deposit collateral and mint DSC in one transaction.
     * 
     * @param tokenCollateralAddress address of the token to deposit as collateral
     * @param amountCollateral amount of collateral to deposit
     * @param amountDscToMint amount of dsc to mint
     * @notice the function will deposit collateral and mint dsc in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountDscToMint
    ) external 
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * Function for users to deposit collateral
     * 
     * @notice follows CEI
     * @param tokenCollateralAddress the address of the token to deposit as collateral 
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) 
        public 
        moreThanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress) 
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * Redeems collateral and burns the token in one transaction
     * 
     * @param tokenCollateralAddress address of the token collateral
     * @param amountDscToBurn amount of DSC user wants to burn
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        // Redeem collateral already checks health factor
        redeemCollateral(tokenCollateralAddress, amountDscToBurn);
    }

    /**
     * Lets the user redeem an amount of DSC for collateral (currency of their choice)
     * 
     * @param tokenCollateralAddress the address of the token collateral
     * @param amountCollateral the amount of collateral
     * @notice In order to redeem collateral the user must satisfy the health factor condition 
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public 
        moreThanZero(amountCollateral) 
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        } 
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        s_DSCMinted[msg.sender] -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint amount of DSC to mint
     * @notice the user must have more collateral value than minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///////////////////////////////////////////
    //   Private & Internal View Functions   //
    ///////////////////////////////////////////
    function _getAccountInfromation(address user)
        private view returns (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        )
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user); 
    }
    /**
     * Returns how close the user is to being liquidated.
     * If the user gets below the value of 1, they can get liquidated.
     * 
     * @param user to check healthfactor
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalMinted, uint256 collateralValueInUsd) = _getAccountInfromation(user);
        uint256 collateralAdjustedForThreshold = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////////////
    //   Public & External View Functions   //
    //////////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for(uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

}