use alloy::{
    dyn_abi::Eip712Domain,
    primitives::{Address, Uint},
    signers::{Error as SignerError, Signature, Signer},
    sol_types::SolStruct,
};

alloy::sol! {
    /// @dev Struct for the relay authentication.
    struct RelayAuthentication {
        address owner;
        bytes32 salt;
        address to;
        uint256 value;
        bytes data;
    }

    #[sol(rpc)]
    contract Deployer {
        /// @dev Error thrown when an authentication is already used.
        error AuthenticationAlreadyUsed();
        /// @dev Error thrown when an invalid signer is provided.
        error InvalidSigner(address signer, address owner);

        /// @dev Error thrown when a wallet is not deployed.
        error WalletNotDeployed();

        /// @dev Event emitted when a wallet is deployed.
        event Deployed(address indexed owner, bytes32 indexed salt, address indexed wallet);

        /// @notice Deploy a wallet.
        /// @param salt The salt of the wallet.
        /// @param to The address to call.
        /// @param value The value to send.
        /// @param data The data to send.
        function deploy(bytes32 salt, address to, uint256 value, bytes memory data);

        /// @notice Deploy a wallet with a relayer covering the gas costs.
        /// @param relayAuthentication The relayer
        /// @param signature The signature of the relay authentication.
        function relayDeploy(RelayAuthentication calldata relayAuthentication, bytes memory signature);

        /// @notice Make a call to the wallet as the owner.
        /// @param salt The salt of the wallet.
        /// @param to The address to call.
        /// @param value The value to send.
        /// @param data The data to send.
        function ownerCall(bytes32 salt, address to, uint256 value, bytes memory data);
    }
}

impl RelayAuthentication {
    /// Sign an instance of a relay authentication.
    ///
    /// This would be computed by the relayee, and the signature would be submitted
    /// by the relayer.
    ///
    /// # Errors:
    /// - [`SignerError::Other`] if the signer address does not match the owner.
    pub async fn sign<S: Signer>(
        &self,
        signer: &S,
        domain: &Eip712Domain,
    ) -> Result<Signature, SignerError> {
        if signer.address() != self.owner {
            return Err(SignerError::Other(
                "Signer address does not match owner".into(),
            ));
        }

        signer.sign_hash(&self.eip712_signing_hash(domain)).await
    }
}

/// Create an [`Eip712Domain`] from the verifiying contract address and chain id.
pub fn auth_domain(chain_id: u64, contract: Address) -> Eip712Domain {
    Eip712Domain {
        name: Some("RelayAuthentication".into()),
        version: None,
        chain_id: Some(Uint::from(chain_id)),
        verifying_contract: Some(contract),
        salt: None,
    }
}
