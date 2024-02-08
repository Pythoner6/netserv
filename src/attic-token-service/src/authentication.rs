use std::env;
use std::str::FromStr;
use serde::{Serialize, Deserialize};
use openidconnect::{Nonce, ClientId, IssuerUrl, NonceVerifier};
use openidconnect::core::CoreClient;
use openidconnect::reqwest::async_http_client;
use anyhow::Result;
use actix_web::dev::ServiceRequest;
use actix_web_httpauth::extractors::bearer::BearerAuth;
use actix_web::{error, web, HttpMessage};
use serde_json;
use crate::model::ErrorResponse;

static AUDIENCE: &str = "AUDIENCE";
static OIDC_URL: &str = "OIDC_URL";

#[derive(Clone,Debug,Serialize,Deserialize)]
struct AdditionalMetadata {
    introspection_endpoint: String,
}

impl openidconnect::AdditionalProviderMetadata for AdditionalMetadata {}

type ProviderMetadata = openidconnect::ProviderMetadata<
    AdditionalMetadata,
    openidconnect::core::CoreAuthDisplay,
    openidconnect::core::CoreClientAuthMethod,
    openidconnect::core::CoreClaimName,
    openidconnect::core::CoreClaimType,
    openidconnect::core::CoreGrantType,
    openidconnect::core::CoreJweContentEncryptionAlgorithm,
    openidconnect::core::CoreJweKeyManagementAlgorithm,
    openidconnect::core::CoreJwsSigningAlgorithm,
    openidconnect::core::CoreJsonWebKeyType,
    openidconnect::core::CoreJsonWebKeyUse,
    openidconnect::core::CoreJsonWebKey,
    openidconnect::core::CoreResponseMode,
    openidconnect::core::CoreResponseType,
    openidconnect::core::CoreSubjectIdentifierType,
>;

#[derive(Clone,Debug,Serialize,Deserialize)]
struct AdditionalClaims {
    namespace_path: String
}

impl openidconnect::AdditionalClaims for AdditionalClaims {}

type IdToken = openidconnect::IdToken<
    AdditionalClaims,
    openidconnect::core::CoreGenderClaim,
    openidconnect::core::CoreJweContentEncryptionAlgorithm,
    openidconnect::core::CoreJwsSigningAlgorithm,
    openidconnect::core::CoreJsonWebKeyType,
>;

struct TrivialNonceVerifier {}
impl NonceVerifier for TrivialNonceVerifier {
    fn verify(self, _nonce: Option<&Nonce>) -> Result<(), String> {
        Ok(())
    }
}

#[derive(Clone)]
pub struct AuthenticationData {
    pub subject: String,
    pub namespace_path: String,
}

#[derive(Clone)]
pub struct Verifier {
    audience: String,
    oidc_url: String,
}

impl Verifier {
    pub fn new() -> Result<Self> {
        let audience = env::var(AUDIENCE)?;
        let audience = audience.trim().into();

        let oidc_url = env::var(OIDC_URL)?;
        let oidc_url = oidc_url.trim().into();

        Ok(Self {
            audience,
            oidc_url,
        })
    }

    async fn verify(&self, tok: &str) -> Result<AuthenticationData> {
        let metadata = ProviderMetadata::discover_async(
            IssuerUrl::new(self.oidc_url.clone())?,
            async_http_client
        ).await?;
        let client = CoreClient::from_provider_metadata(metadata, ClientId::new(self.audience.clone()), None);
        let id_token = IdToken::from_str(tok)?;
        let claims = id_token.claims(&client.id_token_verifier(), TrivialNonceVerifier{})?;

        Ok(AuthenticationData { subject: claims.subject().to_string(), namespace_path: claims.additional_claims().namespace_path.clone() })
    }
}

pub async fn authenticate(req: ServiceRequest, credentials: BearerAuth) -> std::result::Result<ServiceRequest, (actix_web::Error, ServiceRequest)> {
    match req.app_data::<web::Data<Verifier>>().unwrap().verify(credentials.token()).await {
        Ok(data) => {
            req.extensions_mut().insert(data);
            Ok(req)
        },
        Err(err) => {
            eprintln!("ERROR: {:?}", err);
            Err((error::ErrorUnauthorized(serde_json::to_string(&ErrorResponse { error: "unauthorized".into() }).unwrap()), req))
        }
    }
}
