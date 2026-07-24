//! Canonical resolved JSON bundling and SHA-256 fingerprinting.

use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

use crate::spec_import::bundle::{BundleContext, is_remote_reference};
use crate::spec_import::limits::MAX_REF_DEPTH;

/// SHA-256 hex digest of canonical resolved spec bytes.
pub fn hash_bytes(bytes: &[u8]) -> String {
  let digest = Sha256::digest(bytes);
  digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// Bundle internal `$ref`s, sort object keys, and emit canonical JSON bytes.
pub fn bundle_and_canonicalize(root: &Value) -> Result<Vec<u8>, String> {
  bundle_and_canonicalize_with_bundle(root, None)
}

/// Bundle `$ref`s including local bundle files when `bundle` is present.
pub fn bundle_and_canonicalize_with_bundle(root: &Value, bundle: Option<&BundleContext>) -> Result<Vec<u8>, String> {
  let bundled = bundle_refs(root, bundle)?;
  let canonical = sort_value(&bundled);
  serde_json::to_vec(&canonical).map_err(|err| format!("Failed to serialize canonical spec: {err}"))
}

fn bundle_refs(root: &Value, bundle: Option<&BundleContext>) -> Result<Value, String> {
  let mut resolving = Vec::new();
  bundle_value(root, root, 0, &mut resolving, bundle)
}

fn bundle_value(
  root: &Value,
  value: &Value,
  depth: usize,
  resolving: &mut Vec<String>,
  bundle: Option<&BundleContext>,
) -> Result<Value, String> {
  if depth > MAX_REF_DEPTH {
    return Err(format!("$ref resolution exceeds maximum depth of {MAX_REF_DEPTH}"));
  }

  match value {
    Value::Object(map) => {
      if let Some(reference) = map.get("$ref").and_then(Value::as_str) {
        if map.len() != 1 {
          // Reference objects with siblings: resolve target and merge is out of P0 scope;
          // follow the $ref target for fingerprint stability.
        }
        return resolve_and_bundle(root, reference, depth, resolving, bundle);
      }

      let mut out = BTreeMap::new();
      for (key, child) in map {
        out.insert(key.clone(), bundle_value(root, child, depth, resolving, bundle)?);
      }
      Ok(Value::Object(out.into_iter().collect()))
    }
    Value::Array(items) => {
      let out: Result<Vec<_>, _> = items
        .iter()
        .map(|item| bundle_value(root, item, depth, resolving, bundle))
        .collect();
      Ok(Value::Array(out?))
    }
    _ => Ok(value.clone()),
  }
}

fn resolve_and_bundle(
  root: &Value,
  reference: &str,
  depth: usize,
  resolving: &mut Vec<String>,
  bundle: Option<&BundleContext>,
) -> Result<Value, String> {
  if is_remote_reference(reference) {
    return Err(format!("Remote $ref is not allowed: {reference}"));
  }

  if resolving.last().is_some_and(|top| top == reference) {
    // OpenAPI discriminator stubs often use a self-$ref inside oneOf as a mapping anchor.
    return Ok(serde_json::json!({ "type": "object" }));
  }
  if resolving.iter().any(|item| item == reference) {
    return Err(format!("Cyclic $ref detected: {reference}"));
  }

  if !reference.starts_with("#/") {
    let Some(ctx) = bundle else {
      return Err(format!("External $ref is not allowed in P0: {reference}"));
    };
    resolving.push(reference.to_owned());
    let external = ctx.load_external_value(reference)?;
    let fragment = reference.split_once('#').map(|(_, fragment)| fragment);
    let target = match fragment {
      Some(fragment) if !fragment.is_empty() => {
        resolve_json_pointer_in_value(&external, fragment).ok_or_else(|| format!("Unresolved $ref: {reference}"))?
      }
      _ => &external,
    };
    let bundled = bundle_value(root, target, depth + 1, resolving, bundle)?;
    resolving.pop();
    return Ok(bundled);
  }

  resolving.push(reference.to_owned());

  let target = resolve_json_pointer(root, reference).ok_or_else(|| format!("Unresolved $ref: {reference}"))?;

  let bundled = bundle_value(root, target, depth + 1, resolving, bundle)?;
  resolving.pop();
  Ok(bundled)
}

fn resolve_json_pointer<'a>(root: &'a Value, reference: &str) -> Option<&'a Value> {
  let pointer = reference.strip_prefix("#/")?;
  if pointer.is_empty() {
    return Some(root);
  }

  let mut current = root;
  for segment in pointer.split('/') {
    let key = segment.replace("~1", "/").replace("~0", "~");
    current = match current {
      Value::Object(map) => map.get(&key)?,
      Value::Array(array) => {
        let index: usize = key.parse().ok()?;
        array.get(index)?
      }
      _ => return None,
    };
  }
  Some(current)
}

fn resolve_json_pointer_in_value<'a>(value: &'a Value, pointer: &str) -> Option<&'a Value> {
  resolve_json_pointer(value, &format!("#/{pointer}"))
}

fn sort_value(value: &Value) -> Value {
  match value {
    Value::Object(map) => {
      let sorted: BTreeMap<_, _> = map.iter().map(|(k, v)| (k.clone(), sort_value(v))).collect();
      Value::Object(sorted.into_iter().collect())
    }
    Value::Array(items) => Value::Array(items.iter().map(sort_value).collect()),
    _ => value.clone(),
  }
}

/// Collect every `$ref` string in a document (pre-parse guard).
pub fn collect_refs(value: &Value, out: &mut Vec<String>) {
  match value {
    Value::Object(map) => {
      if let Some(reference) = map.get("$ref").and_then(Value::as_str) {
        out.push(reference.to_owned());
      }
      for child in map.values() {
        collect_refs(child, out);
      }
    }
    Value::Array(items) => {
      for item in items {
        collect_refs(item, out);
      }
    }
    _ => {}
  }
}

/// Fatal guard for remote/external refs before normalization.
pub fn validate_refs(value: &Value) -> Result<(), String> {
  validate_refs_with_bundle(value, None)
}

/// Fatal guard for remote/external refs, allowing local bundle files when provided.
pub fn validate_refs_with_bundle(value: &Value, bundle: Option<&BundleContext>) -> Result<(), String> {
  let mut refs = Vec::new();
  collect_refs(value, &mut refs);

  for reference in refs {
    if is_remote_reference(&reference) {
      return Err(format!("Remote $ref is not allowed: {reference}"));
    }
    if reference.starts_with("#/") {
      continue;
    }
    if let Some(ctx) = bundle {
      ctx.validate_file_reference(&reference)?;
      continue;
    }
    return Err(format!("External $ref is not allowed in P0: {reference}"));
  }

  // Cycle / depth detection happens during bundle.
  bundle_refs(value, bundle)?;
  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  #[test]
  fn hash_bytes_is_sha256_hex() {
    assert_eq!(
      hash_bytes(b"hello"),
      "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    );
  }

  #[test]
  fn rejects_remote_ref() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "paths": {},
      "components": {
        "schemas": {
          "Pet": { "$ref": "https://example.com/pet.json" }
        }
      }
    });

    let err = validate_refs(&spec).expect_err("remote ref");
    assert!(err.contains("Remote $ref"), "unexpected: {err}");
  }

  #[test]
  fn rejects_cyclic_ref() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "paths": {},
      "components": {
        "schemas": {
          "A": { "$ref": "#/components/schemas/B" },
          "B": { "$ref": "#/components/schemas/A" }
        }
      }
    });

    let err = validate_refs(&spec).expect_err("cyclic ref");
    assert!(err.contains("Cyclic $ref"), "unexpected: {err}");
  }

  #[test]
  fn rejects_deep_ref_chain() {
    let mut spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "paths": {},
      "components": { "schemas": {} }
    });

    let schemas = spec["components"]["schemas"].as_object_mut().unwrap();
    let terminal = MAX_REF_DEPTH + 1;
    for index in 0..=terminal {
      let name = format!("S{index}");
      let next = if index == terminal {
        json!({ "type": "string" })
      } else {
        json!({ "$ref": format!("#/components/schemas/S{}", index + 1) })
      };
      schemas.insert(name, next);
    }

    let err = validate_refs(&spec).expect_err("deep ref");
    assert!(
      err.contains("maximum depth") || err.contains("Cyclic"),
      "unexpected: {err}"
    );
  }

  #[test]
  fn canonical_json_sorts_object_keys() {
    let value = json!({ "z": 1, "a": { "y": 2, "b": 3 } });
    let bytes = bundle_and_canonicalize(&value).expect("bundle");
    let text = String::from_utf8(bytes).expect("utf8");
    assert_eq!(text, r#"{"a":{"b":3,"y":2},"z":1}"#);
  }
}
