# Not So Private Transfers

This repo establishes a basic set of contracts and a corresponding Rust library for creating "not so private transfers". 
In other words, we can create an ephermal account at a determinsitic address, such that we can later sweep the funds from this account,
without explicity funding it.

The purpose of this is to give a sort of "burner" wallet to recieive funds, that at first, doesnt reveal your actual wallet address to the whoever needs
to interact with this address.

Currently, this repo uses create2 to deploy to a determinstic address and atomically do some call operation, this could be like sending Eth or interacting with an ERC20.

In the future this could be done better by using using clones, or ideally, rewriting the `Wallet.sol` contract to just be some short sequence of opcodes, as the logic is quite simple.

Note that we dont want to do the sweep in the constructor, as that would change the `init_code_hash`, efficively making you commit to call youre going to make for determinism.

## Layout

### `lib/`

- This is a Rust library for interacting with the `Deployer`, signing relayed messages, and computing addresses.

### `contracts/`

- This is the solidity implentation of the "Not So Private Transfers" protocol.