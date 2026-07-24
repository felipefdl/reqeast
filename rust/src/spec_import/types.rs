//! UniFFI types for spec import normalized IR and entry points.

use thiserror::Error;

use serde_json::Value;

use std::path::PathBuf;

use crate::spec_import::asyncapi::{is_asyncapi_document, normalize_asyncapi};
use crate::spec_import::bruno::{is_bruno_opencollection, normalize_bruno};
use crate::spec_import::bundle::BundleContext;
use crate::spec_import::fingerprint::hash_bytes;
use crate::spec_import::graphql::{is_graphql_sdl, normalize_graphql};
use crate::spec_import::har::{is_har_log, normalize_har};
use crate::spec_import::ingress::parse_ingress;
use crate::spec_import::insomnia::{is_insomnia_export, normalize_insomnia};
use crate::spec_import::normalize::{normalize_openapi, normalize_openapi_with_bundle};
use crate::spec_import::postman::{is_postman_collection, normalize_postman};

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SpecSourceHint {
  Unknown,
  Json,
  Yaml,
  OpenApi,
  Postman,
  Insomnia,
  Bruno,
  Graphql,
  Har,
  AsyncApi,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ValueSource {
  FromExample,
  FromDefault,
  FromEnum,
  Synthesized,
  Missing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ParameterLocation {
  Query,
  Path,
  Header,
  Cookie,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum OperationProtocol {
  Http,
  WebSocket,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BindingProtocol {
  Http,
  WebSocket,
  Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NormalizedBinding {
  pub protocol: BindingProtocol,
  pub address: String,
  pub operation_type: String,
  pub message_template: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NormalizedKeyValue {
  pub key: String,
  pub value: String,
  pub enabled: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NormalizedFormDataEntry {
  pub key: String,
  pub value: String,
  pub is_file: bool,
  pub file_name: Option<String>,
  pub content_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NormalizedParameter {
  pub location: ParameterLocation,
  pub name: String,
  pub value: String,
  pub required: bool,
  pub enabled: bool,
  pub value_source: ValueSource,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum NormalizedBody {
  None,
  Json { content: String },
  Urlencoded { fields: Vec<NormalizedKeyValue> },
  FormData { entries: Vec<NormalizedFormDataEntry> },
  Raw { content: String, content_type: String },
  Binary { file_name: String },
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NormalizedBodyCandidate {
  pub content_type: String,
  pub body: NormalizedBody,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NormalizedAuth {
  pub scheme_type: String,
  pub header_name: Option<String>,
  pub query_name: Option<String>,
  pub placeholder_value: String,
  /// OAuth2 grant flow key (e.g. `clientCredentials`, `authorizationCode`).
  pub oauth2_grant_type: Option<String>,
  pub oauth2_auth_url: Option<String>,
  pub oauth2_token_url: Option<String>,
  /// Space-separated scopes requested by the operation.
  pub oauth2_scopes: Option<String>,
}

impl NormalizedAuth {
  pub fn without_oauth2_scaffold(
    scheme_type: impl Into<String>,
    header_name: Option<String>,
    query_name: Option<String>,
    placeholder_value: impl Into<String>,
  ) -> Self {
    Self {
      scheme_type: scheme_type.into(),
      header_name,
      query_name,
      placeholder_value: placeholder_value.into(),
      oauth2_grant_type: None,
      oauth2_auth_url: None,
      oauth2_token_url: None,
      oauth2_scopes: None,
    }
  }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NormalizedSecurityScheme {
  pub name: String,
  pub scheme_type: String,
  pub description: Option<String>,
  pub header_name: Option<String>,
  pub query_name: Option<String>,
  pub in_location: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NormalizedOperation {
  pub primary_key: String,
  pub alternate_keys: Vec<String>,
  pub name: String,
  pub method: String,
  pub path: String,
  pub deprecated: bool,
  pub tags: Vec<String>,
  pub protocol: OperationProtocol,
  pub binding: Option<NormalizedBinding>,
  pub folder_id: Option<String>,
  pub parameters: Vec<NormalizedParameter>,
  pub body: NormalizedBody,
  /// All request-body content types from the spec; mapper picks preferred type in Swift.
  pub body_candidates: Vec<NormalizedBodyCandidate>,
  pub auth: Option<NormalizedAuth>,
  pub description: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NormalizedFolder {
  pub id: String,
  pub parent_id: Option<String>,
  pub name: String,
  pub sort_hint: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NormalizedEnvironment {
  pub name: String,
  pub variables: Vec<NormalizedKeyValue>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NormalizedProject {
  pub title: String,
  pub description: Option<String>,
  pub version: Option<String>,
  /// OpenAPI `info.x-logo.url` or favicon derived from the first server URL.
  pub icon_url: Option<String>,
  pub security_schemes: Vec<NormalizedSecurityScheme>,
  pub folders: Vec<NormalizedFolder>,
  pub operations: Vec<NormalizedOperation>,
  pub environments: Vec<NormalizedEnvironment>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct SpecWarning {
  pub code: String,
  pub message: String,
  pub operation_ref: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct SpecImportResult {
  pub project: NormalizedProject,
  pub warnings: Vec<SpecWarning>,
  pub content_fingerprint: String,
}

#[derive(Debug, Clone, Copy, Default, uniffi::Record)]
pub struct SpecParseOptions {
  #[uniffi(default = false)]
  pub enable_schema_synthesis: bool,
  #[uniffi(default = false)]
  pub import_har_credentials_as_placeholders: bool,
}

#[derive(Debug, Error, uniffi::Error)]
pub enum SpecImportError {
  #[error("Invalid spec: {0}")]
  InvalidSpec(String),

  #[error("Unsupported format: {0}")]
  UnsupportedFormat(String),

  #[error("Parse error: {0}")]
  ParseError(String),
}

/// Parses a spec file into normalized IR.
///
/// When `bundle_entry_path` is set, local `file://` and relative `$ref`s are resolved
/// inside that bundle directory. Remote refs remain fatal.
#[uniffi::export]
pub fn parse_spec(
  bytes: Vec<u8>,
  source_hint: SpecSourceHint,
  bundle_entry_path: Option<String>,
  options: SpecParseOptions,
) -> Result<SpecImportResult, SpecImportError> {
  let bundle = bundle_entry_path
    .map(PathBuf::from)
    .map(BundleContext::from_entry_path)
    .transpose()?;

  if source_hint == SpecSourceHint::Graphql || is_graphql_sdl(&bytes) {
    let normalized = normalize_graphql(&bytes)?;
    return Ok(SpecImportResult {
      project: normalized.project,
      warnings: normalized.warnings,
      content_fingerprint: normalized.content_fingerprint,
    });
  }

  let value = parse_ingress(&bytes).map_err(|err| SpecImportError::ParseError(err.to_string()))?;
  let normalized = match detect_spec_format(&value, source_hint) {
    SpecFormat::Postman => normalize_postman(value)?,
    SpecFormat::Insomnia => normalize_insomnia(value)?,
    SpecFormat::Bruno => normalize_bruno(value)?,
    SpecFormat::Har => normalize_har(value, options)?,
    SpecFormat::AsyncApi => normalize_asyncapi(value)?,
    SpecFormat::OpenApi => match bundle {
      Some(ctx) => normalize_openapi_with_bundle(value, Some(ctx), options)?,
      None => normalize_openapi(value, options)?,
    },
    SpecFormat::Unknown => {
      return Err(SpecImportError::UnsupportedFormat(
        "Unrecognized spec format; expected OpenAPI, Postman, Insomnia, Bruno, GraphQL SDL, HAR, or AsyncAPI".into(),
      ));
    }
  };

  Ok(SpecImportResult {
    project: normalized.project,
    warnings: normalized.warnings,
    content_fingerprint: normalized.content_fingerprint,
  })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SpecFormat {
  OpenApi,
  Postman,
  Insomnia,
  Bruno,
  Har,
  AsyncApi,
  Unknown,
}

fn detect_spec_format(value: &Value, source_hint: SpecSourceHint) -> SpecFormat {
  if source_hint == SpecSourceHint::Postman || is_postman_collection(value) {
    return SpecFormat::Postman;
  }

  if source_hint == SpecSourceHint::Insomnia || is_insomnia_export(value) {
    return SpecFormat::Insomnia;
  }

  if source_hint == SpecSourceHint::Bruno || is_bruno_opencollection(value) {
    return SpecFormat::Bruno;
  }

  if source_hint == SpecSourceHint::Har || is_har_log(value) {
    return SpecFormat::Har;
  }

  if source_hint == SpecSourceHint::AsyncApi || is_asyncapi_document(value) {
    return SpecFormat::AsyncApi;
  }

  if source_hint == SpecSourceHint::OpenApi || value.get("openapi").is_some() || value.get("swagger").is_some() {
    return SpecFormat::OpenApi;
  }

  SpecFormat::Unknown
}

/// SHA-256 hex digest of canonical resolved spec bytes.
#[uniffi::export]
pub fn canonical_fingerprint(resolved_bytes: Vec<u8>) -> String {
  hash_bytes(&resolved_bytes)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn canonical_fingerprint_is_sha256_hex() {
    let fingerprint = canonical_fingerprint(b"hello".to_vec());
    assert_eq!(
      fingerprint,
      "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    );
  }

  #[test]
  fn parse_spec_rejects_invalid_json() {
    let err = parse_spec(
      b"{not json".to_vec(),
      SpecSourceHint::Json,
      None,
      SpecParseOptions::default(),
    )
    .expect_err("invalid json");
    assert!(matches!(err, SpecImportError::ParseError(_)));
  }

  #[test]
  fn parse_spec_normalizes_valid_openapi() {
    let result = parse_spec(
      br#"{"openapi":"3.0.0","info":{"title":"Petstore","version":"1.0.0"},"paths":{}}"#.to_vec(),
      SpecSourceHint::OpenApi,
      None,
      SpecParseOptions::default(),
    )
    .expect("valid json should parse");

    assert_eq!(result.project.title, "Petstore");
    assert!(result.project.operations.is_empty());
    assert!(!result.content_fingerprint.is_empty());
  }

  #[test]
  fn parse_spec_normalizes_valid_insomnia_export() {
    let export = br#"{
      "_type": "export",
      "__export_format": 4,
      "resources": [
        { "_id": "wrk_demo", "_type": "workspace", "parentId": null, "name": "Insomnia Demo" },
        {
          "_id": "req_ping",
          "_type": "request",
          "parentId": "wrk_demo",
          "name": "Ping",
          "method": "GET",
          "url": "{{base_url}}/ping",
          "parameters": [],
          "headers": [],
          "body": {},
          "authentication": {}
        }
      ]
    }"#;

    let result = parse_spec(
      export.to_vec(),
      SpecSourceHint::Insomnia,
      None,
      SpecParseOptions::default(),
    )
    .expect("insomnia parse");
    assert_eq!(result.project.title, "Insomnia Demo");
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].primary_key, "GET /ping");
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "MIGRATION_FROM_INSOMNIA")
    );
  }

  #[test]
  fn parse_spec_normalizes_valid_bruno_collection() {
    let collection = br#"{
      "opencollection": "1.0.0",
      "info": { "name": "Bruno Demo", "version": "1.0.0" },
      "items": [
        {
          "info": { "name": "Ping", "type": "http" },
          "http": { "method": "GET", "url": "{{base_url}}/ping" }
        }
      ]
    }"#;

    let result = parse_spec(
      collection.to_vec(),
      SpecSourceHint::Bruno,
      None,
      SpecParseOptions::default(),
    )
    .expect("bruno parse");
    assert_eq!(result.project.title, "Bruno Demo");
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].primary_key, "GET /ping");
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "MIGRATION_FROM_BRUNO")
    );
  }

  #[test]
  fn parse_spec_normalizes_valid_graphql_sdl() {
    let sdl = br#"
      type Query {
        ping: String!
      }
    "#;

    let result =
      parse_spec(sdl.to_vec(), SpecSourceHint::Graphql, None, SpecParseOptions::default()).expect("graphql parse");
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].primary_key, "query ping");
    assert_eq!(result.project.operations[0].method, "POST");
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "GRAPHQL_SDL_IMPORT")
    );
  }

  #[test]
  fn parse_spec_normalizes_valid_har_capture() {
    let capture = br#"{
      "log": {
        "version": "1.2",
        "creator": { "name": "Capture" },
        "entries": [
          {
            "request": {
              "method": "GET",
              "url": "https://api.example.com/ping",
              "headers": [
                { "name": "Authorization", "value": "Bearer secret" }
              ]
            },
            "response": { "status": 200, "headers": [] }
          }
        ]
      }
    }"#;

    let result =
      parse_spec(capture.to_vec(), SpecSourceHint::Har, None, SpecParseOptions::default()).expect("har parse");
    assert_eq!(result.project.title, "Capture");
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].primary_key, "GET /ping");
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "HAR_CREDENTIALS_STRIPPED")
    );
  }

  #[test]
  fn parse_spec_normalizes_valid_postman_collection() {
    let collection = br#"{
      "info": {
        "name": "Sample",
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
      },
      "item": [
        {
          "name": "Ping",
          "request": { "method": "GET", "url": "{{base_url}}/ping" }
        }
      ]
    }"#;

    let result = parse_spec(
      collection.to_vec(),
      SpecSourceHint::Postman,
      None,
      SpecParseOptions::default(),
    )
    .expect("postman parse");
    assert_eq!(result.project.title, "Sample");
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].primary_key, "GET /ping");
  }

  #[test]
  fn normalized_body_json_variant() {
    let body = NormalizedBody::Json {
      content: r#"{"id":1}"#.into(),
    };
    if let NormalizedBody::Json { content } = body {
      assert!(content.contains("id"));
    } else {
      panic!("expected Json variant");
    }
  }

  #[test]
  fn parse_spec_unknown_json_returns_unsupported_format() {
    let err = parse_spec(
      br#"{"foo":"bar"}"#.to_vec(),
      SpecSourceHint::Unknown,
      None,
      SpecParseOptions::default(),
    )
    .expect_err("unknown json should be unsupported");

    assert!(matches!(err, SpecImportError::UnsupportedFormat(_)));
  }
}
