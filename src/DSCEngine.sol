// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
contract DSCEngine {

    function depositCollateralAndMintDsc() external {}

    function depositCollateral() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function burnDsc() external {}

    function mintDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}