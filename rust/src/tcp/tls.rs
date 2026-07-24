use std::sync::Arc;

use crate::error::ReqeastError;
use crate::tls::InsecureCertVerifier;
use crate::util::Pipe;

use super::client::{TcpConfig, TcpEvent};

pub(crate) async fn upgrade_to_tls(
  stream: tokio::net::TcpStream,
  config: &TcpConfig,
) -> Result<tokio_rustls::client::TlsStream<tokio::net::TcpStream>, TcpEvent> {
  let tls_config = if config.allow_insecure_tls {
    create_insecure_tls_config()
  } else {
    create_tls_config()
  };

  let tls_config = tls_config.map_err(|e| TcpEvent::Error {
    error: format!("TLS setup failed: {e}"),
  })?;

  let connector = tokio_rustls::TlsConnector::from(Arc::new(tls_config));
  let domain = rustls::pki_types::ServerName::try_from(config.host.clone()).map_err(|e| TcpEvent::Error {
    error: format!("Invalid server name: {e}"),
  })?;

  connector.connect(domain, stream).await.map_err(|e| TcpEvent::Error {
    error: format!("TLS handshake failed: {e}"),
  })
}

pub(crate) fn create_tls_config() -> Result<rustls::ClientConfig, ReqeastError> {
  let provider = rustls::crypto::aws_lc_rs::default_provider();
  let root_store = rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());

  rustls::ClientConfig::builder_with_provider(Arc::new(provider))
    .with_safe_default_protocol_versions()
    .map_err(|e| ReqeastError::TlsError(e.to_string()))?
    .with_root_certificates(root_store)
    .with_no_client_auth()
    .pipe(Ok)
}

pub(crate) fn create_insecure_tls_config() -> Result<rustls::ClientConfig, ReqeastError> {
  let provider = rustls::crypto::aws_lc_rs::default_provider();

  let config = rustls::ClientConfig::builder_with_provider(Arc::new(provider))
    .with_safe_default_protocol_versions()
    .map_err(|e| ReqeastError::TlsError(e.to_string()))?
    .dangerous()
    .with_custom_certificate_verifier(Arc::new(InsecureCertVerifier))
    .with_no_client_auth();

  Ok(config)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn create_tls_config_succeeds() {
    let result = create_tls_config();
    assert!(result.is_ok());
  }

  #[test]
  fn create_insecure_tls_config_succeeds() {
    let result = create_insecure_tls_config();
    assert!(result.is_ok());
  }
}
