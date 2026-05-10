// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract VerifierRegistry {
    mapping(string => address) public verifiers;
    string[] public verifierNames;
    address public owner;

    event VerifierRegistered(string name, address verifier);
    event VerifierUnregistered(string name);

    error NotOwner();
    error VerifierNotFound();
    error ZeroAddress();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Transfer registry owner (typically to governance after bootstrap registration).
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function register(string calldata name, address verifier) external onlyOwner {
        if (verifiers[name] == address(0)) {
            verifierNames.push(name);
        }
        verifiers[name] = verifier;
        emit VerifierRegistered(name, verifier);
    }

    function unregister(string calldata name) external onlyOwner {
        address v = verifiers[name];
        if (v == address(0)) revert VerifierNotFound();
        delete verifiers[name];
        uint256 len = verifierNames.length;
        for (uint256 i = 0; i < len; i++) {
            if (keccak256(bytes(verifierNames[i])) == keccak256(bytes(name))) {
                verifierNames[i] = verifierNames[len - 1];
                verifierNames.pop();
                break;
            }
        }
        emit VerifierUnregistered(name);
    }

    function get(string calldata name) external view returns (address) {
        address v = verifiers[name];
        if (v == address(0)) revert VerifierNotFound();
        return v;
    }

    function getAllNames() external view returns (string[] memory) {
        return verifierNames;
    }
}
