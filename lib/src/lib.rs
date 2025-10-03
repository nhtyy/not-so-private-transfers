mod relay;
use alloy::primitives::{B256, FixedBytes, b256};
pub use relay::{RelayAuthentication, auth_domain};

mod config;
pub use config::{ChainConfig, Config};

pub const INIT_CODE_HASH: B256 =
    b256!("0x62e14bf431c1d9122ac5bd07b039cf9bbd14ef67657d530332cc61533071fac8");

/// Generate a cryptographically secure random salt for a wallet.
pub fn random_salt() -> B256 {
    B256::random()
}

#[cfg(test)]
mod test {
    use std::path::PathBuf;
    use std::process::Command;

    use alloy::network::EthereumWallet;
    use alloy::primitives::utils::parse_ether;
    use alloy::primitives::U256;
    use alloy::providers::Provider;
    use alloy::rpc::types::TransactionRequest;
    use alloy::signers::local::LocalSigner;

    use crate::Config;

    // The manifest directory is the directory of the crate.
    const MANIFEST_DIR: &str = env!("CARGO_MANIFEST_DIR");

    /// Check if a command is installed.
    fn check_command_installed(command: &str) {
        if Command::new("which").arg(command).output().is_err() {
            panic!("command `{}` not found in PATH", command);
        }
    }

    #[test]
    fn check_init_code_hash_matches_const() {
        check_command_installed("forge");

        let init_code_hex_0x_prefixed = Command::new("forge")
            .arg("inspect")
            .arg("Wallet")
            .arg("bytecode")
            .arg("--no-metadata")
            .current_dir(
                PathBuf::from(MANIFEST_DIR)
                    .parent()
                    .unwrap()
                    .join("contracts"),
            )
            .output()
            .expect("Failed to execute `forge inspect Wallet bytecode`")
            .stdout;

        let init_code_hex_string_0x_prefixed =
            String::from_utf8(init_code_hex_0x_prefixed).expect("Failed to decode init code");
        let init_code_hex_string = init_code_hex_string_0x_prefixed
            .trim()
            .trim_start_matches("0x");

        let init_code = hex::decode(init_code_hex_string).expect("Failed to decode init code");
        let init_code_hash = alloy::primitives::keccak256(&init_code);

        assert_eq!(init_code_hash, super::INIT_CODE_HASH);
    }

    #[tokio::test]
    async fn test_can_create_wallet_with_relay_from_rust() {
        check_command_installed("forge");
        check_command_installed("anvil");

        let anvil = alloy::node_bindings::Anvil::new().spawn();
        let anvil_private_key_0 = anvil.keys()[0].clone();
        let anvil_private_key_0_signer =
            LocalSigner::from_signing_key(anvil_private_key_0.clone().into());
        let wallet = EthereumWallet::new(anvil_private_key_0_signer.clone());
        let provider = alloy::providers::ProviderBuilder::new()
            .wallet(wallet)
            .connect_http(anvil.endpoint_url());

        let output = Command::new("forge")
            .arg("script")
            .arg("script/Protocol.s.sol")
            .arg("--rpc-url")
            .arg(anvil.endpoint())
            .arg("--private-key")
            .arg(format!("0x{}", hex::encode(anvil_private_key_0.to_bytes())))
            .arg("--broadcast")
            .current_dir(
                PathBuf::from(MANIFEST_DIR)
                    .parent()
                    .unwrap()
                    .join("contracts"),
            )
            .output()
            .expect("Failed to execute `forge script Relay.s.sol:RelayScript`");

        if !output.status.success() {
            eprintln!("stderr: {}", String::from_utf8_lossy(&output.stderr));
            eprintln!("stdout: {}", String::from_utf8_lossy(&output.stdout));
            panic!("Failed to execute `forge script Relay.s.sol:RelayScript`");
        }

        // Parse the deployments.json file.
        let deployments: Config = Config::parse_json(
            PathBuf::from(MANIFEST_DIR)
                .parent()
                .unwrap()
                .join("contracts")
                .join("deployments.json"),
        )
        .unwrap();

        // Ensure the Deployer is setup correctly.
        let anvil_config = deployments.get(anvil.chain_id()).unwrap();
        assert!(
            provider
                .get_code_at(anvil_config.verifying_contract)
                .await
                .expect("Failed to get code")
                .len()
                > 0,
            "expected verifying contract to be deployed"
        );

        // Create a random salt / wallet and send 1 ether to it.
        let salt = super::random_salt();
        let wallet_address = anvil_config.predict_address(salt, anvil.addresses()[0]);
        let one_ether = parse_ether("1").expect("Failed to parse 1 ether");

        // First send 1 ether to the wallet
        provider
            .send_transaction(
                TransactionRequest::default()
                    .to(wallet_address)
                    .value(one_ether),
            )
            .await
            .expect("Failed to send 1 ether to the wallet")
            .watch()
            .await
            .expect("Failed to watch transaction");

        // Check that the balance is actually 1 ether
        assert_eq!(
            provider
                .get_balance(wallet_address)
                .await
                .expect("Failed to get balance"),
            one_ether
        );

        // Send 1 ether back from the wallet to the owner.
        let auth = super::RelayAuthentication {
            owner: anvil_private_key_0_signer.address(),
            salt,
            to: anvil_private_key_0_signer.address(),
            value: one_ether,
            data: Default::default(),
        };

        let signature = auth
            .sign(&anvil_private_key_0_signer, anvil_config.domain())
            .await
            .expect("Failed to sign auth");

        let deployer = crate::relay::Deployer::new(anvil_config.verifying_contract, &provider);
        let tx_hash = deployer
            .relayDeploy(auth, signature.as_bytes().into())
            .send()
            .await
            .expect("Failed to send deploy")
            .watch()
            .await
            .expect("Failed to watch deploy");

        let reciept = provider.get_transaction_receipt(tx_hash).await.expect("Failed to get transaction receipt").expect("Failed to get reciept");
        let as_event = reciept.decode_first_log::<crate::relay::Deployer::Deployed>().expect("Failed to decode event");

        // Assert that the wallet created was the one we predicted.
        assert_eq!(as_event.wallet, wallet_address);

        // Ensure the wallet has no balance.
        assert_eq!(
            provider
                .get_balance(wallet_address)
                .await
                .expect("Failed to get balance"),
            U256::ZERO,
        );
    }
}
