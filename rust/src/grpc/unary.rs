//! Synchronous unary gRPC invoke (`block_on` on the UniFFI caller thread).

use std::time::Duration;

use prost_reflect::DynamicMessage;
use tonic::client::Grpc;
use tonic::codegen::http::uri::PathAndQuery;
use tonic::metadata::{Ascii, KeyAndValueRef, MetadataKey, MetadataMap, MetadataValue};
use tonic::{Code, Request, Response, Status};
use tonic_prost::ProstCodec;

use crate::error::ReqeastError;
use crate::grpc::client::grpc_runtime;
use crate::grpc::codec::{hex_to_wire_str, json_to_wire, message_to_json_and_hex};
use crate::grpc::config::{GrpcConfig, GrpcRpcKind, GrpcUnaryResponse};
use crate::grpc::dynamic_decode::{DynamicDecode, with_response_descriptor_async};
use crate::grpc::error::map_transport_error;
use crate::grpc::limits::MAX_MESSAGE_BYTES;
use crate::grpc::schema::{descriptor_pool_from_bytes, resolve_method};
use crate::grpc::transport::build_endpoint;
use crate::types::KeyValuePair;

/// Invoke a unary gRPC RPC synchronously on the caller thread.
#[uniffi::export]
pub fn invoke_unary(
  config: GrpcConfig,
  descriptor_bytes: Vec<u8>,
  request_body: String,
  body_is_hex: bool,
) -> Result<GrpcUnaryResponse, ReqeastError> {
  grpc_runtime()?.block_on(invoke_unary_async(config, descriptor_bytes, request_body, body_is_hex))
}

async fn invoke_unary_async(
  config: GrpcConfig,
  descriptor_bytes: Vec<u8>,
  request_body: String,
  body_is_hex: bool,
) -> Result<GrpcUnaryResponse, ReqeastError> {
  let pool = descriptor_pool_from_bytes(&descriptor_bytes)?;
  let (method, rpc_kind) = resolve_method(&pool, &config.service, &config.method)?;
  if rpc_kind != GrpcRpcKind::Unary {
    return Err(ReqeastError::InvalidConfig(format!(
      "Method {}/{} is {rpc_kind:?}, expected unary",
      config.service, config.method
    )));
  }

  let request_wire = if body_is_hex {
    hex_to_wire_str(&request_body)?
  } else {
    json_to_wire(&request_body, &pool, method.input().full_name())?
  };
  let request_message = DynamicMessage::decode(method.input(), request_wire.as_slice())
    .map_err(|err| ReqeastError::InvalidConfig(format!("Failed to encode request message: {err}")))?;

  let endpoint = build_endpoint(
    &config.authority,
    config.use_tls,
    config.allow_insecure_tls,
    config.timeout_secs,
  )?;
  let channel = endpoint.connect().await.map_err(map_transport_error)?;
  let path = grpc_path(&config.service, &config.method)?;
  let mut request = Request::new(request_message);
  if config.deadline_ms > 0 {
    request.set_timeout(Duration::from_millis(config.deadline_ms.into()));
  }
  apply_request_metadata(&mut request, &config.metadata)?;

  let mut client = Grpc::with_origin(channel, endpoint.uri().clone()).max_decoding_message_size(MAX_MESSAGE_BYTES);
  let codec = ProstCodec::<DynamicMessage, DynamicDecode>::default();
  let output_descriptor = method.output().clone();

  client.ready().await.map_err(map_transport_error)?;

  match with_response_descriptor_async(output_descriptor, async { client.unary(request, path, codec).await }).await {
    Ok(response) => Ok(success_response(response)),
    Err(status) => Ok(error_response(status)),
  }
}

pub(crate) fn grpc_path(service: &str, method: &str) -> Result<PathAndQuery, ReqeastError> {
  format!("/{service}/{method}")
    .parse()
    .map_err(|err| ReqeastError::InvalidConfig(format!("invalid gRPC path: {err}")))
}

pub(crate) fn apply_request_metadata<T>(
  request: &mut Request<T>,
  metadata: &[KeyValuePair],
) -> Result<(), ReqeastError> {
  for pair in metadata {
    if pair.key.is_empty() {
      continue;
    }
    let key = pair
      .key
      .parse::<MetadataKey<Ascii>>()
      .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid metadata key '{}': {err}", pair.key)))?;
    let value = pair
      .value
      .parse::<MetadataValue<Ascii>>()
      .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid metadata value for '{}': {err}", pair.key)))?;
    request.metadata_mut().insert(key, value);
  }
  Ok(())
}

fn success_response(response: Response<DynamicDecode>) -> GrpcUnaryResponse {
  let trailers = metadata_to_pairs(response.metadata());
  let message = response.into_inner().into_inner();
  let (response_json, response_hex, truncated) = message_to_json_and_hex(&message);
  GrpcUnaryResponse {
    status_code: Code::Ok as i32,
    status_message: String::new(),
    response_json,
    response_hex,
    truncated,
    trailers,
  }
}

fn error_response(status: Status) -> GrpcUnaryResponse {
  GrpcUnaryResponse {
    status_code: status.code() as i32,
    status_message: status.message().to_owned(),
    response_json: String::new(),
    response_hex: String::new(),
    truncated: false,
    trailers: metadata_to_pairs(status.metadata()),
  }
}

pub(crate) fn metadata_to_pairs(metadata: &MetadataMap) -> Vec<KeyValuePair> {
  metadata
    .iter()
    .filter_map(|entry| match entry {
      KeyAndValueRef::Ascii(key, value) => Some(KeyValuePair {
        key: key.as_str().to_owned(),
        value: value.to_str().ok()?.to_owned(),
        enabled: true,
      }),
      KeyAndValueRef::Binary(..) => None,
    })
    .collect()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::grpc::dynamic_decode::with_response_descriptor;
  use crate::grpc::schema::compile_proto_bundle;
  use prost::Message;

  fn hello_fixture() -> (Vec<u8>, GrpcConfig) {
    let root = env!("CARGO_MANIFEST_DIR");
    let bundle =
      compile_proto_bundle(format!("{root}/tests/fixtures/grpc"), vec!["hello.proto".into()]).expect("compile");
    let config = GrpcConfig {
      authority: "localhost:50051".into(),
      use_tls: false,
      allow_insecure_tls: false,
      metadata: vec![KeyValuePair {
        key: "x-test".into(),
        value: "1".into(),
        enabled: true,
      }],
      service: "helloworld.Greeter".into(),
      method: "SayHello".into(),
      rpc_kind: GrpcRpcKind::Unary,
      deadline_ms: 0,
      timeout_secs: 30,
    };
    (bundle.descriptor_bytes, config)
  }

  #[test]
  fn unary_wiring_resolves_method_and_encodes_request() {
    let (descriptor_bytes, config) = hello_fixture();
    let pool = descriptor_pool_from_bytes(&descriptor_bytes).expect("pool");
    let (method, kind) = resolve_method(&pool, &config.service, &config.method).expect("resolve");
    assert_eq!(kind, GrpcRpcKind::Unary);

    let wire = json_to_wire(r#"{"name":"Reqeast"}"#, &pool, &method.input().full_name()).unwrap();
    let message = DynamicMessage::decode(method.input(), wire.as_slice()).unwrap();
    let name = message
      .get_field_by_name("name")
      .and_then(|value| value.as_str().map(str::to_owned));
    assert_eq!(name.as_deref(), Some("Reqeast"));
  }

  #[test]
  fn grpc_path_formats_service_and_method() {
    let path = grpc_path("helloworld.Greeter", "SayHello").unwrap();
    assert_eq!(path.as_str(), "/helloworld.Greeter/SayHello");
  }

  #[test]
  fn resolve_method_derives_unary_for_say_hello() {
    let (descriptor_bytes, config) = hello_fixture();
    let pool = descriptor_pool_from_bytes(&descriptor_bytes).expect("pool");
    let (_, kind) = resolve_method(&pool, &config.service, &config.method).expect("resolve");
    assert_eq!(kind, GrpcRpcKind::Unary);
  }

  #[test]
  fn error_response_maps_grpc_status_fields() {
    let status = Status::invalid_argument("bad request");
    let response = error_response(status);
    assert_eq!(response.status_code, Code::InvalidArgument as i32);
    assert_eq!(response.status_message, "bad request");
    assert!(response.response_json.is_empty());
  }

  #[test]
  fn dynamic_decode_round_trip_with_fixture_descriptor() {
    let (descriptor_bytes, _) = hello_fixture();
    let pool = descriptor_pool_from_bytes(&descriptor_bytes).expect("pool");
    let output = pool
      .get_message_by_name(".helloworld.HelloResponse")
      .expect("output descriptor");

    let original = json_to_wire(r#"{"message":"Hello, Reqeast!"}"#, &pool, ".helloworld.HelloResponse").unwrap();
    let decoded = with_response_descriptor(output.clone(), || {
      DynamicDecode::decode(original.as_slice()).expect("decode")
    });
    let (json, _hex, truncated) = message_to_json_and_hex(&decoded.into_inner());
    assert!(json.contains("Hello, Reqeast!"));
    assert!(!truncated);
  }
}
