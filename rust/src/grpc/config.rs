use crate::types::KeyValuePair;

#[derive(Debug, Clone, uniffi::Record)]
pub struct CompiledProtoBundle {
  pub descriptor_bytes: Vec<u8>,
  pub content_fingerprint: String,
  pub entry_file: String,
  pub file_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GrpcServiceInfo {
  pub name: String,
  pub methods: Vec<GrpcMethodInfo>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GrpcMethodInfo {
  pub name: String,
  pub rpc_kind: GrpcRpcKind,
  pub input_type: String,
  pub output_type: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GrpcReflectionConfig {
  pub authority: String,
  pub use_tls: bool,
  pub allow_insecure_tls: bool,
  pub timeout_secs: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GrpcUnaryResponse {
  pub status_code: i32,
  pub status_message: String,
  pub response_json: String,
  pub response_hex: String,
  pub truncated: bool,
  pub trailers: Vec<KeyValuePair>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum GrpcRpcKind {
  Unary,
  ServerStreaming,
  ClientStreaming,
  Bidirectional,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum GrpcEvent {
  Connected,
  MetadataReceived {
    headers: Vec<KeyValuePair>,
  },
  MessageReceived {
    json: String,
    hex: String,
    truncated: bool,
  },
  StreamHalfClosed,
  Completed {
    status_code: i32,
    status_message: String,
    trailers: Vec<KeyValuePair>,
  },
  Error {
    error: String,
  },
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GrpcConfig {
  pub authority: String,
  pub use_tls: bool,
  pub allow_insecure_tls: bool,
  pub metadata: Vec<KeyValuePair>,
  pub service: String,
  pub method: String,
  pub rpc_kind: GrpcRpcKind,
  pub deadline_ms: u32,
  pub timeout_secs: u32,
}

#[uniffi::export(callback_interface)]
pub trait GrpcEventHandler: Send + Sync {
  fn on_event(&self, event: GrpcEvent);
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn grpc_config_round_trip_fields() {
    let config = GrpcConfig {
      authority: "localhost:50051".into(),
      use_tls: false,
      allow_insecure_tls: false,
      metadata: vec![],
      service: "helloworld.Greeter".into(),
      method: "SayHello".into(),
      rpc_kind: GrpcRpcKind::Unary,
      deadline_ms: 0,
      timeout_secs: 30,
    };
    assert_eq!(config.method, "SayHello");
  }
}
