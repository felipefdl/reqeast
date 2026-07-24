//! Streaming gRPC event loop with biased command/stream select.

use std::sync::Arc;
use std::time::Duration;

use futures_util::StreamExt;
use prost_reflect::{DescriptorPool, DynamicMessage, MethodDescriptor};
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::client::Grpc;
use tonic::metadata::MetadataMap;
use tonic::{Code, Request, Response, Status};
use tonic_prost::ProstCodec;

use super::client::GrpcCommand;
use crate::grpc::codec::{hex_to_wire_str, json_to_wire, message_to_json_and_hex};
use crate::grpc::config::{GrpcConfig, GrpcEvent, GrpcEventHandler, GrpcRpcKind};
use crate::grpc::dynamic_decode::{DynamicDecode, ResponseDescriptorScope};
use crate::grpc::error::map_transport_error;
use crate::grpc::limits::{MAX_MESSAGE_BYTES, MAX_STREAM_MESSAGES};
use crate::grpc::schema::{descriptor_pool_from_bytes, resolve_method};
use crate::grpc::transport::build_endpoint;
use crate::grpc::unary::{apply_request_metadata, grpc_path, metadata_to_pairs};

struct StreamingSession<'a> {
  config: &'a GrpcConfig,
  pool: &'a DescriptorPool,
  method: &'a MethodDescriptor,
  cmd_rx: &'a mut mpsc::Receiver<GrpcCommand>,
  handler: &'a Arc<dyn GrpcEventHandler>,
  client: &'a mut Grpc<tonic::transport::Channel>,
  path: tonic::codegen::http::uri::PathAndQuery,
  output_descriptor: prost_reflect::MessageDescriptor,
  codec: ProstCodec<DynamicMessage, DynamicDecode>,
}

pub(crate) async fn run_event_loop(
  config: GrpcConfig,
  descriptor_bytes: Vec<u8>,
  request_body: String,
  request_body_is_hex: bool,
  mut cmd_rx: mpsc::Receiver<GrpcCommand>,
  handler: Arc<dyn GrpcEventHandler>,
) {
  if let Err(error) = run_event_loop_inner(
    config,
    descriptor_bytes,
    request_body,
    request_body_is_hex,
    &mut cmd_rx,
    &handler,
  )
  .await
  {
    handler.on_event(GrpcEvent::Error { error });
  }
}

async fn run_event_loop_inner(
  config: GrpcConfig,
  descriptor_bytes: Vec<u8>,
  request_body: String,
  request_body_is_hex: bool,
  cmd_rx: &mut mpsc::Receiver<GrpcCommand>,
  handler: &Arc<dyn GrpcEventHandler>,
) -> Result<(), String> {
  let pool = descriptor_pool_from_bytes(&descriptor_bytes).map_err(|err| err.to_string())?;
  let (method, rpc_kind) = resolve_method(&pool, &config.service, &config.method).map_err(|err| err.to_string())?;
  if rpc_kind == GrpcRpcKind::Unary {
    return Err("Unary RPCs must use invoke_unary, not start_stream".into());
  }

  let endpoint = build_endpoint(
    &config.authority,
    config.use_tls,
    config.allow_insecure_tls,
    config.timeout_secs,
  )
  .map_err(|err| err.to_string())?;
  let channel = endpoint
    .connect()
    .await
    .map_err(|err| map_transport_error(err).to_string())?;
  handler.on_event(GrpcEvent::Connected);

  let path = grpc_path(&config.service, &config.method).map_err(|err| err.to_string())?;
  let output_descriptor = method.output().clone();
  let mut client = Grpc::with_origin(channel, endpoint.uri().clone()).max_decoding_message_size(MAX_MESSAGE_BYTES);
  let codec = ProstCodec::<DynamicMessage, DynamicDecode>::default();
  client
    .ready()
    .await
    .map_err(|err| map_transport_error(err).to_string())?;

  let mut session = StreamingSession {
    config: &config,
    pool: &pool,
    method: &method,
    cmd_rx,
    handler,
    client: &mut client,
    path,
    output_descriptor,
    codec,
  };

  match rpc_kind {
    GrpcRpcKind::ServerStreaming => run_server_streaming(&mut session, request_body, request_body_is_hex).await,
    GrpcRpcKind::ClientStreaming => run_client_streaming(&mut session, request_body, request_body_is_hex).await,
    GrpcRpcKind::Bidirectional => run_bidirectional(&mut session, request_body, request_body_is_hex).await,
    GrpcRpcKind::Unary => unreachable!("filtered above"),
  }
}

async fn run_server_streaming(
  session: &mut StreamingSession<'_>,
  request_body: String,
  request_body_is_hex: bool,
) -> Result<(), String> {
  let _descriptor_scope = ResponseDescriptorScope::new(session.output_descriptor.clone());
  let request_message = encode_request_message(&request_body, request_body_is_hex, session.pool, session.method)?;
  let mut request = Request::new(request_message);
  apply_request_metadata(&mut request, &session.config.metadata).map_err(|err| err.to_string())?;
  if session.config.deadline_ms > 0 {
    request.set_timeout(Duration::from_millis(session.config.deadline_ms.into()));
  }

  let path = session.path.clone();
  let codec = session.codec.clone();
  let response = session
    .client
    .server_streaming(request, path, codec)
    .await
    .map_err(status_message)?;

  session.handler.on_event(GrpcEvent::MetadataReceived {
    headers: metadata_to_pairs(response.metadata()),
  });

  let mut stream = response.into_inner();
  let mut message_count = 0usize;
  loop {
    tokio::select! {
      biased;

      cmd = session.cmd_rx.recv() => {
        match cmd {
          Some(GrpcCommand::Cancel) => {
            emit_cancelled(session.handler);
            return Ok(());
          }
          Some(GrpcCommand::HalfClose) | Some(GrpcCommand::SendMessage { .. }) => {}
          None => return Err("Command channel closed".into()),
        }
      }

      item = stream.next() => {
        match item {
          Some(Ok(message)) => {
            if !emit_message_received(session.handler, message, &mut message_count)? {
              return Ok(());
            }
          }
          Some(Err(status)) => {
            emit_status_completed(session.handler, status);
            return Ok(());
          }
          None => {
            let trailers = stream.trailers().await.map_err(status_message)?.unwrap_or_default();
            emit_ok_completed(session.handler, trailers);
            return Ok(());
          }
        }
      }
    }
  }
}

async fn run_client_streaming(
  session: &mut StreamingSession<'_>,
  request_body: String,
  request_body_is_hex: bool,
) -> Result<(), String> {
  let _descriptor_scope = ResponseDescriptorScope::new(session.output_descriptor.clone());
  // Drive the outbound stream as soon as the RPC starts so the bounded channel can drain
  // without waiting for half-close (Rust futures are lazy; see F1).
  let (out_tx, out_rx) = mpsc::channel(32);
  encode_and_send(
    &request_body,
    request_body_is_hex,
    session.pool,
    session.method,
    &out_tx,
  )
  .await?;
  let mut out_tx = Some(out_tx);

  let mut request = Request::new(ReceiverStream::new(out_rx));
  apply_request_metadata(&mut request, &session.config.metadata).map_err(|err| err.to_string())?;
  if session.config.deadline_ms > 0 {
    request.set_timeout(Duration::from_millis(session.config.deadline_ms.into()));
  }

  let path = session.path.clone();
  let codec = session.codec.clone();
  // Poll unconditionally so tonic can pull outbound messages while the client still sends.
  let mut rpc_future = std::pin::pin!(session.client.client_streaming(request, path, codec));

  let mut half_closed = false;
  loop {
    tokio::select! {
      biased;

      cmd = session.cmd_rx.recv() => {
        match cmd {
          Some(GrpcCommand::SendMessage { body, body_is_hex }) => {
            if half_closed {
              return Err("Cannot send after half-close".into());
            }
            if let Some(sender) = out_tx.as_ref() {
              encode_and_send(&body, body_is_hex, session.pool, session.method, sender).await?;
            } else {
              return Err("Outbound stream closed".into());
            }
          }
          Some(GrpcCommand::HalfClose) => {
            half_closed = true;
            out_tx.take();
            session.handler.on_event(GrpcEvent::StreamHalfClosed);
          }
          Some(GrpcCommand::Cancel) => {
            emit_cancelled(session.handler);
            return Ok(());
          }
          None => return Err("Command channel closed".into()),
        }
      }

      result = rpc_future.as_mut() => {
        return finish_client_response(result, session.handler).await;
      }
    }
  }
}

async fn run_bidirectional(
  session: &mut StreamingSession<'_>,
  request_body: String,
  request_body_is_hex: bool,
) -> Result<(), String> {
  let _descriptor_scope = ResponseDescriptorScope::new(session.output_descriptor.clone());
  let (out_tx, out_rx) = mpsc::channel(32);
  encode_and_send(
    &request_body,
    request_body_is_hex,
    session.pool,
    session.method,
    &out_tx,
  )
  .await?;
  let mut out_tx = Some(out_tx);

  let mut request = Request::new(ReceiverStream::new(out_rx));
  apply_request_metadata(&mut request, &session.config.metadata).map_err(|err| err.to_string())?;
  if session.config.deadline_ms > 0 {
    request.set_timeout(Duration::from_millis(session.config.deadline_ms.into()));
  }

  let path = session.path.clone();
  let codec = session.codec.clone();
  let response = session
    .client
    .streaming(request, path, codec)
    .await
    .map_err(status_message)?;

  session.handler.on_event(GrpcEvent::MetadataReceived {
    headers: metadata_to_pairs(response.metadata()),
  });

  let mut stream = response.into_inner();
  let mut message_count = 0usize;
  loop {
    tokio::select! {
      biased;

      cmd = session.cmd_rx.recv() => {
        match cmd {
          Some(GrpcCommand::SendMessage { body, body_is_hex }) => {
            if let Some(sender) = out_tx.as_ref() {
              encode_and_send(&body, body_is_hex, session.pool, session.method, sender).await?;
            }
          }
          Some(GrpcCommand::HalfClose) => {
            out_tx.take();
            session.handler.on_event(GrpcEvent::StreamHalfClosed);
          }
          Some(GrpcCommand::Cancel) => {
            emit_cancelled(session.handler);
            return Ok(());
          }
          None => return Err("Command channel closed".into()),
        }
      }

      item = stream.next() => {
        match item {
          Some(Ok(message)) => {
            if !emit_message_received(session.handler, message, &mut message_count)? {
              return Ok(());
            }
          }
          Some(Err(status)) => {
            emit_status_completed(session.handler, status);
            return Ok(());
          }
          None => {
            let trailers = stream.trailers().await.map_err(status_message)?.unwrap_or_default();
            emit_ok_completed(session.handler, trailers);
            return Ok(());
          }
        }
      }
    }
  }
}

async fn finish_client_response(
  result: Result<Response<DynamicDecode>, Status>,
  handler: &Arc<dyn GrpcEventHandler>,
) -> Result<(), String> {
  match result {
    Ok(response) => {
      handler.on_event(GrpcEvent::MetadataReceived {
        headers: metadata_to_pairs(response.metadata()),
      });
      let message = response.into_inner().into_inner();
      let (json, hex, truncated) = message_to_json_and_hex(&message);
      handler.on_event(GrpcEvent::MessageReceived { json, hex, truncated });
      emit_ok_completed(handler, MetadataMap::default());
      Ok(())
    }
    Err(status) => {
      emit_status_completed(handler, status);
      Ok(())
    }
  }
}

fn encode_request_message(
  request_body: &str,
  body_is_hex: bool,
  pool: &DescriptorPool,
  method: &MethodDescriptor,
) -> Result<DynamicMessage, String> {
  let wire = if body_is_hex {
    hex_to_wire_str(request_body).map_err(|err| err.to_string())?
  } else {
    json_to_wire(request_body, pool, method.input().full_name()).map_err(|err| err.to_string())?
  };
  DynamicMessage::decode(method.input(), wire.as_slice())
    .map_err(|err| format!("Failed to encode request message: {err}"))
}

async fn encode_and_send(
  request_body: &str,
  body_is_hex: bool,
  pool: &DescriptorPool,
  method: &MethodDescriptor,
  out_tx: &mpsc::Sender<DynamicMessage>,
) -> Result<(), String> {
  let message = encode_request_message(request_body, body_is_hex, pool, method)?;
  out_tx
    .send(message)
    .await
    .map_err(|_| "Outbound stream closed".to_string())
}

fn emit_message_received(
  handler: &Arc<dyn GrpcEventHandler>,
  message: DynamicDecode,
  message_count: &mut usize,
) -> Result<bool, String> {
  *message_count += 1;
  if *message_count > MAX_STREAM_MESSAGES {
    handler.on_event(GrpcEvent::Error {
      error: format!("Exceeded {MAX_STREAM_MESSAGES} stream messages"),
    });
    return Ok(false);
  }

  let message = message.into_inner();
  let (json, hex, truncated) = message_to_json_and_hex(&message);
  handler.on_event(GrpcEvent::MessageReceived { json, hex, truncated });
  Ok(true)
}

fn emit_ok_completed(handler: &Arc<dyn GrpcEventHandler>, trailers: MetadataMap) {
  handler.on_event(GrpcEvent::Completed {
    status_code: Code::Ok as i32,
    status_message: String::new(),
    trailers: metadata_to_pairs(&trailers),
  });
}

fn emit_status_completed(handler: &Arc<dyn GrpcEventHandler>, status: Status) {
  handler.on_event(GrpcEvent::Completed {
    status_code: status.code() as i32,
    status_message: status.message().to_owned(),
    trailers: metadata_to_pairs(status.metadata()),
  });
}

fn emit_cancelled(handler: &Arc<dyn GrpcEventHandler>) {
  handler.on_event(GrpcEvent::Completed {
    status_code: Code::Cancelled as i32,
    status_message: "RPC cancelled".into(),
    trailers: vec![],
  });
}

fn status_message(status: Status) -> String {
  status.message().to_owned()
}
