//! Resource limits for gRPC proto import and streaming.

/// Maximum single `.proto` file size in bytes (1 MiB).
pub const MAX_PROTO_FILE_BYTES: usize = 1024 * 1024;

/// Maximum total proto bundle size in bytes (5 MiB). Matches `SpecDocument` CKAsset cap.
pub const MAX_PROTO_BUNDLE_BYTES: usize = 5 * 1024 * 1024;

/// Maximum import/`$ref` chain depth when resolving proto bundles.
pub const MAX_DESCRIPTOR_DEPTH: usize = 128;

/// Maximum messages collected per streaming session; truncate with marker beyond this.
pub const MAX_STREAM_MESSAGES: usize = 10_000;

/// Maximum single gRPC message encode/decode size in bytes (4 MiB). Aligns with tonic default.
pub const MAX_MESSAGE_BYTES: usize = 4 * 1024 * 1024;

/// Maximum JSON output size in bytes (8 MiB). Matches jq output cap pattern.
pub const MAX_JSON_OUTPUT_BYTES: usize = 8 * 1024 * 1024;

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn proto_bundle_cap_matches_spec_document() {
    assert_eq!(MAX_PROTO_BUNDLE_BYTES, 5 * 1024 * 1024);
    assert_eq!(MAX_PROTO_FILE_BYTES, 1024 * 1024);
  }
}
