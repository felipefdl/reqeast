/// Caps on collected filter output. jq programs are user-typed and can produce unbounded
/// streams (`repeat(.)`, `range(1e18)`); without caps the output vector grows until the OS
/// kills the process. Hitting a cap truncates with a marker instead of failing, so
/// exploratory filters over huge arrays stay useful.
pub const MAX_OUTPUT_VALUES: usize = 10_000;
pub const MAX_OUTPUT_BYTES: usize = 8 * 1024 * 1024;

/// Maximum JSON nesting accepted before parsing. Both `read::parse_single` and jaq's `recurse`
/// descend one stack frame per level, and a panicking stack overflow aborts the whole app
/// through the UniFFI boundary. 256 levels is far beyond real-world API payloads.
pub const MAX_JSON_DEPTH: usize = 256;

/// Cheap pre-scan for bracket nesting depth, skipping brackets inside JSON strings.
/// False positives are impossible for valid JSON; invalid JSON is rejected by the parser
/// right after anyway.
pub fn exceeds_depth(input: &str, max: usize) -> bool {
  let mut depth = 0usize;
  let mut in_string = false;
  let mut escaped = false;
  for byte in input.bytes() {
    if in_string {
      if escaped {
        escaped = false;
      } else if byte == b'\\' {
        escaped = true;
      } else if byte == b'"' {
        in_string = false;
      }
      continue;
    }
    match byte {
      b'"' => in_string = true,
      b'[' | b'{' => {
        depth += 1;
        if depth > max {
          return true;
        }
      }
      b']' | b'}' => depth = depth.saturating_sub(1),
      _ => {}
    }
  }
  false
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn flat_json_is_within_depth() {
    assert!(!exceeds_depth(r#"{"a": [1, 2, 3]}"#, 256));
  }

  #[test]
  fn deep_nesting_exceeds_depth() {
    let deep = format!("{}1{}", "[".repeat(300), "]".repeat(300));
    assert!(exceeds_depth(&deep, 256));
  }

  #[test]
  fn brackets_inside_strings_are_ignored() {
    assert!(!exceeds_depth(r#"{"a": "[[[[[[[[[["}"#, 5));
  }

  #[test]
  fn escaped_quote_does_not_end_string() {
    assert!(!exceeds_depth(r#"{"a": "\"[[[[["}"#, 5));
  }

  #[test]
  fn depth_at_limit_passes() {
    let nested = format!("{}1{}", "[".repeat(256), "]".repeat(256));
    assert!(!exceeds_depth(&nested, 256));
  }
}
