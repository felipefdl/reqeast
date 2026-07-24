//! Postman Collection v2.1 normalization into the spec import normalized IR.

use std::collections::{BTreeMap, HashSet};

use serde_json::Value;

use crate::spec_import::fingerprint::{bundle_and_canonicalize, hash_bytes};
use crate::spec_import::normalize::NormalizeOutput;
use crate::spec_import::types::{
  NormalizedAuth, NormalizedBody, NormalizedEnvironment, NormalizedFolder, NormalizedFormDataEntry, NormalizedKeyValue,
  NormalizedOperation, NormalizedParameter, NormalizedProject, OperationProtocol, ParameterLocation, SpecImportError,
  SpecWarning, ValueSource,
};

/// Returns true when the JSON value looks like a Postman Collection v2.1 document.
pub fn is_postman_collection(value: &Value) -> bool {
  value
    .get("info")
    .and_then(|info| info.get("schema"))
    .and_then(Value::as_str)
    .is_some_and(|schema| schema.contains("postman"))
}

/// Normalize a parsed Postman Collection v2.1 JSON document into [`NormalizedProject`].
pub fn normalize_postman(value: Value) -> Result<NormalizeOutput, SpecImportError> {
  if !is_postman_collection(&value) {
    return Err(SpecImportError::UnsupportedFormat(
      "Not a Postman Collection v2.1 document".into(),
    ));
  }

  let info = value
    .get("info")
    .ok_or_else(|| SpecImportError::InvalidSpec("Postman collection missing info".into()))?;

  let title = info
    .get("name")
    .and_then(Value::as_str)
    .unwrap_or("Imported Collection")
    .to_owned();

  let description = info.get("description").and_then(description_text);

  let collection_auth = value.get("auth");
  let environments = normalize_collection_variables(value.get("variable"));

  let mut warnings = Vec::new();
  let mut folders = Vec::new();
  let mut operations = Vec::new();
  let mut seen_primary_keys = HashSet::new();

  if let Some(items) = value.get("item").and_then(Value::as_array) {
    collect_items(
      items,
      None,
      &mut folders,
      &mut operations,
      &mut seen_primary_keys,
      collection_auth,
      &mut warnings,
    )?;
  }

  if operations.is_empty() {
    return Err(SpecImportError::InvalidSpec(
      "Postman collection contains no importable HTTP requests".into(),
    ));
  }

  let fingerprint = bundle_and_canonicalize(&value)
    .map(|bytes| hash_bytes(&bytes))
    .map_err(SpecImportError::InvalidSpec)?;

  Ok(NormalizeOutput {
    project: NormalizedProject {
      title,
      description,
      version: None,
      icon_url: None,
      security_schemes: vec![],
      folders,
      operations,
      environments,
    },
    warnings,
    content_fingerprint: fingerprint,
  })
}

fn description_text(value: &Value) -> Option<String> {
  match value {
    Value::String(text) if !text.is_empty() => Some(text.clone()),
    Value::Object(obj) => obj
      .get("content")
      .and_then(Value::as_str)
      .filter(|text| !text.is_empty())
      .map(str::to_owned),
    _ => None,
  }
}

fn normalize_collection_variables(variables: Option<&Value>) -> Vec<NormalizedEnvironment> {
  let Some(entries) = variables.and_then(Value::as_array) else {
    return vec![default_environment()];
  };

  let mut pairs = Vec::new();
  for entry in entries {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
    if disabled {
      continue;
    }
    let Some(key) = obj.get("key").and_then(Value::as_str) else {
      continue;
    };
    let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
    pairs.push(NormalizedKeyValue {
      key: key.to_owned(),
      value,
      enabled: true,
    });
  }

  if pairs.is_empty() {
    return vec![default_environment()];
  }

  if !pairs.iter().any(|pair| pair.key == "base_url") {
    pairs.insert(
      0,
      NormalizedKeyValue {
        key: "base_url".into(),
        value: "/".into(),
        enabled: true,
      },
    );
  }

  vec![NormalizedEnvironment {
    name: "Collection".into(),
    variables: pairs,
  }]
}

fn default_environment() -> NormalizedEnvironment {
  NormalizedEnvironment {
    name: "Collection".into(),
    variables: vec![NormalizedKeyValue {
      key: "base_url".into(),
      value: "/".into(),
      enabled: true,
    }],
  }
}

fn collect_items(
  items: &[Value],
  parent_folder_id: Option<&str>,
  folders: &mut Vec<NormalizedFolder>,
  operations: &mut Vec<NormalizedOperation>,
  seen_primary_keys: &mut HashSet<String>,
  collection_auth: Option<&Value>,
  warnings: &mut Vec<SpecWarning>,
) -> Result<(), SpecImportError> {
  for (index, item) in items.iter().enumerate() {
    let name = item.get("name").and_then(Value::as_str).unwrap_or("Untitled");

    if item.get("request").is_some() {
      let operation = normalize_request_item(name, item, parent_folder_id, collection_auth, warnings)?;
      if !seen_primary_keys.insert(operation.primary_key.clone()) {
        return Err(SpecImportError::InvalidSpec(format!(
          "Duplicate request identity: {}",
          operation.primary_key
        )));
      }
      operations.push(operation);
      continue;
    }

    if let Some(children) = item.get("item").and_then(Value::as_array) {
      let folder_id = folder_id_for_path(parent_folder_id, name);
      folders.push(NormalizedFolder {
        id: folder_id.clone(),
        parent_id: parent_folder_id.map(str::to_owned),
        name: name.to_owned(),
        sort_hint: index as u32,
      });
      collect_items(
        children,
        Some(&folder_id),
        folders,
        operations,
        seen_primary_keys,
        collection_auth,
        warnings,
      )?;
      continue;
    }
  }

  Ok(())
}

fn folder_id_for_path(parent_folder_id: Option<&str>, name: &str) -> String {
  match parent_folder_id {
    Some(parent) => format!("{parent}/{name}"),
    None => format!("folder:{name}"),
  }
}

fn normalize_request_item(
  name: &str,
  item: &Value,
  folder_id: Option<&str>,
  collection_auth: Option<&Value>,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedOperation, SpecImportError> {
  let request = item
    .get("request")
    .ok_or_else(|| SpecImportError::InvalidSpec(format!("Request `{name}` is missing request object")))?;

  let method = request
    .get("method")
    .and_then(Value::as_str)
    .unwrap_or("GET")
    .to_ascii_uppercase();

  let parsed_url = parse_request_url(request.get("url"))?;
  let op_ref = format!("{method} {}", parsed_url.path);

  if item
    .get("response")
    .and_then(Value::as_array)
    .is_some_and(|responses| !responses.is_empty())
  {
    warnings.push(SpecWarning {
      code: "RESPONSE_NOT_IMPORTED".into(),
      message: "Postman response examples are not imported".into(),
      operation_ref: Some(op_ref.clone()),
    });
  }

  let mut parameters = parsed_url.query_params;
  parameters.extend(parsed_url.path_params);
  parameters.extend(normalize_headers(request.get("header"), &op_ref));

  let body = normalize_body(request.get("body"), request.get("header"), &op_ref, warnings)?;
  let auth = normalize_auth(request.get("auth").or(collection_auth), &op_ref, warnings);

  let description = request.get("description").and_then(description_text);

  Ok(NormalizedOperation {
    primary_key: op_ref.clone(),
    alternate_keys: vec![],
    name: name.to_owned(),
    method,
    path: parsed_url.path,
    deprecated: false,
    tags: vec![],
    protocol: OperationProtocol::Http,
    binding: None,
    folder_id: folder_id.map(str::to_owned),
    parameters,
    body,
    body_candidates: vec![],
    auth,
    description,
  })
}

struct ParsedUrl {
  path: String,
  query_params: Vec<NormalizedParameter>,
  path_params: Vec<NormalizedParameter>,
}

fn parse_request_url(url_value: Option<&Value>) -> Result<ParsedUrl, SpecImportError> {
  match url_value {
    Some(Value::String(raw)) => parse_url_string(raw),
    Some(Value::Object(obj)) => parse_url_object(obj),
    None => Ok(ParsedUrl {
      path: "/".into(),
      query_params: vec![],
      path_params: vec![],
    }),
    Some(other) => Err(SpecImportError::InvalidSpec(format!(
      "Unsupported Postman url type: {other}"
    ))),
  }
}

fn parse_url_string(raw: &str) -> Result<ParsedUrl, SpecImportError> {
  let without_query = raw.split('?').next().unwrap_or(raw);
  let path = extract_path_from_raw(without_query);
  let query_params = parse_query_string(raw.split('?').nth(1).unwrap_or_default());
  let path_params = path_variables_from_path(&path);
  Ok(ParsedUrl {
    path,
    query_params,
    path_params,
  })
}

fn parse_url_object(obj: &serde_json::Map<String, Value>) -> Result<ParsedUrl, SpecImportError> {
  let path = if let Some(path_segments) = obj.get("path").and_then(Value::as_array) {
    let segments: Vec<String> = path_segments
      .iter()
      .filter_map(Value::as_str)
      .map(normalize_path_segment)
      .collect();
    if segments.is_empty() {
      "/".into()
    } else {
      format!("/{}", segments.join("/"))
    }
  } else if let Some(raw) = obj.get("raw").and_then(Value::as_str) {
    extract_path_from_raw(raw.split('?').next().unwrap_or(raw))
  } else {
    "/".into()
  };

  let mut path_params = path_variables_from_path(&path);
  if let Some(variables) = obj.get("variable").and_then(Value::as_array) {
    for variable in variables {
      let Some(variable_obj) = variable.as_object() else {
        continue;
      };
      let disabled = variable_obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
      if disabled {
        continue;
      }
      let Some(key) = variable_obj.get("key").and_then(Value::as_str) else {
        continue;
      };
      let value = variable_obj.get("value").and_then(Value::as_str).unwrap_or_default();
      path_params.push(NormalizedParameter {
        location: ParameterLocation::Path,
        name: key.to_owned(),
        value: format!("{{{{{key}}}}}"),
        required: true,
        enabled: true,
        value_source: if value.is_empty() {
          ValueSource::Missing
        } else {
          ValueSource::FromExample
        },
      });
    }
  }

  let query_params = if let Some(query) = obj.get("query").and_then(Value::as_array) {
    normalize_query_array(query)
  } else if let Some(raw) = obj.get("raw").and_then(Value::as_str) {
    parse_query_string(raw.split('?').nth(1).unwrap_or_default())
  } else {
    vec![]
  };

  dedupe_path_params(&mut path_params);

  Ok(ParsedUrl {
    path,
    query_params,
    path_params,
  })
}

fn normalize_path_segment(segment: &str) -> String {
  if let Some(stripped) = segment.strip_prefix(':') {
    format!("{{{stripped}}}")
  } else {
    segment.to_owned()
  }
}

fn extract_path_from_raw(raw: &str) -> String {
  let trimmed = raw.trim();
  if trimmed.is_empty() {
    return "/".into();
  }

  if trimmed.starts_with("{{base_url}}") {
    let suffix = trimmed.trim_start_matches("{{base_url}}");
    return normalize_absolute_path(suffix);
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

fn dedupe_path_params(params: &mut Vec<NormalizedParameter>) {
  let mut seen = HashSet::new();
  params.retain(|param| seen.insert(param.name.clone()));
}

fn parse_query_string(query: &str) -> Vec<NormalizedParameter> {
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

fn normalize_query_array(query: &[Value]) -> Vec<NormalizedParameter> {
  let mut params = Vec::new();
  for entry in query {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
    if disabled {
      continue;
    }
    let Some(key) = obj.get("key").and_then(Value::as_str) else {
      continue;
    };
    let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
    params.push(NormalizedParameter {
      location: ParameterLocation::Query,
      name: key.to_owned(),
      value: value.clone(),
      required: false,
      enabled: true,
      value_source: if value.is_empty() {
        ValueSource::Missing
      } else {
        ValueSource::FromExample
      },
    });
  }
  params
}

fn normalize_headers(headers: Option<&Value>, op_ref: &str) -> Vec<NormalizedParameter> {
  let Some(entries) = headers.and_then(Value::as_array) else {
    return vec![];
  };

  let mut params = Vec::new();
  for entry in entries {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
    let Some(key) = obj.get("key").and_then(Value::as_str) else {
      continue;
    };
    if key.eq_ignore_ascii_case("content-type") {
      continue;
    }
    let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
    params.push(NormalizedParameter {
      location: ParameterLocation::Header,
      name: key.to_owned(),
      value: value.clone(),
      required: false,
      enabled: !disabled,
      value_source: if value.is_empty() {
        ValueSource::Missing
      } else {
        ValueSource::FromExample
      },
    });
  }

  let _ = op_ref;
  params
}

fn normalize_body(
  body: Option<&Value>,
  headers: Option<&Value>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedBody, SpecImportError> {
  let Some(body_obj) = body.and_then(Value::as_object) else {
    return Ok(NormalizedBody::None);
  };

  let mode = body_obj.get("mode").and_then(Value::as_str).unwrap_or("raw");

  match mode {
    "raw" => {
      let content = body_obj
        .get("raw")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
      if content.is_empty() {
        return Ok(NormalizedBody::None);
      }

      let content_type = raw_content_type(body_obj, headers);
      if content_type.contains("json") {
        Ok(NormalizedBody::Json { content })
      } else {
        Ok(NormalizedBody::Raw { content, content_type })
      }
    }
    "urlencoded" => {
      let fields = key_value_entries(body_obj.get("urlencoded"));
      if fields.is_empty() {
        Ok(NormalizedBody::None)
      } else {
        Ok(NormalizedBody::Urlencoded { fields })
      }
    }
    "formdata" => Ok(NormalizedBody::FormData {
      entries: form_data_entries(body_obj.get("formdata"), warnings, op_ref),
    }),
    "file" => Ok(NormalizedBody::Binary {
      file_name: body_obj
        .get("file")
        .and_then(Value::as_object)
        .and_then(|file| file.get("src"))
        .and_then(Value::as_str)
        .map(|src| src.rsplit('/').next().unwrap_or(src).to_owned())
        .unwrap_or_else(|| "upload.bin".into()),
    }),
    "graphql" => {
      let content = body_obj
        .get("graphql")
        .and_then(Value::as_object)
        .map(|graphql| {
          let query = graphql.get("query").and_then(Value::as_str).unwrap_or_default();
          let variables = graphql.get("variables").and_then(Value::as_str).unwrap_or_default();
          if variables.is_empty() {
            query.to_owned()
          } else {
            format!("{query}\n{variables}")
          }
        })
        .unwrap_or_default();
      Ok(NormalizedBody::Raw {
        content,
        content_type: "application/json".into(),
      })
    }
    other => {
      warnings.push(SpecWarning {
        code: "UNSUPPORTED_BODY_MODE".into(),
        message: format!("Unsupported Postman body mode `{other}`"),
        operation_ref: Some(op_ref.to_owned()),
      });
      Ok(NormalizedBody::None)
    }
  }
}

fn raw_content_type(body_obj: &serde_json::Map<String, Value>, headers: Option<&Value>) -> String {
  if let Some(options) = body_obj.get("options").and_then(Value::as_object) {
    if let Some(raw) = options.get("raw").and_then(Value::as_object) {
      if let Some(language) = raw.get("language").and_then(Value::as_str) {
        return match language {
          "json" => "application/json".into(),
          "xml" => "application/xml".into(),
          "html" => "text/html".into(),
          "javascript" => "application/javascript".into(),
          other => format!("text/{other}"),
        };
      }
    }
  }

  header_content_type(headers).unwrap_or_else(|| "text/plain".into())
}

fn header_content_type(headers: Option<&Value>) -> Option<String> {
  let entries = headers?.as_array()?;
  for entry in entries {
    let obj = entry.as_object()?;
    let key = obj.get("key")?.as_str()?;
    if key.eq_ignore_ascii_case("content-type") {
      return obj.get("value").and_then(Value::as_str).map(str::to_owned);
    }
  }
  None
}

fn key_value_entries(entries: Option<&Value>) -> Vec<NormalizedKeyValue> {
  let Some(items) = entries.and_then(Value::as_array) else {
    return vec![];
  };

  let mut fields = Vec::new();
  for entry in items {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
    if disabled {
      continue;
    }
    let Some(key) = obj.get("key").and_then(Value::as_str) else {
      continue;
    };
    let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
    fields.push(NormalizedKeyValue {
      key: key.to_owned(),
      value,
      enabled: true,
    });
  }
  fields
}

fn form_data_entries(
  entries: Option<&Value>,
  warnings: &mut Vec<SpecWarning>,
  op_ref: &str,
) -> Vec<NormalizedFormDataEntry> {
  let Some(items) = entries.and_then(Value::as_array) else {
    return vec![];
  };

  let mut out = Vec::new();
  for entry in items {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
    if disabled {
      continue;
    }
    let Some(key) = obj.get("key").and_then(Value::as_str) else {
      continue;
    };
    let entry_type = obj.get("type").and_then(Value::as_str).unwrap_or("text");
    let is_file = entry_type == "file";
    if is_file {
      warnings.push(SpecWarning {
        code: "FILE_PART_PLACEHOLDER".into(),
        message: "Multipart file parts import as placeholders".into(),
        operation_ref: Some(op_ref.to_owned()),
      });
    }
    out.push(NormalizedFormDataEntry {
      key: key.to_owned(),
      value: obj
        .get("value")
        .or_else(|| obj.get("src"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned(),
      is_file,
      file_name: if is_file {
        obj
          .get("src")
          .and_then(Value::as_str)
          .map(|src| src.rsplit('/').next().unwrap_or(src).to_owned())
      } else {
        None
      },
      content_type: obj.get("contentType").and_then(Value::as_str).map(str::to_owned),
    });
  }
  out
}

fn normalize_auth(auth: Option<&Value>, op_ref: &str, warnings: &mut Vec<SpecWarning>) -> Option<NormalizedAuth> {
  let auth_obj = auth?.as_object()?;
  let auth_type = auth_obj.get("type").and_then(Value::as_str).unwrap_or("noauth");
  if auth_type == "noauth" {
    return None;
  }

  match auth_type {
    "apikey" => auth_entries(auth_obj.get("apikey")).map(|(key_name, value, location)| {
      let (header_name, query_name) = match location.as_str() {
        "query" => (None, Some(key_name)),
        _ => (Some(key_name), None),
      };
      NormalizedAuth::without_oauth2_scaffold("apiKey", header_name, query_name, value)
    }),
    "bearer" => auth_entries(auth_obj.get("bearer")).map(|(_, value, _)| {
      NormalizedAuth::without_oauth2_scaffold(
        "http:bearer",
        Some("Authorization".into()),
        None,
        if value.is_empty() {
          "Bearer {{token}}".into()
        } else {
          format!("Bearer {value}")
        },
      )
    }),
    "basic" => {
      let entries = auth_entries_map(auth_obj.get("basic"));
      Some(NormalizedAuth::without_oauth2_scaffold(
        "http:basic",
        Some("Authorization".into()),
        None,
        format!(
          "Basic {}:{}",
          entries
            .get("username")
            .cloned()
            .unwrap_or_else(|| "{{username}}".into()),
          entries
            .get("password")
            .cloned()
            .unwrap_or_else(|| "{{password}}".into())
        ),
      ))
    }
    "oauth2" => Some(NormalizedAuth::without_oauth2_scaffold(
      "oauth2",
      Some("Authorization".into()),
      None,
      "Bearer {{token}}",
    )),
    other => {
      warnings.push(SpecWarning {
        code: "UNSUPPORTED_AUTH".into(),
        message: format!("Unsupported Postman auth type `{other}`"),
        operation_ref: Some(op_ref.to_owned()),
      });
      None
    }
  }
}

fn auth_entries(entries: Option<&Value>) -> Option<(String, String, String)> {
  let map = auth_entries_map(entries);
  let key_name = map.get("key").cloned().unwrap_or_else(|| "X-API-Key".into());
  let value = map.get("value").cloned().unwrap_or_else(|| "{{api_key}}".into());
  let location = map.get("in").cloned().unwrap_or_else(|| "header".into());
  Some((key_name, value, location))
}

fn auth_entries_map(entries: Option<&Value>) -> BTreeMap<String, String> {
  let Some(items) = entries.and_then(Value::as_array) else {
    return BTreeMap::new();
  };

  let mut map = BTreeMap::new();
  for entry in items {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let Some(key) = obj.get("key").and_then(Value::as_str) else {
      continue;
    };
    let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
    map.insert(key.to_owned(), value);
  }
  map
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  fn minimal_collection() -> Value {
    json!({
      "info": {
        "name": "Demo API",
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
      },
      "variable": [
        { "key": "base_url", "value": "https://api.example.com" }
      ],
      "item": [
        {
          "name": "Users",
          "item": [
            {
              "name": "List users",
              "request": {
                "method": "GET",
                "url": "{{base_url}}/users?limit=10"
              },
              "response": [{ "name": "ok", "status": "OK", "code": 200 }]
            }
          ]
        }
      ]
    })
  }

  #[test]
  fn detects_postman_collection_schema() {
    let value = minimal_collection();
    assert!(is_postman_collection(&value));
  }

  #[test]
  fn normalizes_nested_folder_and_variables() {
    let result = normalize_postman(minimal_collection()).expect("normalize");
    assert_eq!(result.project.title, "Demo API");
    assert_eq!(result.project.folders.len(), 1);
    assert_eq!(result.project.folders[0].name, "Users");
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].method, "GET");
    assert_eq!(result.project.operations[0].path, "/users");
    assert_eq!(
      result.project.environments[0].variables[0].value,
      "https://api.example.com"
    );
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "RESPONSE_NOT_IMPORTED")
    );
  }

  #[test]
  fn rejects_non_postman_document() {
    let err = normalize_postman(json!({"openapi":"3.0.0"})).expect_err("not postman");
    assert!(matches!(err, SpecImportError::UnsupportedFormat(_)));
  }

  #[test]
  fn rejects_duplicate_request_identity() {
    let collection = json!({
      "info": {
        "name": "Dup",
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
      },
      "item": [
        { "name": "A", "request": { "method": "GET", "url": "/pets" } },
        { "name": "B", "request": { "method": "GET", "url": "/pets" } }
      ]
    });
    let err = normalize_postman(collection).expect_err("duplicate");
    assert!(matches!(err, SpecImportError::InvalidSpec(message) if message.contains("Duplicate")));
  }
}
