//! Spec ingress: format sniffing and safe JSON/YAML parsing.

use crate::error::ReqeastError;
use crate::spec_import::limits::{
  MAX_SPEC_BYTES, MAX_YAML_ALIASES, MAX_YAML_DEPTH, MAX_YAML_NODES,
};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SniffResult {
  Json,
  Yaml,
  Unknown,
}

/// Parses raw spec bytes into a JSON value after size checks and format sniffing.
pub fn parse_ingress(bytes: &[u8]) -> Result<Value, ReqeastError> {
  if bytes.len() > MAX_SPEC_BYTES {
    return Err(ReqeastError::InvalidConfig(format!(
      "Spec exceeds maximum size of {MAX_SPEC_BYTES} bytes"
    )));
  }

  match sniff_format(bytes) {
    SniffResult::Json => parse_json(bytes),
    SniffResult::Yaml => parse_yaml(bytes),
    SniffResult::Unknown => parse_json(bytes).or_else(|_| parse_yaml(bytes)),
  }
}

fn sniff_format(bytes: &[u8]) -> SniffResult {
  let trimmed = trim_leading(bytes);
  if trimmed.starts_with(b"---") || trimmed.starts_with(b"%YAML") {
    SniffResult::Yaml
  } else if trimmed.starts_with(b"{") || trimmed.starts_with(b"[") {
    SniffResult::Json
  } else {
    SniffResult::Unknown
  }
}

fn trim_leading(bytes: &[u8]) -> &[u8] {
  let mut start = 0;
  if bytes.len() >= 3 && bytes[0..3] == [0xEF, 0xBB, 0xBF] {
    start = 3;
  }
  while start < bytes.len() && bytes[start].is_ascii_whitespace() {
    start += 1;
  }
  &bytes[start..]
}

fn parse_json(bytes: &[u8]) -> Result<Value, ReqeastError> {
  serde_json::from_slice(bytes).map_err(|e| ReqeastError::InvalidConfig(format!("Invalid JSON: {e}")))
}

fn parse_yaml(bytes: &[u8]) -> Result<Value, ReqeastError> {
  const _: () = assert!(MAX_YAML_DEPTH == 128);

  let text = std::str::from_utf8(bytes)
    .map_err(|e| ReqeastError::InvalidConfig(format!("Invalid UTF-8 in YAML spec: {e}")))?;

  if count_yaml_anchor_definitions(text) > MAX_YAML_ALIASES {
    return Err(ReqeastError::InvalidConfig(format!(
      "YAML exceeds maximum alias count of {MAX_YAML_ALIASES}"
    )));
  }

  let yaml_value: serde_yaml_ng::Value = serde_yaml_ng::from_slice(bytes)
    .map_err(|e| ReqeastError::InvalidConfig(format!("Invalid YAML: {e}")))?;

  if count_value_nodes(&yaml_value) > MAX_YAML_NODES {
    return Err(ReqeastError::InvalidConfig(format!(
      "YAML exceeds maximum node count of {MAX_YAML_NODES}"
    )));
  }

  serde_json::to_value(&yaml_value)
    .map_err(|e| ReqeastError::InvalidConfig(format!("YAML to JSON conversion failed: {e}")))
}

fn count_yaml_anchor_definitions(input: &str) -> usize {
  let bytes = input.as_bytes();
  let mut count = 0;
  let mut index = 0;

  while index < bytes.len() {
    if bytes[index] == b'&' && is_anchor_boundary_before(bytes.get(index.wrapping_sub(1))) {
      let mut end = index + 1;
      while end < bytes.len() && is_anchor_char(bytes[end]) {
        end += 1;
      }
      if end > index + 1 {
        count += 1;
        index = end;
        continue;
      }
    }
    index += 1;
  }

  count
}

fn is_anchor_boundary_before(previous: Option<&u8>) -> bool {
  match previous {
    None => true,
    Some(byte) => matches!(
      *byte,
      b' ' | b'\t' | b'\n' | b'\r' | b',' | b'[' | b'{' | b':' | b'-' | b'>' | b'|'
    ),
  }
}

fn is_anchor_char(byte: u8) -> bool {
  byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-'
}

fn count_value_nodes(value: &serde_yaml_ng::Value) -> usize {
  match value {
    serde_yaml_ng::Value::Null
    | serde_yaml_ng::Value::Bool(_)
    | serde_yaml_ng::Value::Number(_)
    | serde_yaml_ng::Value::String(_) => 1,
    serde_yaml_ng::Value::Sequence(sequence) => {
      1 + sequence.iter().map(count_value_nodes).sum::<usize>()
    }
    serde_yaml_ng::Value::Mapping(mapping) => {
      1 + mapping.values().map(count_value_nodes).sum::<usize>()
    }
    serde_yaml_ng::Value::Tagged(tagged) => count_value_nodes(&tagged.value),
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::spec_import::limits::MAX_SPEC_BYTES;

  #[test]
  fn sniff_json_object() {
    let value = parse_ingress(br#"{"openapi":"3.0.0","info":{"title":"Test"}}"#).expect("json parse");
    assert_eq!(value["openapi"], "3.0.0");
    assert_eq!(value["info"]["title"], "Test");
  }

  #[test]
  fn sniff_json_array() {
    let value = parse_ingress(b"[1,2,3]").expect("json array parse");
    assert_eq!(value, serde_json::json!([1, 2, 3]));
  }

  #[test]
  fn sniff_yaml_document_marker() {
    let yaml = b"---\nopenapi: 3.0.0\ninfo:\n  title: Test\n";
    let value = parse_ingress(yaml).expect("yaml parse");
    assert_eq!(value["openapi"], "3.0.0");
    assert_eq!(value["info"]["title"], "Test");
  }

  #[test]
  fn sniff_yaml_percent_header() {
    let yaml = b"%YAML 1.1\n---\nkey: value\n";
    let value = parse_ingress(yaml).expect("yaml percent header parse");
    assert_eq!(value["key"], "value");
  }

  #[test]
  fn rejects_spec_over_max_bytes() {
    let oversized = vec![b' '; MAX_SPEC_BYTES + 1];
    let err = parse_ingress(&oversized).expect_err("oversized spec should fail");
    let message = err.to_string();
    assert!(message.contains("maximum size"), "unexpected error: {message}");
  }

  #[test]
  fn billion_laughs_fails_safely() {
    let yaml = b"a: &a ~\n\
b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a]\n\
c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b]\n\
d: &d [*c,*c,*c,*c,*c,*c,*c,*c,*c]\n\
e: &e [*d,*d,*d,*d,*d,*d,*d,*d,*d]\n\
f: &f [*e,*e,*e,*e,*e,*e,*e,*e,*e]\n\
g: &g [*f,*f,*f,*f,*f,*f,*f,*f,*f]\n\
h: &h [*g,*g,*g,*g,*g,*g,*g,*g,*g]\n\
i: &i [*h,*h,*h,*h,*h,*h,*h,*h,*h]\n";

    let err = parse_ingress(yaml).expect_err("billion laughs should fail");
    let message = err.to_string().to_ascii_lowercase();
    assert!(
      message.contains("repetition limit") || message.contains("invalid yaml"),
      "unexpected error: {message}"
    );
  }

  #[test]
  fn unknown_format_tries_json_then_yaml() {
    let yaml = b"openapi: 3.0.0\ninfo:\n  title: Fallback\n";
    let value = parse_ingress(yaml).expect("unknown format should fall back to yaml");
    assert_eq!(value["info"]["title"], "Fallback");
  }
}