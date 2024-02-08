use anyhow::Result;
use std::env;
use actix_web::{post, web, HttpResponse, Responder};
use attic::cache::CacheNamePattern;
use attic_token::{Token, HS256Key};
use chrono::{Duration, Utc};
use base64::{Engine, engine::general_purpose::STANDARD};
use crate::model::{TokenResponse, ErrorResponse};
use crate::authentication::AuthenticationData;

static HS256_SECRET: &str = "HS256_SECRET";

pub fn get_signing_key() -> Result<HS256Key> {
    let base64_secret = env::var(HS256_SECRET)?;
    let secret = HS256Key::from_bytes(&STANDARD.decode(base64_secret)?);

    Ok(secret)
}

#[post("/_token")]
async fn create_token(signing_key: web::Data<HS256Key>, auth: web::ReqData<AuthenticationData>) -> impl Responder {
    let expiration = Utc::now() + Duration::hours(1);
    let mut token = Token::new(auth.subject.clone(), &expiration);
    let permissions = token.get_or_insert_permission_mut(CacheNamePattern::new(auth.namespace_path.clone()).unwrap());
    permissions.create_cache = true;
    permissions.configure_cache = true;
    permissions.configure_cache_retention = true;
    permissions.delete = true;
    permissions.pull = true;
    permissions.push = true;
    match token.encode(&signing_key) {
        Ok(token) => HttpResponse::Ok().body(serde_json::to_string(&TokenResponse { token }).unwrap()),
        Err(err) => HttpResponse::InternalServerError().body(serde_json::to_string(&ErrorResponse { error: err.to_string() }).unwrap()),
    }
}

pub fn token_service(key: HS256Key) -> impl Fn(&mut web::ServiceConfig) {
    move |cfg| { 
        cfg.app_data(web::Data::new(key.clone())).service(create_token); 
    }
}
