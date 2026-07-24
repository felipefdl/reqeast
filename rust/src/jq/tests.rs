use super::limits::{MAX_JSON_DEPTH, MAX_OUTPUT_VALUES};
use super::*;

#[test]
fn identity_filter() {
  let result = jq_filter(r#"{"a": 1}"#.into(), ".".into()).unwrap();
  assert_eq!(result, r#"{"a":1}"#);
}

#[test]
fn field_access() {
  let result = jq_filter(r#"{"name": "test", "value": 42}"#.into(), ".name".into()).unwrap();
  assert_eq!(result, r#""test""#);
}

#[test]
fn array_elements() {
  let result = jq_filter(r#"[1, 2, 3]"#.into(), ".[]".into()).unwrap();
  assert_eq!(result, "1\n2\n3");
}

#[test]
fn nested_field() {
  let result = jq_filter(r#"{"a": {"b": "deep"}}"#.into(), ".a.b".into()).unwrap();
  assert_eq!(result, r#""deep""#);
}

#[test]
fn invalid_json_returns_error() {
  let result = jq_filter("not json".into(), ".".into());
  assert!(result.is_err());
}

#[test]
fn invalid_filter_returns_error() {
  let result = jq_filter(r#"{"a": 1}"#.into(), ".[invalid".into());
  assert!(result.is_err());
}

#[test]
fn parse_error_has_readable_message() {
  let result = jq_filter(r#"{"a": 1}"#.into(), ".[invalid".into());
  let err = result.unwrap_err().to_string();
  assert!(
    !err.contains("Span {"),
    "parse error should not leak Span {{..}} debug output: {err}"
  );
  assert!(
    !err.contains("File {"),
    "parse error should not leak File {{..}} debug output: {err}"
  );
}

#[test]
fn type_error_returns_readable_message() {
  let result = jq_filter(r#"{"data": "not an object"}"#.into(), ".data.foo".into());
  let err = result.unwrap_err().to_string();
  assert!(
    err.contains("cannot index") || err.contains("cannot use"),
    "error should be human-readable, got: {err}"
  );
  assert!(
    !err.contains("Str("),
    "error should not contain Rust debug output, got: {err}"
  );
}

#[test]
fn missing_field_returns_null() {
  let result = jq_filter(r#"{"a": 1}"#.into(), ".b".into()).unwrap();
  assert_eq!(result, "null");
}

#[test]
fn fromjson_parses_string_field() {
  let result = jq_filter(r#"{"data": "{\"aaa\": 123}"}"#.into(), ".data | fromjson | .aaa".into()).unwrap();
  assert_eq!(result, "123");
}

#[test]
fn infinite_stream_is_capped_by_value_count() {
  let result = jq_filter("1".into(), "repeat(.)".into()).unwrap();
  let lines: Vec<&str> = result.lines().collect();
  assert_eq!(
    lines.len(),
    MAX_OUTPUT_VALUES + 1,
    "expected cap plus truncation marker"
  );
  assert!(lines.last().unwrap().contains("truncated"));
}

#[test]
fn huge_range_is_capped() {
  let result = jq_filter("null".into(), "range(100000000)".into()).unwrap();
  assert!(result.lines().count() <= MAX_OUTPUT_VALUES + 1);
  assert!(result.contains("truncated"));
}

#[test]
fn large_outputs_are_capped_by_bytes() {
  // Each output is a 100 KB string; the byte cap stops the stream long before the value cap.
  let result = jq_filter("null".into(), r#"range(1000) | ("a" * 100000)"#.into()).unwrap();
  let count = result.lines().count();
  assert!(count < 200, "byte cap should stop after ~84 values, got {count} lines");
  assert!(result.contains("truncated"));
}

#[test]
fn output_under_caps_has_no_marker() {
  let result = jq_filter("null".into(), "range(10)".into()).unwrap();
  assert_eq!(result.lines().count(), 10);
  assert!(!result.contains("truncated"));
}

#[test]
fn deeply_nested_input_is_rejected() {
  let deep = format!(
    "{}1{}",
    "[".repeat(MAX_JSON_DEPTH + 50),
    "]".repeat(MAX_JSON_DEPTH + 50)
  );
  let err = jq_filter(deep, ".".into()).unwrap_err().to_string();
  assert!(err.contains("nesting"), "expected depth rejection, got: {err}");
}

#[test]
fn brackets_inside_strings_do_not_trip_depth_guard() {
  let result = jq_filter(r#"{"a": "]]]]][[[[["}"#.into(), ".a".into()).unwrap();
  assert_eq!(result, r#""]]]]][[[[[""#);
}
