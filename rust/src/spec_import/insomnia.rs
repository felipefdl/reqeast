//! Insomnia export v4/v5 normalization into the spec import normalized IR.

use std::collections::{HashMap, HashSet};

use serde_json::Value;

use crate::spec_import::fingerprint::{bundle_and_canonicalize, hash_bytes};
use crate::spec_import::normalize::NormalizeOutput;
use crate::spec_import::types::{
  NormalizedAuth, NormalizedBody, NormalizedEnvironment, NormalizedFolder, NormalizedFormDataEntry, NormalizedKeyValue,
  NormalizedOperation, NormalizedParameter, NormalizedProject, OperationProtocol, ParameterLocation, SpecImportError,
  SpecWarning, ValueSource,
};

/// Returns true when the JSON value looks like an Insomnia export document.
pub fn is_insomnia_export(value: &Value) -> bool {
  if value.get("_type").and_then(Value::as_str) == Some("export")
    && value.get("resources").and_then(Value::as_array).is_some()
  {
    return true;
  }

  value
    .get("resources")
    .and_then(Value::as_array)
    .is_some_and(|resources| {
      resources
        .iter()
        .any(|resource| resource.get("_type").and_then(Value::as_str) == Some("workspace"))
    })
}

/// Normalize a parsed Insomnia export JSON document into [`NormalizedProject`].
pub fn normalize_insomnia(value: Value) -> Result<NormalizeOutput, SpecImportError> {
  if !is_insomnia_export(&value) {
    return Err(SpecImportError::UnsupportedFormat(
      "Not an Insomnia export document".into(),
    ));
  }

  let resources = value
    .get("resources")
    .and_then(Value::as_array)
    .ok_or_else(|| SpecImportError::InvalidSpec("Insomnia export missing resources".into()))?;

  let mut warnings = vec![SpecWarning {
    code: "MIGRATION_FROM_INSOMNIA".into(),
    message: "Imported from Insomnia; scripts, tests, and cookie jars are not migrated".into(),
    operation_ref: None,
  }];

  let mut by_id: HashMap<String, &Value> = HashMap::new();
  let mut workspaces = Vec::new();
  let mut request_groups = Vec::new();
  let mut requests = Vec::new();
  let mut environments = Vec::new();
  let mut response_count = 0usize;
  let mut cookie_jar_count = 0usize;
  let mut api_spec_count = 0usize;

  for resource in resources {
    let Some(id) = resource.get("_id").and_then(Value::as_str) else {
      continue;
    };
    by_id.insert(id.to_owned(), resource);
    match resource.get("_type").and_then(Value::as_str) {
      Some("workspace") => workspaces.push(resource),
      Some("request_group") => request_groups.push(resource),
      Some("request") => requests.push(resource),
      Some("environment") => environments.push(resource),
      Some("response") => response_count += 1,
      Some("cookie_jar") => cookie_jar_count += 1,
      Some("api_spec") => api_spec_count += 1,
      _ => {}
    }
  }

  if response_count > 0 {
    warnings.push(SpecWarning {
      code: "RESPONSE_NOT_IMPORTED".into(),
      message: "Insomnia response examples are not imported".into(),
      operation_ref: None,
    });
  }
  if cookie_jar_count > 0 {
    warnings.push(SpecWarning {
      code: "COOKIE_JAR_NOT_IMPORTED".into(),
      message: "Insomnia cookie jars are not imported".into(),
      operation_ref: None,
    });
  }
  if api_spec_count > 0 {
    warnings.push(SpecWarning {
      code: "API_SPEC_NOT_IMPORTED".into(),
      message: "Embedded Insomnia API specs are not imported".into(),
      operation_ref: None,
    });
  }

  let workspace = workspaces
    .first()
    .ok_or_else(|| SpecImportError::InvalidSpec("Insomnia export contains no workspace".into()))?;

  let workspace_id = workspace
    .get("_id")
    .and_then(Value::as_str)
    .ok_or_else(|| SpecImportError::InvalidSpec("Insomnia workspace missing _id".into()))?;

  let title = workspace
    .get("name")
    .and_then(Value::as_str)
    .unwrap_or("Imported Workspace")
    .to_owned();

  let description = workspace
    .get("description")
    .and_then(Value::as_str)
    .filter(|text| !text.is_empty())
    .map(str::to_owned);

  let mut folders = Vec::new();
  let mut folder_paths: HashMap<String, String> = HashMap::new();
  let mut sorted_groups: Vec<&Value> = request_groups;
  sorted_groups.sort_by_key(|group| group.get("metaSortKey").and_then(Value::as_f64).unwrap_or(0.0) as i64);

  for (index, group) in sorted_groups.iter().enumerate() {
    let Some(group_id) = group.get("_id").and_then(Value::as_str) else {
      continue;
    };
    let name = group.get("name").and_then(Value::as_str).unwrap_or("Untitled");
    let parent_folder_id = group
      .get("parentId")
      .and_then(Value::as_str)
      .filter(|parent| *parent != workspace_id)
      .and_then(|parent| folder_paths.get(parent).cloned());

    let folder_id = match parent_folder_id.as_deref() {
      Some(parent) => format!("{parent}/{name}"),
      None => format!("folder:{name}"),
    };
    folder_paths.insert(group_id.to_owned(), folder_id.clone());
    folders.push(NormalizedFolder {
      id: folder_id,
      parent_id: parent_folder_id,
      name: name.to_owned(),
      sort_hint: index as u32,
    });
  }

  let mut operations = Vec::new();
  let mut seen_primary_keys = HashSet::new();

  for request in requests {
    let operation = normalize_request(request, workspace_id, &folder_paths, &mut warnings)?;
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
      "Insomnia export contains no importable HTTP requests".into(),
    ));
  }

  let normalized_environments = normalize_environments(environments, workspace_id, &mut warnings);

  let fingerprint = bundle_and_canonicalize(&value)
    .map(|bytes| hash_bytes(&bytes))
    .map_err(SpecImportError::InvalidSpec)?;

  Ok(NormalizeOutput {
    project: NormalizedProject {
      title,
      description,
      version: value
        .get("__export_format")
        .and_then(Value::as_u64)
        .map(|format| format!("insomnia-v{format}")),
      icon_url: None,
      security_schemes: vec![],
      folders,
      operations,
      environments: normalized_environments,
    },
    warnings,
    content_fingerprint: fingerprint,
  })
}

fn normalize_request(
  request: &Value,
  workspace_id: &str,
  folder_paths: &HashMap<String, String>,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedOperation, SpecImportError> {
  let name = request.get("name").and_then(Value::as_str).unwrap_or("Untitled");

  let method = request
    .get("method")
    .and_then(Value::as_str)
    .unwrap_or("GET")
    .to_ascii_uppercase();

  let raw_url = request.get("url").and_then(Value::as_str).unwrap_or("/");

  if request
    .get("preRequestScript")
    .and_then(Value::as_str)
    .is_some_and(|text| !text.is_empty())
    || request
      .get("tests")
      .and_then(Value::as_str)
      .is_some_and(|text| !text.is_empty())
  {
    warnings.push(SpecWarning {
      code: "SCRIPT_NOT_IMPORTED".into(),
      message: "Insomnia pre-request scripts and tests are not imported".into(),
      operation_ref: Some(format!("{method} {}", extract_path(raw_url))),
    });
  }

  let parsed_url = parse_url(raw_url)?;
  let op_ref = format!("{method} {}", parsed_url.path);

  let mut parameters = parsed_url.query_params;
  parameters.extend(parsed_url.path_params);
  parameters.extend(normalize_insomnia_parameters(request.get("parameters"), &op_ref));
  parameters.extend(normalize_headers(request.get("headers"), &op_ref));

  let body = normalize_body(request.get("body"), request.get("headers"), &op_ref, warnings)?;
  let auth = normalize_auth(request.get("authentication"), &op_ref, warnings);

  let folder_id = request
    .get("parentId")
    .and_then(Value::as_str)
    .filter(|parent| *parent != workspace_id)
    .and_then(|parent| folder_paths.get(parent).cloned());

  let description = request
    .get("description")
    .and_then(Value::as_str)
    .filter(|text| !text.is_empty())
    .map(str::to_owned);

  Ok(NormalizedOperation {
    primary_key: op_ref,
    alternate_keys: vec![],
    name: name.to_owned(),
    method,
    path: parsed_url.path,
    deprecated: false,
    tags: vec![],
    protocol: OperationProtocol::Http,
    binding: None,
    folder_id,
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

fn parse_url(raw: &str) -> Result<ParsedUrl, SpecImportError> {
  let without_query = raw.split('?').next().unwrap_or(raw);
  let path = extract_path(without_query);
  let query_params = parse_query_string(raw.split('?').nth(1).unwrap_or_default());
  let path_params = path_variables_from_path(&path);
  Ok(ParsedUrl {
    path,
    query_params,
    path_params,
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
    } else if segment.starts_with("{{") && segment.ends_with("}}") {
      let name = segment.trim_start_matches("{{").trim_end_matches("}}");
      format!("{{{name}}}")
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

fn normalize_insomnia_parameters(parameters: Option<&Value>, op_ref: &str) -> Vec<NormalizedParameter> {
  let Some(entries) = parameters.and_then(Value::as_array) else {
    return vec![];
  };

  let mut params = Vec::new();
  for entry in entries {
    let Some(obj) = entry.as_object() else {
      continue;
    };
    let disabled = obj.get("disabled").and_then(Value::as_bool).unwrap_or(false);
    if disabled {
      continue;
    }
    let Some(name) = obj.get("name").and_then(Value::as_str).filter(|name| !name.is_empty()) else {
      continue;
    };
    let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
    params.push(NormalizedParameter {
      location: ParameterLocation::Query,
      name: name.to_owned(),
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

  let _ = op_ref;
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
  headers: Option<&Value>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedBody, SpecImportError> {
  let Some(body_obj) = body.and_then(Value::as_object) else {
    return Ok(NormalizedBody::None);
  };

  if body_obj.is_empty() {
    return Ok(NormalizedBody::None);
  }

  let mime_type = body_obj
    .get("mimeType")
    .and_then(Value::as_str)
    .unwrap_or_default()
    .to_ascii_lowercase();

  if let Some(text) = body_obj.get("text").and_then(Value::as_str) {
    if text.is_empty() {
      return Ok(NormalizedBody::None);
    }
    if mime_type.contains("json") {
      return Ok(NormalizedBody::Json {
        content: text.to_owned(),
      });
    }
    return Ok(NormalizedBody::Raw {
      content: text.to_owned(),
      content_type: if mime_type.is_empty() {
        header_content_type(headers).unwrap_or_else(|| "text/plain".into())
      } else {
        mime_type
      },
    });
  }

  if let Some(params) = body_obj.get("params").and_then(Value::as_array) {
    if params.is_empty() {
      return Ok(NormalizedBody::None);
    }
    if mime_type.contains("multipart") {
      return Ok(NormalizedBody::FormData {
        entries: form_data_entries(params, warnings, op_ref),
      });
    }
    return Ok(NormalizedBody::Urlencoded {
      fields: key_value_entries(params),
    });
  }

  Ok(NormalizedBody::None)
}

fn header_content_type(headers: Option<&Value>) -> Option<String> {
  let entries = headers?.as_array()?;
  for entry in entries {
    let obj = entry.as_object()?;
    let key = obj.get("name")?.as_str()?;
    if key.eq_ignore_ascii_case("content-type") {
      return obj.get("value").and_then(Value::as_str).map(str::to_owned);
    }
  }
  None
}

fn key_value_entries(entries: &[Value]) -> Vec<NormalizedKeyValue> {
  let mut fields = Vec::new();
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
    let value = obj.get("value").and_then(Value::as_str).unwrap_or_default().to_owned();
    fields.push(NormalizedKeyValue {
      key: key.to_owned(),
      value,
      enabled: true,
    });
  }
  fields
}

fn form_data_entries(entries: &[Value], warnings: &mut Vec<SpecWarning>, op_ref: &str) -> Vec<NormalizedFormDataEntry> {
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
        .or_else(|| obj.get("fileName"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned(),
      is_file,
      file_name: if is_file {
        obj.get("fileName").and_then(Value::as_str).map(str::to_owned)
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
  if auth_obj.is_empty() {
    return None;
  }

  let auth_type = auth_obj.get("type").and_then(Value::as_str).unwrap_or("none");
  if auth_type == "none" {
    return None;
  }

  match auth_type {
    "apikey" => {
      let key = auth_obj.get("key").and_then(Value::as_str).unwrap_or("X-API-Key");
      let value = auth_obj.get("value").and_then(Value::as_str).unwrap_or("{{api_key}}");
      let add_to = auth_obj
        .get("addTo")
        .or_else(|| auth_obj.get("addto"))
        .and_then(Value::as_str)
        .unwrap_or("header");
      let (header_name, query_name) = if add_to == "query" {
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
        message: format!("Unsupported Insomnia auth type `{other}`"),
        operation_ref: Some(op_ref.to_owned()),
      });
      None
    }
  }
}

fn normalize_environments(
  environments: Vec<&Value>,
  workspace_id: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Vec<NormalizedEnvironment> {
  let mut normalized = Vec::new();

  for environment in environments {
    let parent_id = environment.get("parentId").and_then(Value::as_str);
    if parent_id != Some(workspace_id) && parent_id.is_some() {
      // Nested sub-environments are flattened into named environments.
    }

    let name = environment
      .get("name")
      .and_then(Value::as_str)
      .unwrap_or("Environment")
      .to_owned();

    let mut variables = Vec::new();
    let mut nested_found = false;
    if let Some(data) = environment.get("data").and_then(Value::as_object) {
      for (key, value) in data {
        match value {
          Value::String(text) => variables.push(NormalizedKeyValue {
            key: key.clone(),
            value: text.clone(),
            enabled: true,
          }),
          Value::Number(number) => variables.push(NormalizedKeyValue {
            key: key.clone(),
            value: number.to_string(),
            enabled: true,
          }),
          Value::Bool(flag) => variables.push(NormalizedKeyValue {
            key: key.clone(),
            value: flag.to_string(),
            enabled: true,
          }),
          _ => nested_found = true,
        }
      }
    }

    if nested_found {
      warnings.push(SpecWarning {
        code: "NESTED_ENV_NOT_IMPORTED".into(),
        message: format!("Nested Insomnia environment values in `{name}` were skipped"),
        operation_ref: None,
      });
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
    name: "Workspace".into(),
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

  fn minimal_export() -> Value {
    json!({
      "_type": "export",
      "__export_format": 4,
      "resources": [
        {
          "_id": "wrk_demo",
          "_type": "workspace",
          "parentId": null,
          "name": "Demo API"
        },
        {
          "_id": "fld_users",
          "_type": "request_group",
          "parentId": "wrk_demo",
          "name": "Users",
          "metaSortKey": -1
        },
        {
          "_id": "req_list",
          "_type": "request",
          "parentId": "fld_users",
          "name": "List users",
          "method": "GET",
          "url": "{{base_url}}/users?limit=10",
          "parameters": [],
          "headers": [],
          "body": {},
          "authentication": {}
        },
        {
          "_id": "res_ok",
          "_type": "response",
          "parentId": "req_list",
          "name": "OK"
        }
      ]
    })
  }

  #[test]
  fn detects_insomnia_export() {
    assert!(is_insomnia_export(&minimal_export()));
  }

  #[test]
  fn normalizes_nested_folder_and_migration_warnings() {
    let result = normalize_insomnia(minimal_export()).expect("normalize");
    assert_eq!(result.project.title, "Demo API");
    assert_eq!(result.project.folders.len(), 1);
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].path, "/users");
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "MIGRATION_FROM_INSOMNIA")
    );
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "RESPONSE_NOT_IMPORTED")
    );
  }

  #[test]
  fn rejects_non_insomnia_document() {
    let err = normalize_insomnia(json!({"openapi":"3.0.0"})).expect_err("not insomnia");
    assert!(matches!(err, SpecImportError::UnsupportedFormat(_)));
  }
}
