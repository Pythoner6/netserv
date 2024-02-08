use std::env;
use anyhow::Result;
use actix_web::{web, App, HttpServer};
use actix_web_httpauth::middleware::HttpAuthentication;
use env_logger;

mod authentication;
use authentication::{Verifier, authenticate};

mod model;

mod token;
use token::{token_service, get_signing_key};

static LISTEN_ADDRESS: &str = "LISTEN_ADDRESS";
static LISTEN_PORT: &str = "LISTEN_PORT";

#[actix_web::main]
async fn main() -> Result<()> {
    env_logger::init();

    let address = env::var(LISTEN_ADDRESS).unwrap_or("127.0.0.1".into());
    let address = address.trim().to_string();

    let port = env::var(LISTEN_PORT).unwrap_or("80".into());
    let port = port.trim();
    let port = port.parse::<u16>()?;

    let verifier = Verifier::new()?;
    let key = get_signing_key()?;

    Ok(HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(verifier.clone()))
            .wrap(HttpAuthentication::bearer(authenticate))
            .configure(token_service(key.clone()))
    }).bind((address, port))?.run().await?)
}
