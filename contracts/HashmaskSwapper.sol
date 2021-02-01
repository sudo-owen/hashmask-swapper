// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "./IHashmask.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HashmaskSwapper is ReentrancyGuard {

  using EnumerableMap for EnumerableMap.UintToAddressMap;

  enum SwapType { Swap, Sell}  

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

    // Record the swap, names are all set to lowercase
    swapRecords[id] = NameSwap(
      hashmask.toLower(hashmask.tokenNameByIndex(id)),
      hashmask.toLower(desiredName),
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
   * desiredName is set to "" which will allow any tokenId to claim
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
    originalOwner.set(id, address(0));
    delete swapRecords[id];

    // Get back the original NFT
    hashmask.transferFrom(address(this), msg.sender, id);

    // Get back the funds put in
    nct.transfer(msg.sender, transferAmount);
  }

  /**
  * @dev Take up an existing swap that's a sell. Only swaps the taker's name to the swap creator's name.
   */
  function takeSell(uint256 swapId, uint256 takerId, string calldata placeholder1) external nonReentrant {
    NameSwap memory nameSwapPair = swapRecords[swapId];

    require((bytes(nameSwapPair.name2).length == 0), "Not sell swap");

    // Move tokens from the taker's address to the swap proposer's address
    IERC20 token = IERC20(nameSwapPair.token);
    (, address swapProposer) = originalOwner.at(swapId);
    token.transferFrom(msg.sender, swapProposer, nameSwapPair.price);

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
    originalOwner.set(swapId, address(0));
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
    originalOwner.set(swapId, address(0));
    delete swapRecords[swapId];

    // Transfer both NFTs back to their respective owners
    hashmask.transferFrom(address(this), msg.sender, takerId);
    hashmask.transferFrom(address(this), otherOwner, swapId);
  }

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