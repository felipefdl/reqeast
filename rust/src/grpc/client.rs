//! Shared Tokio runtime for gRPC one-shot and streaming operations.

use std::sync::{Arc, OnceLock};

use tokio::runtime::Runtime;
use tokio::sync::mpsc;

use crate::error::ReqeastError;
use crate::grpc::config::{GrpcConfig, GrpcEventHandler};

pub(crate) fn grpc_runtime() -> Result<&'static Runtime, ReqeastError> {
  static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
  let result = RUNTIME.get_or_init(|| Runtime::new().map_err(|err| format!("Failed to create gRPC runtime: {err}")));
  match result {
    Ok(runtime) => Ok(runtime),
    Err(err) => Err(ReqeastError::InternalError(err.clone())),
  }
}

#[allow(dead_code)]
pub(crate) enum GrpcCommand {
  SendMessage { body: String, body_is_hex: bool },
  HalfClose,
  Cancel,
}

#[derive(uniffi::Object)]
pub struct GrpcClient {
  #[allow(dead_code)]
  runtime: Arc<Runtime>,
  command_tx: std::sync::Mutex<Option<mpsc::Sender<GrpcCommand>>>,
}

#[uniffi::export]
impl GrpcClient {
  #[uniffi::constructor]
  pub fn new() -> Result<Self, ReqeastError> {
    let runtime = tokio::runtime::Runtime::new()
      .map_err(|e| ReqeastError::InternalError(format!("Failed to create runtime: {e}")))?;

    Ok(Self {
      runtime: Arc::new(runtime),
      command_tx: std::sync::Mutex::new(None),
    })
  }

  pub fn start_stream(
    &self,
    config: GrpcConfig,
    descriptor_bytes: Vec<u8>,
    request_body: String,
    body_is_hex: bool,
    handler: Box<dyn GrpcEventHandler>,
  ) -> Result<(), ReqeastError> {
    let handler: Arc<dyn GrpcEventHandler> = Arc::from(handler);
    let (cmd_tx, cmd_rx) = mpsc::channel::<GrpcCommand>(32);

    {
      let mut tx = self
        .command_tx
        .lock()
        .map_err(|e| ReqeastError::InternalError(e.to_string()))?;
      *tx = Some(cmd_tx);
    }

    let runtime = self.runtime.clone();
    std::thread::spawn(move || {
      runtime.block_on(super::event_loop::run_event_loop(
        config,
        descriptor_bytes,
        request_body,
        body_is_hex,
        cmd_rx,
        handler,
      ));
    });

    Ok(())
  }

  pub fn send_message(&self, body: String, body_is_hex: bool) -> Result<(), ReqeastError> {
    self.send_command(GrpcCommand::SendMessage { body, body_is_hex })
  }

  pub fn half_close(&self) -> Result<(), ReqeastError> {
    self.send_command(GrpcCommand::HalfClose)
  }

  pub fn cancel(&self) -> Result<(), ReqeastError> {
    self.send_command(GrpcCommand::Cancel)
  }
}

impl GrpcClient {
  fn send_command(&self, cmd: GrpcCommand) -> Result<(), ReqeastError> {
    let tx = self
      .command_tx
      .lock()
      .map_err(|e| ReqeastError::InternalError(e.to_string()))?;

    if let Some(ref tx) = *tx {
      tx.blocking_send(cmd).map_err(|_| ReqeastError::NotConnected)?;
      Ok(())
    } else {
      Err(ReqeastError::NotConnected)
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::grpc::config::{GrpcEvent, GrpcRpcKind};

  struct NoopHandler;

  impl GrpcEventHandler for NoopHandler {
    fn on_event(&self, _event: GrpcEvent) {}
  }

  #[test]
  fn grpc_runtime_initializes() {
    let runtime = grpc_runtime();
    assert!(runtime.is_ok());
    assert!(grpc_runtime().is_ok());
  }

  #[test]
  fn grpc_client_new_succeeds() {
    let client = GrpcClient::new();
    assert!(client.is_ok());
  }

  #[test]
  fn start_stream_starts_background_event_loop() {
    let client = GrpcClient::new().unwrap();
    let config = GrpcConfig {
      authority: "localhost:50051".into(),
      use_tls: false,
      allow_insecure_tls: false,
      metadata: vec![],
      service: "helloworld.Greeter".into(),
      method: "SayHello".into(),
      rpc_kind: GrpcRpcKind::ServerStreaming,
      deadline_ms: 0,
      timeout_secs: 30,
    };
    let result = client.start_stream(config, vec![], "{}".into(), false, Box::new(NoopHandler));
    assert!(result.is_ok());
  }

  #[test]
  fn send_message_when_disconnected_returns_not_connected() {
    let client = GrpcClient::new().unwrap();
    let result = client.send_message("{}".into(), false);
    assert!(matches!(result, Err(ReqeastError::NotConnected)));
  }
}
