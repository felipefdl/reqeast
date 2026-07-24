use std::net::SocketAddr;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use reqwest::dns::{Addrs, Name, Resolve, Resolving};

pub(crate) struct TimedResolver {
  dns_elapsed_ns: Arc<AtomicU64>,
}

impl TimedResolver {
  pub fn new(dns_elapsed_ns: Arc<AtomicU64>) -> Self {
    Self { dns_elapsed_ns }
  }
}

impl Resolve for TimedResolver {
  fn resolve(&self, name: Name) -> Resolving {
    let elapsed = self.dns_elapsed_ns.clone();
    Box::pin(async move {
      let host = format!("{}:0", name.as_str());
      let start = std::time::Instant::now();
      let addrs: Vec<SocketAddr> = tokio::net::lookup_host(host).await?.collect();
      elapsed.store(start.elapsed().as_nanos() as u64, Ordering::Relaxed);
      let addrs: Addrs = Box::new(addrs.into_iter());
      Ok(addrs)
    })
  }
}

pub(crate) fn estimate_request_headers_size(method: &str, url: &str, headers: &reqwest::header::HeaderMap) -> u64 {
  // Request line: "GET /path HTTP/1.1\r\n"
  let path = reqwest::Url::parse(url)
    .map(|u| u.path().to_string())
    .unwrap_or_else(|_| "/".to_string());
  let request_line = format!("{method} {path} HTTP/1.1\r\n");
  let mut size = request_line.len() as u64;

  for (name, value) in headers.iter() {
    // "Header-Name: value\r\n"
    size += name.as_str().len() as u64 + 2 + value.len() as u64 + 2;
  }
  size += 2; // trailing \r\n
  size
}

pub(crate) fn estimate_response_headers_size(status_code: u16, status_text: &str, headers: &[(String, String)]) -> u64 {
  // Status line: "HTTP/1.1 200 OK\r\n"
  let status_line = format!("HTTP/1.1 {status_code} {status_text}\r\n");
  let mut size = status_line.len() as u64;

  for (name, value) in headers {
    size += name.len() as u64 + 2 + value.len() as u64 + 2;
  }
  size += 2; // trailing \r\n
  size
}

#[cfg(test)]
mod tests {
  use super::*;
  use reqwest::header::{HeaderMap, HeaderValue};

  #[test]
  fn estimate_request_headers_size_basic() {
    let mut headers = HeaderMap::new();
    headers.insert("host", HeaderValue::from_static("example.com"));
    // Request line: "GET /path HTTP/1.1\r\n" = 20
    // Header: "host" (4) + ": " (2) + "example.com" (11) + "\r\n" (2) = 19
    // Trailing: "\r\n" = 2
    let size = estimate_request_headers_size("GET", "https://example.com/path", &headers);
    assert_eq!(size, 20 + 19 + 2);
  }

  #[test]
  fn estimate_request_headers_size_multiple_headers() {
    let mut headers = HeaderMap::new();
    headers.insert("host", HeaderValue::from_static("example.com"));
    headers.insert("accept", HeaderValue::from_static("*/*"));
    // Request line: "POST / HTTP/1.1\r\n" = 17
    // "host: example.com\r\n" = 19
    // "accept: */*\r\n" = 6+2+3+2 = 13
    // Trailing: 2
    let size = estimate_request_headers_size("POST", "https://example.com/", &headers);
    assert_eq!(size, 17 + 19 + 13 + 2);
  }

  #[test]
  fn estimate_request_headers_size_empty_headers() {
    let headers = HeaderMap::new();
    // "GET / HTTP/1.1\r\n" = 16
    // Trailing: 2
    let size = estimate_request_headers_size("GET", "https://example.com/", &headers);
    assert_eq!(size, 16 + 2);
  }

  #[test]
  fn estimate_response_headers_size_basic() {
    let headers = vec![("content-type".to_string(), "text/html".to_string())];
    // "HTTP/1.1 200 OK\r\n" = 17
    // "content-type" (12) + ": " (2) + "text/html" (9) + "\r\n" (2) = 25
    // Trailing: 2
    let size = estimate_response_headers_size(200, "OK", &headers);
    assert_eq!(size, 17 + 25 + 2);
  }

  #[test]
  fn estimate_response_headers_size_empty_headers() {
    let headers: Vec<(String, String)> = vec![];
    // "HTTP/1.1 404 Not Found\r\n" = 24
    // Trailing: 2
    let size = estimate_response_headers_size(404, "Not Found", &headers);
    assert_eq!(size, 24 + 2);
  }

  #[test]
  fn estimate_response_headers_size_long_status_text() {
    let headers: Vec<(String, String)> = vec![];
    // "HTTP/1.1 500 Internal Server Error\r\n" = 36
    // Trailing: 2
    let size = estimate_response_headers_size(500, "Internal Server Error", &headers);
    assert_eq!(size, 36 + 2);
  }
}
