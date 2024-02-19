use tokio;
use scylla::{SessionBuilder, Session, FromRow};
use openssl::ssl::{SslContext, SslMethod, SslFiletype, SslVerifyMode};
use openssl::rand::rand_priv_bytes;
use anyhow::Result;
use base64::prelude::*;
use clap::{Parser, Args, Subcommand};
use serde::{Serialize, Deserialize};
use serde_json;

#[derive(Parser, Debug)]
#[clap(name = "alternator-credentials", version)]
struct App {
    #[clap(flatten)]
    global: GlobalArgs,
    #[clap(subcommand)]
    command: Command,
}

impl App {
    async fn run(self) -> Result<()> {
        match self.command {
            Command::Generate(generate) => generate.run(self.global).await,
            Command::Retreive(retreive) => retreive.run(self.global).await,
        }
    }
}

#[derive(Args, Debug)]
struct GlobalArgs {
    #[clap(long, global = true)]
    nodes: Vec<String>,
    #[clap(long, global = true)]
    ca: Option<String>,
    #[clap(long, global = true)]
    cert: Option<String>,
    #[clap(long, global = true)]
    key: Option<String>,
}

#[derive(Subcommand, Debug)]
enum Command {
    Generate(GenerateArgs),
    Retreive(RetreiveArgs),
}

#[derive(Args, Debug)]
struct GenerateArgs {
    #[clap(long)]
    role: String,
}

impl GenerateArgs {
    async fn run(self, global: GlobalArgs) -> Result<()> {
        let session = build_session(global).await?;
        let mut secret_key = [0u8; 30];
        rand_priv_bytes(&mut secret_key)?;
        let secret_key = BASE64_STANDARD.encode(secret_key);
        session.query(
            "UPDATE system_auth.roles SET can_login = false, is_superuser = false, salted_hash = ? WHERE role = ?",
            (secret_key, self.role)
        ).await?;
        Ok(())
    }
}

#[derive(Args, Debug)]
struct RetreiveArgs {
    #[clap(long)]
    role: String,
}

#[derive(FromRow)]
struct RetreiveResult {
    salted_hash: String,
}

impl RetreiveArgs {
    async fn run(self, global: GlobalArgs) -> Result<()> {
        let session = build_session(global).await?;
        let result = session.query(
            "SELECT salted_hash FROM system_auth.roles WHERE role = ? LIMIT 1",
            (&self.role,)
        ).await?;
        let result: RetreiveResult = result.first_row()?.into_typed()?;
        println!("{}", serde_json::to_string(&AWSCredentials {
            version: 1,
            access_key_id: self.role,
            secret_access_key: result.salted_hash,
            session_token: None,
        })?);
        Ok(())
    }
}

#[derive(Serialize, Deserialize)]
struct AWSCredentials {
    #[serde(rename = "Version")]
    version: i64,
    #[serde(rename = "AccessKeyId")]
    access_key_id: String,
    #[serde(rename = "SecretAccessKey")]
    secret_access_key: String,
    #[serde(rename = "SessionToken", skip_serializing_if = "Option::is_none")]
    session_token: Option<String>,
    // TODO expiration
}

async fn build_session(args: GlobalArgs) -> Result<Session> {
    let mut ssl = SslContext::builder(SslMethod::tls_client())?;
    ssl.set_ca_file(args.ca.unwrap())?;
    ssl.set_certificate_file(args.cert.unwrap(), SslFiletype::PEM)?;
    ssl.set_private_key_file(args.key.unwrap(), SslFiletype::PEM)?;
    ssl.set_verify(SslVerifyMode::PEER);

    Ok(SessionBuilder::new()
        .known_nodes(args.nodes)
        .fetch_schema_metadata(false)
        .ssl_context(Some(ssl.build()))
        .build().await?)
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    let app = App::try_parse()?;
    app.run().await?;
    Ok(())
}
