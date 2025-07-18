// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { ProductionVault } from "../contracts/ProductionVault.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockERC20 is IERC20Metadata {
    string public constant name = "MockBVP";
    string public constant symbol = "MBVP";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 public override totalSupply;

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract ProductionVaultTest is Test {
    ProductionVault public vault;
    MockERC20 public token;

    address admin = address(0x1);
    address producer = address(0x2);
    address approver1 = address(0x3);
    address approver2 = address(0x4);

    bytes32 constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    bytes32 internal projectId;
    uint256[] internal milestones;
    address[] internal approvers;

    function setUp() public {
        token = new MockERC20();
        vault = new ProductionVault(address(token));

        token.mint(admin, 1_000_000 ether);

        vm.prank(admin);
        token.approve(address(vault), 1_000_000 ether);

        // address(this) is the deployer and has DEFAULT_ADMIN_ROLE by default
        vault.grantRole(ROLE_ADMIN, admin);

        projectId = keccak256("project1");

        milestones = [uint256(300 ether), 700 ether];
        approvers = [approver1, approver2];

        vm.startPrank(admin);
        vault.createProject(projectId, "Test Project", 1000 ether, milestones, producer, approvers);
        vm.stopPrank();
    }

    function testApproveMilestoneAndRelease() public {
        vm.prank(approver1);
        vault.approveMilestone(projectId);

        vm.prank(approver2);
        vault.approveMilestone(projectId);

        assertEq(token.balanceOf(producer), 300 ether);
    }

    function testCancelAndWithdraw() public {
        vm.prank(admin);
        vault.cancelProject(projectId);

        vm.prank(producer);
        vault.withdrawRemaining(projectId);

        assertEq(token.balanceOf(producer), 1000 ether);
    }

    function testRejectDuplicateProject() public {
        vm.startPrank(admin);
        vm.expectRevert("Project already exists");
        vault.createProject(projectId, "Dup", 1000 ether, milestones, producer, approvers);
        vm.stopPrank();
    }

    function testRejectNonApproverApproval() public {
        vm.prank(address(0x5));
        vm.expectRevert("Not approver");
        vault.approveMilestone(projectId);
    }

    function testRejectDoubleApproval() public {
        vm.prank(approver1);
        vault.approveMilestone(projectId);

        vm.prank(approver1);
        vm.expectRevert("Already approved");
        vault.approveMilestone(projectId);
    }

    function testRejectWithdrawIfNotProducer() public {
        vm.prank(admin);
        vault.cancelProject(projectId);

        vm.prank(approver1);
        vm.expectRevert("Not producer");
        vault.withdrawRemaining(projectId);
    }

    function testRejectWithdrawIfNotCanceled() public {
        vm.prank(producer);
        vm.expectRevert("Project not canceled");
        vault.withdrawRemaining(projectId);
    }
}
