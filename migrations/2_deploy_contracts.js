let mask = artifacts.require('./Testmasks.sol');
let nct = artifacts.require('./TestNCT.sol');
let swapper = artifacts.require('./HashmaskSwapper.sol');


module.exports = async(deployer) => {
  await deployer.deploy(nct);
  await deployer.deploy(mask, "TestMask", "TM", nct.address);
  await deployer.deploy(swapper, mask.address, nct.address);
}
