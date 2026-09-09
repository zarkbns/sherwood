// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ERC721
/// @notice Lean, self-contained ERC721. No enumeration, no metadata. Deliberately
///         dependency-free so the build never requires network access.
interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

abstract contract ERC721 {
    string public name;
    string public symbol;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    error ERC721NonexistentToken(uint256 tokenId);
    error ERC721InvalidOwner(address owner);
    error ERC721InvalidReceiver(address receiver);
    error ERC721Unauthorized(address sender, uint256 tokenId);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function balanceOf(address account) public view returns (uint256) {
        if (account == address(0)) revert ERC721InvalidOwner(address(0));
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert ERC721NonexistentToken(tokenId);
        return tokenOwner;
    }

    function approve(address to, uint256 tokenId) public {
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner && !isApprovedForAll(tokenOwner, msg.sender)) {
            revert ERC721Unauthorized(msg.sender, tokenId);
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        if (_owners[tokenId] == address(0)) revert ERC721NonexistentToken(tokenId);
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert ERC721InvalidReceiver(address(0));
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner && msg.sender != getApproved(tokenId) && !isApprovedForAll(tokenOwner, msg.sender)) {
            revert ERC721Unauthorized(msg.sender, tokenId);
        }
        if (tokenOwner != from) revert ERC721Unauthorized(msg.sender, tokenId);
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, "") returns (bytes4 selector) {
                if (selector != IERC721Receiver.onERC721Received.selector) revert ERC721InvalidReceiver(to);
            } catch {
                revert ERC721InvalidReceiver(to);
            }
        }
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        delete _tokenApprovals[tokenId];
        emit Transfer(from, to, tokenId);
    }

    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert ERC721InvalidReceiver(address(0));
        if (_owners[tokenId] != address(0)) revert ERC721InvalidReceiver(to);
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }
}
