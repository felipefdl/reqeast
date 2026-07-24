//! Postman Collection v2.1 export from project HTTP request data.

use std::collections::{HashMap, HashSet};

use serde_json::{Map, Value, json};

use crate::spec_import::export_types::{
  ExportAuthType, ExportBodyType, ExportEnvironment, ExportFolder, ExportFormDataEntry,
  ExportHttpRequestData, ExportKeyValue, ExportOperation, ExportPostmanOptions, ExportProjectInput,
  SpecExportError,
};
use crate::spec_import::types::{
  NormalizedAuth, NormalizedBody, NormalizedFormDataEntry, NormalizedKeyValue, NormalizedOperation,
  NormalizedProject, ParameterLocation,
};

const POSTMAN_SCHEMA: &str =
  "https://schema.getpostman.com/json/collection/v2.1.0/collection.json";

const SENSITIVE_HEADERS: &[&str] = &["authorization", "cookie", "x-api-key"];

/// Serializes a project slice to Postman Collection v2.1 JSON bytes.
#[uniffi::export]
pub fn export_postman(
  input: ExportProjectInput,
  options: ExportPostmanOptions,
) -> Result<Vec<u8>, SpecExportError> {
  let collection = build_collection(&input, &options)?;
  serde_json::to_vec_pretty(&collection)
    .map_err(|err| SpecExportError::InvalidInput(format!("Failed to serialize Postman collection: {err}")))
}

/// Builds export input from normalized IR using the same defaults as Swift `SpecImportMapper`.
pub fn export_input_from_normalized(project: &NormalizedProject) -> ExportProjectInput {
  ExportProjectInput {
    title: project.title.clone(),
    description: project.description.clone(),
    version: project.version.clone(),
    folders: project
      .folders
      .iter()
      .map(|folder| ExportFolder {
        id: folder.id.clone(),
        parent_id: folder.parent_id.clone(),
        name: folder.name.clone(),
        sort_order: folder.sort_hint,
      })
      .collect(),
    operations: project
      .operations
      .iter()
      .enumerate()
      .filter(|(_, operation)| operation.protocol == crate::spec_import::types::OperationProtocol::Http)
      .map(|(index, operation)| normalized_operation_to_export(operation, index as u32))
      .collect(),
    environments: project
      .environments
      .iter()
      .enumerate()
      .map(|(index, environment)| ExportEnvironment {
        name: environment.name.clone(),
        variables: environment
          .variables
          .iter()
          .map(|variable| ExportKeyValue {
            key: variable.key.clone(),
            value: variable.value.clone(),
            enabled: variable.enabled,
          })
          .collect(),
        is_active: index == 0,
      })
      .collect(),
  }
}

fn normalized_operation_to_export(operation: &NormalizedOperation, sort_order: u32) -> ExportOperation {
  ExportOperation {
    name: strip_deprecated_prefix(&operation.name),
    folder_id: operation.folder_id.clone(),
    sort_order,
    deprecated: operation.deprecated,
    description: operation.description.clone(),
    spec_primary_key: Some(operation.primary_key.clone()),
    request_body_content_types: operation
      .body_candidates
      .iter()
      .map(|candidate| candidate.content_type.clone())
      .collect(),
    http: normalized_http_from_operation(operation),
  }
}

fn strip_deprecated_prefix(name: &str) -> String {
  name
    .strip_prefix("[Deprecated] ")
    .unwrap_or(name)
    .to_owned()
}

fn normalized_http_from_operation(operation: &NormalizedOperation) -> ExportHttpRequestData {
  let mut http = ExportHttpRequestData {
    method: operation.method.clone(),
    url: request_url_for_path(&operation.path),
    params: vec![],
    headers: vec![],
    body_type: ExportBodyType::None,
    body_content: String::new(),
    body_form_data: vec![],
    body_form_data_entries: vec![],
    raw_content_type: "text/plain".into(),
    binary_file_name: String::new(),
    auth_type: ExportAuthType::None,
    auth_token: String::new(),
    auth_username: String::new(),
    auth_password: String::new(),
    auth_api_key_name: String::new(),
    auth_api_key_value: String::new(),
    auth_api_key_location: "header".into(),
  };

  for parameter in &operation.parameters {
    match parameter.location {
      ParameterLocation::Query | ParameterLocation::Cookie => {
        http.params.push(ExportKeyValue {
          key: parameter.name.clone(),
          value: parameter.value.clone(),
          enabled: parameter.enabled,
        });
      }
      ParameterLocation::Header => {
        http.headers.push(ExportKeyValue {
          key: parameter.name.clone(),
          value: parameter.value.clone(),
          enabled: parameter.enabled,
        });
      }
      ParameterLocation::Path => {}
    }
  }

  apply_normalized_body(&mut http, &operation.body);

  if let Some(auth) = &operation.auth {
    apply_normalized_auth(&mut http, auth);
  }

  http
}

fn request_url_for_path(path: &str) -> String {
  let templated_path = path.replace('{', "{{").replace('}', "}}");
  format!("{{{{base_url}}}}{templated_path}")
}

fn apply_normalized_body(http: &mut ExportHttpRequestData, body: &NormalizedBody) {
  match body {
    NormalizedBody::None => {}
    NormalizedBody::Json { content } => {
      http.body_type = ExportBodyType::Json;
      http.body_content = content.clone();
    }
    NormalizedBody::Urlencoded { fields } => {
      http.body_type = ExportBodyType::Urlencoded;
      http.body_form_data = fields.iter().map(key_value_to_export).collect();
    }
    NormalizedBody::FormData { entries } => {
      http.body_type = ExportBodyType::FormData;
      http.body_form_data_entries = entries.iter().map(form_data_to_export).collect();
    }
    NormalizedBody::Raw { content, content_type } => {
      http.body_type = ExportBodyType::Raw;
      http.body_content = content.clone();
      http.raw_content_type = content_type.clone();
    }
    NormalizedBody::Binary { file_name } => {
      http.body_type = ExportBodyType::Binary;
      http.binary_file_name = file_name.clone();
    }
  }
}

fn key_value_to_export(field: &NormalizedKeyValue) -> ExportKeyValue {
  ExportKeyValue {
    key: field.key.clone(),
    value: field.value.clone(),
    enabled: field.enabled,
  }
}

fn form_data_to_export(entry: &NormalizedFormDataEntry) -> ExportFormDataEntry {
  ExportFormDataEntry {
    key: entry.key.clone(),
    value: entry.value.clone(),
    enabled: true,
    is_file: entry.is_file,
    file_name: entry.file_name.clone().unwrap_or_default(),
    content_type: entry.content_type.clone().unwrap_or_default(),
  }
}

fn apply_normalized_auth(http: &mut ExportHttpRequestData, auth: &NormalizedAuth) {
  match auth.scheme_type.as_str() {
    "apiKey" => {
      http.auth_type = ExportAuthType::ApiKey;
      http.auth_api_key_name = auth
        .header_name
        .clone()
        .or_else(|| auth.query_name.clone())
        .unwrap_or_else(|| "X-API-Key".into());
      http.auth_api_key_value = auth.placeholder_value.clone();
      http.auth_api_key_location = if auth.query_name.is_some() {
        "query".into()
      } else {
        "header".into()
      };
    }
    "http:basic" => {
      http.auth_type = ExportAuthType::Basic;
      parse_basic_placeholder(&auth.placeholder_value, http);
    }
    "oauth2" => {
      http.auth_type = ExportAuthType::Oauth2;
      http.auth_token = token_without_prefix(&auth.placeholder_value, "Bearer ");
    }
    "http:bearer" | "openIdConnect" => {
      http.auth_type = ExportAuthType::Bearer;
      http.auth_token = token_without_prefix(&auth.placeholder_value, "Bearer ");
    }
    _ => {
      http.auth_type = ExportAuthType::Bearer;
      http.auth_token = auth.placeholder_value.clone();
    }
  }
}

fn token_without_prefix(value: &str, prefix: &str) -> String {
  value
    .strip_prefix(prefix)
    .unwrap_or(value)
    .to_owned()
}

fn parse_basic_placeholder(value: &str, http: &mut ExportHttpRequestData) {
  let stripped = value.strip_prefix("Basic ").unwrap_or(value);
  if let Some((username, password)) = stripped.split_once(':') {
    http.auth_username = username.to_owned();
    http.auth_password = password.to_owned();
  } else {
    http.auth_username = "{{username}}".into();
    http.auth_password = "{{password}}".into();
  }
}

fn build_collection(
  input: &ExportProjectInput,
  options: &ExportPostmanOptions,
) -> Result<Value, SpecExportError> {
  let operations: Vec<_> = input
    .operations
    .iter()
    .filter(|operation| options.include_deprecated || !operation.deprecated)
    .collect();

  if operations.is_empty() {
    return Err(SpecExportError::InvalidInput(
      "Export contains no HTTP operations".into(),
    ));
  }

  let collection_auth = detect_uniform_auth(&operations);

  let mut info = Map::new();
  info.insert("name".into(), Value::String(input.title.clone()));
  info.insert("schema".into(), Value::String(POSTMAN_SCHEMA.into()));
  if let Some(description) = &input.description {
    if !description.is_empty() {
      info.insert("description".into(), Value::String(description.clone()));
    }
  }

  let mut collection = Map::new();
  collection.insert("info".into(), Value::Object(info));
  collection.insert(
    "item".into(),
    Value::Array(build_items(
      &input.folders,
      &operations,
      collection_auth.is_some(),
    )?),
  );

  if options.include_environments {
    if let Some(variables) = collection_variables(&input.environments) {
      collection.insert("variable".into(), variables);
    }
  }

  if let Some(auth) = collection_auth {
    collection.insert("auth".into(), auth);
  }

  Ok(Value::Object(collection))
}

fn collection_variables(environments: &[ExportEnvironment]) -> Option<Value> {
  let environment = environments
    .iter()
    .find(|env| env.is_active)
    .or_else(|| environments.first())?;

  let variables: Vec<Value> = environment
    .variables
    .iter()
    .filter(|variable| variable.enabled && !variable.key.is_empty())
    .map(|variable| {
      json!({
        "key": variable.key,
        "value": variable.value,
      })
    })
    .collect();

  if variables.is_empty() {
    None
  } else {
    Some(Value::Array(variables))
  }
}

fn detect_uniform_auth(operations: &[&ExportOperation]) -> Option<Value> {
  let auths: Vec<Value> = operations
    .iter()
    .filter_map(|operation| build_request_auth(&operation.http, true))
    .collect();
  if auths.is_empty() {
    return None;
  }
  if auths.iter().all(|auth| auth == &auths[0]) {
    Some(auths[0].clone())
  } else {
    None
  }
}

fn build_items(
  folders: &[ExportFolder],
  operations: &[&ExportOperation],
  has_collection_auth: bool,
) -> Result<Vec<Value>, SpecExportError> {
  let mut children_by_parent: HashMap<Option<String>, Vec<&ExportFolder>> = HashMap::new();
  for folder in folders {
    children_by_parent
      .entry(folder.parent_id.clone())
      .or_default()
      .push(folder);
  }
  for children in children_by_parent.values_mut() {
    children.sort_by_key(|folder| folder.sort_order);
  }

  let mut operations_by_folder: HashMap<Option<String>, Vec<&ExportOperation>> = HashMap::new();
  for operation in operations {
    operations_by_folder
      .entry(operation.folder_id.clone())
      .or_default()
      .push(operation);
  }
  for ops in operations_by_folder.values_mut() {
    ops.sort_by_key(|operation| operation.sort_order);
  }

  build_mixed_items(
    None,
    &children_by_parent,
    &operations_by_folder,
    has_collection_auth,
  )
}

fn build_mixed_items(
  parent_id: Option<&str>,
  children_by_parent: &HashMap<Option<String>, Vec<&ExportFolder>>,
  operations_by_folder: &HashMap<Option<String>, Vec<&ExportOperation>>,
  has_collection_auth: bool,
) -> Result<Vec<Value>, SpecExportError> {
  let parent_key = parent_id.map(str::to_owned);
  let mut mixed: Vec<(u32, Value)> = Vec::new();

  if let Some(folders) = children_by_parent.get(&parent_key) {
    for folder in folders {
      let child_items = build_mixed_items(
        Some(&folder.id),
        children_by_parent,
        operations_by_folder,
        has_collection_auth,
      )?;
      let mut obj = Map::new();
      obj.insert("name".into(), Value::String(folder.name.clone()));
      obj.insert("item".into(), Value::Array(child_items));
      mixed.push((folder.sort_order, Value::Object(obj)));
    }
  }

  if let Some(operations) = operations_by_folder.get(&parent_key) {
    for operation in operations {
      mixed.push((
        operation.sort_order,
        build_request_item(operation, has_collection_auth)?,
      ));
    }
  }

  mixed.sort_by_key(|(order, _)| *order);
  Ok(mixed.into_iter().map(|(_, item)| item).collect())
}

fn build_request_item(
  operation: &ExportOperation,
  has_collection_auth: bool,
) -> Result<Value, SpecExportError> {
  let mut request = Map::new();
  request.insert(
    "method".into(),
    Value::String(operation.http.method.to_ascii_uppercase()),
  );
  request.insert("url".into(), build_url(&operation.http));

  if let Some(headers) = build_headers(&operation.http) {
    request.insert("header".into(), headers);
  }

  if let Some(body) = build_body(&operation.http) {
    request.insert("body".into(), body);
  }

  if !has_collection_auth {
    if let Some(auth) = build_request_auth(&operation.http, true) {
      request.insert("auth".into(), auth);
    }
  }

  if let Some(description) = &operation.description {
    if !description.is_empty() {
      request.insert("description".into(), Value::String(description.clone()));
    }
  }

  let mut item = Map::new();
  item.insert("name".into(), Value::String(operation.name.clone()));
  item.insert("request".into(), Value::Object(request));
  Ok(Value::Object(item))
}

fn build_headers(http: &ExportHttpRequestData) -> Option<Value> {
  let mut headers: Vec<Value> = http
    .headers
    .iter()
    .filter(|header| header.enabled && !header.key.is_empty())
    .filter(|header| !is_sensitive_header(&header.key))
    .map(|header| {
      json!({
        "key": header.key,
        "value": header.value,
      })
    })
    .collect();

  if http.body_type == ExportBodyType::Json
    && !headers.iter().any(|header| {
      header
        .get("key")
        .and_then(Value::as_str)
        .is_some_and(|key| key.eq_ignore_ascii_case("content-type"))
    })
  {
    headers.push(json!({
      "key": "Content-Type",
      "value": "application/json",
    }));
  }

  if headers.is_empty() {
    None
  } else {
    Some(Value::Array(headers))
  }
}

fn is_sensitive_header(name: &str) -> bool {
  SENSITIVE_HEADERS.contains(&name.to_ascii_lowercase().as_str())
}

fn build_body(http: &ExportHttpRequestData) -> Option<Value> {
  match http.body_type {
    ExportBodyType::None => None,
    ExportBodyType::Json => Some(json!({
      "mode": "raw",
      "raw": http.body_content,
      "options": {
        "raw": {
          "language": "json"
        }
      }
    })),
    ExportBodyType::Urlencoded => {
      let fields: Vec<Value> = http
        .body_form_data
        .iter()
        .filter(|field| field.enabled && !field.key.is_empty())
        .map(|field| {
          json!({
            "key": field.key,
            "value": field.value,
          })
        })
        .collect();
      if fields.is_empty() {
        None
      } else {
        Some(json!({
          "mode": "urlencoded",
          "urlencoded": fields,
        }))
      }
    }
    ExportBodyType::FormData => {
      let entries: Vec<Value> = http
        .body_form_data_entries
        .iter()
        .filter(|entry| entry.enabled && !entry.key.is_empty())
        .map(build_form_data_entry)
        .collect();
      if entries.is_empty() {
        None
      } else {
        Some(json!({
          "mode": "formdata",
          "formdata": entries,
        }))
      }
    }
    ExportBodyType::Raw => {
      if http.body_content.is_empty() {
        return None;
      }
      Some(json!({
        "mode": "raw",
        "raw": http.body_content,
        "options": {
          "raw": {
            "language": raw_language(&http.raw_content_type)
          }
        }
      }))
    }
    ExportBodyType::Binary => Some(json!({
      "mode": "file",
      "file": {
        "src": http.binary_file_name
      }
    })),
  }
}

fn build_form_data_entry(entry: &ExportFormDataEntry) -> Value {
  if entry.is_file {
    let mut obj = Map::from_iter([
      ("key".into(), Value::String(entry.key.clone())),
      ("type".into(), Value::String("file".into())),
    ]);
    if !entry.file_name.is_empty() {
      obj.insert("src".into(), Value::String(entry.file_name.clone()));
    } else if !entry.value.is_empty() {
      obj.insert("src".into(), Value::String(entry.value.clone()));
    }
    Value::Object(obj)
  } else {
    let mut obj = Map::from_iter([
      ("key".into(), Value::String(entry.key.clone())),
      ("value".into(), Value::String(entry.value.clone())),
      ("type".into(), Value::String("text".into())),
    ]);
    if !entry.content_type.is_empty() {
      obj.insert("contentType".into(), Value::String(entry.content_type.clone()));
    }
    Value::Object(obj)
  }
}

fn raw_language(content_type: &str) -> String {
  let normalized = content_type.split(';').next().unwrap_or(content_type).trim();
  if normalized.contains("json") {
    "json".into()
  } else if normalized.contains("xml") {
    "xml".into()
  } else if normalized.contains("html") {
    "html".into()
  } else if normalized.contains("javascript") {
    "javascript".into()
  } else {
    "text".into()
  }
}

fn build_url(http: &ExportHttpRequestData) -> Value {
  let path_suffix = strip_base_url(&http.url);
  let (path_segments, path_variables) = path_segments_and_variables(&path_suffix);
  let query: Vec<Value> = http
    .params
    .iter()
    .filter(|param| param.enabled && !param.key.is_empty())
    .map(|param| {
      json!({
        "key": param.key,
        "value": param.value,
      })
    })
    .collect();

  if query.is_empty() && path_variables.is_empty() {
    return Value::String(http.url.clone());
  }

  let raw = build_raw_url(&http.url, &query);
  let mut url_obj = Map::new();
  url_obj.insert("raw".into(), Value::String(raw));
  url_obj.insert("host".into(), json!(["{{base_url}}"]));
  url_obj.insert("path".into(), Value::Array(path_segments));
  if !query.is_empty() {
    url_obj.insert("query".into(), Value::Array(query));
  }
  if !path_variables.is_empty() {
    url_obj.insert("variable".into(), Value::Array(path_variables));
  }
  Value::Object(url_obj)
}

fn strip_base_url(url: &str) -> String {
  let trimmed = url.trim();
  if let Some(suffix) = trimmed.strip_prefix("{{base_url}}") {
    return normalize_path_suffix(suffix);
  }
  if let Some(path_start) = trimmed.find("://") {
    let after_scheme = &trimmed[path_start + 3..];
    if let Some(path_index) = after_scheme.find('/') {
      return normalize_path_suffix(&after_scheme[path_index..]);
    }
    return "/".into();
  }
  normalize_path_suffix(trimmed)
}

fn normalize_path_suffix(path: &str) -> String {
  let trimmed = path.trim();
  if trimmed.is_empty() {
    "/".into()
  } else if trimmed.starts_with('/') {
    trimmed.to_owned()
  } else {
    format!("/{trimmed}")
  }
}

fn path_segments_and_variables(path: &str) -> (Vec<Value>, Vec<Value>) {
  let trimmed = path.trim();
  let segments_source = trimmed.strip_prefix('/').unwrap_or(trimmed);
  if segments_source.is_empty() {
    return (vec![], vec![]);
  }

  let mut segments = Vec::new();
  let mut variables = Vec::new();
  let mut seen_variables = HashSet::new();

  for segment in segments_source.split('/') {
    if segment.is_empty() {
      continue;
    }
    if let Some(name) = segment
      .strip_prefix("{{")
      .and_then(|value| value.strip_suffix("}}"))
    {
      segments.push(Value::String(format!(":{name}")));
      if seen_variables.insert(name.to_owned()) {
        variables.push(json!({
          "key": name,
          "value": segment,
        }));
      }
    } else {
      segments.push(Value::String(segment.to_owned()));
    }
  }

  (segments, variables)
}

fn build_raw_url(base_url: &str, query: &[Value]) -> String {
  if query.is_empty() {
    return base_url.to_owned();
  }
  let query_string = query
    .iter()
    .filter_map(|entry| {
      let key = entry.get("key")?.as_str()?;
      let value = entry.get("value").and_then(Value::as_str).unwrap_or_default();
      Some(format!("{key}={value}"))
    })
    .collect::<Vec<_>>()
    .join("&");
  format!("{base_url}?{query_string}")
}

fn build_request_auth(http: &ExportHttpRequestData, sanitize: bool) -> Option<Value> {
  match http.auth_type {
    ExportAuthType::None => None,
    ExportAuthType::ApiKey => Some(json!({
      "type": "apikey",
      "apikey": [
        {"key": "key", "value": if http.auth_api_key_name.is_empty() { "X-API-Key" } else { http.auth_api_key_name.as_str() }},
        {"key": "value", "value": auth_placeholder(&http.auth_api_key_value, "{{api_key}}", sanitize)},
        {"key": "in", "value": if http.auth_api_key_location.is_empty() { "header" } else { http.auth_api_key_location.as_str() }},
      ]
    })),
    ExportAuthType::Bearer => Some(json!({
      "type": "bearer",
      "bearer": [
        {"key": "token", "value": bearer_placeholder(&http.auth_token, sanitize)},
      ]
    })),
    ExportAuthType::Basic => Some(json!({
      "type": "basic",
      "basic": [
        {"key": "username", "value": auth_placeholder(&http.auth_username, "{{username}}", sanitize)},
        {"key": "password", "value": auth_placeholder(&http.auth_password, "{{password}}", sanitize)},
      ]
    })),
    ExportAuthType::Oauth2 => Some(json!({
      "type": "oauth2",
      "oauth2": [
        {"key": "token", "value": bearer_placeholder(&http.auth_token, sanitize)},
      ]
    })),
  }
}

fn auth_placeholder(value: &str, fallback: &str, sanitize: bool) -> String {
  if !sanitize {
    return value.to_owned();
  }
  if value.is_empty() || looks_like_secret(value) {
    fallback.to_owned()
  } else {
    value.to_owned()
  }
}

fn bearer_placeholder(token: &str, sanitize: bool) -> String {
  if !sanitize {
    return token.to_owned();
  }
  if token.is_empty() || looks_like_secret(token) {
    "{{token}}".into()
  } else {
    token.to_owned()
  }
}

fn looks_like_secret(value: &str) -> bool {
  if value.contains("{{") && value.contains("}}") {
    return false;
  }
  value.len() > 20
    && value
      .chars()
      .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::spec_import::golden::{parse_fixture, result_to_json};
  use crate::spec_import::postman::normalize_postman;
  use crate::spec_import::types::{SpecParseOptions, SpecSourceHint, parse_spec};
  use serde_json::Value;

  fn project_from_result(result: &crate::spec_import::types::SpecImportResult) -> Value {
    result_to_json(result).get("project").cloned().expect("project")
  }

  #[test]
  fn export_postman_produces_collection_schema() {
    let input = ExportProjectInput {
      title: "Demo".into(),
      description: None,
      version: None,
      folders: vec![],
      operations: vec![ExportOperation {
        name: "Ping".into(),
        folder_id: None,
        sort_order: 0,
        deprecated: false,
        description: None,
        spec_primary_key: Some("GET /ping".into()),
        request_body_content_types: vec![],
        http: ExportHttpRequestData {
          method: "GET".into(),
          url: "{{base_url}}/ping".into(),
          params: vec![],
          headers: vec![],
          body_type: ExportBodyType::None,
          body_content: String::new(),
          body_form_data: vec![],
          body_form_data_entries: vec![],
          raw_content_type: "text/plain".into(),
          binary_file_name: String::new(),
          auth_type: ExportAuthType::None,
          auth_token: String::new(),
          auth_username: String::new(),
          auth_password: String::new(),
          auth_api_key_name: String::new(),
          auth_api_key_value: String::new(),
          auth_api_key_location: "header".into(),
        },
      }],
      environments: vec![ExportEnvironment {
        name: "Collection".into(),
        variables: vec![ExportKeyValue {
          key: "base_url".into(),
          value: "https://api.example.com".into(),
          enabled: true,
        }],
        is_active: true,
      }],
    };

    let bytes = export_postman(input, ExportPostmanOptions::default()).expect("export");
    let value: Value = serde_json::from_slice(&bytes).expect("json");
    assert!(value
      .get("info")
      .and_then(|info| info.get("schema"))
      .and_then(Value::as_str)
      .is_some_and(|schema| schema.contains("postman")));
  }

  #[test]
  fn export_never_emits_raw_secrets() {
    let input = ExportProjectInput {
      title: "Auth".into(),
      description: None,
      version: None,
      folders: vec![],
      operations: vec![ExportOperation {
        name: "Secret".into(),
        folder_id: None,
        sort_order: 0,
        deprecated: false,
        description: None,
        spec_primary_key: None,
        request_body_content_types: vec![],
        http: ExportHttpRequestData {
          method: "GET".into(),
          url: "{{base_url}}/health".into(),
          params: vec![],
          headers: vec![ExportKeyValue {
            key: "Authorization".into(),
            value: "Bearer super-secret-token-value".into(),
            enabled: true,
          }],
          body_type: ExportBodyType::None,
          body_content: String::new(),
          body_form_data: vec![],
          body_form_data_entries: vec![],
          raw_content_type: "text/plain".into(),
          binary_file_name: String::new(),
          auth_type: ExportAuthType::Bearer,
          auth_token: "super-secret-token-value".into(),
          auth_username: String::new(),
          auth_password: String::new(),
          auth_api_key_name: String::new(),
          auth_api_key_value: String::new(),
          auth_api_key_location: "header".into(),
        },
      }],
      environments: vec![],
    };

    let bytes = export_postman(input, ExportPostmanOptions::default()).expect("export");
    let text = String::from_utf8(bytes).expect("utf8");
    assert!(!text.contains("super-secret-token-value"));
    assert!(text.contains("{{token}}"));
  }

  #[test]
  fn postman_nested_round_trip_ac20() {
    let imported = parse_fixture("postman-nested").expect("import");
    let export_input = export_input_from_normalized(&imported.project);
    let exported = export_postman(export_input, ExportPostmanOptions::default()).expect("export");
    let roundtrip = parse_spec(
      exported,
      SpecSourceHint::Postman,
      None,
      SpecParseOptions::default(),
    )
    .expect("re-import");

    assert_eq!(
      project_from_result(&imported),
      project_from_result(&roundtrip),
      "postman-nested export round-trip project mismatch"
    );
  }

  #[test]
  fn postman_vars_round_trip_ac20() {
    let imported = parse_fixture("postman-vars").expect("import");
    let export_input = export_input_from_normalized(&imported.project);
    let exported = export_postman(export_input, ExportPostmanOptions::default()).expect("export");
    let value: Value = serde_json::from_slice(&exported).expect("json");
    assert!(value.get("auth").is_some());

    let roundtrip = parse_spec(
      exported,
      SpecSourceHint::Postman,
      None,
      SpecParseOptions::default(),
    )
    .expect("re-import");

    assert_eq!(
      project_from_result(&imported),
      project_from_result(&roundtrip),
      "postman-vars export round-trip project mismatch"
    );
  }

  #[test]
  fn normalize_exported_collection_is_valid_postman() {
    let imported = parse_fixture("postman-nested").expect("import");
    let export_input = export_input_from_normalized(&imported.project);
    let exported = export_postman(export_input, ExportPostmanOptions::default()).expect("export");
    let value: Value = serde_json::from_slice(&exported).expect("json");
    normalize_postman(value).expect("normalize exported collection");
  }
}