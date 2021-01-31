const { mkdirSync } = require('fs');
const truffleAssert = require('truffle-assertions');
const maskArtifact = artifacts.require('./Testmasks.sol');
const nctArtifact = artifacts.require('./TestNCT.sol');
const swapperArtifact = artifacts.require('./HashmaskSwapper.sol');

let expected, results;
let amt = '100000000000000000000000000000000000';

contract("HashmaskSwapper tests", async accounts => {
  it ("correctly handles deposit/withdraw of swaps", async() => {
    let mask = await maskArtifact.deployed();
    let nct = await nctArtifact.deployed();
    let swapper = await swapperArtifact.deployed();

    // Mint id = 0 to accounts[0]
    await mask.mintNFT(1, {from: accounts[0]});

    // Mint a bunch of tokens to accounts[0]
    await nct.mint(accounts[0], web3.utils.toBN(amt), {from: accounts[0]});

    // Approve the swapper to spend NCT and Masks
    await mask.setApprovalForAll(swapper.address, true, {from: accounts[0]});
    await nct.approve(swapper.address, web3.utils.toBN(amt), {from: accounts[0]});

    // Set up swap for desired name
    await swapper.setSwap(0, 'hello', {from: accounts[0]});

    // Make sure other accounts can't remove th swap
    await truffleAssert.reverts(
      swapper.removeSwap(0, {from: accounts[1]}),
      "Not owner"
    )

    // Get back the swap
    await swapper.removeSwap(0, {from: accounts[0]});

    // Assert owner of NFT 0 is accounts[0]
    results = await mask.ownerOf(0);
    expect(results).to.eql(accounts[0]);

    // Assert balance is unchanged
    results = await nct.balanceOf(accounts[0]);
    expect(results).to.eql(web3.utils.toBN(amt));
  });
});

contract("HashmaskSwapper tests", async accounts => {
  it ("correctly handles deposit/withdraw of swaps even with multiple accounts", async() => {
    let mask = await maskArtifact.deployed();
    let nct = await nctArtifact.deployed();
    let swapper = await swapperArtifact.deployed();

    // Mint id = 0 to accounts[0], id = 1 to accounts[1]
    await mask.mintNFT(1, {from: accounts[0]});
    await mask.mintNFT(1, {from: accounts[1]});

    // Mint a bunch of tokens to accounts[0]
    await nct.mint(accounts[0], web3.utils.toBN(amt), {from: accounts[0]});
    await nct.mint(accounts[1], web3.utils.toBN(amt), {from: accounts[0]});

    // Approve the swapper to spend NCT and Masks
    await mask.setApprovalForAll(swapper.address, true, {from: accounts[0]});
    await nct.approve(swapper.address, web3.utils.toBN(amt), {from: accounts[0]});
    await mask.setApprovalForAll(swapper.address, true, {from: accounts[1]});
    await nct.approve(swapper.address, web3.utils.toBN(amt), {from: accounts[1]});

    // Expect that no one can set up a swap for a mask they don't own
    await truffleAssert.reverts(
      swapper.setSwap(0, 'hello', {from: accounts[1]}),
      "Not owner"
    );
    await truffleAssert.reverts(
      swapper.setSwap(1, 'hello', {from: accounts[0]}),
      "Not owner"
    );

    // Set up swap for desired name
    await swapper.setSwap(0, 'hello', {from: accounts[0]});
    await swapper.setSwap(1, 'test', {from: accounts[1]});

    // Make sure other accounts can't remove the swap
    await truffleAssert.reverts(
      swapper.removeSwap(0, {from: accounts[1]}),
      "Not owner"
    );
    await truffleAssert.reverts(
      swapper.removeSwap(1, {from: accounts[0]}),
      "Not owner"
    );

    // Get back the swap
    await swapper.removeSwap(0, {from: accounts[0]});
    await swapper.removeSwap(1, {from: accounts[1]});

    // Assert owner of NFT 0 is accounts[0] and owner of NFT 1 is accounts[1]
    results = await mask.ownerOf(0);
    expect(results).to.eql(accounts[0]);
    results = await mask.ownerOf(1);
    expect(results).to.eql(accounts[1]);

    // Assert balance is unchanged for both accounts[0]/[1]
    results = await nct.balanceOf(accounts[0]);
    expect(results).to.eql(web3.utils.toBN(amt));
    results = await nct.balanceOf(accounts[1]);
    expect(results).to.eql(web3.utils.toBN(amt));
  });
});

contract("HashmaskSwapper tests", async accounts => {
  it ("correctly swaps two names", async() => {
    let mask = await maskArtifact.deployed();
    let nct = await nctArtifact.deployed();
    let swapper = await swapperArtifact.deployed();

    // Mint id = 0 to accounts[0], id = 1 to accounts[1], id = 2 to accounts[2]
    await mask.mintNFT(1, {from: accounts[0]});
    await mask.mintNFT(1, {from: accounts[1]});
    await mask.mintNFT(1, {from: accounts[2]});

    // Mint a bunch of tokens to accounts[0]
    await nct.mint(accounts[0], web3.utils.toBN(amt), {from: accounts[0]});
    await nct.mint(accounts[1], web3.utils.toBN(amt), {from: accounts[0]});

    // Approve the swapper to spend NCT and Masks
    await mask.setApprovalForAll(swapper.address, true, {from: accounts[0]});
    await nct.approve(swapper.address, web3.utils.toBN(amt), {from: accounts[0]});

    await mask.setApprovalForAll(swapper.address, true, {from: accounts[1]});
    await nct.approve(swapper.address, web3.utils.toBN(amt), {from: accounts[1]});

    // Approve the Masks to spend NCT
    await nct.approve(mask.address, web3.utils.toBN(amt), {from: accounts[0]});
    await nct.approve(mask.address, web3.utils.toBN(amt), {from: accounts[1]});

    // Set name of NFT 0 to be "a" and NFT 0 to be "b"
    await mask.changeName(0, "a", {from: accounts[0]});
    await mask.changeName(1, "b", {from: accounts[1]});

    results = await mask.tokenNameByIndex(0);
    expect(results).to.eql("a");
    results = await mask.tokenNameByIndex(1);
    expect(results).to.eql("b");

    // Let account 0 set up a swap desiring b
    await swapper.setSwap(0, "b", {from: accounts[0]});

    // Expect revert to someone who doesn't have "b" as a name
    await truffleAssert.reverts(
      swapper.takeSwap(0, 2, "test", {from: accounts[2]}),
      "Not desired name"
    );

    // Take swap from accounts[1]
    await swapper.takeSwap(0, 1, "adihoahfa", {from: accounts[1]});

    // Expect that accounts[0] has NFT 0 with name "b"
    results = await mask.ownerOf(0);
    expect(results).to.eql(accounts[0]);
    results = await mask.tokenNameByIndex(0);
    expect(results).to.eql("b");

    // Expect that accounts[1] has NFT 1 with name "a"
    results = await mask.ownerOf(1);
    expect(results).to.eql(accounts[1]);
    results = await mask.tokenNameByIndex(1);
    expect(results).to.eql("a");
  });
});