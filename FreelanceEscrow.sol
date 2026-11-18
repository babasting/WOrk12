// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FreelanceEscrow {
    enum Status { Created, Funded, Submitted, Completed, Disputed, Refunded }
    struct Job {
        address payable client;
        address payable freelancer;
        string title;
        string details;
        uint256 amount;
        Status status;
        string workProof;
    }
    uint256 public jobCount;
    mapping(uint256 => Job) private jobs;
    address public immutable arbiter;
    uint256 private lockState = 1;
    event JobCreated(uint256 indexed jobId, address indexed client, address indexed freelancer, uint256 amount);
    event Deposited(uint256 indexed jobId, uint256 amount);
    event WorkSubmitted(uint256 indexed jobId, string proof);
    event PaymentReleased(uint256 indexed jobId, address indexed freelancer, uint256 amount);
    event DisputeOpened(uint256 indexed jobId, address indexed by);
    event DisputeResolved(uint256 indexed jobId, bool paidFreelancer);
    modifier nonReentrant() { require(lockState == 1, "Reentrant call"); lockState = 2; _; lockState = 1; }
    modifier jobExists(uint256 id) { require(id > 0 && id <= jobCount, "Job not found"); _; }
    constructor() { arbiter = msg.sender; }
    function createJob(address payable freelancer, string calldata title, string calldata details, uint256 amount) external returns (uint256) {
        require(freelancer != address(0) && freelancer != msg.sender, "Invalid freelancer");
        require(amount > 0, "Amount must be positive");
        require(bytes(title).length > 0, "Title required");
        uint256 id = ++jobCount;
        jobs[id] = Job(payable(msg.sender), freelancer, title, details, amount, Status.Created, "");
        emit JobCreated(id, msg.sender, freelancer, amount);
        return id;
    }
    function deposit(uint256 id) external payable jobExists(id) {
        Job storage j = jobs[id];
        require(msg.sender == j.client, "Client only");
        require(j.status == Status.Created, "Not awaiting deposit");
        require(msg.value == j.amount, "Send exact amount");
        j.status = Status.Funded;
        emit Deposited(id, msg.value);
    }
    function submitWork(uint256 id, string calldata proof) external jobExists(id) {
        Job storage j = jobs[id];
        require(msg.sender == j.freelancer, "Freelancer only");
        require(j.status == Status.Funded, "Job not funded");
        require(bytes(proof).length > 0, "Proof required");
        j.workProof = proof;
        j.status = Status.Submitted;
        emit WorkSubmitted(id, proof);
    }
    function approveAndRelease(uint256 id) external nonReentrant jobExists(id) {
        Job storage j = jobs[id];
        require(msg.sender == j.client, "Client only");
        require(j.status == Status.Submitted, "Work not submitted");
        j.status = Status.Completed;
        (bool ok,) = j.freelancer.call{value: j.amount}("");
        require(ok, "Payment failed");
        emit PaymentReleased(id, j.freelancer, j.amount);
    }
    function openDispute(uint256 id) external jobExists(id) {
        Job storage j = jobs[id];
        require(msg.sender == j.client || msg.sender == j.freelancer, "Not a participant");
        require(j.status == Status.Funded || j.status == Status.Submitted, "Cannot dispute");
        j.status = Status.Disputed;
        emit DisputeOpened(id, msg.sender);
    }
    function resolveDispute(uint256 id, bool payFreelancer) external nonReentrant jobExists(id) {
        require(msg.sender == arbiter, "Arbiter only");
        Job storage j = jobs[id];
        require(j.status == Status.Disputed, "Not disputed");
        j.status = payFreelancer ? Status.Completed : Status.Refunded;
        address payable recipient = payFreelancer ? j.freelancer : j.client;
        (bool ok,) = recipient.call{value: j.amount}("");
        require(ok, "Transfer failed");
        emit DisputeResolved(id, payFreelancer);
    }
    function getJob(uint256 id) external view jobExists(id) returns (Job memory) { return jobs[id]; }
}
