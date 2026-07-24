use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum ReqeastError {
  #[error("HTTP error: {0}")]
  HttpError(String),

  #[error("Connection failed: {0}")]
  ConnectionFailed(String),

  #[error("Not connected")]
  NotConnected,

  #[error("TLS error: {0}")]
  TlsError(String),

  #[error("Invalid configuration: {0}")]
  InvalidConfig(String),

  #[error("Request timed out: {0}")]
  Timeout(String),

  #[error("Internal error: {0}")]
  InternalError(String),

  #[error("WebSocket error: {0}")]
  WebSocketError(String),

  #[error("SSE error: {0}")]
  SseError(String),
}

impl From<reqwest::Error> for ReqeastError {
  fn from(err: reqwest::Error) -> Self {
    let msg = err.to_string();

    if err.is_timeout() {
      ReqeastError::Timeout(msg)
    } else if err.is_builder() {
      ReqeastError::InvalidConfig(msg)
    } else if err.is_redirect() {
      ReqeastError::HttpError(format!("redirect loop: {msg}"))
    } else if err.is_connect() {
      map_connect_error(&err)
    } else if err.is_body() {
      ReqeastError::HttpError(format!("request body error: {msg}"))
    } else if err.is_decode() {
      ReqeastError::HttpError(format!("response decode error: {msg}"))
    } else if err.is_request() {
      ReqeastError::InvalidConfig(msg)
    } else {
      ReqeastError::HttpError(msg)
    }
  }
}

/// Map a connect/transport error using TLS vs DNS vs refused heuristics.
pub(crate) fn map_connect_error(err: &(dyn std::error::Error + 'static)) -> ReqeastError {
  let chain = full_error_chain(err);
  if is_tls_error(&chain) {
    ReqeastError::TlsError(extract_tls_detail(&chain))
  } else if is_dns_error(&chain) {
    ReqeastError::ConnectionFailed(extract_dns_detail(&chain))
  } else {
    ReqeastError::ConnectionFailed(extract_connect_detail(&chain))
  }
}

/// Collect all Display messages from the error source chain.
pub(crate) fn full_error_chain(err: &dyn std::error::Error) -> Vec<String> {
  let mut chain = vec![err.to_string()];
  let mut current = err.source();
  while let Some(src) = current {
    chain.push(src.to_string());
    current = src.source();
  }
  chain
}

pub(crate) fn is_tls_error(chain: &[String]) -> bool {
  chain.iter().any(|s| {
    let lower = s.to_ascii_lowercase();
    lower.contains("certificate")
      || lower.contains("handshake")
      || lower.contains("ssl")
      || lower.contains("invalidcertificate")
      || lower.contains("certnotvalidfor")
      || lower.contains("certexpired")
      || (lower.contains("tls") && !lower.contains("atlas"))
  })
}

pub(crate) fn is_dns_error(chain: &[String]) -> bool {
  chain.iter().any(|s| {
    let lower = s.to_ascii_lowercase();
    lower.contains("dns error")
      || lower.contains("failed to lookup")
      || lower.contains("no such host")
      || lower.contains("name or service not known")
      || lower.contains("nodename nor servname")
      || lower.contains("getaddrinfo")
      || lower.contains("resolve")
  })
}

/// Extract the most specific TLS error message from the chain.
pub(crate) fn extract_tls_detail(chain: &[String]) -> String {
  // Walk from the deepest cause upward; the innermost TLS-related message is most specific
  for s in chain.iter().rev() {
    let lower = s.to_ascii_lowercase();
    if lower.contains("certificate")
      || lower.contains("handshake")
      || lower.contains("invalidcertificate")
      || lower.contains("certnotvalidfor")
      || lower.contains("certexpired")
    {
      return s.clone();
    }
  }
  chain.last().cloned().unwrap_or_default()
}

/// Extract a clean DNS error message.
pub(crate) fn extract_dns_detail(chain: &[String]) -> String {
  for s in chain.iter().rev() {
    let lower = s.to_ascii_lowercase();
    if lower.contains("dns")
      || lower.contains("lookup")
      || lower.contains("resolve")
      || lower.contains("nodename")
      || lower.contains("getaddrinfo")
    {
      return s.clone();
    }
  }
  chain.last().cloned().unwrap_or_default()
}

/// Extract connection detail (refused, reset, etc.)
pub(crate) fn extract_connect_detail(chain: &[String]) -> String {
  // Prefer the deepest (most specific) cause
  chain.last().cloned().unwrap_or_default()
}

impl From<std::io::Error> for ReqeastError {
  fn from(err: std::io::Error) -> Self {
    ReqeastError::ConnectionFailed(err.to_string())
  }
}

impl From<tokio_tungstenite::tungstenite::Error> for ReqeastError {
  fn from(err: tokio_tungstenite::tungstenite::Error) -> Self {
    ReqeastError::WebSocketError(err.to_string())
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn http_error_display_includes_message() {
    let err = ReqeastError::HttpError("404 not found".into());
    assert_eq!(format!("{err}"), "HTTP error: 404 not found");
  }

  #[test]
  fn connection_failed_display() {
    let err = ReqeastError::ConnectionFailed("timeout".into());
    assert_eq!(format!("{err}"), "Connection failed: timeout");
  }

  #[test]
  fn not_connected_display() {
    let err = ReqeastError::NotConnected;
    assert_eq!(format!("{err}"), "Not connected");
  }

  #[test]
  fn tls_error_display() {
    let err = ReqeastError::TlsError("cert expired".into());
    assert_eq!(format!("{err}"), "TLS error: cert expired");
  }

  #[test]
  fn invalid_config_display() {
    let err = ReqeastError::InvalidConfig("bad port".into());
    assert_eq!(format!("{err}"), "Invalid configuration: bad port");
  }

  #[test]
  fn timeout_display() {
    let err = ReqeastError::Timeout("30s elapsed".into());
    assert_eq!(format!("{err}"), "Request timed out: 30s elapsed");
  }

  #[test]
  fn internal_error_display() {
    let err = ReqeastError::InternalError("oops".into());
    assert_eq!(format!("{err}"), "Internal error: oops");
  }

  #[test]
  fn websocket_error_display() {
    let err = ReqeastError::WebSocketError("protocol error".into());
    assert_eq!(format!("{err}"), "WebSocket error: protocol error");
  }

  #[test]
  fn sse_error_display() {
    let err = ReqeastError::SseError("stream closed".into());
    assert_eq!(format!("{err}"), "SSE error: stream closed");
  }
}
