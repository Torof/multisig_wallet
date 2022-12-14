// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract MultiSigWallet  is IERC721Receiver, IERC165{
    event Deposit(address indexed sender, uint amount);
    event Submit(uint indexed txId);
    event Approve(address indexed owner, uint indexed txId);
    event Revoke(address indexed owner, uint indexed txId);
    event Execute(uint indexed txId);
    event NFTreceived(address contractAddress, uint tokenId, address operator, address from, bytes data);

    /// TODO: add ERC1155 support
    struct Transaction {
        address to;
        bytes data;
        bool executed;
        uint index;
    }

    struct NFT {
        address contractAddress;
        uint tokenId;
        bytes4 standard;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;
    NFT[] public allNFTs;
    uint public required;

    Transaction[] public transactions;
    // mapping from tx id => owner => bool
    mapping(uint => mapping(address => bool)) public approved;

    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint _txId) {
        require(_txId < transactions.length, "tx does not exist");
        _;
    }

    modifier notApproved(uint _txId) {
        require(!approved[_txId][msg.sender], "tx already approved");
        _;
    }

    modifier notExecuted(uint _txId) {
        require(!transactions[_txId].executed, "tx already executed");
        _;
    }

    constructor(address[] memory _owners, uint _required) {
        require(_owners.length > 0, "owners required");
        require(
            _required > 0 && _required <= _owners.length,
            "invalid required number of owners"
        );

        for (uint i; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner is not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }

        required = _required;
    }
    
    receive() external payable {
        emit Deposit(msg.sender,msg.value);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4){
        allNFTs.push(NFT({contractAddress: msg.sender, tokenId: tokenId, standard: type(IERC721).interfaceId}));
        emit NFTreceived(msg.sender, tokenId, operator,from, data);
        return IERC721Receiver.onERC721Received.selector;
    }
    
    /// TODO:Submitting NFT transfer
    function submit(address _to, uint _txIndex, bytes calldata _data) external onlyOwner {
        transactions.push(Transaction({
            to: _to,
            index: _txIndex,
            data: _data,
            executed: false
        }));
        emit Submit(transactions.length -1);
    }
    
    function approve(uint _txId) external 
    onlyOwner 
    txExists(_txId) 
    notApproved(_txId) 
    notExecuted(_txId) 
    {
        approved[_txId][msg.sender] = true;
        emit Approve(msg.sender,_txId);
    } 
    
    ///TODO: add ERC1155 transfer
    function execute(uint _txId) external 
    onlyOwner
    txExists(_txId) 
    notExecuted(_txId) 
    {
        require(_getApprovalCount(_txId) >= required, "not enough approvals");
        Transaction storage tr = transactions[_txId];
        tr.executed = true;
        NFT memory nft = allNFTs[tr.index];
        if(nft.standard == type(IERC721).interfaceId) _transferERC721(nft.contractAddress,tr.to, nft.tokenId);
        emit Execute(_txId); 
    }
    
    function revoke(uint _txId) external onlyOwner txExists(_txId) notExecuted(_txId) {
        require(approved[_txId][msg.sender], "is not approved");
        approved[_txId][msg.sender] = false;
        emit Revoke(msg.sender, _txId);
    }

    function _getApprovalCount(uint _txId) private view returns (uint count){
        for(uint i = 0; i < owners.length; i++){
            if(approved[_txId][owners[i]]){
                count++;
            }
        }
    }

    function _transferERC721(address _contract, address _to, uint _tokenId) private {
        IERC721(_contract).safeTransferFrom(address(this), _to, _tokenId);
    }
}