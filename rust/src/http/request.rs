use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use reqwest::header::{HeaderMap, HeaderName, HeaderValue};

use crate::error::ReqeastError;
use crate::types::{HttpBody, HttpCookie, HttpMethod, KeyValuePair, MultipartField};

use super::cert;
use super::client::{
  HttpCertificateInfo, HttpRedirectEntry, HttpRequestConfig, HttpResponse, HttpSizeInfo, HttpTimingBreakdown,
};
use super::timing::{self, TimedResolver};

struct ResponseContext {
  dns_elapsed_ns: Arc<AtomicU64>,
  redirect_chain: Vec<HttpRedirectEntry>,
  request_method: String,
  request_url: String,
  request_headers: HeaderMap,
  request_body_size: u64,
}

pub(crate) async fn send_async(config: HttpRequestConfig) -> Result<HttpResponse, ReqeastError> {
  let dns_elapsed_ns = Arc::new(AtomicU64::new(0));
  let resolver = TimedResolver::new(dns_elapsed_ns.clone());

  let mut builder = reqwest::Client::builder()
    .timeout(Duration::from_secs(config.timeout_secs as u64))
    .redirect(reqwest::redirect::Policy::none())
    .danger_accept_invalid_certs(!config.ssl_verify)
    .dns_resolver(Arc::new(resolver))
    .tls_info(true);

  match config.http_version {
    crate::types::HttpVersion::Http1 => {
      builder = builder.http1_only();
    }
    crate::types::HttpVersion::Http2 => {
      builder = builder.http2_prior_knowledge();
    }
    crate::types::HttpVersion::Auto => {}
  }

  let client = builder
    .build()
    .map_err(|e| ReqeastError::InternalError(e.to_string()))?;

  let method = to_reqwest_method(config.method);
  let method_str = format!("{method}");
  let mut current_url = config.url.clone();
  let mut current_method = method.clone();
  let mut current_body = config.body.clone();
  let original_url =
    reqwest::Url::parse(&config.url).map_err(|e| ReqeastError::InvalidConfig(format!("Invalid URL: {e}")))?;

  let mut user_headers = build_header_map(&config.headers)?;

  for cookie in &config.cookies {
    if cookie.enabled {
      let cookie_str = format!("{}={}", cookie.key, cookie.value);
      append_cookie_header(&mut user_headers, &cookie_str);
    }
  }

  let request_body_size = estimate_body_size(&config.body);

  let start = Instant::now();
  let mut redirects_followed: u32 = 0;
  let mut redirect_chain: Vec<HttpRedirectEntry> = Vec::new();

  loop {
    let mut request = client.request(current_method.clone(), &current_url);
    request = request.headers(user_headers.clone());

    if !is_body_stripped(&current_method) {
      request = apply_body(request, &current_body)?;
    }

    let response = request.send().await?;
    let status = response.status();

    if config.follow_redirects && status.is_redirection() && redirects_followed >= config.max_redirects {
      let location = response
        .headers()
        .get("location")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();
      return Err(ReqeastError::HttpError(format!(
        "too many redirects ({redirects_followed} followed, last location: {location})",
      )));
    }

    if config.follow_redirects && status.is_redirection() && redirects_followed < config.max_redirects {
      if let Some(location) = response.headers().get("location") {
        let location_str = location
          .to_str()
          .map_err(|e| ReqeastError::HttpError(format!("Invalid redirect location header: {e}")))?;

        let redirect_url = resolve_redirect_url(&current_url, location_str)?;

        redirect_chain.push(HttpRedirectEntry {
          url: current_url.clone(),
          status_code: status.as_u16(),
        });

        redirects_followed += 1;
        let is_cross_origin = is_cross_origin(&original_url, &redirect_url);

        match status.as_u16() {
          301..=303 => {
            if config.follow_original_method {
              // Keep original method
            } else {
              current_method = reqwest::Method::GET;
              current_body = HttpBody::None;
            }
          }
          307 | 308 => {
            // Always preserve method and body
          }
          _ => {}
        }

        if is_cross_origin && !config.follow_auth_header {
          user_headers.remove("authorization");
        }

        if config.remove_referer_on_redirect {
          user_headers.remove("referer");
        }

        current_url = redirect_url.to_string();
        continue;
      }
    }

    let total_elapsed_ms = start.elapsed().as_millis() as u64;
    let ctx = ResponseContext {
      dns_elapsed_ns,
      redirect_chain,
      request_method: method_str,
      request_url: config.url.clone(),
      request_headers: user_headers,
      request_body_size,
    };
    return collect_response(response, total_elapsed_ms, ctx).await;
  }
}

fn to_reqwest_method(method: HttpMethod) -> reqwest::Method {
  match method {
    HttpMethod::Get => reqwest::Method::GET,
    HttpMethod::Post => reqwest::Method::POST,
    HttpMethod::Put => reqwest::Method::PUT,
    HttpMethod::Patch => reqwest::Method::PATCH,
    HttpMethod::Delete => reqwest::Method::DELETE,
    HttpMethod::Head => reqwest::Method::HEAD,
    HttpMethod::Options => reqwest::Method::OPTIONS,
  }
}

fn build_header_map(headers: &[KeyValuePair]) -> Result<HeaderMap, ReqeastError> {
  let mut map = HeaderMap::new();
  for header in headers {
    if header.enabled {
      let name = HeaderName::from_bytes(header.key.as_bytes())
        .map_err(|e| ReqeastError::InvalidConfig(format!("Invalid header name '{}': {e}", header.key)))?;
      let value = HeaderValue::from_str(&header.value)
        .map_err(|e| ReqeastError::InvalidConfig(format!("Invalid header value for '{}': {e}", header.key)))?;
      map.append(name, value);
    }
  }
  Ok(map)
}

fn append_cookie_header(headers: &mut HeaderMap, cookie: &str) {
  if let Some(existing) = headers.get("cookie") {
    if let Ok(existing_str) = existing.to_str() {
      let combined = format!("{existing_str}; {cookie}");
      if let Ok(val) = HeaderValue::from_str(&combined) {
        headers.insert("cookie", val);
      }
    }
  } else if let Ok(val) = HeaderValue::from_str(cookie) {
    headers.insert("cookie", val);
  }
}

fn is_body_stripped(method: &reqwest::Method) -> bool {
  matches!(method, &reqwest::Method::GET | &reqwest::Method::HEAD)
}

fn resolve_redirect_url(current: &str, location: &str) -> Result<reqwest::Url, ReqeastError> {
  let base = reqwest::Url::parse(current).map_err(|e| ReqeastError::HttpError(format!("Invalid current URL: {e}")))?;
  base
    .join(location)
    .map_err(|e| ReqeastError::HttpError(format!("Invalid redirect URL '{location}': {e}")))
}

fn is_cross_origin(original: &reqwest::Url, redirect: &reqwest::Url) -> bool {
  original.origin() != redirect.origin()
}

async fn collect_response(
  response: reqwest::Response,
  total_elapsed_ms: u64,
  ctx: ResponseContext,
) -> Result<HttpResponse, ReqeastError> {
  let status_code = response.status().as_u16();
  let status_text = response.status().canonical_reason().unwrap_or("").to_string();
  let final_url = response.url().to_string();
  let domain = response.url().host_str().unwrap_or("").to_string();
  let http_version = format!("{:?}", response.version());
  let remote_addr = response.remote_addr().map(|a| a.to_string());

  // Extract TLS certificate before consuming the response
  let certificate = response
    .extensions()
    .get::<reqwest::tls::TlsInfo>()
    .and_then(|tls| tls.peer_certificate())
    .and_then(cert::parse_certificate)
    .map(|info| HttpCertificateInfo {
      subject_cn: info.subject_cn,
      issuer_cn: info.issuer_cn,
      valid_until: info.valid_until,
    });

  // Check for compression: Content-Encoding present + Content-Length
  let content_encoding = response.headers().get("content-encoding").and_then(|v| v.to_str().ok());
  let content_length = response
    .headers()
    .get("content-length")
    .and_then(|v| v.to_str().ok())
    .and_then(|v| v.parse::<u64>().ok());
  let response_compressed_size = if content_encoding.is_some_and(|e| !e.eq_ignore_ascii_case("identity")) {
    content_length.unwrap_or(0)
  } else {
    0
  };

  let headers: Vec<KeyValuePair> = response
    .headers()
    .iter()
    .map(|(name, value)| KeyValuePair {
      key: name.to_string(),
      value: value.to_str().unwrap_or("").to_string(),
      enabled: true,
    })
    .collect();

  let response_headers_for_size: Vec<(String, String)> =
    headers.iter().map(|h| (h.key.clone(), h.value.clone())).collect();

  let cookies = parse_set_cookies(&headers, &domain);

  // Stream body and measure download time
  let download_start = Instant::now();
  let mut body = Vec::new();
  let mut stream = response;
  while let Some(chunk) = stream.chunk().await? {
    body.extend_from_slice(&chunk);
  }
  let download_ms = download_start.elapsed().as_secs_f64() * 1000.0;
  let body_size = body.len() as u64;

  // Calculate timing breakdown
  let dns_lookup_ms = ctx.dns_elapsed_ns.load(Ordering::Relaxed) as f64 / 1_000_000.0;
  let total_ms = total_elapsed_ms as f64;
  let connection_ms = (total_ms - dns_lookup_ms - download_ms).max(0.0);

  let timing = Some(HttpTimingBreakdown {
    dns_lookup_ms,
    connection_ms,
    download_ms,
    total_ms,
  });

  // Calculate size breakdown
  let request_headers_size =
    timing::estimate_request_headers_size(&ctx.request_method, &ctx.request_url, &ctx.request_headers);
  let response_headers_size =
    timing::estimate_response_headers_size(status_code, &status_text, &response_headers_for_size);

  let size_info = Some(HttpSizeInfo {
    request_headers_size,
    request_body_size: ctx.request_body_size,
    response_headers_size,
    response_body_size: body_size,
    response_compressed_size,
  });

  Ok(HttpResponse {
    status_code,
    status_text,
    headers,
    body,
    elapsed_ms: total_elapsed_ms,
    body_size,
    final_url,
    cookies,
    http_version,
    remote_addr,
    timing,
    certificate,
    size_info,
    redirect_chain: ctx.redirect_chain,
  })
}

fn parse_set_cookies(headers: &[KeyValuePair], domain: &str) -> Vec<HttpCookie> {
  headers
    .iter()
    .filter(|h| h.key.eq_ignore_ascii_case("set-cookie"))
    .filter_map(|h| parse_single_cookie(&h.value, domain))
    .collect()
}

fn parse_single_cookie(header_value: &str, default_domain: &str) -> Option<HttpCookie> {
  let mut parts = header_value.split(';');
  let name_value = parts.next()?.trim();
  let (name, value) = name_value.split_once('=')?;

  let mut cookie = HttpCookie {
    name: name.trim().to_string(),
    value: value.trim().to_string(),
    domain: default_domain.to_string(),
    path: "/".to_string(),
    expires: None,
    http_only: false,
    secure: false,
    same_site: None,
  };

  for attr in parts {
    let attr = attr.trim();
    let (key, val) = attr.split_once('=').unwrap_or((attr, ""));
    match key.trim().to_ascii_lowercase().as_str() {
      "domain" => cookie.domain = val.trim().trim_start_matches('.').to_string(),
      "path" => cookie.path = val.trim().to_string(),
      "expires" => cookie.expires = Some(val.trim().to_string()),
      "max-age" => cookie.expires = Some(format!("max-age={}", val.trim())),
      "httponly" => cookie.http_only = true,
      "secure" => cookie.secure = true,
      "samesite" => cookie.same_site = Some(val.trim().to_string()),
      _ => {}
    }
  }

  Some(cookie)
}

fn estimate_body_size(body: &HttpBody) -> u64 {
  match body {
    HttpBody::None => 0,
    HttpBody::Json { content } => content.len() as u64,
    HttpBody::FormUrlencoded { fields } => fields
      .iter()
      .filter(|f| f.enabled)
      .map(|f| f.key.len() + 1 + f.value.len())
      .sum::<usize>() as u64,
    HttpBody::Raw { content, .. } => content.len() as u64,
    HttpBody::Binary { data, .. } => data.len() as u64,
    HttpBody::Multipart { fields } => fields.iter().map(|f| f.value.len() as u64 + 200).sum(),
  }
}

fn apply_body(mut request: reqwest::RequestBuilder, body: &HttpBody) -> Result<reqwest::RequestBuilder, ReqeastError> {
  match body {
    HttpBody::None => {}
    HttpBody::Json { content } => {
      request = request.header("Content-Type", "application/json").body(content.clone());
    }
    HttpBody::FormUrlencoded { fields } => {
      let params: Vec<(&str, &str)> = fields
        .iter()
        .filter(|f| f.enabled)
        .map(|f| (f.key.as_str(), f.value.as_str()))
        .collect();
      request = request.form(&params);
    }
    HttpBody::Raw { content, content_type } => {
      request = request
        .header("Content-Type", content_type.as_str())
        .body(content.clone());
    }
    HttpBody::Binary { data, content_type } => {
      request = request.header("Content-Type", content_type.as_str()).body(data.clone());
    }
    HttpBody::Multipart { fields } => {
      return apply_multipart(request, fields);
    }
  }
  Ok(request)
}

fn apply_multipart(
  request: reqwest::RequestBuilder,
  fields: &[MultipartField],
) -> Result<reqwest::RequestBuilder, ReqeastError> {
  let mut form = reqwest::multipart::Form::new();
  for field in fields {
    if field.is_file {
      let ct = field.content_type.as_deref().unwrap_or("application/octet-stream");
      let part = reqwest::multipart::Part::bytes(field.value.clone())
        .file_name(field.file_name.clone().unwrap_or_default())
        .mime_str(ct)
        .map_err(|e| ReqeastError::InvalidConfig(format!("Invalid MIME type '{ct}': {e}")))?;
      form = form.part(field.name.clone(), part);
    } else {
      let text = String::from_utf8_lossy(&field.value).to_string();
      form = form.text(field.name.clone(), text);
    }
  }
  Ok(request.multipart(form))
}

#[cfg(test)]
mod tests {
  use super::*;

  // resolve_redirect_url tests

  #[test]
  fn resolve_redirect_url_absolute() {
    let result = resolve_redirect_url("https://example.com/old", "https://other.com/new").unwrap();
    assert_eq!(result.as_str(), "https://other.com/new");
  }

  #[test]
  fn resolve_redirect_url_relative_slash() {
    let result = resolve_redirect_url("https://example.com/old/path", "/new").unwrap();
    assert_eq!(result.as_str(), "https://example.com/new");
  }

  #[test]
  fn resolve_redirect_url_relative_no_slash() {
    let result = resolve_redirect_url("https://example.com/old/path", "other").unwrap();
    assert_eq!(result.as_str(), "https://example.com/old/other");
  }

  #[test]
  fn resolve_redirect_url_invalid_base() {
    let result = resolve_redirect_url("not-a-url", "/new");
    assert!(result.is_err());
  }

  // is_cross_origin tests

  #[test]
  fn is_cross_origin_same_origin() {
    let a = reqwest::Url::parse("https://example.com/a").unwrap();
    let b = reqwest::Url::parse("https://example.com/b").unwrap();
    assert!(!is_cross_origin(&a, &b));
  }

  #[test]
  fn is_cross_origin_different_host() {
    let a = reqwest::Url::parse("https://example.com/a").unwrap();
    let b = reqwest::Url::parse("https://other.com/a").unwrap();
    assert!(is_cross_origin(&a, &b));
  }

  #[test]
  fn is_cross_origin_different_scheme() {
    let a = reqwest::Url::parse("https://example.com/a").unwrap();
    let b = reqwest::Url::parse("http://example.com/a").unwrap();
    assert!(is_cross_origin(&a, &b));
  }

  // build_header_map tests

  #[test]
  fn build_header_map_enabled_headers() {
    let headers = vec![
      KeyValuePair {
        key: "content-type".into(),
        value: "application/json".into(),
        enabled: true,
      },
      KeyValuePair {
        key: "accept".into(),
        value: "text/html".into(),
        enabled: true,
      },
    ];
    let map = build_header_map(&headers).unwrap();
    assert_eq!(map.get("content-type").unwrap(), "application/json");
    assert_eq!(map.get("accept").unwrap(), "text/html");
  }

  #[test]
  fn build_header_map_skips_disabled() {
    let headers = vec![
      KeyValuePair {
        key: "x-custom".into(),
        value: "yes".into(),
        enabled: true,
      },
      KeyValuePair {
        key: "x-skip".into(),
        value: "no".into(),
        enabled: false,
      },
    ];
    let map = build_header_map(&headers).unwrap();
    assert!(map.get("x-custom").is_some());
    assert!(map.get("x-skip").is_none());
  }

  #[test]
  fn build_header_map_invalid_name_errors() {
    let headers = vec![KeyValuePair {
      key: "invalid header\x00name".into(),
      value: "val".into(),
      enabled: true,
    }];
    let result = build_header_map(&headers);
    assert!(result.is_err());
  }

  // estimate_body_size tests

  #[test]
  fn estimate_body_size_none() {
    assert_eq!(estimate_body_size(&HttpBody::None), 0);
  }

  #[test]
  fn estimate_body_size_json() {
    let body = HttpBody::Json {
      content: r#"{"a":"b"}"#.into(),
    };
    assert_eq!(estimate_body_size(&body), 9);
  }

  #[test]
  fn estimate_body_size_form_urlencoded() {
    let body = HttpBody::FormUrlencoded {
      fields: vec![
        KeyValuePair {
          key: "name".into(),
          value: "test".into(),
          enabled: true,
        },
        KeyValuePair {
          key: "skip".into(),
          value: "no".into(),
          enabled: false,
        },
        KeyValuePair {
          key: "age".into(),
          value: "30".into(),
          enabled: true,
        },
      ],
    };
    // "name" + "=" + "test" = 4+1+4 = 9, "age" + "=" + "30" = 3+1+2 = 6 => 15
    assert_eq!(estimate_body_size(&body), 15);
  }

  #[test]
  fn estimate_body_size_raw() {
    let body = HttpBody::Raw {
      content: "hello world".into(),
      content_type: "text/plain".into(),
    };
    assert_eq!(estimate_body_size(&body), 11);
  }

  #[test]
  fn estimate_body_size_binary() {
    let body = HttpBody::Binary {
      data: vec![1, 2, 3, 4, 5],
      content_type: "application/octet-stream".into(),
    };
    assert_eq!(estimate_body_size(&body), 5);
  }

  // parse_single_cookie tests

  #[test]
  fn parse_single_cookie_full_attributes() {
    let header = "session=abc123; Domain=.example.com; Path=/api; Expires=Thu, 01 Jan 2030 00:00:00 GMT; HttpOnly; Secure; SameSite=Lax";
    let cookie = parse_single_cookie(header, "fallback.com").unwrap();
    assert_eq!(cookie.name, "session");
    assert_eq!(cookie.value, "abc123");
    assert_eq!(cookie.domain, "example.com");
    assert_eq!(cookie.path, "/api");
    assert_eq!(cookie.expires.as_deref(), Some("Thu, 01 Jan 2030 00:00:00 GMT"));
    assert!(cookie.http_only);
    assert!(cookie.secure);
    assert_eq!(cookie.same_site.as_deref(), Some("Lax"));
  }

  #[test]
  fn parse_single_cookie_minimal() {
    let cookie = parse_single_cookie("token=xyz", "mysite.com").unwrap();
    assert_eq!(cookie.name, "token");
    assert_eq!(cookie.value, "xyz");
    assert_eq!(cookie.domain, "mysite.com");
    assert_eq!(cookie.path, "/");
    assert!(cookie.expires.is_none());
    assert!(!cookie.http_only);
    assert!(!cookie.secure);
    assert!(cookie.same_site.is_none());
  }

  // append_cookie_header tests

  #[test]
  fn append_cookie_header_merges_existing() {
    let mut headers = HeaderMap::new();
    headers.insert("cookie", HeaderValue::from_static("a=1"));
    append_cookie_header(&mut headers, "b=2");
    assert_eq!(headers.get("cookie").unwrap(), "a=1; b=2");
  }

  #[test]
  fn append_cookie_header_creates_new() {
    let mut headers = HeaderMap::new();
    append_cookie_header(&mut headers, "session=abc");
    assert_eq!(headers.get("cookie").unwrap(), "session=abc");
  }
}
