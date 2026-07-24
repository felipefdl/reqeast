//! HAR 1.2 normalization into the spec import normalized IR.

use std::collections::HashSet;

use serde_json::Value;

use crate::spec_import::fingerprint::{bundle_and_canonicalize, hash_bytes};
use crate::spec_import::normalize::NormalizeOutput;
use crate::spec_import::types::{
  NormalizedAuth, NormalizedBody, NormalizedEnvironment, NormalizedFormDataEntry, NormalizedKeyValue,
  NormalizedOperation, NormalizedParameter, NormalizedProject, OperationProtocol, ParameterLocation, SpecImportError,
  SpecParseOptions, SpecWarning, ValueSource,
};

const CREDENTIAL_HEADER_NAMES: &[&str] = &["cookie", "authorization", "set-cookie"];

/// Returns true when the JSON value looks like a HAR 1.x log document.
pub fn is_har_log(value: &Value) -> bool {
  let Some(log) = value.get("log").and_then(Value::as_object) else {
    return false;
  };

  log
    .get("version")
    .and_then(Value::as_str)
    .is_some_and(|version| version.starts_with("1."))
    && log.get("entries").and_then(Value::as_array).is_some()
}

/// Normalize a parsed HAR 1.2 JSON document into [`NormalizedProject`].
pub fn normalize_har(value: Value, options: SpecParseOptions) -> Result<NormalizeOutput, SpecImportError> {
  if !is_har_log(&value) {
    return Err(SpecImportError::UnsupportedFormat("Not a HAR 1.2 log document".into()));
  }

  let log = value
    .get("log")
    .ok_or_else(|| SpecImportError::InvalidSpec("HAR document missing log object".into()))?;

  let title = log
    .get("creator")
    .and_then(|creator| creator.get("name"))
    .and_then(Value::as_str)
    .or_else(|| {
      log
        .get("browser")
        .and_then(|browser| browser.get("name"))
        .and_then(Value::as_str)
    })
    .unwrap_or("Imported HAR Capture")
    .to_owned();

  let description = log
    .get("comment")
    .and_then(Value::as_str)
    .filter(|text| !text.is_empty())
    .map(str::to_owned);

  let entries = log
    .get("entries")
    .and_then(Value::as_array)
    .ok_or_else(|| SpecImportError::InvalidSpec("HAR log missing entries array".into()))?;

  let mut warnings = vec![SpecWarning {
    code: "MIGRATION_FROM_HAR".into(),
    message: "Imported from HAR capture; responses and timing metadata are not migrated".into(),
    operation_ref: None,
  }];

  let mut operations = Vec::new();
  let mut seen_primary_keys = HashSet::new();
  let mut base_url: Option<String> = None;

  for (index, entry) in entries.iter().enumerate() {
    let operation = normalize_entry(entry, index, options, &mut warnings)?;
    if let Some(origin) = extract_origin_from_path(&operation.path).or_else(|| {
      entry
        .get("request")
        .and_then(|request| request.get("url"))
        .and_then(Value::as_str)
        .and_then(extract_origin_from_url)
    }) {
      base_url.get_or_insert(origin);
    }

    let normalized_path = normalize_operation_path(&operation.path);
    let mut operation = operation;
    operation.path = normalized_path;

    if !seen_primary_keys.insert(operation.primary_key.clone()) {
      return Err(SpecImportError::InvalidSpec(format!(
        "Duplicate request identity: {}",
        operation.primary_key
      )));
    }
    operations.push(operation);
  }

  if operations.is_empty() {
    return Err(SpecImportError::InvalidSpec(
      "HAR log contains no importable HTTP requests".into(),
    ));
  }

  let environments = vec![default_environment(base_url.as_deref())];

  let fingerprint = bundle_and_canonicalize(&value)
    .map(|bytes| hash_bytes(&bytes))
    .map_err(SpecImportError::InvalidSpec)?;

  Ok(NormalizeOutput {
    project: NormalizedProject {
      title,
      description,
      version: log.get("version").and_then(Value::as_str).map(str::to_owned),
      icon_url: None,
      security_schemes: vec![],
      folders: vec![],
      operations,
      environments,
    },
    warnings,
    content_fingerprint: fingerprint,
  })
}

fn default_environment(base_url: Option<&str>) -> NormalizedEnvironment {
  NormalizedEnvironment {
    name: "Capture".into(),
    variables: vec![NormalizedKeyValue {
      key: "base_url".into(),
      value: base_url.unwrap_or("/").into(),
      enabled: true,
    }],
  }
}

fn normalize_entry(
  entry: &Value,
  index: usize,
  options: SpecParseOptions,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedOperation, SpecImportError> {
  let request = entry
    .get("request")
    .ok_or_else(|| SpecImportError::InvalidSpec(format!("HAR entry {index} is missing request")))?;

  let method = request
    .get("method")
    .and_then(Value::as_str)
    .unwrap_or("GET")
    .to_ascii_uppercase();

  let parsed_url = parse_request_url(request.get("url"))?;
  let op_ref = format!("{method} {}", parsed_url.path);

  let mut parameters = parsed_url.query_params;
  parameters.extend(parsed_url.path_params);

  let header_auth = normalize_headers_and_auth(request, entry.get("response"), options, &op_ref);
  parameters.extend(header_auth.headers);
  let auth = header_auth.auth;
  let credentials_stripped = header_auth.credentials_stripped;

  if credentials_stripped {
    warnings.push(SpecWarning {
      code: "HAR_CREDENTIALS_STRIPPED".into(),
      message: "Sensitive Cookie, Authorization, or Set-Cookie values were removed from this request".into(),
      operation_ref: Some(op_ref.clone()),
    });
  }

  if entry.get("response").is_some() {
    warnings.push(SpecWarning {
      code: "RESPONSE_NOT_IMPORTED".into(),
      message: "HAR response data is not imported".into(),
      operation_ref: Some(op_ref.clone()),
    });
  }

  let body = normalize_body(request.get("postData"), &op_ref, warnings)?;
  let name = entry_name(entry, index, &method, &parsed_url.path);

  Ok(NormalizedOperation {
    primary_key: op_ref,
    alternate_keys: vec![],
    name,
    method,
    path: parsed_url.path,
    deprecated: false,
    tags: vec![],
    protocol: OperationProtocol::Http,
    binding: None,
    folder_id: None,
    parameters,
    body,
    body_candidates: vec![],
    auth,
    description: entry
      .get("comment")
      .and_then(Value::as_str)
      .filter(|text| !text.is_empty())
      .map(str::to_owned),
  })
}

fn entry_name(entry: &Value, _index: usize, method: &str, path: &str) -> String {
  if let Some(comment) = entry.get("comment").and_then(Value::as_str) {
    let trimmed = comment.trim();
    if !trimmed.is_empty() {
      return trimmed.to_owned();
    }
  }

  if let Some(page_ref) = entry.get("pageref").and_then(Value::as_str) {
    let trimmed = page_ref.trim();
    if !trimmed.is_empty() {
      return format!("{method} {trimmed}");
    }
  }

  format!("{method} {path}")
}

struct ParsedUrl {
  path: String,
  query_params: Vec<NormalizedParameter>,
  path_params: Vec<NormalizedParameter>,
}

fn parse_request_url(url_value: Option<&Value>) -> Result<ParsedUrl, SpecImportError> {
  let raw = url_value
    .and_then(Value::as_str)
    .ok_or_else(|| SpecImportError::InvalidSpec("HAR request is missing url".into()))?;

  let (path, query) = split_url(raw);
  let path_params = path_variables_from_path(&path);
  let query_params = parse_query_pairs(query);

  Ok(ParsedUrl {
    path,
    query_params,
    path_params,
  })
}

fn split_url(raw: &str) -> (String, &str) {
  let trimmed = raw.trim();
  if trimmed.is_empty() {
    return ("/".into(), "");
  }

  let without_fragment = trimmed.split('#').next().unwrap_or(trimmed);
  let (base, query) = match without_fragment.split_once('?') {
    Some((base, query)) => (base, query),
    None => (without_fragment, ""),
  };

  (extract_path_from_url(base), query)
}

fn extract_path_from_url(raw: &str) -> String {
  let trimmed = raw.trim();
  if trimmed.is_empty() {
    return "/".into();
  }

  if let Some(path_start) = trimmed.find("://") {
    let after_scheme = &trimmed[path_start + 3..];
    if let Some(path_index) = after_scheme.find('/') {
      return normalize_absolute_path(&after_scheme[path_index..]);
    }
    return "/".into();
  }

  normalize_absolute_path(trimmed)
}

fn extract_origin_from_url(raw: &str) -> Option<String> {
  let trimmed = raw.trim();
  let scheme_end = trimmed.find("://")?;
  let scheme = &trimmed[..scheme_end];
  let after_scheme = &trimmed[scheme_end + 3..];
  let authority = after_scheme.split('/').next().unwrap_or(after_scheme);
  if authority.is_empty() {
    return None;
  }
  Some(format!("{scheme}://{authority}"))
}

fn extract_origin_from_path(path: &str) -> Option<String> {
  if path.starts_with("http://") || path.starts_with("https://") {
    return extract_origin_from_url(path);
  }
  None
}

fn normalize_operation_path(path: &str) -> String {
  if let Some(origin) = extract_origin_from_path(path) {
    let suffix = path.strip_prefix(&origin).unwrap_or(path);
    return normalize_absolute_path(suffix);
  }
  normalize_absolute_path(path)
}

fn normalize_absolute_path(path: &str) -> String {
  let trimmed = path.trim();
  if trimmed.is_empty() || trimmed == "/" {
    return "/".into();
  }
  if trimmed.starts_with('/') {
    trimmed.to_owned()
  } else {
    format!("/{trimmed}")
  }
}

fn path_variables_from_path(path: &str) -> Vec<NormalizedParameter> {
  let mut params = Vec::new();
  for segment in path.split('/') {
    if let Some(name) = segment.strip_prefix('{').and_then(|value| value.strip_suffix('}')) {
      params.push(NormalizedParameter {
        location: ParameterLocation::Path,
        name: name.to_owned(),
        value: format!("{{{{{name}}}}}"),
        required: true,
        enabled: true,
        value_source: ValueSource::FromExample,
      });
    }
  }
  params
}

fn parse_query_pairs(query: &str) -> Vec<NormalizedParameter> {
  if query.is_empty() {
    return vec![];
  }

  query
    .split('&')
    .filter_map(|pair| {
      let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
      if key.is_empty() {
        return None;
      }
      Some(NormalizedParameter {
        location: ParameterLocation::Query,
        name: key.to_owned(),
        value: value.to_owned(),
        required: false,
        enabled: !value.is_empty(),
        value_source: if value.is_empty() {
          ValueSource::Missing
        } else {
          ValueSource::FromExample
        },
      })
    })
    .collect()
}

struct HeaderAuthResult {
  headers: Vec<NormalizedParameter>,
  auth: Option<NormalizedAuth>,
  credentials_stripped: bool,
}

fn normalize_headers_and_auth(
  request: &Value,
  response: Option<&Value>,
  options: SpecParseOptions,
  op_ref: &str,
) -> HeaderAuthResult {
  let mut headers = Vec::new();
  let mut auth = None;
  let mut credentials_stripped = false;
  let mut saw_cookie_header = false;

  if let Some(entries) = request.get("headers").and_then(Value::as_array) {
    for entry in entries {
      let Some(obj) = entry.as_object() else {
        continue;
      };
      let Some(name) = obj.get("name").and_then(Value::as_str) else {
        continue;
      };
      if name.eq_ignore_ascii_case("content-type") {
        continue;
      }

      let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();

      if is_credential_header(name) {
        credentials_stripped = true;
        if name.eq_ignore_ascii_case("cookie") {
          saw_cookie_header = true;
        }
        if options.import_har_credentials_as_placeholders {
          if name.eq_ignore_ascii_case("authorization") {
            let placeholder = authorization_placeholder(&value);
            auth = authorization_auth(&value, &placeholder);
            headers.push(header_param(name, placeholder));
          } else if name.eq_ignore_ascii_case("cookie") {
            headers.push(header_param(name, "{{cookie}}".into()));
          }
        }
        continue;
      }

      headers.push(header_param(name, value));
    }
  }

  if request
    .get("cookies")
    .and_then(Value::as_array)
    .is_some_and(|cookies| !cookies.is_empty())
  {
    credentials_stripped = true;
    if options.import_har_credentials_as_placeholders && !saw_cookie_header {
      headers.push(header_param("Cookie", "{{cookie}}".into()));
    }
  }

  if let Some(response_headers) = response
    .and_then(|value| value.get("headers"))
    .and_then(Value::as_array)
  {
    for entry in response_headers {
      let Some(obj) = entry.as_object() else {
        continue;
      };
      let Some(name) = obj.get("name").and_then(Value::as_str) else {
        continue;
      };
      if name.eq_ignore_ascii_case("set-cookie") {
        credentials_stripped = true;
      }
    }
  }

  let _ = op_ref;
  HeaderAuthResult {
    headers,
    auth,
    credentials_stripped,
  }
}

fn header_param(name: &str, value: String) -> NormalizedParameter {
  NormalizedParameter {
    location: ParameterLocation::Header,
    name: name.to_owned(),
    value: value.clone(),
    required: false,
    enabled: !value.is_empty(),
    value_source: if value.is_empty() {
      ValueSource::Missing
    } else {
      ValueSource::FromExample
    },
  }
}

fn is_credential_header(name: &str) -> bool {
  CREDENTIAL_HEADER_NAMES
    .iter()
    .any(|candidate| name.eq_ignore_ascii_case(candidate))
}

fn authorization_placeholder(value: &str) -> String {
  let trimmed = value.trim();
  if trimmed.is_empty() {
    return "{{authorization}}".into();
  }
  if trimmed.to_ascii_lowercase().starts_with("bearer ") {
    return "Bearer {{token}}".into();
  }
  if trimmed.to_ascii_lowercase().starts_with("basic ") {
    return "Basic {{username}}:{{password}}".into();
  }
  "{{authorization}}".into()
}

fn authorization_auth(value: &str, placeholder: &str) -> Option<NormalizedAuth> {
  let trimmed = value.trim();
  if trimmed.to_ascii_lowercase().starts_with("bearer ") {
    return Some(NormalizedAuth::without_oauth2_scaffold(
      "http:bearer",
      Some("Authorization".into()),
      None,
      placeholder.to_owned(),
    ));
  }
  if trimmed.to_ascii_lowercase().starts_with("basic ") {
    return Some(NormalizedAuth::without_oauth2_scaffold(
      "http:basic",
      Some("Authorization".into()),
      None,
      placeholder.to_owned(),
    ));
  }
  None
}

fn normalize_body(
  post_data: Option<&Value>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedBody, SpecImportError> {
  let Some(post_data) = post_data.and_then(Value::as_object) else {
    return Ok(NormalizedBody::None);
  };

  let mime_type = post_data
    .get("mimeType")
    .and_then(Value::as_str)
    .unwrap_or_default()
    .to_ascii_lowercase();

  if let Some(params) = post_data.get("params").and_then(Value::as_array) {
    if !params.is_empty() {
      if mime_type.contains("multipart/form-data") {
        return Ok(NormalizedBody::FormData {
          entries: form_data_entries(params, warnings, op_ref),
        });
      }
      let fields = urlencoded_fields(params);
      if !fields.is_empty() {
        return Ok(NormalizedBody::Urlencoded { fields });
      }
    }
  }

  let text = post_data
    .get("text")
    .and_then(Value::as_str)
    .unwrap_or_default()
    .to_owned();
  if text.is_empty() {
    return Ok(NormalizedBody::None);
  }

  if mime_type.contains("json") {
    return Ok(NormalizedBody::Json { content: text });
  }

  Ok(NormalizedBody::Raw {
    content: text,
    content_type: if mime_type.is_empty() {
      "text/plain".into()
    } else {
      post_data
        .get("mimeType")
        .and_then(Value::as_str)
        .unwrap_or("text/plain")
        .to_owned()
    },
  })
}

fn urlencoded_fields(params: &[Value]) -> Vec<NormalizedKeyValue> {
  let mut fields = Vec::new();
  for entry in params {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let Some(name) = obj.get("name").and_then(Value::as_str) else {
      continue;
    };
    let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
    fields.push(NormalizedKeyValue {
      key: name.to_owned(),
      value,
      enabled: true,
    });
  }
  fields
}

fn form_data_entries(params: &[Value], warnings: &mut Vec<SpecWarning>, op_ref: &str) -> Vec<NormalizedFormDataEntry> {
  let mut entries = Vec::new();
  for entry in params {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let Some(name) = obj.get("name").and_then(Value::as_str) else {
      continue;
    };
    let file_name = obj.get("fileName").and_then(Value::as_str);
    let is_file = file_name.is_some();
    if is_file {
      warnings.push(SpecWarning {
        code: "FILE_PART_PLACEHOLDER".into(),
        message: "Multipart file parts import as placeholders".into(),
        operation_ref: Some(op_ref.to_owned()),
      });
    }
    entries.push(NormalizedFormDataEntry {
      key: name.to_owned(),
      value: obj
        .get("value")
        .or_else(|| obj.get("text"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned(),
      is_file,
      file_name: file_name.map(str::to_owned),
      content_type: obj.get("contentType").and_then(Value::as_str).map(str::to_owned),
    });
  }
  entries
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  fn sample_har() -> Value {
    json!({
      "log": {
        "version": "1.2",
        "creator": { "name": "HAR Demo" },
        "entries": [
          {
            "comment": "List pets",
            "request": {
              "method": "GET",
              "url": "https://api.example.com/pets?limit=5",
              "headers": [
                { "name": "Accept", "value": "application/json" },
                { "name": "Cookie", "value": "session=secret" },
                { "name": "Authorization", "value": "Bearer secret-token" }
              ]
            },
            "response": {
              "status": 200,
              "headers": [
                { "name": "Set-Cookie", "value": "session=secret; HttpOnly" }
              ]
            }
          },
          {
            "request": {
              "method": "POST",
              "url": "https://api.example.com/pets",
              "headers": [
                { "name": "Content-Type", "value": "application/json" }
              ],
              "postData": {
                "mimeType": "application/json",
                "text": "{\"name\":\"Ada\"}"
              }
            }
          }
        ]
      }
    })
  }

  #[test]
  fn detects_har_log() {
    assert!(is_har_log(&sample_har()));
    assert!(!is_har_log(&json!({"openapi":"3.0.0"})));
  }

  #[test]
  fn strips_credentials_by_default() {
    let result = normalize_har(sample_har(), SpecParseOptions::default()).expect("normalize");
    assert_eq!(result.project.operations.len(), 2);
    assert_eq!(result.project.operations[0].path, "/pets");
    let list_pets = &result.project.operations[0];
    assert!(
      list_pets
        .parameters
        .iter()
        .any(|param| param.location == ParameterLocation::Query && param.name == "limit")
    );
    assert!(
      list_pets
        .parameters
        .iter()
        .any(|param| param.location == ParameterLocation::Header && param.name == "Accept")
    );
    assert!(!list_pets.parameters.iter().any(|param| {
      param.location == ParameterLocation::Header
        && (param.name.eq_ignore_ascii_case("cookie") || param.name.eq_ignore_ascii_case("authorization"))
    }));
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "HAR_CREDENTIALS_STRIPPED")
    );
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "MIGRATION_FROM_HAR")
    );
  }

  #[test]
  fn imports_credentials_as_placeholders_when_enabled() {
    let result = normalize_har(
      sample_har(),
      SpecParseOptions {
        enable_schema_synthesis: false,
        import_har_credentials_as_placeholders: true,
      },
    )
    .expect("normalize");

    let headers: Vec<_> = result.project.operations[0]
      .parameters
      .iter()
      .filter(|param| param.location == ParameterLocation::Header)
      .collect();
    assert!(
      headers
        .iter()
        .any(|param| param.name == "Cookie" && param.value == "{{cookie}}")
    );
    assert!(
      headers
        .iter()
        .any(|param| param.name == "Authorization" && param.value == "Bearer {{token}}")
    );
    assert!(result.project.operations[0].auth.is_some());
  }

  #[test]
  fn rejects_non_har_document() {
    let err = normalize_har(json!({"openapi":"3.0.0"}), SpecParseOptions::default()).expect_err("not har");
    assert!(matches!(err, SpecImportError::UnsupportedFormat(_)));
  }
}
