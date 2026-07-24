use std::sync::Arc;

use tokio::sync::mpsc;

use crate::error::ReqeastError;
use crate::types::KeyValuePair;

#[derive(Debug, Clone, uniffi::Record)]
pub struct WsConfig {
  pub url: String,
  pub headers: Vec<KeyValuePair>,
  pub subprotocols: Vec<String>,
  pub timeout_secs: u32,
  pub allow_insecure_tls: bool,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum WsEvent {
  Connected { protocol: Option<String> },
  TextReceived { text: String },
  BinaryReceived { data: Vec<u8> },
  PongReceived { data: Vec<u8> },
  Disconnected { code: u16, reason: String },
  Error { error: String },
}

#[uniffi::export(callback_interface)]
pub trait WsEventHandler: Send + Sync {
  fn on_event(&self, event: WsEvent);
}

pub(crate) enum WsCommand {
  SendText(String),
  SendBinary(Vec<u8>),
  Ping(Vec<u8>),
  Close,
}

#[derive(uniffi::Object)]
pub struct WsClient {
  runtime: Arc<tokio::runtime::Runtime>,
  command_tx: std::sync::Mutex<Option<mpsc::Sender<WsCommand>>>,
}

#[uniffi::export]
impl WsClient {
  #[uniffi::constructor]
  pub fn new() -> Result<Self, ReqeastError> {
    let runtime = tokio::runtime::Runtime::new()
      .map_err(|e| ReqeastError::InternalError(format!("Failed to create runtime: {e}")))?;

    Ok(Self {
      runtime: Arc::new(runtime),
      command_tx: std::sync::Mutex::new(None),
    })
  }

  pub fn connect(&self, config: WsConfig, handler: Box<dyn WsEventHandler>) -> Result<(), ReqeastError> {
    let handler: Arc<dyn WsEventHandler> = Arc::from(handler);
    let (cmd_tx, cmd_rx) = mpsc::channel::<WsCommand>(32);

    {
      let mut tx = self
        .command_tx
        .lock()
        .map_err(|e| ReqeastError::InternalError(e.to_string()))?;
      *tx = Some(cmd_tx);
    }

    let runtime = self.runtime.clone();
    std::thread::spawn(move || {
      runtime.block_on(super::event_loop::run_event_loop(config, cmd_rx, handler));
    });

    Ok(())
  }

  pub fn send_text(&self, text: String) -> Result<(), ReqeastError> {
    self.send_command(WsCommand::SendText(text))
  }

  pub fn send_binary(&self, data: Vec<u8>) -> Result<(), ReqeastError> {
    self.send_command(WsCommand::SendBinary(data))
  }

  pub fn ping(&self, data: Vec<u8>) -> Result<(), ReqeastError> {
    self.send_command(WsCommand::Ping(data))
  }

  pub fn disconnect(&self) -> Result<(), ReqeastError> {
    let tx = self
      .command_tx
      .lock()
      .map_err(|e| ReqeastError::InternalError(e.to_string()))?;

    if let Some(ref tx) = *tx {
      let _ = tx.blocking_send(WsCommand::Close);
    }
    Ok(())
  }
}

impl WsClient {
  fn send_command(&self, cmd: WsCommand) -> Result<(), ReqeastError> {
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

  #[test]
  fn ws_client_new_succeeds() {
    let client = WsClient::new();
    assert!(client.is_ok());
  }

  #[test]
  fn ws_config_clone() {
    let config = WsConfig {
      url: "ws://localhost:8080".into(),
      headers: vec![],
      subprotocols: vec!["graphql-ws".into()],
      timeout_secs: 30,
      allow_insecure_tls: false,
    };
    let cloned = config.clone();
    assert_eq!(cloned.url, "ws://localhost:8080");
    assert_eq!(cloned.subprotocols, vec!["graphql-ws"]);
  }

  #[test]
  fn send_text_when_disconnected_returns_error() {
    let client = WsClient::new().unwrap();
    let result = client.send_text("hello".into());
    assert!(result.is_err());
  }

  #[test]
  fn send_binary_when_disconnected_returns_error() {
    let client = WsClient::new().unwrap();
    let result = client.send_binary(vec![1, 2, 3]);
    assert!(result.is_err());
  }
}
