// SPDX-License-Identifier: Business Source License 1.1
// First Release Time : 2024.11.30

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ixinterface.sol";
import "./interfaces/islc.sol";
import "./interfaces/islcoracle.sol";
import "./interfaces/iRewardMini.sol";

// Only Use USDT & USDC To Mint

contract slcVault3  {
    using SafeERC20 for IERC20;

    uint public stableCoinType = 2;
    bool public priceAutoBalance; //Automatic balance switch

    address public USD1;//USD1
    address public USD2;//USD2
    address public USD1_USD2_Lp;

    address public superLibraCoin;
    uint    public slcValueScale;
    address public accoladesAddress;

    uint    public floorLimit;
    uint    public upperLimit;

    address public xInterface;
    address public oracleAddr;
    address public rewardContract;

    address public setter;
    address newsetter;

    uint public latestBlockNumber;
    address public latestBlockUser;

    mapping(address => bool) public slcInterface;
    mapping(address => uint) public userObtainedSLCAmount;
    //              a     b
    // "SLCTOUSD1"  1     a1 ether
    // "SLCTOUSD2"  2     a2 ether
    // "USD1TOSLC"  3     a3 ether
    // "USD2TOSLC"  4     a4 ether
    mapping(uint => uint) public tokensLimitsAmount;

    uint public slcSum;
    //----------------------------modifier ----------------------------
    modifier onlySetter() {
        require(msg.sender == setter, 'SLC Vaults: Only Manager Use');
        _;
    }

    modifier autobalance() {
        if(priceAutoBalance){
            _;
        }
    }
    //----------------------------- event -----------------------------
    event SlcInterfaceSetup(address indexed _interface, bool _ToF);
    event ObtainSLC(address indexed msgSender, uint amount, address user);
    event ReturnSLC(address indexed msgSender, uint amount, address user);
    event SlcValueScale(uint scale);
    event TokensLimitsAmount(uint mode, uint amount);
    event Setter(address  setter);
    //------------------------------------------------------------------

    constructor() {
        setter = msg.sender;
        slcValueScale = 1 ether;
        // priceAutoBalance = true;
    }

    //-----------------------------Setup-------------------------------

    function transferSetter(address _set) external onlySetter{
        newsetter = _set;
    }

    function acceptSetter(bool _TorF) external {
        require(msg.sender == newsetter, 'SLC Vaults: Permission FORBIDDEN');
        if(_TorF){
            setter = newsetter;
        }
        newsetter = address(0);
        emit Setter(setter);
    }

    function setupPriceAutoBalance(bool _priceAutoBalance) public onlySetter{
        priceAutoBalance = _priceAutoBalance;
    }

    function floorAndUpperLimit(uint _floorLimit,uint _upperLimit) public onlySetter{
        floorLimit = _floorLimit;
        upperLimit = _upperLimit;
    }

    function setup( address _superLibraCoin,
                    address _xInterface,
                    address _accoladesAddress,
                    address _oracleAddr ) public onlySetter{
        superLibraCoin = _superLibraCoin;
        xInterface = _xInterface;
        oracleAddr = _oracleAddr;
        accoladesAddress = _accoladesAddress;
    }
    function setUSDAddress( address _USD1,
                            address _USD2,
                            address _USD1_USD2_Lp ) public onlySetter{
        USD1 = _USD1;
        USD2 = _USD2;
        USD1_USD2_Lp = _USD1_USD2_Lp;
    }

    function rewardContractSetup(address _rewardContract,uint _stableCoinType) public onlySetter{
        rewardContract = _rewardContract;
        stableCoinType = _stableCoinType;
        iRewardMini(rewardContract).factoryUsedRegist(address(this), stableCoinType);
    }

    function setSlcInterface(address _ifSlcInterface, bool _ToF) public onlySetter{
        slcInterface[_ifSlcInterface] = _ToF;
        emit SlcInterfaceSetup(_ifSlcInterface, _ToF);
    }

    function setTokenLimits(uint mode, uint amount) public onlySetter{
        tokensLimitsAmount[mode] = amount;
        emit TokensLimitsAmount(mode, amount);
    }

    //-----------------------------Default Setting-------------------------------

    function defualtSetting() external onlySetter{
        floorAndUpperLimit(0.99 ether, 1.02 ether);
        setup(  (0x8c4B892AF3655eAE24cf426c4D242Ab95bc3903D),
                (0xD3C5c8B9439E84ad42c20716c335974822BC211a),
                (0xfA5f635492601EA92898693F710A24Fca7665ef7),
                (0x945dbfdd972B5628AB9235BF28E68Eb59aF98703));
        setUSDAddress(  (0x27Fc32d2AD515c9AFE5e6c8434B32053ce0b042B),
                        (0xcB12b404c3Ed1bB67d9Bd6ca044283497a8eB18a),
                        (0xAA35686Ca0CdaD6A56Cc68b74798D967FE3ded93));
        rewardContractSetup((0x99d5524a63dc7Eee5BC0dC6f6aD49D19c1B89E5F),2);
        setTokenLimits(1, 1 ether);
        setTokenLimits(2, 1 ether);
        setTokenLimits(3, 1 ether);
        setTokenLimits(4, 1 ether);
    }
    //------------------------------------------------------------------------------

    function swapApprove() public {
        IERC20(USD1).approve(xInterface, type(uint).max);
        IERC20(USD2).approve(xInterface, type(uint).max);
        IERC20(superLibraCoin).approve(xInterface, type(uint).max);
        IERC20(USD1_USD2_Lp).approve(xInterface, type(uint).max);
    }
    //--------------------Price synchronization and value-added----------------------

    // Evaluate the value of superLibraCoin
    function slcValue() public view returns(uint value, uint lpvalue, uint accolades){
        uint[2] memory TokenInSwapVaults;
        uint lpSum;
        uint lpInSLCVaults = IERC20(USD1_USD2_Lp).balanceOf(address(this));
        
        (TokenInSwapVaults,,lpSum) = ixInterface(xInterface).getLpReserve(USD1_USD2_Lp);
        lpvalue = (TokenInSwapVaults[0] + TokenInSwapVaults[1]) * 1 ether / (lpSum * 2);
        value = (TokenInSwapVaults[0] + TokenInSwapVaults[1]) * 1 ether / lpSum * lpInSLCVaults / slcSum;
        if(value > 1 ether){
            accolades = (TokenInSwapVaults[0] + TokenInSwapVaults[1]) * lpInSLCVaults / lpSum - slcSum;
        }
    }
    function slcValueRenew() public autobalance returns(uint value, uint lpvalue, uint accolades){
        (value,lpvalue,accolades) = slcValue();
        if(value > (1001 ether / 1000)){
            slcValueScale = lpvalue;// 
            iSlc(superLibraCoin).mintSLC(accoladesAddress,accolades);
            slcSum += accolades;
        }
        emit SlcValueScale(slcValueScale);
    }

    // update price and buy&sell slc
    function priceCheck(address token) public view returns(uint price){
        price = iSlcOracle(oracleAddr).getPrice(token);
    }

    function valueRegression() public autobalance{
        uint outAmount;
        address[] memory tokens = new address[](2);

        if(priceCheck(superLibraCoin) > upperLimit){
            tokens[0] = superLibraCoin;
            tokens[1] = USD1;
            (outAmount,) = ixInterface(xInterface).xExchangeEstimateInput(tokens, tokensLimitsAmount[1]);
            if(IERC20(superLibraCoin).balanceOf(address(this))>=tokensLimitsAmount[1]){
                if(outAmount > tokensLimitsAmount[1] * 1001 / 1000){
                    ixInterface(xInterface).xexchange(tokens,tokensLimitsAmount[1],outAmount,outAmount/10, block.timestamp + 100);
                }
            }
            tokens[1] = USD2;
            (outAmount,) = ixInterface(xInterface).xExchangeEstimateInput(tokens, tokensLimitsAmount[2]);
            if(IERC20(superLibraCoin).balanceOf(address(this))>=tokensLimitsAmount[2]){
                if(outAmount > tokensLimitsAmount[2] * 1001 / 1000){
                    ixInterface(xInterface).xexchange(tokens,tokensLimitsAmount[2],outAmount,outAmount/10, block.timestamp + 100);
                }
            }
        }else if(priceCheck(superLibraCoin) < floorLimit){
            tokens[0] = USD1;
            tokens[1] = superLibraCoin;
            (outAmount,) = ixInterface(xInterface).xExchangeEstimateInput(tokens, tokensLimitsAmount[3]);
            if(outAmount > tokensLimitsAmount[3] * 1001 / 1000){
                if(IERC20(USD1).balanceOf(address(this))>=tokensLimitsAmount[3]){
                    ixInterface(xInterface).xexchange(tokens,tokensLimitsAmount[3],outAmount,outAmount/10, block.timestamp + 100);
                }else {
                    ixInterface(xInterface).xLpRedeem(USD1_USD2_Lp, tokensLimitsAmount[3]);
                    ixInterface(xInterface).xexchange(tokens,tokensLimitsAmount[3],outAmount,outAmount/10, block.timestamp + 100);
                }
            }
            tokens[0] = USD2;
            (outAmount,) = ixInterface(xInterface).xExchangeEstimateInput(tokens, tokensLimitsAmount[4]);
            if(outAmount > tokensLimitsAmount[4] * 1001 / 1000){
                if(IERC20(USD2).balanceOf(address(this))>=tokensLimitsAmount[4]){
                    ixInterface(xInterface).xexchange(tokens,tokensLimitsAmount[4],outAmount,outAmount/10, block.timestamp + 100);
                }else{
                    ixInterface(xInterface).xLpRedeem(USD1_USD2_Lp, tokensLimitsAmount[4]);
                    ixInterface(xInterface).xexchange(tokens,tokensLimitsAmount[4],outAmount,outAmount/10, block.timestamp + 100);
                }
            }
        }
        if(IERC20(USD1).balanceOf(address(this))> 0.1 ether && IERC20(USD2).balanceOf(address(this))> 0.1 ether){
            ixInterface(xInterface).xLpSubscribe(USD1_USD2_Lp, [IERC20(USD1).balanceOf(address(this)), IERC20(USD2).balanceOf(address(this))]);
        }
    }

    //---------------------------- mint & burn  Function----------------------------
    // obtain SLC coin
    function mintSLC(address token, uint inputAmount, address user) public  returns(uint outputAmount){

        if(slcInterface[msg.sender]==false){
            require(user == msg.sender,"SLC Vaults: Not registered as slcInterface or user need be msg.sender!");
            require(latestBlockNumber < block.number,"SLC Vaults: Same block can only have ONE obtain operation ");
        }
        require(inputAmount > 0,"SLC Vaults: Cant Pledge 0 amount");
        require(token == USD1 || token == USD2,"SLC Vaults: Only USDT Or USDC accepted");
        IERC20(token).safeTransferFrom(msg.sender,address(this),inputAmount);

        latestBlockNumber = block.number;
        latestBlockUser = user;

        // uint[2] memory _amount;
        address[] memory tokens = new address[](2);
        tokens[0] = token;
        if(token == USD1){
            tokens[1] = USD2;
        }else{
            tokens[1] = USD1;
        }
        outputAmount = ixInterface(xInterface).xexchange(tokens,inputAmount/2,inputAmount/2,inputAmount/20, block.timestamp + 100);
        if(token == USD1){
            (,outputAmount) = ixInterface(xInterface).xLpSubscribe(USD1_USD2_Lp, [inputAmount/2, outputAmount]);
        }else{
            (,outputAmount) = ixInterface(xInterface).xLpSubscribe(USD1_USD2_Lp, [outputAmount, inputAmount/2]);
        }
        outputAmount = outputAmount * 2 * slcValueScale / 1 ether;
        iSlc(superLibraCoin).mintSLC(msg.sender,outputAmount);
        userObtainedSLCAmount[user] += outputAmount ;
        slcSum += outputAmount;

        valueRegression();
        slcValueRenew();

        iRewardMini(rewardContract).recordUpdate(user,userObtainedSLCAmount[user]);
        emit ObtainSLC(msg.sender, outputAmount, user);
    }

    // return SLC coin
    function burnSLC(uint amount, address user, address token) public  returns(uint outputAmount){
        if(slcInterface[msg.sender]==false){
            require(user == msg.sender,"SLC Vaults: Not registered as slcInterface or user need be msg.sender!");
            require(amount <= IERC20(superLibraCoin).balanceOf(user),"SLC Vaults: amount need <= balance Of user.");
        }
        latestBlockNumber = block.number;
        latestBlockUser = user;

        require(amount > 0,"SLC Vaults: Cant Pledge 0 amount");
        require(token == USD1 || token == USD2,"SLC Vaults: Only USDT Or USDC accepted");
        uint[2] memory _amount;
        iSlc(superLibraCoin).burnSLC(msg.sender, amount);
        userObtainedSLCAmount[user] -= amount;
        slcSum -= amount;
        

        outputAmount = amount * 1 ether / (2 * slcValueScale);
        _amount = ixInterface(xInterface).xLpRedeem(USD1_USD2_Lp, outputAmount);

        address[] memory tokens = new address[](2);
        
        tokens[1] = token;
        if(token == USD1){
            tokens[0] = USD2;
        }else{
            tokens[0] = USD1;
        }
        if(token == USD1){
            outputAmount = ixInterface(xInterface).xexchange(tokens,_amount[0],_amount[0],_amount[0], block.timestamp + 100);
            IERC20(token).safeTransfer(msg.sender,outputAmount + _amount[1]);
        }else{
            outputAmount = ixInterface(xInterface).xexchange(tokens,_amount[1],_amount[1],_amount[1], block.timestamp + 100);
            IERC20(token).safeTransfer(msg.sender,outputAmount + _amount[0]);
        }
        
        valueRegression();
        slcValueRenew();

        iRewardMini(rewardContract).recordUpdate(user,userObtainedSLCAmount[user]);
        emit ReturnSLC(msg.sender, amount, user);
    }
    // ======================== contract base methods =====================
    fallback() external payable {}
    receive() external payable {}
}