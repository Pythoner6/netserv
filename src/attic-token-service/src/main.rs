use actix_web::dev::ServiceRequest;
use actix_web_httpauth::extractors::bearer::BearerAuth;
use anyhow::Result;
use openidconnect::{AccessToken, Nonce, ClientId, ClientSecret, IssuerUrl, TokenIntrospectionResponse, EmptyAdditionalClaims, NonceVerifier, IntrospectionUrl, AdditionalProviderMetadata};
use openidconnect::core::{CoreClient, CoreProviderMetadata, CoreIdToken};
use openidconnect::reqwest::async_http_client;
use actix_web::{error, get, post, web, http::header, App, HttpMessage, HttpResponse, HttpServer, Responder};
use std::env;
use std::str::FromStr;
use actix_web_httpauth::middleware::HttpAuthentication;
use serde::{Serialize, Deserialize};
use attic_token::{Token, HS256Key};
use attic::cache::CacheNamePattern;
use chrono::{Duration, Utc};
use base64::{Engine, engine::general_purpose::STANDARD};

#[derive(Clone)]
struct AuthenticationData {
    subject: String,
    namespace_path: String,
}

struct SecretData {
    key: HS256Key
}

#[derive(Clone,Debug,Serialize,Deserialize)]
struct TokenResponse {
    token: String
}

#[derive(Clone,Debug,Serialize,Deserialize)]
struct ErrorResponse {
    error: String
}

#[post("/_token")]
async fn token(data: web::Data<SecretData>, auth: web::ReqData<AuthenticationData>) -> impl Responder {
    let mut token = Token::new(auth.subject.clone(), &Utc::now().checked_add_signed(Duration::hours(1)).unwrap());
    let permissions = token.get_or_insert_permission_mut(CacheNamePattern::new(auth.namespace_path.clone()).unwrap());
    permissions.pull = true;
    permissions.push = true;
    match token.encode(&data.key) {
        Ok(token) => HttpResponse::Ok().body(serde_json::to_string(&TokenResponse { token }).unwrap()),
        Err(err) => HttpResponse::InternalServerError().body(serde_json::to_string(&ErrorResponse { error: err.to_string() }).unwrap()),
    }
}

#[actix_web::main]
async fn main() -> Result<()> {
    let secret_path = env::var("HS256_SECRET_PATH")?;
    let base64_secret = std::fs::read_to_string(secret_path)?;
    let key = HS256Key::from_bytes(&STANDARD.decode(base64_secret)?);

    let address = env::var("LISTEN_ADDRESS")?;
    let address = address.trim();
    let address = if address.is_empty() { "127.0.0.1".into() } else { address };
    let port = env::var("LISTEN_PORT")?;
    let port = port.trim();
    let port = if port.is_empty() { "80".into() } else { port };
    let port = port.parse::<u16>()?;

    Ok(HttpServer::new(move || {
        App::new().app_data(SecretData { key: key.clone() }).wrap(HttpAuthentication::bearer(authenticate)).service(token)
    }).bind((address, port))?.run().await?)
}

async fn authenticate(req: ServiceRequest, credentials: BearerAuth) -> std::result::Result<ServiceRequest, (actix_web::Error, ServiceRequest)> {
    match verify_token(credentials.token()).await {
        Ok(data) => {
            req.extensions_mut().insert(data);
            Ok(req)
        },
        Err(err) => {
            eprintln!("ERROR: {}", err);
            Err((error::ErrorUnauthorized("unauthorized"), req))
        }
    }
}

struct TrivialNonceVerifier {}
impl NonceVerifier for TrivialNonceVerifier {
    fn verify(self, _nonce: Option<&Nonce>) -> Result<(), String> {
        Ok(())
    }
}

#[derive(Clone,Debug,Serialize,Deserialize)]
struct AdditionalMetadata {
    introspection_endpoint: String,
}

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

impl openidconnect::AdditionalProviderMetadata for AdditionalMetadata {
}

type IdToken = openidconnect::IdToken<
    AdditionalClaims,
    openidconnect::core::CoreGenderClaim,
    openidconnect::core::CoreJweContentEncryptionAlgorithm,
    openidconnect::core::CoreJwsSigningAlgorithm,
    openidconnect::core::CoreJsonWebKeyType,
>;

#[derive(Clone,Debug,Serialize,Deserialize)]
struct AdditionalClaims {
    namespace_path: String
}

impl openidconnect::AdditionalClaims for AdditionalClaims {}

async fn verify_token(tok: &str) -> Result<AuthenticationData> {
    let metadata = ProviderMetadata::discover_async(
        IssuerUrl::new("https://gitlab.home.josephmartin.org".into())?,
        async_http_client
    ).await?;
    let introspection_url = metadata.additional_metadata().introspection_endpoint.clone();

    let client_id = env::var("CLIENT_ID")?;
    let client_secret = env::var("CLIENT_SECRET").ok();
    let client = CoreClient::from_provider_metadata(metadata, ClientId::new(client_id.into()), client_secret.map(ClientSecret::new))
        .set_introspection_uri(IntrospectionUrl::new(introspection_url)?);
    let id_token = IdToken::from_str(tok)?;
    let claims = id_token.claims(&client.id_token_verifier().require_audience_match(false), TrivialNonceVerifier{})?;

    if !client.introspect(&AccessToken::new(tok.into()))?.request_async(async_http_client).await?.active() {
        return Err(anyhow::anyhow!("token not active"));
    }

    Ok(AuthenticationData { subject: claims.subject().to_string(), namespace_path: claims.additional_claims().namespace_path.clone() })
}
