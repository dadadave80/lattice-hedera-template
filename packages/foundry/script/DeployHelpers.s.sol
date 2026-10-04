//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";

/// @title ScaffoldETHDeploy
/// @notice Scaffold-ETH's base for deploy scripts that write `deployments/<chainId>.json`. Here only
///         `DeployTokenSaleV2` uses it; the diamond scripts extend Lattice's `BaseDeploy` instead.
contract ScaffoldETHDeploy is Script {
    /// @notice No endpoint in `foundry.toml`'s `[rpc_endpoints]` serves the current chain.
    error InvalidChain();
    /// @notice The deployer has no balance to pay for the deployment.
    error DeployerHasNoBalance();
    /// @notice The broadcast resolved to no deployer address.
    error InvalidPrivateKey(string);

    /// @notice Emitted when a local Anvil deployer with no balance is funded.
    /// @param account The deployer.
    /// @param amount The balance set, in wei.
    event AnvilSetBalance(address account, uint256 amount);
    /// @notice Emitted when funding the Anvil deployer failed.
    event FailedAnvilRequest();

    /// @notice One contract to record in `deployments/<chainId>.json`.
    struct Deployment {
        string name;
        address addr;
    }

    string root;
    string path;
    /// @notice What `run` deployed, in order. `exportDeployments` writes it out.
    Deployment[] public deployments;
    uint256 constant ANVIL_BASE_BALANCE = 10000 ether;

    /// @notice The deployer address for every run
    address deployer;

    /// @notice Use this modifier on your run() function on your deploy scripts. It broadcasts the body and then
    ///         writes every entry of `deployments` to `deployments/<chainId>.json`.
    modifier ScaffoldEthDeployerRunner() {
        deployer = _startBroadcast();
        if (deployer == address(0)) {
            revert InvalidPrivateKey("Invalid private key");
        }
        _;
        _stopBroadcast();
        exportDeployments();
    }

    function _startBroadcast() internal returns (address) {
        vm.startBroadcast();
        (, address _deployer,) = vm.readCallers();

        if (block.chainid == 31337 && _deployer.balance == 0) {
            try vm.deal(_deployer, ANVIL_BASE_BALANCE) {
                emit AnvilSetBalance(_deployer, ANVIL_BASE_BALANCE);
            } catch {
                emit FailedAnvilRequest();
            }
        }
        return _deployer;
    }

    function _stopBroadcast() internal {
        vm.stopBroadcast();
    }

    function exportDeployments() internal {
        // fetch already existing contracts
        root = vm.projectRoot();
        path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory jsonWrite;

        uint256 len = deployments.length;

        for (uint256 i = 0; i < len; i++) {
            vm.serializeString(jsonWrite, vm.toString(deployments[i].addr), deployments[i].name);
        }

        string memory chainName;

        try vm.getChain(block.chainid) returns (Vm.Chain memory chain) {
            chainName = chain.name;
        } catch {
            chainName = findChainName();
        }
        jsonWrite = vm.serializeString(jsonWrite, "networkName", chainName);
        vm.writeJson(jsonWrite, path);
    }

    /// @notice The name `foundry.toml`'s `[rpc_endpoints]` gives the current chain, for chains forge-std does not
    ///         know. Forks each endpoint in turn to read its chain id.
    /// @return The endpoint's name. Reverts with `InvalidChain` if no endpoint serves the current chain.
    function findChainName() public returns (string memory) {
        uint256 thisChainId = block.chainid;
        string[2][] memory allRpcUrls = vm.rpcUrls();
        for (uint256 i = 0; i < allRpcUrls.length; i++) {
            try vm.createSelectFork(allRpcUrls[i][1]) {
                if (block.chainid == thisChainId) {
                    return allRpcUrls[i][0];
                }
            } catch {
                continue;
            }
        }
        revert InvalidChain();
    }
}
