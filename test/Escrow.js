const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MultiEscrow", function () {
  let MultiEscrow, multiEscrow, owner, firstOwner, addr1, addr2, addr3;

  beforeEach(async function () {
    [owner, firstOwner, addr1, addr2, addr3] = await ethers.getSigners();
    MultiEscrow = await ethers.getContractFactory("MultiEscrow");
    multiEscrow = await MultiEscrow.deploy(firstOwner.address);
    await multiEscrow.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await multiEscrow.owner()).to.equal(owner.address);
    });

    it("Should set the right first owner", async function () {
      expect(await multiEscrow.firstOwner()).to.equal(firstOwner.address);
    });
  });

  describe("Ownership", function () {
    it("Should transfer ownership", async function () {
      await multiEscrow.transferOwnership(addr1.address);
      expect(await multiEscrow.owner()).to.equal(addr1.address);
    });

    it("Should change first owner", async function () {
      await multiEscrow.changeFirstOwner(addr1.address);
      expect(await multiEscrow.firstOwner()).to.equal(addr1.address);
    });

    it("Should fail if non-owner tries to transfer ownership", async function () {
      await expect(multiEscrow.connect(addr1).transferOwnership(addr2.address)).to.be.revertedWith("Only owner can call this function");
    });
  });

  describe("Deposits", function () {
    it("Should accept deposits and update total ETH", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address]);
      await expect(multiEscrow.connect(firstOwner).depositEth([addr1.address], { value: depositAmount }))
        .to.emit(multiEscrow, "Deposit")
        .withArgs(firstOwner.address, depositAmount);
      
      expect(await multiEscrow.totalEth()).to.equal(depositAmount);
    });

    it("Should fail if deposit amount is zero", async function () {
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address]);
      await expect(multiEscrow.connect(firstOwner).depositEth([addr1.address])).to.be.revertedWith("amount > 0");
    });
  });

  describe("Whitelisting", function () {
    it("Should whitelist multiple accounts", async function () {
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address, addr2.address]);
      expect(await multiEscrow.whiteListAccounts(addr1.address)).to.be.true;
      expect(await multiEscrow.whiteListAccounts(addr2.address)).to.be.true;
    });

    it("Should remove an account from whitelist", async function () {
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address]);
      await multiEscrow.connect(firstOwner).removeFromWhitelist(addr1.address);
      expect(await multiEscrow.whiteListAccounts(addr1.address)).to.be.false;
    });
  });

  describe("Blacklisting", function () {
    it("Should blacklist a whitelisted address", async function () {
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address]);
      await multiEscrow.connect(firstOwner).blacklistAddress(addr1.address);
      expect(await multiEscrow.blackListAccounts(addr1.address)).to.be.true;
    });

    it("Should fail to blacklist a non-whitelisted address", async function () {
      await expect(multiEscrow.connect(firstOwner).blacklistAddress(addr1.address)).to.be.revertedWith("Address not whitelisted");
    });
  });

  describe("Distribution and Allocation", function () {
    it("Should distribute ETH equally among beneficiaries", async function () {
      const depositAmount = ethers.utils.parseEther("3");
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address, addr2.address, addr3.address]);
      await multiEscrow.connect(firstOwner).depositEth([addr1.address, addr2.address, addr3.address], { value: depositAmount });
      
      const expectedShare = depositAmount.div(3);
      expect(await multiEscrow.allocations(addr1.address)).to.equal(expectedShare);
      expect(await multiEscrow.allocations(addr2.address)).to.equal(expectedShare);
      expect(await multiEscrow.allocations(addr3.address)).to.equal(expectedShare);
    });

    it("Should allow custom allocation", async function () {
      const depositAmount = ethers.utils.parseEther("3");
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address, addr2.address]);
      await multiEscrow.connect(firstOwner).depositEth([addr1.address, addr2.address], { value: depositAmount });
      
      const allocations = [ethers.utils.parseEther("1"), ethers.utils.parseEther("2")];
      await multiEscrow.connect(firstOwner).customAllocation(allocations);
      
      expect(await multiEscrow.allocations(addr1.address)).to.equal(allocations[0]);
      expect(await multiEscrow.allocations(addr2.address)).to.equal(allocations[1]);
    });
  });

  describe("Withdrawals", function () {
    it("Should allow whitelisted address to withdraw", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address]);
      await multiEscrow.connect(firstOwner).depositEth([addr1.address], { value: depositAmount });
      
      await expect(() => multiEscrow.connect(addr1).withdraw())
        .to.changeEtherBalance(addr1, depositAmount);
    });

    it("Should fail if blacklisted address tries to withdraw", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address]);
      await multiEscrow.connect(firstOwner).depositEth([addr1.address], { value: depositAmount });
      await multiEscrow.connect(firstOwner).blacklistAddress(addr1.address);
      
      await expect(multiEscrow.connect(addr1).withdraw()).to.be.revertedWith("Beneficiary is blacklisted");
    });
  });

  describe("Fund Recovery", function () {
    it("Should recover funds from blacklisted addresses", async function () {
      const depositAmount = ethers.utils.parseEther("2");
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address, addr2.address]);
      await multiEscrow.connect(firstOwner).depositEth([addr1.address, addr2.address], { value: depositAmount });
      await multiEscrow.connect(firstOwner).blacklistAddress(addr1.address);
      await multiEscrow.connect(firstOwner).blacklistAddress(addr2.address);
      
      await expect(() => multiEscrow.connect(firstOwner).recoverBlacklistedFunds([addr1.address, addr2.address]))
        .to.changeEtherBalance(firstOwner, depositAmount);
    });
  });

  describe("Utility Functions", function () {
    it("Should return correct contract balance", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address]);
      await multiEscrow.connect(firstOwner).depositEth([addr1.address], { value: depositAmount });
      expect(await multiEscrow.getBalance()).to.equal(depositAmount);
    });

    it("Should return correct account status", async function () {
      await multiEscrow.connect(firstOwner).whitelistAccounts([addr1.address]);
      await multiEscrow.connect(firstOwner).blacklistAddress(addr1.address);
      
      const [isWhitelisted, isBlacklisted] = await multiEscrow.getStatus(addr1.address);
      expect(isWhitelisted).to.be.true;
      expect(isBlacklisted).to.be.true;
    });
  });
});