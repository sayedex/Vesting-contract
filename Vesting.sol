// SPDX-License-Identifier: MIT

/**************************
BRANAVERSE Company WALLET
**************************/
pragma solidity =0.8.20;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vesting is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    enum LockCategory {
        TreasureTokens,
        Company,
        ExchangeAndLiquidity,
        Marketing,
        Partnerships,
        FoundersAndTeam,
        EcosystemAndDevelopment,
        SecuredFund,
        BranaAI
    }

    // uint256 public constant monthly = 30 days;
    uint256 public constant monthly = 1 minutes;
    uint256 public companyVault = 0;
    uint256 public count;
    uint256 public constant hPercent = 100; //100%
    address public tokenaddress;

    event WithdrawalBNB(uint256 _amount, uint256 decimal, address to);
    event WithdrawalBRANA(uint256 _amount, uint256 decimal, address to);
    event WithdrawalBEP20(
        address _tokenAddr,
        uint256 _amount,
        uint256 decimals,
        address to
    );
    event LockWalletAdded(
        uint256 indexed id,
        uint256 totalAmount,
        uint256 lockamount,
        uint256 monthLock,
        uint256 lockTime,
        uint256 timeStart,
        uint256 mP,
        LockCategory lockCategory
    );

    event MonthlyTokenClaimed(
        uint256 indexed id,
        address indexed receiver,
        uint256 claimedAmount,
        uint256 remainingLockAmount,
        uint256 nextMonthLock
    );

    struct Vaultstate {
        uint256 totalAmount;
        uint256 lockamount;
        uint256 monthLock;
        uint256 lockTime;
        uint256 timeStart;
        uint256 mP;
        LockCategory lockCategory; // Add an enum property
    }

    mapping(uint256 => Vaultstate) public vault;

    constructor(address _BRANA, address _owner) Ownable(_owner) {
        tokenaddress = _BRANA;
    }

    modifier onlyAfterTotalTimeLock(uint256 _id) {
        uint256 totalTimeLock = vault[_id].monthLock;
        require(totalTimeLock <= block.timestamp, "Not yet");
        uint256 remainAmount = vault[_id].lockamount;
        require(remainAmount > 0, "No BRANA");
        _;
    }

    /// @notice Add a lock wallet with specified details.
    function addLockwallet(
        uint256 _amount,
        uint256 _lockTime,
        uint256 _mP,
        LockCategory category
    ) external onlyOwner nonReentrant {
        transferCurrency(tokenaddress, msg.sender, address(this), _amount);
        //uint256 lockTime = _lockTime.mul(1 days);
        uint256 lockTime = _lockTime.mul(1 minutes);
        Vaultstate memory newWallet = Vaultstate({
            totalAmount: _amount,
            lockamount: _amount,
            monthLock: lockTime.add(block.timestamp),
            lockTime: lockTime.add(block.timestamp),
            timeStart: block.timestamp,
            mP: _mP,
            lockCategory: category
        });

        companyVault += _amount;
        vault[count] = newWallet;
        count++;

        // Emit the event
        emit LockWalletAdded(
            count,
            newWallet.totalAmount,
            newWallet.lockamount,
            newWallet.monthLock,
            newWallet.lockTime,
            newWallet.timeStart,
            newWallet.mP,
            newWallet.lockCategory
        );
    }

    /// @notice Claim monthly tokens for a specific vault.
    function claimMonthlyToken(address _rcv, uint256 _id)
        external
        onlyOwner
        onlyAfterTotalTimeLock(_id)
        nonReentrant
    {
        uint256 mainAmount = vault[_id].totalAmount;
        uint256 _mp = vault[_id].mP;
        uint256 amountAllowed = mainAmount.mul(_mp).div(hPercent);
        vault[_id].lockamount -= amountAllowed;
        vault[_id].monthLock == monthly.add(block.timestamp);
        vault[_id].lockTime += monthly.add(block.timestamp);
        companyVault -= amountAllowed;

        transferCurrency(tokenaddress, address(this), _rcv, amountAllowed);
        // Emit the event
        emit MonthlyTokenClaimed(
            _id,
            _rcv,
            amountAllowed,
            vault[_id].lockamount,
            vault[_id].monthLock
        );
    }

    /// @notice Change the monthly percentage for a specific vault.
    function changeMP(uint256 _id, uint256 _newMP) external onlyOwner {
        require(_id < count, "Invalid ID");
        require(_newMP >= 0 && _newMP <= 100, "Invalid monthly percentage");
        vault[_id].mP = _newMP;
    }

    /// @notice Change the lock category for a specific vault.
    function changeLockCategory(uint256 _id, LockCategory _newCategory)
        external
        onlyOwner
    {
        require(_id < count, "Invalid ID");
        vault[_id].lockCategory = _newCategory;
    }

    /// @notice Allows the owner to withdraw BRANA tokens.
    function withdrawalBRANA(
        uint256 _amount,
        uint256 decimal,
        address to
    ) external onlyOwner {
        uint256 amount = IERC20(tokenaddress).balanceOf(address(this)).sub(
            companyVault
        );
        uint256 dcml = 10**decimal;
        require(amount > 0 && _amount * dcml <= amount, "No BRANA!"); // can only withdraw what is not locked for Company Wallet.
        emit WithdrawalBRANA(_amount, decimal, to);
        transferCurrency(tokenaddress, address(this), to, _amount);
    }

    /// @notice Allows the owner to withdraw tokens of any ERC20 compatible token.
    function withdrawalBEP20(
        address _tokenAddr,
        uint256 _amount,
        uint256 decimal,
        address to
    ) external onlyOwner {
        require(_tokenAddr != tokenaddress, "No!"); //Can't withdraw BRANA using this function!
        emit WithdrawalBEP20(_tokenAddr, _amount, decimal, to);
        transferCurrency(_tokenAddr, address(this), msg.sender, _amount);
    }

    /// @notice Allows the owner to withdraw BNB.
    function withdrawalBNB(
        uint256 _amount,
        uint256 decimal,
        address to
    ) external onlyOwner {
        require(address(this).balance >= _amount, "Balanace"); //No BNB balance available
        uint256 dcml = 10**decimal;
        emit WithdrawalBNB(_amount, decimal, to);
        payable(to).transfer(_amount * dcml);
    }

    /// @notice Transfers a given amount of currency.
    function transferCurrency(
        address _currency,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_amount == 0) {
            return;
        }
        safeTransferERC20(_currency, _from, _to, _amount);
    }

    /// @notice Transfers `amount` of ERC20 token from `from` to `to`.
    function safeTransferERC20(
        address _currency,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_from == _to) {
            return;
        }

        if (_from == address(this)) {
            IERC20(_currency).safeTransfer(_to, _amount);
        } else {
            IERC20(_currency).safeTransferFrom(_from, _to, _amount);
        }
    }

    /// @notice return valult info
    function getVaultDetails(uint256 _id)
        external
        view
        returns (
            uint256 totalAmount,
            uint256 lockamount,
            uint256 monthLock,
            uint256 lockTime,
            uint256 timeStart,
            uint256 mP,
            LockCategory lockCategory
        )
    {
        require(_id < count, "Invalid ID");

        Vaultstate storage vaultDetails = vault[_id];

        return (
            vaultDetails.totalAmount,
            vaultDetails.lockamount,
            vaultDetails.monthLock,
            vaultDetails.lockTime,
            vaultDetails.timeStart,
            vaultDetails.mP,
            vaultDetails.lockCategory
        );
    }

    /// @notice Allows the contract to receive BNB.
    receive() external payable {}
}
