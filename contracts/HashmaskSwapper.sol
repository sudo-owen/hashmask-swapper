// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "./IHashmask.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract HashmaskSwapper is ReentrancyGuard {

  using EnumerableMap for EnumerableMap.UintToAddressMap;
  using SafeMath for uint256;

  // Struct for the two names being swapped
  // name1 is the caller, name2 should be the taker
  struct NameSwap {
    string name1;
    string name2;
    address token;
    uint256 price;
    uint256 escrowedNCTAmount;
  }

  IHashmask public hashmask;
  IERC20 public nct;

  // Note this is 150% of the normal name change price to handle 3 name swaps
  // 1830 * 1.5 = 2745
  uint256 public constant MODIFIED_NAME_CHANGE_PRICE = 2745 * (10 ** 18);

  // Normal NCT name change fee
  uint256 public constant NAME_CHANGE_PRICE = 1830 * (10**18);

  // Parameters for sale fees, 1% goes to XMON deployer
  address public constant XMON_DEPLOYER =  0x75d4bdBf6593ed463e9625694272a0FF9a6D346F;
  uint256 public constant BASE = 100;
  uint256 public constant PAID_AMOUNT = 99;
  uint256 public constant FEE_AMOUNT = 1;

  EnumerableMap.UintToAddressMap private originalOwner;
  mapping(uint256 => NameSwap) public swapRecords;

  constructor(address mask, address token) public {
    hashmask = IHashmask(mask);
    nct = IERC20(token);

    // large enough approval for all the swaps we'll ever need
    nct.approve(address(hashmask), uint256(-1));
  }

  /**
    @dev Proposes a swap, not publicly available
   */
  function createSwap(uint256 id, string memory desiredName, address token, uint256 price, uint256 transferAmount) private nonReentrant {
    require(hashmask.ownerOf(id) == msg.sender, "Not owner");

    // Record the swap, names are not lowercase, lowercase is only checked when taking
    swapRecords[id] = NameSwap(
      hashmask.tokenNameByIndex(id),
      desiredName,
      token,
      price,
      transferAmount
    );

    // Record original NFT owner
    originalOwner.set(id, msg.sender);

    // Let contract hold the NFT as escrow
    hashmask.transferFrom(msg.sender, address(this), id);

    // Escrow enough NCT for the relevant swap
    nct.transferFrom(msg.sender, address(this), transferAmount);
  }

  /**
   @dev Propose a swap between two names (current and desired) and deposit NFT into contract
   * token is set to be the zero address
   * price is set to 0
   */
  function setNameSwap(uint256 id, string calldata desiredName) external {

    // Transfer enough funds in to do one way of the swap (need 150% of the normal rate b/c it's 3 swaps)
    createSwap(id, desiredName, address(0), 0, MODIFIED_NAME_CHANGE_PRICE);
  }

  /**
    @dev Propose a name sell. Allows anyone with the tokens can accept the swap
   * desiredName is set to "" (empty string) which will allow any tokenId to take the swap
   */
  function setNameSale(uint256 id, address token, uint256 price) external {
    createSwap(id, "", token, price, NAME_CHANGE_PRICE);
  }

  /**
   @dev Remove a proposed swap and get back the deposited NFT.
  */
  function removeSwap(uint256 id) external nonReentrant {

    // Only original owner can remove the swap proposal
    require(msg.sender == originalOwner.get(id), "Not owner");

    uint256 transferAmount = swapRecords[id].escrowedNCTAmount;

    // Clear out storage
    originalOwner.remove(id);
    delete swapRecords[id];

    // Get back the original NFT
    hashmask.transferFrom(address(this), msg.sender, id);

    // Get back the NCT tokens put in
    nct.transfer(msg.sender, transferAmount);
  }

  /**
  * @dev Take up an existing swap that's a sell. Only swaps the taker's name to the swap creator's name.
   */
  function takeSell(uint256 swapId, uint256 takerId, string calldata placeholder1) external nonReentrant {
    NameSwap memory nameSwapPair = swapRecords[swapId];

    // Only succeeds if desired name is "" (empty string)
    require((bytes(nameSwapPair.name2).length == 0), "Not sell swap");

    // Move tokens from the taker's address to the swap proposer's address
    IERC20 token = IERC20(nameSwapPair.token);
    (, address swapProposer) = originalOwner.at(swapId);
    uint256 tokensToSeller = nameSwapPair.price.mul(PAID_AMOUNT).div(BASE);
    token.transferFrom(msg.sender, swapProposer, tokensToSeller);

    // Move tokens to XMON deployer to collect sale fee
    uint256 tokenFee = nameSwapPair.price.mul(FEE_AMOUNT).div(BASE);
    token.transferFrom(msg.sender, XMON_DEPLOYER, tokenFee);

    // Give taker's NFT to contract for escrow
    hashmask.transferFrom(msg.sender, address(this), takerId);

    // Transfer enough tokens to do the name change (we are only doing 2 swaps, so it's just the normal price)
    nct.transferFrom(msg.sender, address(this), NAME_CHANGE_PRICE);

    // set swapId to be placeholder
    hashmask.changeName(swapId, placeholder1);

    // Set takerId to be sawpId's name
    hashmask.changeName(takerId, nameSwapPair.name1);

    // Get the address of the other NFT's original owner
    address otherOwner = originalOwner.get(swapId);

    // Clean up records
    originalOwner.remove(swapId);
    delete swapRecords[swapId];

    // Transfer both NFTs back to their respective owners
    hashmask.transferFrom(address(this), msg.sender, takerId);
    hashmask.transferFrom(address(this), otherOwner, swapId);
  }

  /**
    @dev Take up an existing swap. Swaps the names and then returns the NFTs
    - Note: It is up to the caller to find a placeholder name that has not been used.
    - Front-ends can make this more convenient by selecting random strings.
   */
  function takeSwap(uint256 swapId, uint256 takerId, string calldata placeholder1) external nonReentrant {
    NameSwap memory nameSwapPair = swapRecords[swapId];

    // Require that taker's NFT's is actually the name requested by the swapPair
    // Both names are set to lowercase here
    require(sha256(bytes(hashmask.toLower(hashmask.tokenNameByIndex(takerId)))) ==
    sha256(bytes(hashmask.toLower(nameSwapPair.name2))), "Not desired name");

    // Give taker's NFT to contract for escrow
    hashmask.transferFrom(msg.sender, address(this), takerId);

    // Transfer enough tokens to do the name change (note this is also 150% the normal price because we are about to do 3 swaps)
    nct.transferFrom(msg.sender, address(this), MODIFIED_NAME_CHANGE_PRICE);

    // set swapId to be placeholder
    hashmask.changeName(swapId, placeholder1);

    // Set takerId to be sawpId's name
    hashmask.changeName(takerId, nameSwapPair.name1);

    // Set swapId to be takerId's name
    hashmask.changeName(swapId, nameSwapPair.name2);

    // Get the address of the other NFT's original owner
    address otherOwner = originalOwner.get(swapId);

    // Clean up records
    originalOwner.remove(swapId);
    delete swapRecords[swapId];

    // Transfer both NFTs back to their respective owners
    hashmask.transferFrom(address(this), msg.sender, takerId);
    hashmask.transferFrom(address(this), otherOwner, swapId);
  }

  function doubleNameSwap(uint256 id, string calldata name1, string calldata name2) external nonReentrant {

    // Give NFT to contract for escrow
    hashmask.transferFrom(msg.sender, address(this), id);

    // Transfer enough tokens to do the name change (note this is also 200%% the normal price because we are about to do 2 swaps)
    nct.transferFrom(msg.sender, address(this), NAME_CHANGE_PRICE.mul(2));

    // Set takerId to be first name
    hashmask.changeName(id, name1);

    // Set swapId to be second name
    hashmask.changeName(id, name2);

    hashmask.transferFrom(address(this), msg.sender, id);
  }

  // TODO: Separate this into open sales and open swaps
  function getAllOpenSwaps() public view returns(uint256[] memory) {
    uint256 len = originalOwner.length();
    uint256[] memory swapList = new uint256[](len);
    for (uint256 i = 0; i < len; i++) {
      (uint256 id, ) = originalOwner.at(i);
      swapList[i] = id;
    }
    return(swapList);
  }
}