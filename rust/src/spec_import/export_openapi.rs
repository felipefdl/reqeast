//! OpenAPI 3.1 export from project HTTP request data (T46 / AC19).

use std::collections::{BTreeMap, HashMap, HashSet};

use indexmap::IndexMap;
use serde_json::{Map, Value};

use crate::spec_import::export_types::{
  ExportAuthType, ExportBodyType, ExportEnvironment, ExportFormDataEntry, ExportFormat, ExportHttpRequestData,
  ExportKeyValue, ExportOpenApiOptions, ExportOperation, ExportProjectInput, SpecExportError,
};

type OpenApiPathsAndSecurity = (Map<String, Value>, Map<String, Value>);

/// Serializes a project slice to OpenAPI 3.1 YAML or JSON bytes.
#[uniffi::export]
pub fn export_openapi(
  input: ExportProjectInput,
  format: ExportFormat,
  options: ExportOpenApiOptions,
) -> Result<Vec<u8>, SpecExportError> {
  let spec = build_openapi_spec(&input, &options)?;
  serialize_spec(&spec, format)
}

fn build_openapi_spec(input: &ExportProjectInput, options: &ExportOpenApiOptions) -> Result<Value, SpecExportError> {
  let mut root = Map::new();
  root.insert("openapi".into(), Value::String("3.1.0".into()));

  let mut info = Map::new();
  info.insert("title".into(), Value::String(input.title.clone()));
  if let Some(description) = &input.description {
    if !description.is_empty() {
      info.insert("description".into(), Value::String(description.clone()));
    }
  }
  info.insert(
    "version".into(),
    Value::String(input.version.clone().unwrap_or_else(|| "1.0.0".into())),
  );
  root.insert("info".into(), Value::Object(info));

  if options.include_environments {
    let servers = build_servers(&input.environments);
    if !servers.is_empty() {
      root.insert("servers".into(), Value::Array(servers));
    }
  }

  let folder_name_by_id: HashMap<String, String> = input
    .folders
    .iter()
    .map(|folder| (folder.id.clone(), folder.name.clone()))
    .collect();

  let tag_names = collect_tag_names(input, &folder_name_by_id);
  if !tag_names.is_empty() {
    root.insert(
      "tags".into(),
      Value::Array(
        tag_names
          .iter()
          .map(|name| Value::Object(Map::from_iter([("name".into(), Value::String(name.clone()))])))
          .collect(),
      ),
    );
  }

  let (paths, security_schemes) = build_paths_and_security(input, options, &folder_name_by_id)?;
  root.insert("paths".into(), Value::Object(paths));

  if !security_schemes.is_empty() {
    root.insert(
      "components".into(),
      Value::Object(Map::from_iter([(
        "securitySchemes".into(),
        Value::Object(security_schemes),
      )])),
    );
  }

  Ok(Value::Object(root))
}

fn collect_tag_names(input: &ExportProjectInput, folder_name_by_id: &HashMap<String, String>) -> Vec<String> {
  let mut seen = HashSet::new();
  let mut tags = Vec::new();

  for folder in &input.folders {
    if seen.insert(folder.name.clone()) {
      tags.push(folder.name.clone());
    }
  }

  for operation in &input.operations {
    if let Some(folder_id) = &operation.folder_id {
      if let Some(folder_name) = folder_name_by_id.get(folder_id) {
        if seen.insert(folder_name.clone()) {
          tags.push(folder_name.clone());
        }
      }
    }
  }

  tags
}

fn build_servers(environments: &[ExportEnvironment]) -> Vec<Value> {
  environments
    .iter()
    .filter_map(|environment| {
      let base_url = environment
        .variables
        .iter()
        .find(|variable| variable.key == "base_url" && variable.enabled)
        .map(|variable| variable.value.trim())
        .filter(|value| !value.is_empty())?;

      let mut server = Map::new();
      server.insert("url".into(), Value::String(base_url.to_owned()));
      if !environment.name.is_empty() {
        server.insert("description".into(), Value::String(environment.name.clone()));
      }

      let extra_vars: Vec<_> = environment
        .variables
        .iter()
        .filter(|variable| variable.key != "base_url" && variable.enabled && !variable.key.is_empty())
        .collect();

      if !extra_vars.is_empty() {
        let mut variables = Map::new();
        for variable in extra_vars {
          variables.insert(
            variable.key.clone(),
            Value::Object(Map::from_iter([(
              "default".into(),
              Value::String(variable.value.clone()),
            )])),
          );
        }
        server.insert("variables".into(), Value::Object(variables));
      }

      Some(Value::Object(server))
    })
    .collect()
}

fn build_paths_and_security(
  input: &ExportProjectInput,
  options: &ExportOpenApiOptions,
  folder_name_by_id: &HashMap<String, String>,
) -> Result<OpenApiPathsAndSecurity, SpecExportError> {
  let mut paths: BTreeMap<String, Map<String, Value>> = BTreeMap::new();
  let mut security_schemes: IndexMap<String, Map<String, Value>> = IndexMap::new();

  for operation in &input.operations {
    if operation.deprecated && !options.include_deprecated {
      continue;
    }

    let (path, path_params) = extract_openapi_path(&operation.http.url)?;
    let method = operation.http.method.to_ascii_lowercase();

    let path_item = paths.entry(path).or_default();
    let mut op_object = Map::new();

    op_object.insert("summary".into(), Value::String(operation.name.clone()));
    if operation.deprecated {
      op_object.insert("deprecated".into(), Value::Bool(true));
    }
    if let Some(description) = &operation.description {
      if !description.is_empty() {
        op_object.insert("description".into(), Value::String(description.clone()));
      }
    }

    if let Some(primary_key) = &operation.spec_primary_key {
      if !primary_key.is_empty() {
        op_object.insert("operationId".into(), Value::String(primary_key.clone()));
      }
    }

    if let Some(folder_id) = &operation.folder_id {
      if let Some(folder_name) = folder_name_by_id.get(folder_id) {
        op_object.insert("tags".into(), Value::Array(vec![Value::String(folder_name.clone())]));
      }
    }

    let mut parameters = Vec::new();
    parameters.extend(path_params);
    parameters.extend(build_query_parameters(&operation.http)?);
    parameters.extend(build_header_parameters(&operation.http)?);
    if !parameters.is_empty() {
      op_object.insert("parameters".into(), Value::Array(parameters));
    }

    if let Some(request_body) = build_request_body(operation)? {
      op_object.insert("requestBody".into(), request_body);
    }

    if let Some(scheme_name) = register_security_scheme(&operation.http, &mut security_schemes) {
      op_object.insert(
        "security".into(),
        Value::Array(vec![Value::Object(Map::from_iter([(
          scheme_name,
          Value::Array(vec![]),
        )]))]),
      );
    }

    op_object.insert(
      "responses".into(),
      Value::Object(Map::from_iter([(
        "200".into(),
        Value::Object(Map::from_iter([(
          "description".into(),
          Value::String("Successful operation".into()),
        )])),
      )])),
    );

    path_item.insert(method, Value::Object(op_object));
  }

  let paths_value = paths
    .into_iter()
    .map(|(path, item)| (path, Value::Object(item)))
    .collect();

  let schemes_value = security_schemes
    .into_iter()
    .map(|(name, definition)| (name, Value::Object(definition)))
    .collect();

  Ok((paths_value, schemes_value))
}

fn extract_openapi_path(url: &str) -> Result<(String, Vec<Value>), SpecExportError> {
  let trimmed = url.trim();
  if trimmed.is_empty() {
    return Err(SpecExportError::InvalidInput("Operation URL is empty".into()));
  }

  let without_base = strip_base_url_prefix(trimmed);
  let openapi_path = template_to_openapi_path(&without_base);
  let path_params = extract_path_parameters(&openapi_path);

  if !openapi_path.starts_with('/') {
    return Err(SpecExportError::InvalidInput(format!(
      "Operation URL must resolve to an absolute path, got `{openapi_path}`"
    )));
  }

  Ok((openapi_path, path_params))
}

fn strip_base_url_prefix(url: &str) -> String {
  if let Some(rest) = url.strip_prefix("{{base_url}}") {
    return rest.to_owned();
  }

  if let Ok(parsed) = url::Url::parse(url) {
    let mut path = parsed.path().to_owned();
    if let Some(query) = parsed.query() {
      path.push('?');
      path.push_str(query);
    }
    return path;
  }

  url.to_owned()
}

fn template_to_openapi_path(path: &str) -> String {
  path.replace("{{", "{").replace("}}", "}")
}

fn extract_path_parameters(path: &str) -> Vec<Value> {
  let mut seen = HashSet::new();
  let mut parameters = Vec::new();
  let mut chars = path.chars().peekable();

  while let Some(ch) = chars.next() {
    if ch != '{' {
      continue;
    }

    let mut name = String::new();
    while let Some(&next) = chars.peek() {
      chars.next();
      if next == '}' {
        break;
      }
      name.push(next);
    }

    if name.is_empty() || !seen.insert(name.clone()) {
      continue;
    }

    parameters.push(Value::Object(Map::from_iter([
      ("name".into(), Value::String(name.clone())),
      ("in".into(), Value::String("path".into())),
      ("required".into(), Value::Bool(true)),
      (
        "schema".into(),
        Value::Object(Map::from_iter([
          ("type".into(), Value::String("string".into())),
          ("example".into(), Value::String(name)),
        ])),
      ),
    ])));
  }

  parameters
}

fn build_query_parameters(http: &ExportHttpRequestData) -> Result<Vec<Value>, SpecExportError> {
  let mut parameters = Vec::new();

  for param in &http.params {
    if param.key.is_empty() {
      continue;
    }
    parameters.push(Value::Object(Map::from_iter([
      ("name".into(), Value::String(param.key.clone())),
      ("in".into(), Value::String("query".into())),
      ("required".into(), Value::Bool(false)),
      ("schema".into(), Value::Object(schema_with_example(&param.value)?)),
    ])));
  }

  Ok(parameters)
}

fn build_header_parameters(http: &ExportHttpRequestData) -> Result<Vec<Value>, SpecExportError> {
  let mut parameters = Vec::new();

  for header in enabled_entries(&http.headers) {
    if is_auth_scaffold_header(header, http) {
      continue;
    }

    parameters.push(Value::Object(Map::from_iter([
      ("name".into(), Value::String(header.key.clone())),
      ("in".into(), Value::String("header".into())),
      ("required".into(), Value::Bool(false)),
      ("schema".into(), Value::Object(schema_with_example(&header.value)?)),
    ])));
  }

  Ok(parameters)
}

fn enabled_entries(entries: &[ExportKeyValue]) -> Vec<&ExportKeyValue> {
  entries
    .iter()
    .filter(|entry| entry.enabled && !entry.key.is_empty())
    .collect()
}

fn is_auth_scaffold_header(header: &ExportKeyValue, http: &ExportHttpRequestData) -> bool {
  if http.auth_type == ExportAuthType::ApiKey
    && http.auth_api_key_location == "header"
    && !http.auth_api_key_name.is_empty()
    && header.key == http.auth_api_key_name
  {
    return true;
  }

  matches!(
    http.auth_type,
    ExportAuthType::Bearer | ExportAuthType::Basic | ExportAuthType::Oauth2
  ) && header.key.eq_ignore_ascii_case("authorization")
}

fn schema_with_example(value: &str) -> Result<Map<String, Value>, SpecExportError> {
  let mut schema = Map::new();
  if let Ok(number) = value.parse::<i64>() {
    schema.insert("type".into(), Value::String("integer".into()));
    schema.insert("example".into(), Value::Number(number.into()));
  } else if let Ok(number) = value.parse::<f64>() {
    schema.insert("type".into(), Value::String("number".into()));
    schema.insert(
      "example".into(),
      serde_json::Number::from_f64(number)
        .map(Value::Number)
        .ok_or_else(|| SpecExportError::InvalidInput(format!("Invalid numeric example `{value}`")))?,
    );
  } else if value.eq_ignore_ascii_case("true") || value.eq_ignore_ascii_case("false") {
    schema.insert("type".into(), Value::String("boolean".into()));
    schema.insert("example".into(), Value::Bool(value.eq_ignore_ascii_case("true")));
  } else {
    schema.insert("type".into(), Value::String("string".into()));
    if !value.is_empty() {
      schema.insert("example".into(), Value::String(value.to_owned()));
    }
  }
  Ok(schema)
}

fn build_request_body(operation: &ExportOperation) -> Result<Option<Value>, SpecExportError> {
  let http = &operation.http;
  match http.body_type {
    ExportBodyType::None => {
      if operation.request_body_content_types.is_empty() {
        return Ok(None);
      }
      let mut content = Map::new();
      for content_type in &operation.request_body_content_types {
        let base = content_type.split(';').next().unwrap_or(content_type).trim();
        content.insert(
          base.to_owned(),
          Value::Object(Map::from_iter([(
            "schema".into(),
            Value::Object(Map::from_iter([("type".into(), Value::String("object".into()))])),
          )])),
        );
      }
      Ok(Some(Value::Object(Map::from_iter([
        ("required".into(), Value::Bool(true)),
        ("content".into(), Value::Object(content)),
      ]))))
    }
    ExportBodyType::Json => {
      let example = parse_json_body(&http.body_content)?;
      Ok(Some(Value::Object(Map::from_iter([
        ("required".into(), Value::Bool(true)),
        (
          "content".into(),
          Value::Object(Map::from_iter([(
            "application/json".into(),
            Value::Object(Map::from_iter([("example".into(), example)])),
          )])),
        ),
      ]))))
    }
    ExportBodyType::Urlencoded => {
      let example = form_fields_to_object(&http.body_form_data)?;
      Ok(Some(Value::Object(Map::from_iter([
        ("required".into(), Value::Bool(true)),
        (
          "content".into(),
          Value::Object(Map::from_iter([(
            "application/x-www-form-urlencoded".into(),
            Value::Object(Map::from_iter([("example".into(), example)])),
          )])),
        ),
      ]))))
    }
    ExportBodyType::FormData => {
      let example = form_data_entries_to_object(&http.body_form_data_entries)?;
      Ok(Some(Value::Object(Map::from_iter([
        ("required".into(), Value::Bool(true)),
        (
          "content".into(),
          Value::Object(Map::from_iter([(
            "multipart/form-data".into(),
            Value::Object(Map::from_iter([("example".into(), example)])),
          )])),
        ),
      ]))))
    }
    ExportBodyType::Raw => {
      let content_type = if http.raw_content_type.is_empty() {
        "text/plain".into()
      } else {
        http.raw_content_type.clone()
      };
      let example = Value::String(http.body_content.clone());
      Ok(Some(Value::Object(Map::from_iter([
        ("required".into(), Value::Bool(true)),
        (
          "content".into(),
          Value::Object(Map::from_iter([(
            content_type,
            Value::Object(Map::from_iter([("example".into(), example)])),
          )])),
        ),
      ]))))
    }
    ExportBodyType::Binary => Ok(Some(Value::Object(Map::from_iter([
      ("required".into(), Value::Bool(true)),
      (
        "content".into(),
        Value::Object(Map::from_iter([(
          "application/octet-stream".into(),
          Value::Object(Map::from_iter([(
            "schema".into(),
            Value::Object(Map::from_iter([
              ("type".into(), Value::String("string".into())),
              ("format".into(), Value::String("binary".into())),
            ])),
          )])),
        )])),
      ),
    ])))),
  }
}

fn parse_json_body(content: &str) -> Result<Value, SpecExportError> {
  if content.trim().is_empty() {
    return Ok(Value::Object(Map::new()));
  }

  serde_json::from_str(content)
    .map_err(|err| SpecExportError::InvalidInput(format!("Invalid JSON request body: {err}")))
}

fn form_fields_to_object(fields: &[ExportKeyValue]) -> Result<Value, SpecExportError> {
  let mut map = Map::new();
  for field in enabled_entries(fields) {
    map.insert(field.key.clone(), string_to_json_value(&field.value)?);
  }
  Ok(Value::Object(map))
}

fn form_data_entries_to_object(entries: &[ExportFormDataEntry]) -> Result<Value, SpecExportError> {
  let mut map = Map::new();
  for entry in entries.iter().filter(|entry| entry.enabled && !entry.key.is_empty()) {
    let value = if entry.is_file {
      Value::String(if entry.file_name.is_empty() {
        "upload.bin".into()
      } else {
        entry.file_name.clone()
      })
    } else {
      string_to_json_value(&entry.value)?
    };
    map.insert(entry.key.clone(), value);
  }
  Ok(Value::Object(map))
}

fn string_to_json_value(value: &str) -> Result<Value, SpecExportError> {
  if let Ok(number) = value.parse::<i64>() {
    return Ok(Value::Number(number.into()));
  }
  if let Ok(number) = value.parse::<f64>() {
    return serde_json::Number::from_f64(number)
      .map(Value::Number)
      .ok_or_else(|| SpecExportError::InvalidInput(format!("Invalid numeric form value `{value}`")));
  }
  if value.eq_ignore_ascii_case("true") || value.eq_ignore_ascii_case("false") {
    return Ok(Value::Bool(value.eq_ignore_ascii_case("true")));
  }
  Ok(Value::String(value.to_owned()))
}

fn register_security_scheme(
  http: &ExportHttpRequestData,
  schemes: &mut IndexMap<String, Map<String, Value>>,
) -> Option<String> {
  if http.auth_type == ExportAuthType::None {
    return None;
  }

  let scheme_name = security_scheme_name(http);
  if !schemes.contains_key(&scheme_name) {
    schemes.insert(scheme_name.clone(), security_scheme_definition(http));
  }
  Some(scheme_name)
}

fn security_scheme_name(http: &ExportHttpRequestData) -> String {
  match http.auth_type {
    ExportAuthType::Bearer => "bearerAuth".into(),
    ExportAuthType::Basic => "basicAuth".into(),
    ExportAuthType::Oauth2 => "oauth2".into(),
    ExportAuthType::ApiKey => {
      if !http.auth_api_key_name.is_empty() {
        format!("apiKey_{}", sanitize_identifier(&http.auth_api_key_name))
      } else {
        "apiKeyAuth".into()
      }
    }
    ExportAuthType::None => "customAuth".into(),
  }
}

fn sanitize_identifier(value: &str) -> String {
  value
    .chars()
    .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '_' })
    .collect()
}

fn security_scheme_definition(http: &ExportHttpRequestData) -> Map<String, Value> {
  match http.auth_type {
    ExportAuthType::Bearer => Map::from_iter([
      ("type".into(), Value::String("http".into())),
      ("scheme".into(), Value::String("bearer".into())),
    ]),
    ExportAuthType::Basic => Map::from_iter([
      ("type".into(), Value::String("http".into())),
      ("scheme".into(), Value::String("basic".into())),
    ]),
    ExportAuthType::ApiKey => {
      let location = if http.auth_api_key_location == "query" {
        "query"
      } else {
        "header"
      };
      Map::from_iter([
        ("type".into(), Value::String("apiKey".into())),
        ("in".into(), Value::String(location.into())),
        (
          "name".into(),
          Value::String(if http.auth_api_key_name.is_empty() {
            "X-API-Key".into()
          } else {
            http.auth_api_key_name.clone()
          }),
        ),
      ])
    }
    ExportAuthType::Oauth2 => Map::from_iter([
      ("type".into(), Value::String("oauth2".into())),
      (
        "flows".into(),
        Value::Object(Map::from_iter([(
          "clientCredentials".into(),
          Value::Object(Map::from_iter([
            (
              "tokenUrl".into(),
              Value::String("https://example.test/oauth/token".into()),
            ),
            ("scopes".into(), Value::Object(Map::new())),
          ])),
        )])),
      ),
    ]),
    ExportAuthType::None => Map::new(),
  }
}

fn serialize_spec(spec: &Value, format: ExportFormat) -> Result<Vec<u8>, SpecExportError> {
  match format {
    ExportFormat::Json => serde_json::to_vec_pretty(spec)
      .map_err(|err| SpecExportError::InvalidInput(format!("Failed to encode OpenAPI JSON: {err}"))),
    ExportFormat::Yaml => {
      let yaml = serde_yaml_ng::to_string(spec)
        .map_err(|err| SpecExportError::InvalidInput(format!("Failed to encode OpenAPI YAML: {err}")))?;
      Ok(yaml.into_bytes())
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::spec_import::export_postman::export_input_from_normalized;
  use crate::spec_import::golden::{parse_fixture, result_to_json};
  use crate::spec_import::types::{SpecParseOptions, SpecSourceHint, parse_spec};
  use serde_json::Value;

  fn project_from_result(result: &crate::spec_import::types::SpecImportResult) -> Value {
    result_to_json(result).get("project").cloned().expect("project")
  }

  #[test]
  fn export_openapi_petstore_roundtrip_ac19() {
    for fixture in ["petstore-2.0", "petstore-3.0", "petstore-3.1"] {
      let imported = parse_fixture(fixture).expect("fixture should import");
      let export_input = export_input_from_normalized(&imported.project);
      let exported = export_openapi(export_input, ExportFormat::Yaml, ExportOpenApiOptions::default())
        .expect("export should succeed");

      let roundtrip = parse_spec(exported, SpecSourceHint::Yaml, None, SpecParseOptions::default())
        .expect("exported spec should parse");

      assert_eq!(
        project_from_result(&imported),
        project_from_result(&roundtrip),
        "round-trip IR mismatch for {fixture}"
      );
    }
  }

  #[test]
  fn export_openapi_preserves_operation_id_from_spec_identity() {
    let input = ExportProjectInput {
      title: "Demo".into(),
      description: None,
      version: Some("1.0.0".into()),
      folders: vec![],
      environments: vec![ExportEnvironment {
        name: "Default".into(),
        variables: vec![ExportKeyValue {
          key: "base_url".into(),
          value: "https://example.test".into(),
          enabled: true,
        }],
        is_active: true,
      }],
      operations: vec![ExportOperation {
        name: "List".into(),
        folder_id: None,
        sort_order: 0,
        deprecated: false,
        description: None,
        spec_primary_key: Some("listItems".into()),
        request_body_content_types: vec![],
        http: ExportHttpRequestData {
          method: "GET".into(),
          url: "{{base_url}}/items".into(),
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
    };

    let exported = export_openapi(input, ExportFormat::Json, ExportOpenApiOptions::default()).expect("export");
    let value: Value = serde_json::from_slice(&exported).expect("json");
    let operation_id = value
      .pointer("/paths/~1items/get/operationId")
      .and_then(Value::as_str)
      .expect("operationId");
    assert_eq!(operation_id, "listItems");
  }

  #[test]
  fn export_openapi_does_not_embed_live_secrets() {
    let input = ExportProjectInput {
      title: "Secrets".into(),
      description: None,
      version: Some("1.0.0".into()),
      folders: vec![],
      environments: vec![ExportEnvironment {
        name: "Default".into(),
        variables: vec![ExportKeyValue {
          key: "base_url".into(),
          value: "https://example.test".into(),
          enabled: true,
        }],
        is_active: true,
      }],
      operations: vec![ExportOperation {
        name: "Protected".into(),
        folder_id: None,
        sort_order: 0,
        deprecated: false,
        description: None,
        spec_primary_key: Some("getProtected".into()),
        request_body_content_types: vec![],
        http: ExportHttpRequestData {
          method: "GET".into(),
          url: "{{base_url}}/protected".into(),
          params: vec![],
          headers: vec![],
          body_type: ExportBodyType::None,
          body_content: String::new(),
          body_form_data: vec![],
          body_form_data_entries: vec![],
          raw_content_type: "text/plain".into(),
          binary_file_name: String::new(),
          auth_type: ExportAuthType::Bearer,
          auth_token: "super-secret-token".into(),
          auth_username: String::new(),
          auth_password: String::new(),
          auth_api_key_name: String::new(),
          auth_api_key_value: String::new(),
          auth_api_key_location: "header".into(),
        },
      }],
    };

    let exported = export_openapi(input, ExportFormat::Json, ExportOpenApiOptions::default()).expect("export");
    let text = String::from_utf8(exported).expect("utf8");
    assert!(!text.contains("super-secret-token"));
    assert!(text.contains("bearerAuth"));
  }
}
