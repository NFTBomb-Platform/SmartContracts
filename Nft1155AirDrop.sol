pragma solidity ^0.8.0;
// 0xc210c65F8141B71ebac23456d017671196dD3947

interface IaddressController {
    function isManager(address _mAddr) external view returns(bool);
    function getAddr(string calldata _name) external view returns(address);
}

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./utils/math/SafeMath.sol";
import "./IKibombNft721Role.sol";



contract Nft1155AirDropWhiteList is ERC1155Holder,ERC721Holder {

    IaddressController public addrc;

    address public owner;

        // 1155 nft addrss => nft id => nft claim count 
    mapping(address => mapping(uint256 => uint256)) public redeemCount;  // redeemCount
        // 1155 nft addrss => nft id => nft721 address; // for nft721 airdrop
    mapping(address => mapping(uint256 => address)) public nft721s;  // redeemCount

        // 1155 nft addrss => nft id => user whitelist 
    mapping(address=>mapping(uint256=>bytes32)) public whiteList;        // whiteLIst is a merkel tree root of target addresses

        // asset address => asset id => user wallet address => bool
    mapping (address => 
        mapping(uint256 => 
            mapping(address=>bool))) public isRedeemed ;                 // make sure one account can redeem only once

    modifier onlyManager(){
        require(addrc.isManager(msg.sender),"onlyManager"); 
        _;
    }

    modifier markRedeemed(address nftAddr, uint256 tokenId, address user){
        _;
        isRedeemed[nftAddr][tokenId][user] = true;
    }

    constructor(IaddressController _addrc) public {
        addrc = _addrc;
    }

    
    function depositAsset(address nftAddr_, uint256 tokenId_, uint256 amount_, address nft721_) external onlyManager{
        require(nftAddr_!=address(0),"WL: invalid address");
        require(amount_ > 0, "WL: invalid amount");
        IERC1155(nftAddr_).safeTransferFrom(msg.sender, address(this), tokenId_, amount_, "0x00");
        redeemCount[nftAddr_][tokenId_] = amount_;          // 设置剩余的1155的数量, claim时 --
        nft721s[nftAddr_][tokenId_] = nft721_;              // 设置nft721地址
        emit Deposit(nftAddr_, tokenId_, amount_);
    }
    event Deposit(address indexed nftAddr, uint256 tokenId, uint256 amount);

    function claimAirDrop(address nftAddr_, uint256 tokenId_, bytes32[] calldata proof) external {
        address account_ = msg.sender;
        checkWhiteList(nftAddr_, tokenId_, account_, proof);  // 1. check 
        claimAsset(nftAddr_, tokenId_, 1);                    // 2. claim
        isRedeemed[nftAddr_][tokenId_][account_] = true;
    }

    function claimAsset(address nftAddr_, uint256 tokenId_, uint256 amount_) internal {
        uint256 remain = redeemCount[nftAddr_][tokenId_];                                           // check tokens remain
        require(remain >= amount_, "WL: no tokens remain");
        redeemCount[nftAddr_][tokenId_] = remain - amount_;                                         // redeem count --
        address nft721 = nft721s[nftAddr_][tokenId_];
        if(nft721 != address(0)){
           IERC1155(nftAddr_).safeTransferFrom(address(this), nft721, tokenId_, amount_, "0x00");  // transfer nft
           IKibombNft721Role(nft721).safeMint(msg.sender);
           return;
        }
        IERC1155(nftAddr_).safeTransferFrom(address(this), msg.sender, tokenId_, amount_, "0x00");  // transfer nft
        emit Claim(nftAddr_, tokenId_, amount_, msg.sender);                                        // log 
    }
    event Claim(address indexed nftAddr, uint256 tokenId, uint256 amount, address claimer);

    /**
     *   @dev submit the whitelist merkle tree root
     *   @param nftAddr_  nft address for airdrop
     *   @param tokenId_  target nft id
     *   @param whitelistroot_  merkle tree root of the whitelist
     */
    function setWhiteList(address nftAddr_, uint256 tokenId_, bytes32 whitelistroot_) external onlyManager {
        whiteList[nftAddr_][tokenId_] = whitelistroot_;
    }

    /**
    *   @dev vaildation of target address
    *   @param account address of user who want to claim the airdrop
    *   @param proof byty32 proof related to this user address
    */
    function checkWhiteList(address nftAddr_, uint256 tokenId_, address account, bytes32[] memory proof)
    public view
    returns (bool)
    {
        require(_verify(nftAddr_, tokenId_, _leaf(account), proof), "Invalid merkle proof"); // airdrop can only redeem once
        require(!isRedeemed[nftAddr_][tokenId_][account] ,"Can not redeem again");           // count the claim number
        return true;
    }

    function _leaf(address _account) internal pure returns (bytes32){
        return keccak256(abi.encodePacked(_account));
    }

    function _verify(address nftAddr_, uint256 tokenId_, bytes32 leaf, bytes32[] memory proof) internal view returns (bool) {
        return MerkleProof.verify(proof, whiteList[nftAddr_][tokenId_], leaf);
    }
}
