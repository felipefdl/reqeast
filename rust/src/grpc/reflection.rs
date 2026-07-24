//! gRPC server reflection client (v1 with v1alpha fallback).

use std::collections::HashMap;

use prost::Message;
use prost_reflect::DescriptorPool;
use prost_types::{FileDescriptorProto, FileDescriptorSet};
use tokio_stream::{StreamExt, wrappers::ReceiverStream};
use tonic::client::Grpc;
use tonic::codegen::http::uri::PathAndQuery;
use tonic::{Code, Request, Status};
use tonic_prost::ProstCodec;
use tonic_reflection::pb::v1 as reflection_v1;
use tonic_reflection::pb::v1alpha as reflection_v1alpha;

use crate::error::ReqeastError;
use crate::grpc::client::grpc_runtime;
use crate::grpc::config::GrpcReflectionConfig;
use crate::grpc::error::{map_grpc_status, map_transport_error};
use crate::grpc::limits::MAX_MESSAGE_BYTES;
use crate::grpc::transport::build_endpoint;

const REFLECTION_V1_PATH: &str = "/grpc.reflection.v1.ServerReflection/ServerReflectionInfo";
const REFLECTION_V1ALPHA_PATH: &str = "/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo";

/// Fetch merged `FileDescriptorSet` bytes from a reflection-enabled gRPC server.
#[uniffi::export]
pub fn fetch_reflection_descriptors(config: GrpcReflectionConfig) -> Result<Vec<u8>, ReqeastError> {
  grpc_runtime()?.block_on(fetch_reflection_descriptors_async(config))
}

async fn fetch_reflection_descriptors_async(config: GrpcReflectionConfig) -> Result<Vec<u8>, ReqeastError> {
  let endpoint = build_endpoint(
    &config.authority,
    config.use_tls,
    config.allow_insecure_tls,
    config.timeout_secs,
  )?;
  let channel = endpoint.connect().await.map_err(map_transport_error)?;

  match fetch_reflection_v1(channel.clone(), endpoint.uri().clone()).await {
    Ok(bytes) => Ok(bytes),
    Err(status) if should_fallback_to_v1alpha(&status) => fetch_reflection_v1alpha(channel, endpoint.uri().clone())
      .await
      .map_err(map_grpc_status),
    Err(status) => Err(map_grpc_status(status)),
  }
}

async fn fetch_reflection_v1(
  channel: tonic::transport::Channel,
  origin: tonic::codegen::http::Uri,
) -> Result<Vec<u8>, Status> {
  fetch_reflection_with_path::<reflection_v1::ServerReflectionRequest, reflection_v1::ServerReflectionResponse>(
    channel,
    origin,
    REFLECTION_V1_PATH,
    reflection_v1_list_services_request,
    reflection_v1_file_containing_symbol_request,
    reflection_v1_take_message_response,
  )
  .await
}

async fn fetch_reflection_v1alpha(
  channel: tonic::transport::Channel,
  origin: tonic::codegen::http::Uri,
) -> Result<Vec<u8>, Status> {
  fetch_reflection_with_path::<
    reflection_v1alpha::ServerReflectionRequest,
    reflection_v1alpha::ServerReflectionResponse,
  >(
    channel,
    origin,
    REFLECTION_V1ALPHA_PATH,
    reflection_v1alpha_list_services_request,
    reflection_v1alpha_file_containing_symbol_request,
    reflection_v1alpha_take_message_response,
  )
  .await
}

async fn fetch_reflection_with_path<Req, Resp>(
  channel: tonic::transport::Channel,
  origin: tonic::codegen::http::Uri,
  path: &str,
  list_services_request: fn() -> Req,
  file_containing_symbol_request: fn(&str) -> Req,
  take_message_response: fn(Resp) -> Option<ReflectionMessageResponse>,
) -> Result<Vec<u8>, Status>
where
  Req: prost::Message + Send + Sync + 'static,
  Resp: prost::Message + Default + Send + Sync + 'static,
{
  let list_response =
    send_reflection_request(&channel, &origin, path, list_services_request(), take_message_response).await?;

  let services = match list_response {
    ReflectionMessageResponse::ListServices(services) => services,
    ReflectionMessageResponse::Error { code, message } if should_fallback_to_v1alpha_code(code) => {
      return Err(Status::new(code, message));
    }
    ReflectionMessageResponse::Error { code, message } => {
      return Err(Status::new(code, message));
    }
    _ => {
      return Err(Status::internal("unexpected reflection response for ListServices"));
    }
  };

  let mut file_bytes = Vec::new();
  for service in services {
    if service.is_empty() {
      continue;
    }
    let response = send_reflection_request(
      &channel,
      &origin,
      path,
      file_containing_symbol_request(&service),
      take_message_response,
    )
    .await?;
    match response {
      ReflectionMessageResponse::FileDescriptors(mut descriptors) => file_bytes.append(&mut descriptors),
      ReflectionMessageResponse::Error { code, message } => {
        return Err(Status::new(code, message));
      }
      _ => {
        return Err(Status::internal(format!(
          "unexpected reflection response for FileContainingSymbol({service})"
        )));
      }
    }
  }

  merge_file_descriptor_bytes(&file_bytes).map_err(|err| Status::invalid_argument(err.to_string()))
}

async fn send_reflection_request<Req, Resp>(
  channel: &tonic::transport::Channel,
  origin: &tonic::codegen::http::Uri,
  path: &str,
  request: Req,
  take_message_response: fn(Resp) -> Option<ReflectionMessageResponse>,
) -> Result<ReflectionMessageResponse, Status>
where
  Req: prost::Message + Send + Sync + 'static,
  Resp: prost::Message + Default + Send + Sync + 'static,
{
  let path = path
    .parse::<PathAndQuery>()
    .map_err(|err| Status::internal(format!("invalid reflection path: {err}")))?;
  let codec = ProstCodec::<Req, Resp>::default();
  let mut client = Grpc::with_origin(channel.clone(), origin.clone()).max_decoding_message_size(MAX_MESSAGE_BYTES);
  client.ready().await.map_err(|err| Status::from_error(err.into()))?;

  let (request_tx, request_rx) = tokio::sync::mpsc::channel(1);
  request_tx
    .send(request)
    .await
    .map_err(|_| Status::internal("failed to queue reflection request"))?;
  drop(request_tx);

  let mut response = client
    .streaming(Request::new(ReceiverStream::new(request_rx)), path, codec)
    .await?;
  let item = response
    .get_mut()
    .next()
    .await
    .ok_or_else(|| Status::internal("empty reflection stream"))??;

  take_message_response(item).ok_or_else(|| Status::internal("reflection response missing message_response"))
}

enum ReflectionMessageResponse {
  ListServices(Vec<String>),
  FileDescriptors(Vec<Vec<u8>>),
  Error { code: Code, message: String },
}

fn reflection_v1_list_services_request() -> reflection_v1::ServerReflectionRequest {
  reflection_v1::ServerReflectionRequest {
    host: String::new(),
    message_request: Some(reflection_v1::server_reflection_request::MessageRequest::ListServices(
      String::new(),
    )),
  }
}

fn reflection_v1_file_containing_symbol_request(symbol: &str) -> reflection_v1::ServerReflectionRequest {
  reflection_v1::ServerReflectionRequest {
    host: String::new(),
    message_request: Some(
      reflection_v1::server_reflection_request::MessageRequest::FileContainingSymbol(symbol.into()),
    ),
  }
}

fn reflection_v1_take_message_response(
  response: reflection_v1::ServerReflectionResponse,
) -> Option<ReflectionMessageResponse> {
  parse_reflection_response(response.message_response.map(|message| match message {
    reflection_v1::server_reflection_response::MessageResponse::ListServicesResponse(list) => {
      ReflectionParse::ListServices(list.service.into_iter().map(|service| service.name).collect())
    }
    reflection_v1::server_reflection_response::MessageResponse::FileDescriptorResponse(files) => {
      ReflectionParse::FileDescriptors(files.file_descriptor_proto)
    }
    reflection_v1::server_reflection_response::MessageResponse::ErrorResponse(error) => ReflectionParse::Error {
      code: Code::from_i32(error.error_code),
      message: error.error_message,
    },
    _ => ReflectionParse::Unsupported,
  }))
}

fn reflection_v1alpha_list_services_request() -> reflection_v1alpha::ServerReflectionRequest {
  reflection_v1alpha::ServerReflectionRequest {
    host: String::new(),
    message_request: Some(reflection_v1alpha::server_reflection_request::MessageRequest::ListServices(String::new())),
  }
}

fn reflection_v1alpha_file_containing_symbol_request(symbol: &str) -> reflection_v1alpha::ServerReflectionRequest {
  reflection_v1alpha::ServerReflectionRequest {
    host: String::new(),
    message_request: Some(
      reflection_v1alpha::server_reflection_request::MessageRequest::FileContainingSymbol(symbol.into()),
    ),
  }
}

fn reflection_v1alpha_take_message_response(
  response: reflection_v1alpha::ServerReflectionResponse,
) -> Option<ReflectionMessageResponse> {
  parse_reflection_response(response.message_response.map(|message| match message {
    reflection_v1alpha::server_reflection_response::MessageResponse::ListServicesResponse(list) => {
      ReflectionParse::ListServices(list.service.into_iter().map(|service| service.name).collect())
    }
    reflection_v1alpha::server_reflection_response::MessageResponse::FileDescriptorResponse(files) => {
      ReflectionParse::FileDescriptors(files.file_descriptor_proto)
    }
    reflection_v1alpha::server_reflection_response::MessageResponse::ErrorResponse(error) => ReflectionParse::Error {
      code: Code::from_i32(error.error_code),
      message: error.error_message,
    },
    _ => ReflectionParse::Unsupported,
  }))
}

enum ReflectionParse {
  ListServices(Vec<String>),
  FileDescriptors(Vec<Vec<u8>>),
  Error { code: Code, message: String },
  Unsupported,
}

fn parse_reflection_response(parsed: Option<ReflectionParse>) -> Option<ReflectionMessageResponse> {
  match parsed? {
    ReflectionParse::ListServices(services) => Some(ReflectionMessageResponse::ListServices(services)),
    ReflectionParse::FileDescriptors(files) => Some(ReflectionMessageResponse::FileDescriptors(files)),
    ReflectionParse::Error { code, message } => Some(ReflectionMessageResponse::Error { code, message }),
    ReflectionParse::Unsupported => None,
  }
}

fn merge_file_descriptor_bytes(file_bytes: &[Vec<u8>]) -> Result<Vec<u8>, ReqeastError> {
  let mut by_name: HashMap<String, FileDescriptorProto> = HashMap::new();
  for bytes in file_bytes {
    let file = FileDescriptorProto::decode(bytes.as_slice())
      .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid FileDescriptorProto from reflection: {err}")))?;
    if let Some(name) = file.name.clone() {
      by_name.insert(name, file);
    }
  }

  if by_name.is_empty() {
    return Err(ReqeastError::InvalidConfig(
      "Reflection returned no file descriptors".into(),
    ));
  }

  let mut set = FileDescriptorSet {
    file: by_name.into_values().collect(),
  };
  set.file.sort_by(|left, right| left.name.cmp(&right.name));
  DescriptorPool::from_file_descriptor_set(set.clone())
    .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid reflection descriptor pool: {err}")))?;
  Ok(set.encode_to_vec())
}

fn should_fallback_to_v1alpha(status: &Status) -> bool {
  should_fallback_to_v1alpha_code(status.code())
}

fn should_fallback_to_v1alpha_code(code: Code) -> bool {
  matches!(code, Code::Unimplemented | Code::NotFound)
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::grpc::schema::{compile_proto_bundle, list_grpc_services};

  fn hello_file_descriptor_bytes() -> Vec<Vec<u8>> {
    let root = env!("CARGO_MANIFEST_DIR");
    let bundle = compile_proto_bundle(format!("{root}/tests/fixtures/grpc"), vec!["hello.proto".into()])
      .expect("compile hello fixture");
    let set = FileDescriptorSet::decode(bundle.descriptor_bytes.as_slice()).expect("decode set");
    set
      .file
      .into_iter()
      .map(|file| {
        let mut bytes = Vec::new();
        file.encode(&mut bytes).expect("encode file descriptor");
        bytes
      })
      .collect()
  }

  #[test]
  fn merge_reflection_file_descriptors_builds_valid_pool() {
    let merged = merge_file_descriptor_bytes(&hello_file_descriptor_bytes()).expect("merge");
    let services = list_grpc_services(merged).expect("list services");
    assert_eq!(services[0].name, "helloworld.Greeter");
    assert_eq!(services[0].methods[0].name, "SayHello");
  }

  #[test]
  fn merge_reflection_file_descriptors_dedupes_by_name() {
    let files = hello_file_descriptor_bytes();
    let duplicated = files.iter().chain(files.iter()).cloned().collect::<Vec<_>>();
    let merged = merge_file_descriptor_bytes(&duplicated).expect("merge");
    let set = FileDescriptorSet::decode(merged.as_slice()).expect("decode merged set");
    let unique_names: HashMap<_, _> = set
      .file
      .iter()
      .filter_map(|file| file.name.as_ref().map(|name| (name.clone(), ())))
      .collect();
    assert_eq!(unique_names.len(), set.file.len());
  }

  #[test]
  fn captured_file_descriptor_proto_bytes_decode() {
    let files = hello_file_descriptor_bytes();
    for bytes in files {
      let file = FileDescriptorProto::decode(bytes.as_slice()).expect("decode captured bytes");
      assert!(file.name.is_some());
    }
  }

  #[test]
  fn should_fallback_on_unimplemented_and_not_found() {
    assert!(should_fallback_to_v1alpha(&Status::unimplemented(
      "reflection v1 missing"
    )));
    assert!(should_fallback_to_v1alpha(&Status::not_found(
      "reflection service not found"
    )));
    assert!(!should_fallback_to_v1alpha(&Status::invalid_argument("bad request")));
  }

  #[test]
  fn v1_list_services_response_parses_fixture_services() {
    let response = reflection_v1_take_message_response(reflection_v1::ServerReflectionResponse {
      valid_host: String::new(),
      original_request: None,
      message_response: Some(
        reflection_v1::server_reflection_response::MessageResponse::ListServicesResponse(
          reflection_v1::ListServiceResponse {
            service: vec![reflection_v1::ServiceResponse {
              name: "helloworld.Greeter".into(),
            }],
          },
        ),
      ),
    })
    .expect("parse response");

    match response {
      ReflectionMessageResponse::ListServices(services) => {
        assert_eq!(services, vec!["helloworld.Greeter".to_string()]);
      }
      _ => panic!("expected ListServices"),
    }
  }
}
