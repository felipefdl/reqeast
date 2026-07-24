//! OpenAPI ingress sanitization for real-world specs that violate Reference Object rules.

use serde_json::{Map, Value};

const REF_ALLOWED_SIBLINGS: &[&str] = &["$ref", "summary", "description"];

const STRUCTURAL_SCHEMA_KEYS: &[&str] = &[
  "type",
  "$ref",
  "allOf",
  "oneOf",
  "anyOf",
  "not",
  "properties",
  "items",
  "prefixItems",
  "additionalProperties",
  "patternProperties",
  "const",
  "enum",
  "required",
];

const COMPOSITION_KEYS: &[&str] = &["allOf", "oneOf", "anyOf"];

/// Sanitize a parsed OpenAPI JSON value so strict Reference Object parsing succeeds.
///
/// Some published specs attach JSON Schema keywords (for example `required`) as
/// siblings of `$ref` inside `allOf` arrays. OpenAPI only permits `summary` and
/// `description` beside `$ref`. When the parent is an array, illegal siblings are
/// peeled into a following inline schema object so composition semantics are preserved.
pub fn sanitize_openapi_value(value: &mut Value) {
  sanitize_value(value);
  normalize_openapi_compat(value);
}

/// Additional JSON Schema 2020-12 keywords that must be downgraded before `roas` v3.0 parsing.
pub fn sanitize_openapi_value_for_v30(value: &mut Value) {
  normalize_openapi_compat(value);
  normalize_exclusive_bounds_tree(value);
}

fn sanitize_value(value: &mut Value) {
  match value {
    Value::Array(items) => {
      let mut index = 0;
      while index < items.len() {
        if let Some(extra) = peel_ref_siblings(&mut items[index]) {
          items.insert(index + 1, extra);
          index += 2;
        } else {
          index += 1;
        }
      }
      for item in items.iter_mut() {
        sanitize_value(item);
      }
    }
    Value::Object(_) => {
      let _ = peel_ref_siblings(value);
      if let Value::Object(map) = value {
        let keys: Vec<String> = map.keys().cloned().collect();
        for key in keys {
          if let Some(child) = map.get_mut(&key) {
            sanitize_value(child);
          }
        }
      }
    }
    _ => {}
  }
}

fn normalize_openapi_compat(value: &mut Value) {
  match value {
    Value::Object(map) => {
      normalize_type_array(map);
      normalize_number_integer_format(map);
      hoist_composition_metadata_fragments(map);
      for child in map.values_mut() {
        normalize_openapi_compat(child);
      }
    }
    Value::Array(items) => {
      for item in items.iter_mut() {
        normalize_openapi_compat(item);
      }
    }
    _ => {}
  }
}

fn normalize_type_array(map: &mut Map<String, Value>) {
  let Value::Array(types) = map.get("type").cloned().unwrap_or(Value::Null) else {
    return;
  };

  let has_null = types.iter().any(|value| value.as_str() == Some("null"));
  let primary: Vec<Value> = types
    .into_iter()
    .filter(|value| value.as_str() != Some("null"))
    .collect();

  match primary.len() {
    0 if has_null => {
      map.insert("type".into(), Value::String("null".into()));
    }
    1 => {
      map.insert("type".into(), primary[0].clone());
      if has_null {
        map.insert("nullable".into(), Value::Bool(true));
      }
    }
    _ if !primary.is_empty() => {
      map.insert("type".into(), primary[0].clone());
      if has_null {
        map.insert("nullable".into(), Value::Bool(true));
      }
    }
    _ => {}
  }
}

fn normalize_number_integer_format(map: &mut Map<String, Value>) {
  if map.get("type").and_then(Value::as_str) != Some("number") {
    return;
  }

  let Some(format) = map.get("format").and_then(Value::as_str) else {
    return;
  };

  if matches!(format, "int32" | "int64") {
    map.insert("type".into(), Value::String("integer".into()));
  }
}

fn normalize_exclusive_bounds_tree(value: &mut Value) {
  match value {
    Value::Object(map) => {
      normalize_exclusive_bounds(map);
      for child in map.values_mut() {
        normalize_exclusive_bounds_tree(child);
      }
    }
    Value::Array(items) => {
      for item in items.iter_mut() {
        normalize_exclusive_bounds_tree(item);
      }
    }
    _ => {}
  }
}

fn normalize_exclusive_bounds(map: &mut Map<String, Value>) {
  if let Some(bound) = map.remove("exclusiveMinimum").filter(Value::is_number) {
    map.entry("minimum".to_owned()).or_insert(bound);
    map.insert("exclusiveMinimum".to_owned(), Value::Bool(true));
  }

  if let Some(bound) = map.remove("exclusiveMaximum").filter(Value::is_number) {
    map.entry("maximum".to_owned()).or_insert(bound);
    map.insert("exclusiveMaximum".to_owned(), Value::Bool(true));
  }
}

fn hoist_composition_metadata_fragments(map: &mut Map<String, Value>) {
  for key in COMPOSITION_KEYS {
    let Some(Value::Array(items)) = map.get_mut(*key) else {
      continue;
    };

    let mut hoisted = Map::new();
    items.retain_mut(|item| {
      let Value::Object(item_map) = item else {
        return true;
      };
      if !is_metadata_fragment(item_map) {
        return true;
      }

      let keys: Vec<String> = item_map.keys().cloned().collect();
      for hoist_key in keys {
        if let Some(hoist_value) = item_map.remove(&hoist_key) {
          hoisted.entry(hoist_key).or_insert(hoist_value);
        }
      }
      false
    });

    for (hoist_key, hoist_value) in hoisted {
      map.entry(hoist_key).or_insert(hoist_value);
    }
  }
}

fn is_metadata_fragment(map: &Map<String, Value>) -> bool {
  if map.is_empty() || has_structural_schema_keys(map) {
    return false;
  }

  match map.get("default") {
    None => true,
    Some(Value::Object(_)) => true,
    Some(_) => true,
  }
}

fn has_structural_schema_keys(map: &Map<String, Value>) -> bool {
  STRUCTURAL_SCHEMA_KEYS.iter().any(|key| map.contains_key(*key))
}

fn peel_ref_siblings(value: &mut Value) -> Option<Value> {
  let Value::Object(map) = value else {
    return None;
  };
  if !map.contains_key("$ref") {
    return None;
  }

  let extra_keys: Vec<String> = map
    .keys()
    .filter(|key| !REF_ALLOWED_SIBLINGS.contains(&key.as_str()))
    .cloned()
    .collect();
  if extra_keys.is_empty() {
    return None;
  }

  let mut extra = Map::new();
  for key in extra_keys {
    if let Some(peeled) = map.remove(&key) {
      extra.insert(key, peeled);
    }
  }
  Some(Value::Object(extra))
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn splits_ref_siblings_inside_all_of() {
    let mut value = serde_json::json!({
        "allOf": [
            { "$ref": "#/components/schemas/ProductLinks" },
            {
                "$ref": "#/components/schemas/ProductCancelLink",
                "required": ["cancel"]
            }
        ]
    });

    sanitize_openapi_value(&mut value);

    assert_eq!(
      value,
      serde_json::json!({
          "allOf": [
              { "$ref": "#/components/schemas/ProductLinks" },
              { "$ref": "#/components/schemas/ProductCancelLink" },
              { "required": ["cancel"] }
          ]
      })
    );
  }

  #[test]
  fn strips_ref_siblings_outside_arrays() {
    let mut value = serde_json::json!({
        "schema": {
            "$ref": "#/components/schemas/Pet",
            "required": ["id"]
        }
    });

    sanitize_openapi_value(&mut value);

    assert_eq!(
      value,
      serde_json::json!({
          "schema": { "$ref": "#/components/schemas/Pet" }
      })
    );
  }

  #[test]
  fn normalizes_nullable_type_arrays() {
    let mut value = serde_json::json!({
        "type": ["string", "null"]
    });

    sanitize_openapi_value(&mut value);

    assert_eq!(
      value,
      serde_json::json!({
          "type": "string",
          "nullable": true
      })
    );
  }

  #[test]
  fn normalizes_number_int32_to_integer() {
    let mut value = serde_json::json!({
        "type": "number",
        "format": "int32"
    });

    sanitize_openapi_value(&mut value);

    assert_eq!(
      value,
      serde_json::json!({
          "type": "integer",
          "format": "int32"
      })
    );
  }

  #[test]
  fn normalizes_numeric_exclusive_minimum_for_v30() {
    let mut value = serde_json::json!({
        "type": "integer",
        "exclusiveMinimum": 0
    });

    sanitize_openapi_value_for_v30(&mut value);

    assert_eq!(
      value,
      serde_json::json!({
          "type": "integer",
          "minimum": 0,
          "exclusiveMinimum": true
      })
    );
  }

  #[test]
  fn hoists_scalar_default_from_all_of() {
    let mut value = serde_json::json!({
        "allOf": [
            { "$ref": "#/components/schemas/SubscriptionLifecycleStatus" },
            { "default": "active", "description": "Lifecycle statuses available to subscriptions" }
        ]
    });

    sanitize_openapi_value(&mut value);

    assert_eq!(
      value,
      serde_json::json!({
          "allOf": [
              { "$ref": "#/components/schemas/SubscriptionLifecycleStatus" }
          ],
          "default": "active",
          "description": "Lifecycle statuses available to subscriptions"
      })
    );
  }
}