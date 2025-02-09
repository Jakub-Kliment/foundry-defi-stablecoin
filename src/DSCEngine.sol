// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

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

    /////////////////////////
    //   State variables   //
    /////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////
    //   Events      //
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////
    //   External Functions   //
    ////////////////////////////
    function depositCollateralAndMintDsc() external {}

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
        external 
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function burnDsc() external {}

    function mintDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}