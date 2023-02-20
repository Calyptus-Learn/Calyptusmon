// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// preparing for some functions to be restricted
import "@openzeppelin/contracts/access/Ownable.sol";
// importing ERC721 token standard interface
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
// importing openzeppelin script to guard against re-entrancy
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// importing openzeppelin script to make contract pausable
import "@openzeppelin/contracts/security/Pausable.sol";
// importing merkle proof contract for whitelist verification
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
// importing uri storage contract
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract calyptusmonContract is
    ERC721,
    Ownable,
    ReentrancyGuard,
    Pausable,
    ERC721URIStorage
{
    // STATE VARIABLES

    // Only 12 calyptusmons can be created from scratch (generation 0)
    uint256 public GEN0_Limit = 12;
    uint256 public gen0amountTotal;
    // amount of NFTs total in existence - can be queried by showTotalSupply function
    uint256 public totalSupply;

    // whitelist rootHash
    bytes32 public root;

    // Base Uri : 'https://api.dicebear.com/5.x/bottts/svg?seed='
    string BaseUri;

    // STRUCT
    // this struct is the blueprint for new NFTs, they will be created from it
    struct calyptusmon {
        uint256 parent1Id;
        uint256 parent2Id;
        uint256 generation;
        uint256 genes;
        uint256 birthTime;
    }

    // ARRAYS
    // This is an array that holds all calyptusmons.
    // Their position in that array IS their tokenId.
    // they never get deleted here, array only grows and keeps track of them all.
    calyptusmon[] public allCalyptusmonsArray;

    // EVENTS

    // Creation event, emitted after successful NFT creation with these parameters
    event calyptusmonCreated(
        address owner,
        uint256 tokenId,
        uint256 parent1Id,
        uint256 parent2Id,
        uint256 genes
    );

    event BreedingSuccessful(
        uint256 tokenId,
        uint256 genes,
        uint256 birthTime,
        uint256 parent1Id,
        uint256 parent2Id,
        uint256 generation,
        address owner
    );

    // Constructor function
    // is setting _name, and _symbol
    constructor(
        bytes32 _hashRoot,
        string memory baseUri
    ) ERC721("calyptusmons", "calyptusmon") {
        root = _hashRoot;
        BaseUri = baseUri;
    }

    // Functions

    function _baseURI() internal view override returns (string memory) {
        return BaseUri;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function breed(
        uint256 _parent1Id,
        uint256 _parent2Id
    ) public whenNotPaused returns (uint256) {
        // _msgSender() needs to be owner of both crypto calyptusmons
        require(
            ownerOf(_parent1Id) == _msgSender() &&
                ownerOf(_parent2Id) == _msgSender(),
            "must be owner of both parent tokens"
        );

        // first 8 digits in DNA will be selected by dividing, solidity will round down everything to full integers
        uint256 _parent1genes = allCalyptusmonsArray[_parent1Id].genes;

        // second 8 digits in DNA will be selected by using modulo, it's whats left over and indivisible by 100000000
        uint256 _parent2genes = allCalyptusmonsArray[_parent2Id].genes;

        // calculating new DNA string with mentioned formulas
        uint256 _newDna = _mixDna(_parent1genes, _parent2genes);

        // calculate generation here
        uint256 _newGeneration = _calcGeneration(_parent1Id, _parent2Id);

        // creating new calyptusmon
        uint256 newCalyptusmonId = _createCalyptusmon(
            _parent1Id,
            _parent2Id,
            _newGeneration,
            _newDna,
            _msgSender()
        );

        emit BreedingSuccessful(
            newCalyptusmonId,
            allCalyptusmonsArray[newCalyptusmonId].genes,
            allCalyptusmonsArray[newCalyptusmonId].birthTime,
            allCalyptusmonsArray[newCalyptusmonId].parent1Id,
            allCalyptusmonsArray[newCalyptusmonId].parent2Id,
            allCalyptusmonsArray[newCalyptusmonId].generation,
            _msgSender()
        );

        return newCalyptusmonId;
    }

    function _calcGeneration(
        uint256 _parent1Id,
        uint256 _parent2Id
    ) internal view returns (uint256) {
        uint256 _generationOfParent1 = allCalyptusmonsArray[_parent1Id]
            .generation;
        uint256 _generationOfParent2 = allCalyptusmonsArray[_parent2Id]
            .generation;

        // new generation is average of parents generations plus 1
        // for ex. 1 + 5 = 6, 6/2 = 3, 3+1=4, newGeneration would be 4

        // rounding numbers if odd, for ex. 1+2=3, 3*10 = 30, 30/2 = 15
        // 15 % 10 = 5, 5>0, 15+5=20
        // 20 / 10 = 2, 2+1 = 3
        // newGeneration = 3
        uint256 _roundingNumbers = (((_generationOfParent1 +
            _generationOfParent2) * 10) / 2);
        if (_roundingNumbers % 10 > 0) {
            _roundingNumbers + 5;
        }
        uint256 newGeneration = (_roundingNumbers / 10) + 1;

        return newGeneration;
    }

    /**
     * @dev Returns a binary between 00000000-11111111
     */
    function _getRandom() internal view returns (uint8) {
        return uint8(block.timestamp % 255);
    }

    // will generate a pseudo random number and from that decide whether to take mom or dad genes, repeated for 8 pairs of 2 digits each
    function _mixDna(
        uint256 _parent1genes,
        uint256 _parent2genes
    ) internal view returns (uint256) {
        uint256[8] memory _geneArray;
        uint8 _random = _getRandom();
        uint8 index = 7;

        // BitShift: move to next binary bit
        for (uint256 i = 1; i <= 128; i = i * 2) {
            // Then add 2 last digits from the dna to the new dna
            if (_random & i != 0) {
                _geneArray[index] = uint8(_parent1genes % 100);
            } else {
                _geneArray[index] = uint8(_parent2genes % 100);
            }
            //each loop, take off the last 2 digits from the genes number string
            _parent1genes = _parent1genes / 100;
            _parent2genes = _parent2genes / 100;
            index = index--;
        }

        uint256 pseudoRandomAdv = uint256(
            keccak256(
                abi.encodePacked(
                    uint256(_random),
                    totalSupply,
                    allCalyptusmonsArray[allCalyptusmonsArray.length - 1].genes
                )
            )
        );

        // makes this number a 2 digit number between 10-98
        pseudoRandomAdv = (pseudoRandomAdv % 89) + 10;

        // setting first 2 digits in DNA string to random numbers
        _geneArray[0] = pseudoRandomAdv;

        uint256 newGeneSequence;

        // puts in last positioned array entry (2 digits) as first numbers, then adds 00, then adds again,
        // therefore reversing the backwards information in the array again to correct order
        for (uint256 j = 0; j < 8; j++) {
            newGeneSequence = newGeneSequence + _geneArray[j];

            // will stop adding zeros after last repetition
            if (j != 7) {
                newGeneSequence = newGeneSequence * 100;
            }
        }

        return newGeneSequence;
    }

    // gives back an array with the NFT tokenIds that the provided sender address owns
    // deleted NFTs are kept as entries with value 0 (token ID 0 is used by Zero calyptusmon)
    function findCalyptusmonIdsOfAddress(
        address NFTowner
    ) public view returns (uint256[] memory) {
        uint256 amountOwned = balanceOf(NFTowner);

        uint256 entryCounter = 0;

        uint256[] memory ownedTokenIDs = new uint256[](amountOwned);

        for (
            uint256 tokenIDtoCheck = 0;
            tokenIDtoCheck < totalSupply;
            tokenIDtoCheck++
        ) {
            if (ownerOf(tokenIDtoCheck) == NFTowner) {
                ownedTokenIDs[entryCounter] = tokenIDtoCheck;
                entryCounter++;
            }
        }

        return ownedTokenIDs;
    }

    // used for creating gen0 calyptusmons
    function createGen0Calyptusmon(
        uint256 _genes,
        bytes32[] calldata _merkleProof
    ) public {
        // verify if caller is in the whitelist
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
        require(
            MerkleProof.verify(_merkleProof, root, leaf),
            "Incorrect proof"
        );
        // making sure that no more than 12 calyptusmons will exist in gen0
        require(
            gen0amountTotal < GEN0_Limit,
            "Maximum amount of gen 0 calyptusmons reached"
        );

        // increasing counter of gen0 calyptusmons
        gen0amountTotal++;

        // creating
        _createCalyptusmon(0, 0, 0, _genes, _msgSender());
    }

    // used for creating calyptusmons (returns tokenId, could be used)
    function _createCalyptusmon(
        uint256 _parent1Id,
        uint256 _parent2Id,
        uint256 _generation,
        uint256 _genes,
        address _owner
    ) private whenNotPaused returns (uint256) {
        // uses the calyptusmon struct as template and creates a new calyptusmon from it
        calyptusmon memory newCalyptusmon = calyptusmon({
            parent1Id: uint256(_parent1Id),
            parent2Id: uint256(_parent2Id),
            generation: uint256(_generation),
            genes: _genes,
            birthTime: uint256(block.timestamp)
        });

        // updating total supply
        totalSupply++;

        // the push function also returns the length of the array, using that directly and saving it as the ID, starting with 0
        allCalyptusmonsArray.push(newCalyptusmon);
        uint256 newCalyptusmonId = allCalyptusmonsArray.length - 1;

        // after creation, transferring to new owner,
        // transferring address is user, sender is 0 address
        _safeMint(_owner, newCalyptusmonId);

        emit calyptusmonCreated(
            _owner,
            newCalyptusmonId,
            _parent1Id,
            _parent2Id,
            _genes
        );

        // tokenId is returned
        return newCalyptusmonId;
    }

    // gives back all the main details on a NFT
    function getCalyptusmonDetails(
        uint256 tokenId
    )
        public
        view
        returns (
            uint256 genes,
            uint256 birthTime,
            uint256 parent1Id,
            uint256 parent2Id,
            uint256 generation,
            address owner,
            address approvedAddress
        )
    {
        return (
            allCalyptusmonsArray[tokenId].genes,
            allCalyptusmonsArray[tokenId].birthTime,
            allCalyptusmonsArray[tokenId].parent1Id,
            allCalyptusmonsArray[tokenId].parent2Id,
            allCalyptusmonsArray[tokenId].generation,
            ownerOf(tokenId),
            getApproved(tokenId)
        );
    }

    // Returns the _totalSupply
    function showTotalSupply() public view returns (uint256) {
        return totalSupply;
    }

    // The following functions are overrides required by Solidity.

    function _burn(
        uint256 tokenId
    ) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
}
