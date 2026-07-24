use std::sync::Arc;

use crate::error::ReqeastError;
use crate::types::{HttpBody, HttpCookie, HttpMethod, HttpVersion, KeyValuePair};

#[derive(Debug, Clone, uniffi::Record)]
pub struct HttpRequestConfig {
  pub url: String,
  pub method: HttpMethod,
  pub headers: Vec<KeyValuePair>,
  pub body: HttpBody,
  pub timeout_secs: u32,
  pub follow_redirects: bool,
  pub max_redirects: u32,
  pub ssl_verify: bool,
  pub http_version: HttpVersion,
  pub encode_url: bool,
  pub follow_original_method: bool,
  pub follow_auth_header: bool,
  pub remove_referer_on_redirect: bool,
  pub cookies: Vec<KeyValuePair>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HttpTimingBreakdown {
  pub dns_lookup_ms: f64,
  pub connection_ms: f64,
  pub download_ms: f64,
  pub total_ms: f64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HttpCertificateInfo {
  pub subject_cn: Option<String>,
  pub issuer_cn: Option<String>,
  pub valid_until: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HttpSizeInfo {
  pub request_headers_size: u64,
  pub request_body_size: u64,
  pub response_headers_size: u64,
  pub response_body_size: u64,
  pub response_compressed_size: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HttpRedirectEntry {
  pub url: String,
  pub status_code: u16,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HttpResponse {
  pub status_code: u16,
  pub status_text: String,
  pub headers: Vec<KeyValuePair>,
  pub body: Vec<u8>,
  pub elapsed_ms: u64,
  pub body_size: u64,
  pub final_url: String,
  pub cookies: Vec<HttpCookie>,
  pub http_version: String,
  pub remote_addr: Option<String>,
  pub timing: Option<HttpTimingBreakdown>,
  pub certificate: Option<HttpCertificateInfo>,
  pub size_info: Option<HttpSizeInfo>,
  pub redirect_chain: Vec<HttpRedirectEntry>,
}

#[derive(uniffi::Object)]
pub struct HttpClient {
  runtime: Arc<tokio::runtime::Runtime>,
}

#[uniffi::export]
impl HttpClient {
  #[uniffi::constructor]
  pub fn new() -> Result<Self, ReqeastError> {
    let runtime = tokio::runtime::Runtime::new()
      .map_err(|e| ReqeastError::InternalError(format!("Failed to create runtime: {e}")))?;

    Ok(Self {
      runtime: Arc::new(runtime),
    })
  }

  pub fn send(&self, config: HttpRequestConfig) -> Result<HttpResponse, ReqeastError> {
    self.runtime.block_on(super::request::send_async(config))
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn http_request_config_clone() {
    let config = HttpRequestConfig {
      url: "https://example.com".into(),
      method: HttpMethod::Get,
      headers: vec![],
      body: HttpBody::None,
      timeout_secs: 30,
      follow_redirects: true,
      max_redirects: 10,
      ssl_verify: true,
      http_version: HttpVersion::Auto,
      encode_url: true,
      follow_original_method: false,
      follow_auth_header: false,
      remove_referer_on_redirect: false,
      cookies: vec![],
    };
    let cloned = config.clone();
    assert_eq!(cloned.url, "https://example.com");
    assert_eq!(cloned.timeout_secs, 30);
  }

  #[test]
  fn http_response_clone() {
    let response = HttpResponse {
      status_code: 200,
      status_text: "OK".into(),
      headers: vec![],
      body: vec![1, 2, 3],
      elapsed_ms: 42,
      body_size: 3,
      final_url: "https://example.com".into(),
      cookies: vec![],
      http_version: "HTTP/1.1".into(),
      remote_addr: Some("127.0.0.1:443".into()),
      timing: None,
      certificate: None,
      size_info: None,
      redirect_chain: vec![],
    };
    let cloned = response.clone();
    assert_eq!(cloned.status_code, 200);
    assert_eq!(cloned.body, vec![1, 2, 3]);
  }

  #[test]
  fn http_client_new_succeeds() {
    let client = HttpClient::new();
    assert!(client.is_ok());
  }
}
