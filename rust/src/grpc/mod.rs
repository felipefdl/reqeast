//! gRPC client support (proto compile, reflection, dynamic RPC).

pub(crate) mod client;
pub(crate) mod codec;
pub mod config;
pub(crate) mod dynamic_decode;
pub(crate) mod error;
pub(crate) mod event_loop;
pub mod limits;
mod reflection;
pub mod schema;
pub(crate) mod transport;
mod unary;

pub use client::GrpcClient;
pub use codec::hex_to_wire;
pub use config::{
  CompiledProtoBundle, GrpcConfig, GrpcEvent, GrpcEventHandler, GrpcMethodInfo, GrpcReflectionConfig, GrpcRpcKind,
  GrpcServiceInfo, GrpcUnaryResponse,
};
pub use reflection::fetch_reflection_descriptors;
pub use schema::{compile_proto_bundle, fingerprint_descriptor_bytes, list_grpc_services};
pub use unary::invoke_unary;
