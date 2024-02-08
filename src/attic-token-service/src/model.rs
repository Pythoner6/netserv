use serde::{Serialize, Deserialize};

#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct TokenResponse {
    pub token: String
}

#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct ErrorResponse {
    pub error: String
}
