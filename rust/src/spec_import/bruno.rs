//! Bruno OpenCollection JSON normalization into the spec import normalized IR.

use std::collections::HashSet;

use serde_json::Value;

use crate::spec_import::fingerprint::{bundle_and_canonicalize, hash_bytes};
use crate::spec_import::normalize::NormalizeOutput;
use crate::spec_import::types::{
  NormalizedAuth, NormalizedBody, NormalizedEnvironment, NormalizedFolder, NormalizedFormDataEntry, NormalizedKeyValue,
  NormalizedOperation, NormalizedParameter, NormalizedProject, OperationProtocol, ParameterLocation, SpecImportError,
  SpecWarning, ValueSource,
};

/// Returns true when the JSON value looks like a Bruno OpenCollection document.
pub fn is_bruno_opencollection(value: &Value) -> bool {
  value.get("opencollection").and_then(Value::as_str).is_some()
    && value.get("items").and_then(Value::as_array).is_some()
}

/// Normalize a parsed Bruno OpenCollection JSON document into [`NormalizedProject`].
pub fn normalize_bruno(value: Value) -> Result<NormalizeOutput, SpecImportError> {
  if !is_bruno_opencollection(&value) {
    return Err(SpecImportError::UnsupportedFormat(
      "Not a Bruno OpenCollection document".into(),
    ));
  }

  let info = value
    .get("info")
    .ok_or_else(|| SpecImportError::InvalidSpec("Bruno collection missing info".into()))?;

  let title = info
    .get("name")
    .and_then(Value::as_str)
    .unwrap_or("Imported Collection")
    .to_owned();

  let version = info.get("version").and_then(Value::as_str).map(str::to_owned);

  let collection_auth = value.get("request").and_then(|request| request.get("auth"));

  let mut warnings = vec![SpecWarning {
    code: "MIGRATION_FROM_BRUNO".into(),
    message: "Imported from Bruno; scripts, tests, and assertions are not migrated".into(),
    operation_ref: None,
  }];

  let mut folders = Vec::new();
  let mut operations = Vec::new();
  let mut seen_primary_keys = HashSet::new();

  if let Some(items) = value.get("items").and_then(Value::as_array) {
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
      "Bruno collection contains no importable HTTP requests".into(),
    ));
  }

  let environments = normalize_environments(value.get("environments"));

  let fingerprint = bundle_and_canonicalize(&value)
    .map(|bytes| hash_bytes(&bytes))
    .map_err(SpecImportError::InvalidSpec)?;

  Ok(NormalizeOutput {
    project: NormalizedProject {
      title,
      description: None,
      version,
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
    let info = item.get("info").and_then(Value::as_object);
    let item_type = info
      .and_then(|obj| obj.get("type"))
      .and_then(Value::as_str)
      .unwrap_or("http");
    let name = info
      .and_then(|obj| obj.get("name"))
      .and_then(Value::as_str)
      .unwrap_or("Untitled");

    if item_type == "folder" {
      let folder_id = folder_id_for_path(parent_folder_id, name);
      folders.push(NormalizedFolder {
        id: folder_id.clone(),
        parent_id: parent_folder_id.map(str::to_owned),
        name: name.to_owned(),
        sort_hint: info
          .and_then(|obj| obj.get("seq"))
          .and_then(Value::as_u64)
          .unwrap_or(index as u64) as u32,
      });
      if let Some(children) = item.get("items").and_then(Value::as_array) {
        collect_items(
          children,
          Some(&folder_id),
          folders,
          operations,
          seen_primary_keys,
          collection_auth,
          warnings,
        )?;
      }
      continue;
    }

    if item_type != "http" {
      warnings.push(SpecWarning {
        code: "UNSUPPORTED_REQUEST_TYPE".into(),
        message: format!("Unsupported Bruno item type `{item_type}`"),
        operation_ref: None,
      });
      continue;
    }

    let operation = normalize_http_item(name, item, parent_folder_id, collection_auth, warnings)?;
    if !seen_primary_keys.insert(operation.primary_key.clone()) {
      return Err(SpecImportError::InvalidSpec(format!(
        "Duplicate request identity: {}",
        operation.primary_key
      )));
    }
    operations.push(operation);
  }

  Ok(())
}

fn folder_id_for_path(parent_folder_id: Option<&str>, name: &str) -> String {
  match parent_folder_id {
    Some(parent) => format!("{parent}/{name}"),
    None => format!("folder:{name}"),
  }
}

fn normalize_http_item(
  name: &str,
  item: &Value,
  folder_id: Option<&str>,
  collection_auth: Option<&Value>,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedOperation, SpecImportError> {
  let http = item
    .get("http")
    .ok_or_else(|| SpecImportError::InvalidSpec(format!("Request `{name}` is missing http object")))?;

  let method = http
    .get("method")
    .and_then(Value::as_str)
    .unwrap_or("GET")
    .to_ascii_uppercase();

  let raw_url = http.get("url").and_then(Value::as_str).unwrap_or("/");

  if item.get("runtime").is_some() {
    warnings.push(SpecWarning {
      code: "SCRIPT_NOT_IMPORTED".into(),
      message: "Bruno runtime scripts and assertions are not imported".into(),
      operation_ref: Some(format!("{method} {}", extract_path(raw_url))),
    });
  }

  let parsed_url = parse_url(raw_url, http.get("params"))?;
  let op_ref = format!("{method} {}", parsed_url.path);

  let mut parameters = parsed_url.query_params;
  parameters.extend(parsed_url.path_params);
  parameters.extend(parsed_url.header_params);
  parameters.extend(normalize_headers(http.get("headers"), &op_ref));

  let body = normalize_body(http.get("body"), &op_ref, warnings)?;
  let auth = normalize_auth(http.get("auth").or(collection_auth), &op_ref, warnings);

  let description = item.get("docs").and_then(docs_text).or_else(|| {
    item
      .get("info")
      .and_then(|info| info.get("description"))
      .and_then(Value::as_str)
      .filter(|text| !text.is_empty())
      .map(str::to_owned)
  });

  Ok(NormalizedOperation {
    primary_key: op_ref,
    alternate_keys: vec![],
    name: name.to_owned(),
    method,
    path: parsed_url.path,
    deprecated: false,
    tags: item
      .get("info")
      .and_then(|info| info.get("tags"))
      .and_then(Value::as_array)
      .map(|tags| tags.iter().filter_map(Value::as_str).map(str::to_owned).collect())
      .unwrap_or_default(),
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

fn docs_text(value: &Value) -> Option<String> {
  match value {
    Value::String(text) if !text.is_empty() => Some(text.clone()),
    _ => None,
  }
}

struct ParsedUrl {
  path: String,
  query_params: Vec<NormalizedParameter>,
  path_params: Vec<NormalizedParameter>,
  header_params: Vec<NormalizedParameter>,
}

fn parse_url(raw: &str, params: Option<&Value>) -> Result<ParsedUrl, SpecImportError> {
  let without_query = raw.split('?').next().unwrap_or(raw);
  let path = extract_path(without_query);
  let mut query_params = parse_query_string(raw.split('?').nth(1).unwrap_or_default());
  let mut path_params = path_variables_from_path(&path);
  let mut header_params = Vec::new();

  if let Some(entries) = params.and_then(Value::as_array) {
    for entry in entries {
      let Some(obj) = entry.as_object() else {
        continue;
      };
      let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
      if disabled {
        continue;
      }
      let Some(name) = obj.get("name").and_then(Value::as_str) else {
        continue;
      };
      let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
      let param_type = obj
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("query")
        .to_ascii_lowercase();
      let parameter = NormalizedParameter {
        location: match param_type.as_str() {
          "path" => ParameterLocation::Path,
          "header" => ParameterLocation::Header,
          _ => ParameterLocation::Query,
        },
        name: name.to_owned(),
        value: if param_type == "path" && value.is_empty() {
          format!("{{{{{name}}}}}")
        } else {
          value.clone()
        },
        required: param_type == "path",
        enabled: true,
        value_source: if value.is_empty() {
          ValueSource::Missing
        } else {
          ValueSource::FromExample
        },
      };
      match param_type.as_str() {
        "path" => path_params.push(parameter),
        "header" => header_params.push(parameter),
        _ => query_params.push(parameter),
      }
    }
  }

  dedupe_path_params(&mut path_params);

  Ok(ParsedUrl {
    path,
    query_params,
    path_params,
    header_params,
  })
}

fn extract_path(raw: &str) -> String {
  let trimmed = raw.trim();
  if trimmed.is_empty() {
    return "/".into();
  }

  if trimmed.starts_with("{{base_url}}") {
    return normalize_absolute_path(trimmed.trim_start_matches("{{base_url}}"));
  }

  if let Some(path_start) = trimmed.find("://") {
    let after_scheme = &trimmed[path_start + 3..];
    if let Some(path_index) = after_scheme.find('/') {
      return normalize_path_segments(&after_scheme[path_index..]);
    }
    if let Some(fragment_index) = after_scheme.find('#') {
      return normalize_path_segments(&format!("/{}", &after_scheme[fragment_index..]));
    }
    return "/".into();
  }

  normalize_path_segments(trimmed)
}

fn normalize_absolute_path(path: &str) -> String {
  let trimmed = path.trim();
  if trimmed.is_empty() || trimmed == "/" {
    return "/".into();
  }
  if trimmed.starts_with('/') {
    normalize_path_segments(trimmed)
  } else {
    normalize_path_segments(&format!("/{trimmed}"))
  }
}

fn normalize_path_segments(path: &str) -> String {
  let mut segments = Vec::new();
  for segment in path.split('/') {
    if segment.is_empty() {
      continue;
    }
    let normalized = if let Some(stripped) = segment.strip_prefix(':') {
      format!("{{{stripped}}}")
    } else {
      segment.to_owned()
    };
    segments.push(normalized);
  }

  if segments.is_empty() {
    "/".into()
  } else {
    format!("/{}", segments.join("/"))
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
    let Some(key) = obj.get("name").and_then(Value::as_str).filter(|name| !name.is_empty()) else {
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
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedBody, SpecImportError> {
  let Some(body_obj) = body.and_then(Value::as_object) else {
    return Ok(NormalizedBody::None);
  };

  let body_type = body_obj
    .get("type")
    .and_then(Value::as_str)
    .unwrap_or_default()
    .to_ascii_lowercase();

  if body_type.is_empty() {
    return Ok(NormalizedBody::None);
  }

  match body_type.as_str() {
    "json" | "text" | "xml" | "graphql" => {
      let content = body_data_as_string(body_obj.get("data"));
      if content.is_empty() {
        return Ok(NormalizedBody::None);
      }
      if body_type == "json" || body_type == "graphql" {
        Ok(NormalizedBody::Json { content })
      } else {
        Ok(NormalizedBody::Raw {
          content,
          content_type: match body_type.as_str() {
            "xml" => "application/xml".into(),
            _ => format!("text/{body_type}"),
          },
        })
      }
    }
    "form-urlencoded" => {
      let fields = bruno_form_fields(body_obj.get("data"));
      if fields.is_empty() {
        Ok(NormalizedBody::None)
      } else {
        Ok(NormalizedBody::Urlencoded { fields })
      }
    }
    "multipart-form" => Ok(NormalizedBody::FormData {
      entries: bruno_multipart_entries(body_obj.get("data"), warnings, op_ref),
    }),
    "binary" => Ok(NormalizedBody::Binary {
      file_name: body_data_as_string(body_obj.get("data"))
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or("upload.bin")
        .to_owned(),
    }),
    other => {
      warnings.push(SpecWarning {
        code: "UNSUPPORTED_BODY_MODE".into(),
        message: format!("Unsupported Bruno body type `{other}`"),
        operation_ref: Some(op_ref.to_owned()),
      });
      Ok(NormalizedBody::None)
    }
  }
}

fn body_data_as_string(data: Option<&Value>) -> String {
  match data {
    Some(Value::String(text)) => text.clone(),
    Some(other) => other.to_string(),
    None => String::new(),
  }
}

fn bruno_form_fields(data: Option<&Value>) -> Vec<NormalizedKeyValue> {
  match data {
    Some(Value::Array(entries)) => entries
      .iter()
      .filter_map(|entry| {
        let obj = entry.as_object()?;
        let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
        if disabled {
          return None;
        }
        let key = obj.get("name").and_then(Value::as_str)?;
        Some(NormalizedKeyValue {
          key: key.to_owned(),
          value: obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned(),
          enabled: true,
        })
      })
      .collect(),
    Some(Value::String(text)) if !text.is_empty() => text
      .split('&')
      .filter_map(|pair| {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        if key.is_empty() {
          return None;
        }
        Some(NormalizedKeyValue {
          key: key.to_owned(),
          value: value.to_owned(),
          enabled: true,
        })
      })
      .collect(),
    _ => vec![],
  }
}

fn bruno_multipart_entries(
  data: Option<&Value>,
  warnings: &mut Vec<SpecWarning>,
  op_ref: &str,
) -> Vec<NormalizedFormDataEntry> {
  let Some(entries) = data.and_then(Value::as_array) else {
    return vec![];
  };

  let mut out = Vec::new();
  for entry in entries {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
    if disabled {
      continue;
    }
    let Some(key) = obj.get("name").and_then(Value::as_str) else {
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
  let auth_type = auth_obj.get("type").and_then(Value::as_str).unwrap_or("none");
  if auth_type == "none" || auth_type == "inherit" {
    return None;
  }

  match auth_type {
    "apikey" => {
      let key = auth_obj.get("key").and_then(Value::as_str).unwrap_or("X-API-Key");
      let value = auth_obj.get("value").and_then(Value::as_str).unwrap_or("{{api_key}}");
      let placement = auth_obj.get("placement").and_then(Value::as_str).unwrap_or("header");
      let (header_name, query_name) = if placement == "query" {
        (None, Some(key.to_owned()))
      } else {
        (Some(key.to_owned()), None)
      };
      Some(NormalizedAuth::without_oauth2_scaffold(
        "apiKey",
        header_name,
        query_name,
        value.to_owned(),
      ))
    }
    "bearer" => Some(NormalizedAuth::without_oauth2_scaffold(
      "http:bearer",
      Some("Authorization".into()),
      None,
      auth_obj
        .get("token")
        .and_then(Value::as_str)
        .map(|token| {
          if token.is_empty() {
            "Bearer {{token}}".into()
          } else if token.starts_with("Bearer ") {
            token.to_owned()
          } else {
            format!("Bearer {token}")
          }
        })
        .unwrap_or_else(|| "Bearer {{token}}".into()),
    )),
    "basic" => Some(NormalizedAuth::without_oauth2_scaffold(
      "http:basic",
      Some("Authorization".into()),
      None,
      format!(
        "Basic {}:{}",
        auth_obj
          .get("username")
          .and_then(Value::as_str)
          .unwrap_or("{{username}}"),
        auth_obj
          .get("password")
          .and_then(Value::as_str)
          .unwrap_or("{{password}}")
      ),
    )),
    "oauth2" | "oauth1" => Some(NormalizedAuth::without_oauth2_scaffold(
      "oauth2",
      Some("Authorization".into()),
      None,
      "Bearer {{token}}",
    )),
    other => {
      warnings.push(SpecWarning {
        code: "UNSUPPORTED_AUTH".into(),
        message: format!("Unsupported Bruno auth type `{other}`"),
        operation_ref: Some(op_ref.to_owned()),
      });
      None
    }
  }
}

fn normalize_environments(environments: Option<&Value>) -> Vec<NormalizedEnvironment> {
  let Some(entries) = environments.and_then(Value::as_array) else {
    return vec![default_environment()];
  };

  let mut normalized = Vec::new();
  for entry in entries {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let name = obj
      .get("name")
      .and_then(Value::as_str)
      .unwrap_or("Environment")
      .to_owned();

    let mut variables = Vec::new();
    if let Some(vars) = obj.get("variables").and_then(Value::as_array) {
      for variable in vars {
        let Some(var_obj) = variable.as_object() else {
          continue;
        };
        let enabled = var_obj.get("enabled").and_then(Value::as_bool).unwrap_or(true);
        if !enabled {
          continue;
        }
        let key = var_obj
          .get("name")
          .or_else(|| var_obj.get("key"))
          .and_then(Value::as_str);
        let Some(key) = key else {
          continue;
        };
        let value = var_obj
          .get("value")
          .and_then(Value::as_str)
          .unwrap_or_default()
          .to_owned();
        variables.push(NormalizedKeyValue {
          key: key.to_owned(),
          value,
          enabled: true,
        });
      }
    }

    if variables.is_empty() {
      continue;
    }

    if !variables.iter().any(|pair| pair.key == "base_url") {
      variables.insert(
        0,
        NormalizedKeyValue {
          key: "base_url".into(),
          value: "/".into(),
          enabled: true,
        },
      );
    }

    normalized.push(NormalizedEnvironment { name, variables });
  }

  if normalized.is_empty() {
    normalized.push(default_environment());
  }

  normalized
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

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  fn minimal_collection() -> Value {
    json!({
      "opencollection": "1.0.0",
      "info": {
        "name": "Demo API",
        "version": "1.0.0"
      },
      "request": {
        "auth": {
          "type": "bearer",
          "token": "{{token}}"
        }
      },
      "items": [
        {
          "info": { "name": "Users", "type": "folder", "seq": 1 },
          "items": [
            {
              "info": { "name": "List users", "type": "http", "seq": 1 },
              "http": {
                "method": "GET",
                "url": "{{base_url}}/users",
                "params": [
                  { "name": "limit", "value": "10", "type": "query" }
                ]
              },
              "runtime": {
                "scripts": [
                  { "type": "tests", "code": "test(\"ok\", () => {});" }
                ]
              }
            }
          ]
        }
      ]
    })
  }

  #[test]
  fn detects_bruno_opencollection() {
    assert!(is_bruno_opencollection(&minimal_collection()));
  }

  #[test]
  fn normalizes_nested_folder_and_migration_warnings() {
    let result = normalize_bruno(minimal_collection()).expect("normalize");
    assert_eq!(result.project.title, "Demo API");
    assert_eq!(result.project.folders.len(), 1);
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].path, "/users");
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "MIGRATION_FROM_BRUNO")
    );
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "SCRIPT_NOT_IMPORTED")
    );
    assert!(result.project.operations[0].auth.is_some());
  }

  #[test]
  fn rejects_non_bruno_document() {
    let err = normalize_bruno(json!({"openapi":"3.0.0"})).expect_err("not bruno");
    assert!(matches!(err, SpecImportError::UnsupportedFormat(_)));
  }
}
