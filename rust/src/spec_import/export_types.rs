//! UniFFI types for spec export (Swift → Rust).

use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ExportBodyType {
  None,
  Json,
  FormData,
  Urlencoded,
  Raw,
  Binary,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ExportAuthType {
  None,
  Bearer,
  Basic,
  ApiKey,
  Oauth2,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ExportFormat {
  Yaml,
  Json,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportKeyValue {
  pub key: String,
  pub value: String,
  pub enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportFormDataEntry {
  pub key: String,
  pub value: String,
  pub enabled: bool,
  pub is_file: bool,
  pub file_name: String,
  pub content_type: String,
}

/// Mirrors Swift `HttpRequestData` fields needed for spec export.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportHttpRequestData {
  pub method: String,
  pub url: String,
  pub params: Vec<ExportKeyValue>,
  pub headers: Vec<ExportKeyValue>,
  pub body_type: ExportBodyType,
  pub body_content: String,
  pub body_form_data: Vec<ExportKeyValue>,
  pub body_form_data_entries: Vec<ExportFormDataEntry>,
  pub raw_content_type: String,
  pub binary_file_name: String,
  pub auth_type: ExportAuthType,
  pub auth_token: String,
  pub auth_username: String,
  pub auth_password: String,
  pub auth_api_key_name: String,
  pub auth_api_key_value: String,
  pub auth_api_key_location: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportFolder {
  pub id: String,
  pub parent_id: Option<String>,
  pub name: String,
  pub sort_order: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportEnvironment {
  pub name: String,
  pub variables: Vec<ExportKeyValue>,
  pub is_active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportOperation {
  pub name: String,
  pub folder_id: Option<String>,
  pub sort_order: u32,
  pub deprecated: bool,
  pub description: Option<String>,
  pub spec_primary_key: Option<String>,
  /// Content types to emit when `http.body_type` is `None` but the source spec had a request body.
  pub request_body_content_types: Vec<String>,
  pub http: ExportHttpRequestData,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportProjectInput {
  pub title: String,
  pub description: Option<String>,
  pub version: Option<String>,
  pub folders: Vec<ExportFolder>,
  pub operations: Vec<ExportOperation>,
  pub environments: Vec<ExportEnvironment>,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportOpenApiOptions {
  #[uniffi(default = true)]
  pub include_environments: bool,
  #[uniffi(default = true)]
  pub include_deprecated: bool,
}

impl Default for ExportOpenApiOptions {
  fn default() -> Self {
    Self {
      include_environments: true,
      include_deprecated: true,
    }
  }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ExportPostmanOptions {
  #[uniffi(default = true)]
  pub include_environments: bool,
  #[uniffi(default = true)]
  pub include_deprecated: bool,
}

impl Default for ExportPostmanOptions {
  fn default() -> Self {
    Self {
      include_environments: true,
      include_deprecated: true,
    }
  }
}

#[derive(Debug, Error, uniffi::Error)]
pub enum SpecExportError {
  #[error("Invalid export input: {0}")]
  InvalidInput(String),
}