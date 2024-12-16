// SPDX-License-Identifier: Business Source License 1.1
// First Release Time : 2024.09.30

pragma solidity 0.8.6;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/islcvaultV3.sol";
import "./interfaces/ixinterface.sol";
contract slcInterfaceV3  {
    using SafeERC20 for IERC20;

    address public superLibraCoin;
    address public slcVaults;
    address public xInterface;

    address public setter;
    address newsetter;

    address USD1;
    address USD2;
    address USD1_USD2_Lp;

    //----------------------------modifier ----------------------------
    modifier onlySetter() {
        require(msg.sender == setter, 'SLC Interface: Only Manager Use');
        _;
    }

    //------------------------------------------------------------------

    constructor() {
        setter = msg.sender;
    }
    function transferSetter(address _set) external onlySetter{
        newsetter = _set;
    }
    function acceptSetter(bool _TorF) external {
        require(msg.sender == newsetter, 'SLC Interface: Permission FORBIDDEN');
        if(_TorF){
            setter = newsetter;
        }
        newsetter = address(0);
    }
    function setup( address _superLibraCoin,
                    address _slcVaults,
                    address _xInterface) external onlySetter{
        superLibraCoin = _superLibraCoin;
        slcVaults = _slcVaults;
        xInterface = _xInterface;
    }
    function setUSDAddress( address _USD1,
                            address _USD2,
                            address _USD1_USD2_Lp ) public onlySetter{
        USD1 = _USD1;
        USD2 = _USD2;
        USD1_USD2_Lp = _USD1_USD2_Lp;
    }

    //---------------------------- User Used Function ----------------------------------
    function getTVLAndUSDAmount() public view returns(uint[2] memory _amountUSD,uint _TVL){
        // uint[2] memory reserve;
        // uint totalSupply;  
        uint _amountLp = IERC20(USD1_USD2_Lp).balanceOf(slcVaults);   
        (_amountUSD,,_TVL) = ixInterface(xInterface).getLpReserve( USD1_USD2_Lp);
        _amountUSD[0] = _amountUSD[0] * _amountLp / _TVL;
        _amountUSD[1] = _amountUSD[1] * _amountLp / _TVL;
        _amountUSD[0] = IERC20(USD1).balanceOf(slcVaults) + _amountUSD[0];
        _amountUSD[1] = IERC20(USD2).balanceOf(slcVaults) + _amountUSD[1];
        _TVL = _amountUSD[0] + _amountUSD[1];
    }
    
    function getV1MintedCoin() external view returns(uint){
        return islcvaultV3(slcVaults).v1MintedCoin();
    }
    function getUserMintedAmount(address user) public view returns(uint amount){
        return islcvaultV3(slcVaults).userObtainedSLCAmount(user);
    }
    function getTotalMintedAmount() public view returns(uint amount){
        return IERC20(superLibraCoin).totalSupply();
    }
    function getSlcValue() public view returns(uint value){
        (value,,) = islcvaultV3(slcVaults).slcValue();
    }

    // estimate
    function xLpSubscribeEst(address _lp,uint[2] memory _amountEstimated) internal view returns(uint[2] memory _amountActual,uint _amountLp){
        uint[2] memory reserve;
        uint totalSupply;     
        (reserve,,totalSupply) = ixInterface(xInterface).getLpReserve( _lp);
        _amountActual[0] = _amountEstimated[1]*reserve[0]/reserve[1];
        if(_amountActual[0]<=_amountEstimated[0]){
            _amountActual[1] = _amountEstimated[1];
        }else{
            _amountActual[0] = _amountEstimated[0];
            _amountActual[1] = _amountEstimated[0]*reserve[1]/reserve[0];
        }
        _amountLp = _amountActual[0] * totalSupply / reserve[0];
    }

    function mintSLCEst(address token, uint inputAmount) public view returns(uint outputAmount){
        require(token == USD1 || token == USD2,"SLC Vaults: Only USDT Or USDC accepted");
        // uint[2] memory reserve;     
        // uint[2] memory _amountActual;
        
        address[] memory tokens = new address[](2);
        tokens[0] = token;
        if(token == USD1){
            tokens[1] = USD2;
        }else{
            tokens[1] = USD1;
        }
        (outputAmount,) = ixInterface(xInterface).xExchangeEstimateInput(tokens,inputAmount/2);
        if(token == USD1){
            
            (,outputAmount) = xLpSubscribeEst(USD1_USD2_Lp, [inputAmount/2, outputAmount]);
        }else{
            (,outputAmount) = xLpSubscribeEst(USD1_USD2_Lp, [outputAmount, inputAmount/2]);
        }
        outputAmount = outputAmount * 2 * islcvaultV3(slcVaults).slcValueScale() / 1 ether;
    }

    function xLpRedeemEst(address _lp,uint _amountLp) internal view returns(uint[2] memory _amount){
        require(_amountLp > 0,"X SWAP LpManager: _amountLp must > 0");
        uint[2] memory reserve;           
        uint totalSupply;
        (reserve,,totalSupply) = ixInterface(xInterface).getLpReserve( _lp);

        _amount[0] = reserve[0] * _amountLp /totalSupply;
        _amount[1] = reserve[1] * _amountLp /totalSupply;

    }

    // return SLC coin
    function burnSLCEst(uint amount, address token) public view returns(uint outputAmount){
        require(token == USD1 || token == USD2,"SLC Vaults: Only USDT Or USDC accepted");
        uint[2] memory _amount;

        outputAmount = amount * 1 ether / (2 * islcvaultV3(slcVaults).slcValueScale());
        _amount = xLpRedeemEst(USD1_USD2_Lp, outputAmount);

        address[] memory tokens = new address[](2);
        
        tokens[1] = token;
        if(token == USD1){
            tokens[0] = USD2;
        }else{
            tokens[0] = USD1;
        }
        if(token == USD1){
            (outputAmount,) = ixInterface(xInterface).xExchangeEstimateInput(tokens,_amount[1]);
            outputAmount = outputAmount + _amount[0];
        }else{
            (outputAmount,) = ixInterface(xInterface).xExchangeEstimateInput(tokens,_amount[0]);
            outputAmount = outputAmount + _amount[1];
        }
    }


    function mintSLC(address tokenAddr, uint amount) public  returns(uint outputAmount){
        IERC20(tokenAddr).safeTransferFrom(msg.sender,address(this),amount);
        IERC20(tokenAddr).approve(slcVaults, amount);
        outputAmount = islcvaultV3(slcVaults).mintSLC(tokenAddr, amount, msg.sender);

        if(IERC20(superLibraCoin).balanceOf(address(this))>0){
            IERC20(superLibraCoin).safeTransfer(msg.sender,IERC20(superLibraCoin).balanceOf(address(this)));
        }
        if(IERC20(tokenAddr).balanceOf(address(this))>0){
            IERC20(tokenAddr).safeTransfer(msg.sender,IERC20(tokenAddr).balanceOf(address(this)));
        }
    }
    function burnSLC(address tokenAddr, uint amount) public  returns(uint outputAmount){
        IERC20(superLibraCoin).safeTransferFrom(msg.sender,address(this),amount);
        IERC20(superLibraCoin).approve(slcVaults, amount);
        outputAmount = islcvaultV3(slcVaults).burnSLC(amount, msg.sender, tokenAddr) ;

        if(IERC20(superLibraCoin).balanceOf(address(this))>0){
            IERC20(superLibraCoin).safeTransfer(msg.sender,IERC20(superLibraCoin).balanceOf(address(this)));
        }
        if(IERC20(tokenAddr).balanceOf(address(this))>0){
            IERC20(tokenAddr).safeTransfer(msg.sender,IERC20(tokenAddr).balanceOf(address(this)));
        }
    }

    // ======================== contract base methods =====================
    fallback() external payable {}
    receive() external payable {}

}