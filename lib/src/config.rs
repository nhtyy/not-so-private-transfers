use std::collections::HashMap;
use std::path::Path;

use alloy::{
    primitives::{Address, B256},
    sol_types::Eip712Domain,
};
use serde_json::Error as JsonError;

use crate::auth_domain;

/// A mapping of chain ids to [`ChainConfig`].
#[derive(Debug, Clone)]
pub struct Config {
    inner: HashMap<u64, Address>,
}

impl Config {
    /// Create a new config.
    pub fn new(inner: HashMap<u64, Address>) -> Self {
        Self { inner }
    }

    /// Parse the config from a file that looks a JSON encoding of hashmap:
    /// u64 (chain_id) => address (verifying contract)
    pub fn parse_json<P: AsRef<Path>>(path: P) -> Result<Self, ConfigError> {
        let file = std::fs::File::open(path)?;

        Ok(Self::new(serde_json::from_reader(file)?))
    }

    /// Get the chain config for a given chain id.
    pub fn get(&self, chain_id: u64) -> Option<ChainConfig> {
        self.inner.get(&chain_id).map(|address| ChainConfig {
            verifying_contract: *address,
            chain_id,
            domain: auth_domain(chain_id, *address),
        })
    }
}

/// Configuration for a given chain.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ChainConfig {
    pub verifying_contract: Address,
    pub chain_id: u64,
    pub domain: Eip712Domain,
}

impl ChainConfig {
    pub fn domain(&self) -> &Eip712Domain {
        &self.domain
    }

    pub fn predict_address(&self, salt: B256, owner: Address) -> Address {
        let mut salt_bytes = salt.to_vec();
        salt_bytes.extend_from_slice(owner.as_slice());

        let actual_salt = alloy::primitives::keccak256(&salt_bytes);

        self.verifying_contract
            .create2(actual_salt, crate::INIT_CODE_HASH)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("IO Error: {}", .0)]
    Io(#[from] std::io::Error),
    #[error("SerdeJson Error {}", .0)]
    Json(#[from] JsonError),
}
