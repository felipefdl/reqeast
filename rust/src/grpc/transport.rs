use std::time::Duration;

use tonic::transport::{ClientTlsConfig, Endpoint};

use crate::error::ReqeastError;
use crate::tls::insecure::insecure_cert_verifier;

/// Build a tonic `Endpoint` from authority and TLS settings.
pub(crate) fn build_endpoint(
  authority: &str,
  use_tls: bool,
  allow_insecure_tls: bool,
  timeout_secs: u32,
) -> Result<Endpoint, ReqeastError> {
  let (host, endpoint_authority) = parse_authority(authority)?;
  let scheme = if use_tls { "https" } else { "http" };
  let uri = format!("{scheme}://{endpoint_authority}");

  let mut endpoint = Endpoint::from_shared(uri)
    .map_err(|e| ReqeastError::InvalidConfig(format!("invalid gRPC authority: {e}")))?
    .connect_timeout(Duration::from_secs(timeout_secs.into()));

  if use_tls {
    let tls_config = ClientTlsConfig::new().domain_name(host);
    endpoint = if allow_insecure_tls {
      endpoint
        .tls_config_with_verifier(tls_config, insecure_cert_verifier())
        .map_err(map_endpoint_tls_error)?
    } else {
      endpoint
        .tls_config(tls_config.with_webpki_roots())
        .map_err(map_endpoint_tls_error)?
    };
  }

  Ok(endpoint)
}

fn map_endpoint_tls_error(err: tonic::transport::Error) -> ReqeastError {
  ReqeastError::TlsError(err.to_string())
}

/// Split `host:port` (or bracketed IPv6) from authority; strip optional scheme.
fn parse_authority(authority: &str) -> Result<(String, String), ReqeastError> {
  let trimmed = authority.trim();
  if trimmed.is_empty() {
    return Err(ReqeastError::InvalidConfig("gRPC authority is empty".into()));
  }

  let without_scheme = trimmed
    .strip_prefix("https://")
    .or_else(|| trimmed.strip_prefix("http://"))
    .unwrap_or(trimmed);

  let host = extract_host(without_scheme)?;
  Ok((host, without_scheme.to_string()))
}

fn extract_host(authority: &str) -> Result<String, ReqeastError> {
  if authority.starts_with('[') {
    let end = authority
      .find(']')
      .ok_or_else(|| ReqeastError::InvalidConfig(format!("invalid IPv6 authority: {authority}")))?;
    return Ok(authority[1..end].to_string());
  }

  if let Some((host, port)) = authority.rsplit_once(':')
    && !port.is_empty()
    && port.chars().all(|c| c.is_ascii_digit())
  {
    return Ok(host.to_string());
  }

  Ok(authority.to_string())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn build_endpoint_plain_http() {
    let endpoint = build_endpoint("localhost:50051", false, false, 30).expect("endpoint");
    assert_eq!(endpoint.uri().to_string(), "http://localhost:50051/");
  }

  #[test]
  fn build_endpoint_https_secure_tls() {
    let endpoint = build_endpoint("example.com:443", true, false, 15).expect("endpoint");
    assert_eq!(endpoint.uri().to_string(), "https://example.com:443/");
  }

  #[test]
  fn build_endpoint_https_insecure_tls() {
    let endpoint = build_endpoint("example.com:443", true, true, 15).expect("endpoint");
    assert_eq!(endpoint.uri().to_string(), "https://example.com:443/");
  }

  #[test]
  fn build_endpoint_strips_scheme_and_uses_tls_flag() {
    let endpoint = build_endpoint("https://localhost:50051", false, false, 5).expect("endpoint");
    assert_eq!(endpoint.uri().to_string(), "http://localhost:50051/");
  }

  #[test]
  fn build_endpoint_ipv6_host() {
    let endpoint = build_endpoint("[::1]:50051", true, false, 10).expect("endpoint");
    assert_eq!(endpoint.uri().to_string(), "https://[::1]:50051/");
  }

  #[test]
  fn build_endpoint_rejects_empty_authority() {
    let err = build_endpoint("  ", false, false, 30).unwrap_err();
    assert!(matches!(err, ReqeastError::InvalidConfig { .. }));
  }

  #[test]
  fn extract_host_strips_port() {
    assert_eq!(extract_host("localhost:50051").unwrap(), "localhost");
    assert_eq!(extract_host("[::1]:50051").unwrap(), "::1");
    assert_eq!(extract_host("example.com").unwrap(), "example.com");
  }
}
