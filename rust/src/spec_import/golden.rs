//! Golden fixture serialization for spec import integration tests.

use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use crate::spec_import::diff::{
  IdentityChangeDiff, MatchedOperation, OperationDiff, SpecFieldDelta, SpecOperationBinding,
  SpecSyncDiff, SpecSyncField,
};
use crate::spec_import::types::{
  NormalizedAuth, NormalizedBody, NormalizedEnvironment, NormalizedFolder, NormalizedFormDataEntry,
  NormalizedKeyValue, NormalizedOperation, NormalizedParameter, NormalizedProject,
  BindingProtocol, NormalizedBinding, NormalizedSecurityScheme, OperationProtocol,
  ParameterLocation, SpecImportError,
  SpecImportResult, SpecSourceHint, SpecWarning, ValueSource, parse_spec,
};

/// Root directory for shared Swift/Rust spec import fixtures.
pub fn fixtures_dir() -> PathBuf {
  Path::new(env!("CARGO_MANIFEST_DIR"))
    .join("../ReqeastTests/Fixtures/SpecImport")
}

pub fn fixture_input_path(name: &str) -> PathBuf {
  for ext in ["yaml", "yml", "json", "har", "graphql"] {
    let path = fixtures_dir().join(format!("{name}.input.{ext}"));
    if path.exists() {
      return path;
    }
  }
  fixtures_dir().join(format!("{name}.input.yaml"))
}

pub fn fixture_bundle_dir(name: &str) -> PathBuf {
  fixtures_dir().join(name)
}

pub fn is_bundle_fixture(name: &str) -> bool {
  fixture_bundle_dir(name).is_dir()
}

fn bundle_entry_path(dir: &Path) -> Option<PathBuf> {
  for candidate in [
    "openapi.yaml",
    "openapi.yml",
    "openapi.json",
    "swagger.yaml",
    "swagger.yml",
    "swagger.json",
  ] {
    let path = dir.join(candidate);
    if path.is_file() {
      return Some(path);
    }
  }
  None
}

pub fn fixture_golden_path(name: &str) -> PathBuf {
  fixtures_dir().join(format!("{name}.normalized.json"))
}

pub fn fixture_error_path(name: &str) -> PathBuf {
  fixtures_dir().join(format!("{name}.error.json"))
}

/// Parse a named fixture through the public `parse_spec` entry point.
pub fn parse_fixture(name: &str) -> Result<SpecImportResult, SpecImportError> {
  if is_bundle_fixture(name) {
    let dir = fixture_bundle_dir(name);
    let entry = bundle_entry_path(&dir).ok_or_else(|| {
      SpecImportError::ParseError(format!(
        "Bundle fixture `{}` is missing an entry file (openapi.yaml/json)",
        dir.display()
      ))
    })?;
    let bytes = fs::read(&entry).map_err(|err| {
      SpecImportError::ParseError(format!("Failed to read fixture `{}`: {err}", entry.display()))
    })?;
    let hint = if entry.extension().and_then(|ext| ext.to_str()) == Some("json") {
      SpecSourceHint::Json
    } else {
      SpecSourceHint::Yaml
    };
    return parse_spec(
      bytes,
      hint,
      Some(entry.to_string_lossy().into_owned()),
      crate::spec_import::types::SpecParseOptions::default(),
    );
  }

  let path = fixture_input_path(name);
  let bytes = fs::read(&path).map_err(|err| {
    SpecImportError::ParseError(format!("Failed to read fixture `{}`: {err}", path.display()))
  })?;
  let hint = match path.extension().and_then(|ext| ext.to_str()) {
    Some("graphql") => SpecSourceHint::Graphql,
    Some("har") => SpecSourceHint::Har,
    Some("json") => SpecSourceHint::Json,
    _ => SpecSourceHint::Yaml,
  };
  parse_spec(bytes, hint, None, crate::spec_import::types::SpecParseOptions::default())
}

/// Serialize a [`SpecImportResult`] to canonical golden JSON.
pub fn result_to_json(result: &SpecImportResult) -> Value {
  Value::Object(Map::from_iter([
    ("project".into(), project_to_json(&result.project)),
    ("warnings".into(), warnings_to_json(&result.warnings)),
    ("content_fingerprint".into(), Value::String(result.content_fingerprint.clone())),
  ]))
}

pub fn error_to_json(err: &SpecImportError) -> Value {
  let (kind, message) = match err {
    SpecImportError::InvalidSpec(message) => ("InvalidSpec", message.as_str()),
    SpecImportError::UnsupportedFormat(message) => ("UnsupportedFormat", message.as_str()),
    SpecImportError::ParseError(message) => ("ParseError", message.as_str()),
  };
  Value::Object(Map::from_iter([
    ("kind".into(), Value::String(kind.into())),
    ("message".into(), Value::String(message.into())),
  ]))
}

pub fn write_golden_json(path: &Path, value: &Value) -> std::io::Result<()> {
  if let Some(parent) = path.parent() {
    fs::create_dir_all(parent)?;
  }
  let text = serde_json::to_string_pretty(value).expect("golden json serialization");
  fs::write(path, format!("{text}\n"))
}

pub fn update_goldens_enabled() -> bool {
  std::env::var("UPDATE_SPEC_GOLDENS")
    .map(|value| !value.is_empty() && value != "0")
    .unwrap_or(false)
}

pub fn assert_or_update_success_golden(name: &str, result: &SpecImportResult) {
  let golden_path = fixture_golden_path(name);
  let actual = result_to_json(result);
  if update_goldens_enabled() {
    write_golden_json(&golden_path, &actual).expect("write golden");
    return;
  }
  let expected_text = fs::read_to_string(&golden_path)
    .unwrap_or_else(|_| panic!("missing golden file: {}", golden_path.display()));
  let expected: Value = serde_json::from_str(&expected_text).expect("parse golden json");
  assert_json_eq(&expected, &actual, name);
}

pub fn assert_or_update_error_golden(name: &str, err: &SpecImportError) {
  let error_path = fixture_error_path(name);
  let actual = error_to_json(err);
  if update_goldens_enabled() {
    write_golden_json(&error_path, &actual).expect("write error golden");
    return;
  }
  let expected_text = fs::read_to_string(&error_path)
    .unwrap_or_else(|_| panic!("missing error golden file: {}", error_path.display()));
  let expected: Value = serde_json::from_str(&expected_text).expect("parse error golden json");
  assert_json_eq(&expected, &actual, name);
}

fn assert_json_eq(expected: &Value, actual: &Value, fixture: &str) {
  if expected == actual {
    return;
  }
  let expected_text = serde_json::to_string_pretty(expected).expect("serialize expected");
  let actual_text = serde_json::to_string_pretty(actual).expect("serialize actual");
  panic!(
    "golden mismatch for fixture `{fixture}`\n--- expected\n{expected_text}\n--- actual\n{actual_text}"
  );
}

fn project_to_json(project: &NormalizedProject) -> Value {
  Value::Object(Map::from_iter([
    ("title".into(), Value::String(project.title.clone())),
    (
      "description".into(),
      project
        .description
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "version".into(),
      project
        .version
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "icon_url".into(),
      project
        .icon_url
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "security_schemes".into(),
      Value::Array(
        project
          .security_schemes
          .iter()
          .map(security_scheme_to_json)
          .collect(),
      ),
    ),
    (
      "folders".into(),
      Value::Array(project.folders.iter().map(folder_to_json).collect()),
    ),
    (
      "operations".into(),
      Value::Array(project.operations.iter().map(operation_to_json).collect()),
    ),
    (
      "environments".into(),
      Value::Array(project.environments.iter().map(environment_to_json).collect()),
    ),
  ]))
}

fn security_scheme_to_json(scheme: &NormalizedSecurityScheme) -> Value {
  Value::Object(Map::from_iter([
    ("name".into(), Value::String(scheme.name.clone())),
    ("scheme_type".into(), Value::String(scheme.scheme_type.clone())),
    (
      "description".into(),
      scheme
        .description
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "header_name".into(),
      scheme
        .header_name
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "query_name".into(),
      scheme
        .query_name
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "in_location".into(),
      scheme
        .in_location
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
  ]))
}

fn folder_to_json(folder: &NormalizedFolder) -> Value {
  Value::Object(Map::from_iter([
    ("id".into(), Value::String(folder.id.clone())),
    (
      "parent_id".into(),
      folder
        .parent_id
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    ("name".into(), Value::String(folder.name.clone())),
    ("sort_hint".into(), Value::Number(folder.sort_hint.into())),
  ]))
}

fn operation_to_json(operation: &NormalizedOperation) -> Value {
  Value::Object(Map::from_iter([
    ("primary_key".into(), Value::String(operation.primary_key.clone())),
    (
      "alternate_keys".into(),
      Value::Array(
        operation
          .alternate_keys
          .iter()
          .map(|key| Value::String(key.clone()))
          .collect(),
      ),
    ),
    ("name".into(), Value::String(operation.name.clone())),
    ("method".into(), Value::String(operation.method.clone())),
    ("path".into(), Value::String(operation.path.clone())),
    ("deprecated".into(), Value::Bool(operation.deprecated)),
    (
      "tags".into(),
      Value::Array(
        operation
          .tags
          .iter()
          .map(|tag| Value::String(tag.clone()))
          .collect(),
      ),
    ),
    (
      "protocol".into(),
      Value::String(operation_protocol(operation.protocol).into()),
    ),
    ("binding".into(), binding_to_json(operation.binding.as_ref())),
    (
      "folder_id".into(),
      operation
        .folder_id
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "parameters".into(),
      Value::Array(operation.parameters.iter().map(parameter_to_json).collect()),
    ),
    ("body".into(), body_to_json(&operation.body)),
    (
      "body_candidates".into(),
      Value::Array(
        operation
          .body_candidates
          .iter()
          .map(body_candidate_to_json)
          .collect(),
      ),
    ),
    (
      "auth".into(),
      operation
        .auth
        .as_ref()
        .map(auth_to_json)
        .unwrap_or(Value::Null),
    ),
    (
      "description".into(),
      operation
        .description
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
  ]))
}

fn parameter_to_json(parameter: &NormalizedParameter) -> Value {
  Value::Object(Map::from_iter([
    (
      "location".into(),
      Value::String(parameter_location(parameter.location).into()),
    ),
    ("name".into(), Value::String(parameter.name.clone())),
    ("value".into(), Value::String(parameter.value.clone())),
    ("required".into(), Value::Bool(parameter.required)),
    ("enabled".into(), Value::Bool(parameter.enabled)),
    (
      "value_source".into(),
      Value::String(value_source(parameter.value_source).into()),
    ),
  ]))
}

fn body_candidate_to_json(candidate: &crate::spec_import::types::NormalizedBodyCandidate) -> Value {
  Value::Object(Map::from_iter([
    ("content_type".into(), Value::String(candidate.content_type.clone())),
    ("body".into(), body_to_json(&candidate.body)),
  ]))
}

fn body_to_json(body: &NormalizedBody) -> Value {
  match body {
    NormalizedBody::None => Value::Object(Map::from_iter([("kind".into(), Value::String("None".into()))])),
    NormalizedBody::Json { content } => Value::Object(Map::from_iter([
      ("kind".into(), Value::String("Json".into())),
      ("content".into(), Value::String(content.clone())),
    ])),
    NormalizedBody::Urlencoded { fields } => Value::Object(Map::from_iter([
      ("kind".into(), Value::String("Urlencoded".into())),
      ("fields".into(), Value::Array(fields.iter().map(key_value_to_json).collect())),
    ])),
    NormalizedBody::FormData { entries } => Value::Object(Map::from_iter([
      ("kind".into(), Value::String("FormData".into())),
      (
        "entries".into(),
        Value::Array(entries.iter().map(form_data_entry_to_json).collect()),
      ),
    ])),
    NormalizedBody::Raw { content, content_type } => Value::Object(Map::from_iter([
      ("kind".into(), Value::String("Raw".into())),
      ("content".into(), Value::String(content.clone())),
      ("content_type".into(), Value::String(content_type.clone())),
    ])),
    NormalizedBody::Binary { file_name } => Value::Object(Map::from_iter([
      ("kind".into(), Value::String("Binary".into())),
      ("file_name".into(), Value::String(file_name.clone())),
    ])),
  }
}

fn auth_to_json(auth: &NormalizedAuth) -> Value {
  Value::Object(Map::from_iter([
    ("scheme_type".into(), Value::String(auth.scheme_type.clone())),
    (
      "header_name".into(),
      auth.header_name
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "query_name".into(),
      auth.query_name
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    ("placeholder_value".into(), Value::String(auth.placeholder_value.clone())),
    (
      "oauth2_grant_type".into(),
      auth.oauth2_grant_type
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "oauth2_auth_url".into(),
      auth.oauth2_auth_url
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "oauth2_token_url".into(),
      auth.oauth2_token_url
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "oauth2_scopes".into(),
      auth.oauth2_scopes
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
  ]))
}

fn environment_to_json(environment: &NormalizedEnvironment) -> Value {
  Value::Object(Map::from_iter([
    ("name".into(), Value::String(environment.name.clone())),
    (
      "variables".into(),
      Value::Array(
        environment
          .variables
          .iter()
          .map(key_value_to_json)
          .collect(),
      ),
    ),
  ]))
}

fn key_value_to_json(pair: &NormalizedKeyValue) -> Value {
  Value::Object(Map::from_iter([
    ("key".into(), Value::String(pair.key.clone())),
    ("value".into(), Value::String(pair.value.clone())),
    ("enabled".into(), Value::Bool(pair.enabled)),
  ]))
}

fn form_data_entry_to_json(entry: &NormalizedFormDataEntry) -> Value {
  Value::Object(Map::from_iter([
    ("key".into(), Value::String(entry.key.clone())),
    ("value".into(), Value::String(entry.value.clone())),
    ("is_file".into(), Value::Bool(entry.is_file)),
    (
      "file_name".into(),
      entry
        .file_name
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
    (
      "content_type".into(),
      entry
        .content_type
        .as_ref()
        .map(|value| Value::String(value.clone()))
        .unwrap_or(Value::Null),
    ),
  ]))
}

fn warnings_to_json(warnings: &[SpecWarning]) -> Value {
  Value::Array(
    warnings
      .iter()
      .map(|warning| {
        Value::Object(Map::from_iter([
          ("code".into(), Value::String(warning.code.clone())),
          ("message".into(), Value::String(warning.message.clone())),
          (
            "operation_ref".into(),
            warning
              .operation_ref
              .as_ref()
              .map(|value| Value::String(value.clone()))
              .unwrap_or(Value::Null),
          ),
        ]))
      })
      .collect(),
  )
}

fn operation_protocol(protocol: OperationProtocol) -> &'static str {
  match protocol {
    OperationProtocol::Http => "Http",
    OperationProtocol::WebSocket => "WebSocket",
  }
}

fn binding_to_json(binding: Option<&NormalizedBinding>) -> Value {
  let Some(binding) = binding else {
    return Value::Null;
  };

  Value::Object(Map::from_iter([
    (
      "protocol".into(),
      Value::String(binding_protocol(binding.protocol).into()),
    ),
    ("address".into(), Value::String(binding.address.clone())),
    ("operation_type".into(), Value::String(binding.operation_type.clone())),
    (
      "message_template".into(),
      Value::String(binding.message_template.clone()),
    ),
  ]))
}

fn binding_protocol(protocol: BindingProtocol) -> &'static str {
  match protocol {
    BindingProtocol::Http => "Http",
    BindingProtocol::WebSocket => "WebSocket",
    BindingProtocol::Unsupported => "Unsupported",
  }
}

fn parameter_location(location: ParameterLocation) -> &'static str {
  match location {
    ParameterLocation::Query => "Query",
    ParameterLocation::Path => "Path",
    ParameterLocation::Header => "Header",
    ParameterLocation::Cookie => "Cookie",
  }
}

fn value_source(source: ValueSource) -> &'static str {
  match source {
    ValueSource::FromExample => "FromExample",
    ValueSource::FromDefault => "FromDefault",
    ValueSource::FromEnum => "FromEnum",
    ValueSource::Synthesized => "Synthesized",
    ValueSource::Missing => "Missing",
  }
}

// MARK: - diff_spec goldens (AC18)

pub fn fixture_diff_golden_path(name: &str) -> PathBuf {
  fixtures_dir().join(format!("{name}.diff.json"))
}

/// Serialize a [`SpecSyncDiff`] to canonical golden JSON.
pub fn diff_to_json(diff: &SpecSyncDiff) -> Value {
  Value::Object(Map::from_iter([
    (
      "added".into(),
      Value::Array(diff.added.iter().map(operation_to_json).collect()),
    ),
    (
      "removed".into(),
      Value::Array(diff.removed.iter().map(matched_operation_to_json).collect()),
    ),
    (
      "modified".into(),
      Value::Array(diff.modified.iter().map(operation_diff_to_json).collect()),
    ),
    (
      "unchanged".into(),
      Value::Array(diff.unchanged.iter().map(matched_operation_to_json).collect()),
    ),
    (
      "identity_changed".into(),
      Value::Array(
        diff
          .identity_changed
          .iter()
          .map(identity_change_to_json)
          .collect(),
      ),
    ),
  ]))
}

pub fn assert_or_update_diff_golden(name: &str, diff: &SpecSyncDiff) {
  let golden_path = fixture_diff_golden_path(name);
  let actual = diff_to_json(diff);
  if update_goldens_enabled() {
    write_golden_json(&golden_path, &actual).expect("write diff golden");
    return;
  }
  let expected_text = fs::read_to_string(&golden_path)
    .unwrap_or_else(|_| panic!("missing diff golden file: {}", golden_path.display()));
  let expected: Value = serde_json::from_str(&expected_text).expect("parse diff golden json");
  assert_json_eq(&expected, &actual, name);
}

fn matched_operation_to_json(matched: &MatchedOperation) -> Value {
  Value::Object(Map::from_iter([
    ("request_id".into(), Value::String(matched.request_id.clone())),
    ("primary_key".into(), Value::String(matched.primary_key.clone())),
    ("operation".into(), operation_to_json(&matched.operation)),
  ]))
}

fn operation_diff_to_json(diff: &OperationDiff) -> Value {
  Value::Object(Map::from_iter([
    ("request_id".into(), Value::String(diff.request_id.clone())),
    ("primary_key".into(), Value::String(diff.primary_key.clone())),
    (
      "old_operation".into(),
      operation_to_json(&diff.old_operation),
    ),
    (
      "new_operation".into(),
      operation_to_json(&diff.new_operation),
    ),
    (
      "field_deltas".into(),
      Value::Array(diff.field_deltas.iter().map(field_delta_to_json).collect()),
    ),
  ]))
}

fn identity_change_to_json(change: &IdentityChangeDiff) -> Value {
  Value::Object(Map::from_iter([
    ("request_id".into(), Value::String(change.request_id.clone())),
    (
      "old_primary_key".into(),
      Value::String(change.old_primary_key.clone()),
    ),
    (
      "new_primary_key".into(),
      Value::String(change.new_primary_key.clone()),
    ),
    (
      "old_operation".into(),
      operation_to_json(&change.old_operation),
    ),
    (
      "new_operation".into(),
      operation_to_json(&change.new_operation),
    ),
    (
      "field_deltas".into(),
      Value::Array(change.field_deltas.iter().map(field_delta_to_json).collect()),
    ),
  ]))
}

fn field_delta_to_json(delta: &SpecFieldDelta) -> Value {
  Value::Object(Map::from_iter([
    ("field".into(), Value::String(spec_sync_field(delta.field).into())),
    ("old_value".into(), Value::String(delta.old_value.clone())),
    ("new_value".into(), Value::String(delta.new_value.clone())),
    ("is_conflict".into(), Value::Bool(delta.is_conflict)),
  ]))
}

fn spec_sync_field(field: SpecSyncField) -> &'static str {
  match field {
    SpecSyncField::Method => "Method",
    SpecSyncField::Url => "Url",
    SpecSyncField::Params => "Params",
    SpecSyncField::Headers => "Headers",
    SpecSyncField::Body => "Body",
    SpecSyncField::Name => "Name",
  }
}

/// Fixture builders for AC18 diff_spec golden tests.
pub mod diff_fixtures {
  use super::*;

  use crate::spec_import::diff::{DiffOptions, diff_spec};

  pub struct DiffFixture {
    pub name: &'static str,
    pub old: NormalizedProject,
    pub new: NormalizedProject,
    pub bindings: Vec<SpecOperationBinding>,
  }

  pub fn all() -> Vec<DiffFixture> {
    vec![
      added_fixture(),
      modified_fixture(),
      removed_fixture(),
      identity_change_fixture(),
    ]
  }

  pub fn run(fixture: &DiffFixture) -> SpecSyncDiff {
    diff_spec(
      fixture.old.clone(),
      fixture.new.clone(),
      fixture.bindings.clone(),
      DiffOptions::default(),
    )
    .expect("fixture diff should succeed")
  }

  fn empty_project() -> NormalizedProject {
    NormalizedProject {
      title: "Linked Spec".into(),
      description: None,
      version: None,
      icon_url: None,
      security_schemes: vec![],
      folders: vec![],
      operations: vec![],
      environments: vec![],
    }
  }

  fn sample_operation(primary_key: &str, method: &str, path: &str, name: &str) -> NormalizedOperation {
    NormalizedOperation {
      primary_key: primary_key.into(),
      alternate_keys: vec![],
      name: name.into(),
      method: method.into(),
      path: path.into(),
      deprecated: false,
      tags: vec![],
      protocol: OperationProtocol::Http,
      binding: None,
      folder_id: None,
      parameters: vec![],
      body: NormalizedBody::None,
      body_candidates: vec![],
      auth: None,
      description: None,
    }
  }

  fn added_fixture() -> DiffFixture {
    let old = empty_project();
    let mut new = empty_project();
    new.operations
      .push(sample_operation("createPet", "POST", "/pet", "Create pet"));

    DiffFixture {
      name: "diff-added",
      old,
      new,
      bindings: vec![],
    }
  }

  fn modified_fixture() -> DiffFixture {
    let mut old = empty_project();
    let mut new = empty_project();

    let mut old_op = sample_operation("listPets", "GET", "/pet", "List pets");
    old_op.parameters.push(NormalizedParameter {
      location: ParameterLocation::Query,
      name: "limit".into(),
      value: "10".into(),
      required: false,
      enabled: false,
      value_source: ValueSource::FromExample,
    });
    let mut new_op = old_op.clone();
    new_op.parameters[0].value = "25".into();
    new_op.body = NormalizedBody::Json {
      content: "{}".into(),
    };

    old.operations.push(old_op);
    new.operations.push(new_op);

    DiffFixture {
      name: "diff-modified",
      old,
      new,
      bindings: vec![SpecOperationBinding {
        request_id: "00000000-0000-0000-0000-000000000101".into(),
        primary_key: "listPets".into(),
        alternate_keys: vec![],
      }],
    }
  }

  fn removed_fixture() -> DiffFixture {
    let mut old = empty_project();
    let mut new = empty_project();

    old.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));
    old.operations
      .push(sample_operation("getPet", "GET", "/pet/{id}", "Get pet"));
    new.operations
      .push(sample_operation("getPet", "GET", "/pet/{id}", "Get pet"));

    DiffFixture {
      name: "diff-removed",
      old,
      new,
      bindings: vec![
        SpecOperationBinding {
          request_id: "00000000-0000-0000-0000-000000000201".into(),
          primary_key: "listPets".into(),
          alternate_keys: vec![],
        },
        SpecOperationBinding {
          request_id: "00000000-0000-0000-0000-000000000202".into(),
          primary_key: "getPet".into(),
          alternate_keys: vec![],
        },
      ],
    }
  }

  fn identity_change_fixture() -> DiffFixture {
    let mut old = empty_project();
    let mut new = empty_project();

    old.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));
    new.operations
      .push(sample_operation("listAllPets", "GET", "/pet", "List all pets"));

    DiffFixture {
      name: "diff-identity-change",
      old,
      new,
      bindings: vec![SpecOperationBinding {
        request_id: "00000000-0000-0000-0000-000000000301".into(),
        primary_key: "listPets".into(),
        alternate_keys: vec![],
      }],
    }
  }
}