//! Parser and import size limits for spec import.

/// Maximum spec file size in bytes (5 MiB).
pub const MAX_SPEC_BYTES: usize = 5 * 1024 * 1024;

/// Maximum YAML nesting depth (`serde_yaml_ng` 0.10.0 deserializer cap).
pub const MAX_YAML_DEPTH: usize = 128;

/// Maximum YAML alias count during deserialization.
pub const MAX_YAML_ALIASES: usize = 128;

/// Maximum YAML node count during deserialization.
pub const MAX_YAML_NODES: usize = 100_000;

/// Maximum `$ref` visit depth (separate from YAML parse depth).
pub const MAX_REF_DEPTH: usize = 256;
