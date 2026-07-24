//! Proto bundle compilation (protox) and descriptor introspection.

use std::collections::{HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use include_dir::{include_dir, Dir, DirEntry};
use prost::Message;
use prost_reflect::{DescriptorPool, MethodDescriptor};
use prost_types::FileDescriptorSet;
use sha2::{Digest, Sha256};

use crate::error::ReqeastError;
use crate::grpc::config::{CompiledProtoBundle, GrpcMethodInfo, GrpcRpcKind, GrpcServiceInfo};
use crate::grpc::limits::{MAX_DESCRIPTOR_DEPTH, MAX_PROTO_BUNDLE_BYTES, MAX_PROTO_FILE_BYTES};

static EMBEDDED_WELL_KNOWN: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/assets/protobuf");
/// Compiles user `.proto` entry files into a `FileDescriptorSet` with well-known imports.
#[uniffi::export]
pub fn compile_proto_bundle(
  root_path: String,
  entry_files: Vec<String>,
) -> Result<CompiledProtoBundle, ReqeastError> {
  if entry_files.is_empty() {
    return Err(ReqeastError::InvalidConfig("At least one entry .proto file is required".into()));
  }

  let root = PathBuf::from(&root_path);
  if !root.is_dir() {
    return Err(ReqeastError::InvalidConfig(format!("Proto root path not found: {root_path}")));
  }

  let user_files = collect_user_proto_files(&root, &entry_files)?;
  let file_count = u32::try_from(user_files.len())
    .map_err(|_| ReqeastError::InvalidConfig("Too many .proto files in bundle".into()))?;

  let well_known = well_known_include_path()?;
  let descriptor_set =
    protox::compile(&entry_files, [&root, well_known]).map_err(map_protox_error)?;

  let descriptor_bytes = descriptor_set.encode_to_vec();
  let content_fingerprint = fingerprint_descriptor_set(&descriptor_set);

  Ok(CompiledProtoBundle {
    descriptor_bytes,
    content_fingerprint,
    entry_file: entry_files[0].clone(),
    file_count,
  })
}

/// SHA-256 hex fingerprint of canonical `FileDescriptorSet` bytes (sorted files).
#[uniffi::export]
pub fn fingerprint_descriptor_bytes(descriptor_bytes: Vec<u8>) -> Result<String, ReqeastError> {
  let set = FileDescriptorSet::decode(descriptor_bytes.as_slice())
    .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid descriptor bytes: {err}")))?;
  Ok(fingerprint_descriptor_set(&set))
}

/// Lists gRPC services and methods from encoded `FileDescriptorSet` bytes.
#[uniffi::export]
pub fn list_grpc_services(descriptor_bytes: Vec<u8>) -> Result<Vec<GrpcServiceInfo>, ReqeastError> {
  let pool = decode_descriptor_pool(&descriptor_bytes)?;
  let mut services: Vec<GrpcServiceInfo> = pool
    .services()
    .map(|service| GrpcServiceInfo {
      name: service.full_name().to_owned(),
      methods: service
        .methods()
        .map(|method| GrpcMethodInfo {
          name: method.name().to_owned(),
          rpc_kind: rpc_kind_from_method(&method),
          input_type: method.input().full_name().to_owned(),
          output_type: method.output().full_name().to_owned(),
        })
        .collect(),
    })
    .collect();
  services.sort_by(|left, right| left.name.cmp(&right.name));
  Ok(services)
}

/// Decodes serialized `FileDescriptorSet` bytes into a `DescriptorPool`.
pub(crate) fn descriptor_pool_from_bytes(descriptor_bytes: &[u8]) -> Result<DescriptorPool, ReqeastError> {
  decode_descriptor_pool(descriptor_bytes)
}

/// Resolves a service method and derives its RPC kind from descriptor flags.
pub(crate) fn resolve_method(
  pool: &DescriptorPool,
  service: &str,
  method: &str,
) -> Result<(MethodDescriptor, GrpcRpcKind), ReqeastError> {
  let service_desc = pool
    .get_service_by_name(service)
    .ok_or_else(|| ReqeastError::InvalidConfig(format!("Unknown gRPC service: {service}")))?;

  let method_desc = service_desc
    .methods()
    .find(|candidate| candidate.name() == method)
    .ok_or_else(|| ReqeastError::InvalidConfig(format!("Unknown gRPC method: {service}/{method}")))?;

  let kind = rpc_kind_from_method(&method_desc);
  Ok((method_desc, kind))
}

fn well_known_include_path() -> Result<&'static Path, ReqeastError> {
  static INIT: OnceLock<Result<PathBuf, String>> = OnceLock::new();
  let path = INIT.get_or_init(|| {
    let target = std::env::temp_dir().join("reqeast-grpc-well-known");
    extract_embedded_dir(&EMBEDDED_WELL_KNOWN, &target)
      .map(|_| target)
      .map_err(|err| err.to_string())
  });
  match path {
    Ok(value) => Ok(value.as_path()),
    Err(err) => Err(ReqeastError::InternalError(format!("Failed to extract well-known protos: {err}"))),
  }
}

fn extract_embedded_dir(dir: &Dir<'_>, target: &Path) -> std::io::Result<()> {
  for entry in dir.entries() {
    match entry {
      DirEntry::Dir(child) => {
        let child_path = target.join(child.path());
        fs::create_dir_all(&child_path)?;
        extract_embedded_dir(child, &child_path)?;
      }
      DirEntry::File(file) => {
        let file_path = target.join(file.path());
        if let Some(parent) = file_path.parent() {
          fs::create_dir_all(parent)?;
        }
        fs::write(file_path, file.contents())?;
      }
    }
  }
  Ok(())
}

fn collect_user_proto_files(root: &Path, entry_files: &[String]) -> Result<HashSet<PathBuf>, ReqeastError> {
  let mut seen = HashSet::new();
  let mut queue = VecDeque::new();
  let mut total_bytes = 0usize;

  for entry in entry_files {
    let path = root.join(entry);
    if !path.is_file() {
      return Err(ReqeastError::InvalidConfig(format!("Entry .proto file not found: {entry}")));
    }
    enqueue_user_proto(root, &path, 0, &mut seen, &mut queue, &mut total_bytes)?;
  }

  while let Some((path, depth)) = queue.pop_front() {
    let content = fs::read_to_string(&path)
      .map_err(|err| ReqeastError::InvalidConfig(format!("Failed to read {}: {err}", path.display())))?;

    for import in parse_imports(&content) {
      if is_well_known_import(&import) {
        continue;
      }
      let resolved = resolve_user_import(root, &path, &import)?;
      enqueue_user_proto(root, &resolved, depth + 1, &mut seen, &mut queue, &mut total_bytes)?;
    }
  }

  Ok(seen)
}

fn enqueue_user_proto(
  root: &Path,
  path: &Path,
  depth: usize,
  seen: &mut HashSet<PathBuf>,
  queue: &mut VecDeque<(PathBuf, usize)>,
  total_bytes: &mut usize,
) -> Result<(), ReqeastError> {
  if depth > MAX_DESCRIPTOR_DEPTH {
    return Err(ReqeastError::InvalidConfig(format!(
      "Proto import depth exceeds maximum of {MAX_DESCRIPTOR_DEPTH}"
    )));
  }

  let canonical = path
    .canonicalize()
    .map_err(|err| ReqeastError::InvalidConfig(format!("Failed to resolve {}: {err}", path.display())))?;
  if !canonical.starts_with(root.canonicalize().unwrap_or_else(|_| root.to_path_buf())) {
    return Err(ReqeastError::InvalidConfig(format!(
      "Proto file escapes bundle root: {}",
      canonical.display()
    )));
  }

  if !seen.insert(canonical.clone()) {
    return Ok(());
  }

  let metadata = fs::metadata(&canonical)
    .map_err(|err| ReqeastError::InvalidConfig(format!("Failed to stat {}: {err}", canonical.display())))?;
  let size = metadata.len() as usize;
  if size > MAX_PROTO_FILE_BYTES {
    return Err(ReqeastError::InvalidConfig(format!(
      "Proto file exceeds {MAX_PROTO_FILE_BYTES} byte limit: {}",
      canonical.display()
    )));
  }

  *total_bytes += size;
  if *total_bytes > MAX_PROTO_BUNDLE_BYTES {
    return Err(ReqeastError::InvalidConfig(format!(
      "Proto bundle exceeds {MAX_PROTO_BUNDLE_BYTES} byte total limit"
    )));
  }

  queue.push_back((canonical, depth));
  Ok(())
}

fn parse_imports(content: &str) -> Vec<String> {
  let mut imports = Vec::new();
  for line in content.lines() {
    let line = line.split("//").next().unwrap_or(line).trim();
    let Some(rest) = line.strip_prefix("import ") else {
      continue;
    };
    if let Some(path) = rest.strip_prefix('"').and_then(|value| value.strip_suffix('"')) {
      imports.push(path.to_owned());
    } else if let Some(path) = rest.strip_prefix('\'').and_then(|value| value.strip_suffix('\'')) {
      imports.push(path.to_owned());
    }
  }
  imports
}

fn is_well_known_import(import: &str) -> bool {
  import.starts_with("google/protobuf/")
}

fn resolve_user_import(root: &Path, from: &Path, import: &str) -> Result<PathBuf, ReqeastError> {
  let candidates = [
    root.join(import),
    from.parent().map(|parent| parent.join(import)).unwrap_or_else(|| root.join(import)),
  ];

  for candidate in candidates {
    if candidate.is_file() {
      return Ok(candidate);
    }
  }

  Err(ReqeastError::InvalidConfig(format!(
    "Unresolved proto import '{import}' from {}",
    from.display()
  )))
}

fn decode_descriptor_pool(descriptor_bytes: &[u8]) -> Result<DescriptorPool, ReqeastError> {
  let set = FileDescriptorSet::decode(descriptor_bytes)
    .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid descriptor bytes: {err}")))?;
  DescriptorPool::from_file_descriptor_set(set)
    .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid descriptor pool: {err}")))
}

fn fingerprint_descriptor_set(set: &FileDescriptorSet) -> String {
  let mut canonical = set.clone();
  canonical.file.sort_by(|left, right| left.name.cmp(&right.name));
  hash_bytes(&canonical.encode_to_vec())
}

fn hash_bytes(bytes: &[u8]) -> String {
  let digest = Sha256::digest(bytes);
  digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn rpc_kind_from_method(method: &MethodDescriptor) -> GrpcRpcKind {
  match (method.is_client_streaming(), method.is_server_streaming()) {
    (false, false) => GrpcRpcKind::Unary,
    (false, true) => GrpcRpcKind::ServerStreaming,
    (true, false) => GrpcRpcKind::ClientStreaming,
    (true, true) => GrpcRpcKind::Bidirectional,
  }
}

fn map_protox_error(err: protox::Error) -> ReqeastError {
  ReqeastError::InvalidConfig(err.to_string())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn compile_single_proto_with_well_known_import() {
    let root = env!("CARGO_MANIFEST_DIR");
    let bundle = compile_proto_bundle(format!("{root}/tests/fixtures/grpc"), vec!["hello.proto".into()])
      .expect("compile");
    assert!(!bundle.descriptor_bytes.is_empty());
    assert!(!bundle.content_fingerprint.is_empty());
    let services = list_grpc_services(bundle.descriptor_bytes).expect("list");
    assert!(!services.is_empty());
    assert_eq!(services[0].name, "helloworld.Greeter");
    assert_eq!(services[0].methods[0].name, "SayHello");
    assert_eq!(services[0].methods[0].rpc_kind, GrpcRpcKind::Unary);
  }

  #[test]
  fn resolve_method_finds_say_hello() {
    let root = env!("CARGO_MANIFEST_DIR");
    let bundle = compile_proto_bundle(format!("{root}/tests/fixtures/grpc"), vec!["hello.proto".into()])
      .expect("compile");
    let pool = decode_descriptor_pool(&bundle.descriptor_bytes).expect("pool");
    let (method, kind) = resolve_method(&pool, "helloworld.Greeter", "SayHello").expect("resolve");
    assert_eq!(method.name(), "SayHello");
    assert_eq!(kind, GrpcRpcKind::Unary);
  }
}