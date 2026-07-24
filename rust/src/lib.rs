mod error;
pub mod grpc;
#[cfg(feature = "spec-openapi")]
pub mod spec_import;
#[cfg(feature = "spec-openapi")]
pub use spec_import::{
  canonical_fingerprint, diff_spec, export_input_from_normalized, export_openapi, export_postman,
  parse_spec, DiffOptions, ExportAuthType, ExportBodyType, ExportEnvironment, ExportFolder,
  ExportFormat, ExportFormDataEntry, ExportHttpRequestData, ExportKeyValue, ExportOpenApiOptions,
  ExportOperation, ExportPostmanOptions, ExportProjectInput, SpecExportError, SpecFieldDelta,
  SpecImportError, SpecImportResult, SpecOperationBinding, SpecSourceHint, SpecSyncDiff,
  SpecSyncField,
};
mod http;
mod jq;
mod sse;
mod tcp;
mod tls;
mod types;
mod udp;
mod util;
mod ws;

pub use error::ReqeastError;
pub use http::{
  HttpCertificateInfo, HttpClient, HttpRedirectEntry, HttpRequestConfig, HttpResponse, HttpSizeInfo,
  HttpTimingBreakdown,
};
pub use jq::jq_filter;
pub use sse::{SseClient, SseConfig, SseEvent, SseEventHandler};
pub use tcp::{TcpClient, TcpConfig, TcpEvent, TcpEventHandler};
pub use types::{HttpBody, HttpMethod, KeyValuePair};
pub use udp::{UdpClient, UdpConfig, UdpEvent, UdpEventHandler};
pub use ws::{WsClient, WsConfig, WsEvent, WsEventHandler};
pub use grpc::{
  compile_proto_bundle, fetch_reflection_descriptors, fingerprint_descriptor_bytes, hex_to_wire,
  invoke_unary, list_grpc_services, CompiledProtoBundle, GrpcClient, GrpcConfig, GrpcEvent,
  GrpcEventHandler, GrpcMethodInfo, GrpcReflectionConfig, GrpcRpcKind, GrpcServiceInfo,
  GrpcUnaryResponse,
};

use tracing_subscriber::{EnvFilter, fmt, prelude::*};

#[uniffi::export]
pub fn init_logging() {
  tracing_subscriber::registry()
    .with(fmt::layer().with_ansi(false))
    .with(
      EnvFilter::from_default_env().add_directive("reqeast_core=debug".parse().expect("static directive must parse")),
    )
    .try_init()
    .ok();
}

uniffi::setup_scaffolding!();