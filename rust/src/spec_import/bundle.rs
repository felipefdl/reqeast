//! Multi-file OpenAPI bundle resolution with local `file://` refs only.

use std::path::{Component, Path, PathBuf};

use roas::loader::{Loader, LoaderError, ResourceFetcher};
use roas_file_fetcher::FileFetcher;
use serde_json::Value;
use url::Url;

use crate::spec_import::types::SpecImportError;

/// Resolved bundle root and entry document path for multi-file imports.
#[derive(Debug, Clone)]
pub struct BundleContext {
  pub root: PathBuf,
  pub entry_path: PathBuf,
  pub entry_uri: Url,
}

/// Rewrite relative `$ref` strings in `value` against `base`, matching roas loader behavior.
pub fn rewrite_refs_in_value(value: &mut Value, base: &Url) {
  match value {
    Value::Object(map) => {
      if let Some(Value::String(reference)) = map.get_mut("$ref") {
        if let Ok(joined) = base.join(reference) {
          *reference = joined.to_string();
        }
      }
      for child in map.values_mut() {
        rewrite_refs_in_value(child, base);
      }
    }
    Value::Array(items) => {
      for child in items.iter_mut() {
        rewrite_refs_in_value(child, base);
      }
    }
    _ => {}
  }
}

impl BundleContext {
  /// Build bundle context from an absolute entry file path.
  pub fn from_entry_path(entry_path: PathBuf) -> Result<Self, SpecImportError> {
    let entry_path = entry_path
      .canonicalize()
      .map_err(|err| SpecImportError::InvalidSpec(format!("Invalid bundle entry path: {err}")))?;
    let root = entry_path
      .parent()
      .ok_or_else(|| SpecImportError::InvalidSpec("Bundle entry path has no parent directory".into()))?
      .to_path_buf();
    let root = root
      .canonicalize()
      .map_err(|err| SpecImportError::InvalidSpec(format!("Invalid bundle root path: {err}")))?;

    let entry_uri = Url::from_file_path(&entry_path).map_err(|()| {
      SpecImportError::InvalidSpec(format!(
        "Could not convert bundle entry to file URI: {}",
        entry_path.display()
      ))
    })?;

    Ok(Self {
      root,
      entry_path,
      entry_uri,
    })
  }

  /// Configure a loader with the bundle entry preloaded and a scoped file fetcher.
  pub fn configure_loader(&self, loader: &mut Loader, value: Value) -> Result<(), SpecImportError> {
    loader.register_fetcher(
      "file://",
      BundleFileFetcher::with_yaml(self.root.clone()),
    );
    loader
      .preload_resource(self.entry_uri.as_str(), value)
      .map_err(map_loader_error)?;
    Ok(())
  }

  /// Validate that a `$ref` target stays inside the bundle root.
  pub fn validate_file_reference(&self, reference: &str) -> Result<(), String> {
    let resource_uri = resolve_reference_to_file_uri(reference, Some(&self.entry_uri))?;
    let path = file_uri_to_path(&resource_uri)?;
    ensure_within_bundle(&self.root, &path)?;
    Ok(())
  }

  /// Load an external (non-`#/`) document referenced from the bundle entry.
  pub fn load_external_value(&self, reference: &str) -> Result<Value, String> {
    let resource_uri = resolve_reference_to_file_uri(reference, Some(&self.entry_uri))?;
    let path = file_uri_to_path(&resource_uri)?;
    ensure_within_bundle(&self.root, &path)?;
    let bytes = std::fs::read(&path)
      .map_err(|err| format!("Failed to read bundle file `{}`: {err}", path.display()))?;
    parse_bundle_body(&resource_uri, &bytes)
  }
}

/// Scoped filesystem fetcher that only allows reads inside a bundle root.
#[derive(Clone, Debug)]
pub struct BundleFileFetcher {
  bundle_root: PathBuf,
  inner: FileFetcher,
}

impl BundleFileFetcher {
  /// Construct a YAML-aware file fetcher scoped to `bundle_root`.
  pub fn with_yaml(bundle_root: PathBuf) -> Self {
    Self {
      bundle_root,
      inner: FileFetcher::new(),
    }
  }
}

impl ResourceFetcher for BundleFileFetcher {
  fn fetch(&mut self, uri: &Url) -> Result<Value, LoaderError> {
    if uri.scheme() != "file" {
      return Err(LoaderError::UnsupportedFetcherUri(uri.as_str().to_string()));
    }

    let path = file_uri_to_path(uri).map_err(LoaderError::InvalidFileUri)?;
    ensure_within_bundle(&self.bundle_root, &path).map_err(|message| LoaderError::ReadFile {
      path: path.clone(),
      source: std::io::Error::new(std::io::ErrorKind::PermissionDenied, message),
    })?;

    self.inner.fetch(uri)
  }
}

pub fn is_remote_reference(reference: &str) -> bool {
  let lower = reference.to_ascii_lowercase();
  lower.starts_with("http://") || lower.starts_with("https://")
}

fn resolve_reference_to_file_uri(reference: &str, base: Option<&Url>) -> Result<Url, String> {
  if let Ok(url) = Url::parse(reference) {
    if url.scheme() == "file" {
      return Ok(strip_fragment(url));
    }
    return Err(format!("Remote $ref is not allowed: {reference}"));
  }

  let base = base.ok_or_else(|| format!("External $ref is not allowed in P0: {reference}"))?;
  base
    .join(reference)
    .map(strip_fragment)
    .map_err(|_| format!("External $ref is not allowed in P0: {reference}"))
}

fn strip_fragment(mut url: Url) -> Url {
  url.set_fragment(None);
  url
}

fn file_uri_to_path(uri: &Url) -> Result<PathBuf, String> {
  uri
    .to_file_path()
    .map_err(|()| format!("Invalid file URI: {}", uri.as_str()))
}

fn ensure_within_bundle(bundle_root: &Path, target: &Path) -> Result<(), String> {
  let canonical_root = bundle_root
    .canonicalize()
    .map_err(|err| format!("Invalid bundle root `{}`: {err}", bundle_root.display()))?;
  let canonical_target = target
    .canonicalize()
    .map_err(|err| format!("Invalid bundle file `{}`: {err}", target.display()))?;

  if !canonical_target.starts_with(&canonical_root) {
    return Err(format!(
      "External $ref escapes bundle root: {}",
      target.display()
    ));
  }

  for component in target.components() {
    if matches!(component, Component::ParentDir) {
      return Err(format!(
        "External $ref escapes bundle root: {}",
        target.display()
      ));
    }
  }

  Ok(())
}

fn parse_bundle_body(uri: &Url, bytes: &[u8]) -> Result<Value, String> {
  let path = uri.path().to_ascii_lowercase();
  if path.ends_with(".yaml") || path.ends_with(".yml") {
    let yaml_value: serde_yaml_ng::Value = serde_yaml_ng::from_slice(bytes)
      .map_err(|err| format!("Invalid YAML in `{}`: {err}", uri.as_str()))?;
    serde_json::to_value(yaml_value)
      .map_err(|err| format!("YAML to JSON conversion failed for `{}`: {err}", uri.as_str()))
  } else {
    serde_json::from_slice(bytes)
      .map_err(|err| format!("Invalid JSON in `{}`: {err}", uri.as_str()))
  }
}

fn map_loader_error(err: LoaderError) -> SpecImportError {
  SpecImportError::InvalidSpec(err.to_string())
}

#[cfg(test)]
mod tests {
  use super::*;
  use std::fs;
  use std::time::{SystemTime, UNIX_EPOCH};

  fn temp_bundle_dir(name: &str) -> PathBuf {
    let nanos = SystemTime::now()
      .duration_since(UNIX_EPOCH)
      .expect("clock")
      .as_nanos();
    let dir = std::env::temp_dir().join(format!("reqeast-bundle-{name}-{nanos}"));
    fs::create_dir_all(&dir).expect("create temp bundle dir");
    dir
  }

  #[test]
  fn bundle_fetcher_allows_file_inside_root() {
    let root = temp_bundle_dir("allow");
    let child = root.join("components");
    fs::create_dir_all(&child).unwrap();
    fs::write(
      child.join("pet.json"),
      br#"{"components":{"schemas":{"Pet":{"type":"object"}}}}"#,
    )
    .unwrap();

    let uri = Url::from_file_path(child.join("pet.json")).unwrap();
    let mut fetcher = BundleFileFetcher::with_yaml(root.clone());
    let value = fetcher.fetch(&uri).expect("in-bundle file should load");
    assert!(value.get("components").is_some());

    fs::remove_dir_all(root).ok();
  }

  #[test]
  fn bundle_fetcher_rejects_file_outside_root() {
    let root = temp_bundle_dir("reject-root");
    let outside = temp_bundle_dir("reject-outside");
    let outside_file = outside.join("outside.json");
    fs::write(&outside_file, br#"{"ok":true}"#).unwrap();

    let uri = Url::from_file_path(&outside_file).unwrap();
    let mut fetcher = BundleFileFetcher::with_yaml(root.clone());
    let err = fetcher.fetch(&uri).expect_err("outside file should be rejected");
    assert!(matches!(err, LoaderError::ReadFile { .. }));

    fs::remove_dir_all(root).ok();
    fs::remove_dir_all(outside).ok();
  }

  #[test]
  fn bundle_context_loads_relative_yaml_ref() {
    let root = temp_bundle_dir("relative");
    fs::create_dir_all(root.join("components/schemas")).unwrap();
    fs::write(
      root.join("components/schemas/Pet.yaml"),
      b"type: object\nproperties:\n  name:\n    type: string\n    example: Fluffy\n",
    )
    .unwrap();
    fs::write(
      root.join("openapi.yaml"),
      b"openapi: 3.0.0\ninfo:\n  title: Bundle\n  version: 1.0.0\npaths: {}\n",
    )
    .unwrap();

    let ctx = BundleContext::from_entry_path(root.join("openapi.yaml")).expect("bundle context");
    let value = ctx
      .load_external_value("components/schemas/Pet.yaml")
      .expect("relative yaml ref");
    assert_eq!(value["properties"]["name"]["example"], "Fluffy");

    fs::remove_dir_all(root).ok();
  }
}