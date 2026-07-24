use std::sync::Arc;

use tokio::sync::mpsc;

use crate::error::ReqeastError;

#[derive(Debug, Clone, uniffi::Record)]
pub struct TcpConfig {
  pub host: String,
  pub port: u16,
  pub use_tls: bool,
  pub allow_insecure_tls: bool,
  pub timeout_secs: u32,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum TcpEvent {
  Connected,
  DataReceived { data: Vec<u8> },
  Disconnected { reason: String },
  Error { error: String },
}

#[uniffi::export(callback_interface)]
pub trait TcpEventHandler: Send + Sync {
  fn on_event(&self, event: TcpEvent);
}

pub(crate) enum TcpCommand {
  Send(Vec<u8>),
  Disconnect,
}

#[derive(uniffi::Object)]
pub struct TcpClient {
  runtime: Arc<tokio::runtime::Runtime>,
  command_tx: std::sync::Mutex<Option<mpsc::Sender<TcpCommand>>>,
}

#[uniffi::export]
impl TcpClient {
  #[uniffi::constructor]
  pub fn new() -> Result<Self, ReqeastError> {
    let runtime = tokio::runtime::Runtime::new()
      .map_err(|e| ReqeastError::InternalError(format!("Failed to create runtime: {e}")))?;

    Ok(Self {
      runtime: Arc::new(runtime),
      command_tx: std::sync::Mutex::new(None),
    })
  }

  pub fn connect(&self, config: TcpConfig, handler: Box<dyn TcpEventHandler>) -> Result<(), ReqeastError> {
    let handler: Arc<dyn TcpEventHandler> = Arc::from(handler);
    let (cmd_tx, cmd_rx) = mpsc::channel::<TcpCommand>(32);

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

  pub fn send(&self, data: Vec<u8>) -> Result<(), ReqeastError> {
    let tx = self
      .command_tx
      .lock()
      .map_err(|e| ReqeastError::InternalError(e.to_string()))?;

    if let Some(ref tx) = *tx {
      tx.blocking_send(TcpCommand::Send(data))
        .map_err(|_| ReqeastError::NotConnected)?;
      Ok(())
    } else {
      Err(ReqeastError::NotConnected)
    }
  }

  pub fn disconnect(&self) -> Result<(), ReqeastError> {
    let tx = self
      .command_tx
      .lock()
      .map_err(|e| ReqeastError::InternalError(e.to_string()))?;

    if let Some(ref tx) = *tx {
      let _ = tx.blocking_send(TcpCommand::Disconnect);
    }
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn tcp_client_new_succeeds() {
    let client = TcpClient::new();
    assert!(client.is_ok());
  }

  #[test]
  fn tcp_config_clone() {
    let config = TcpConfig {
      host: "localhost".into(),
      port: 8080,
      use_tls: false,
      allow_insecure_tls: false,
      timeout_secs: 30,
    };
    let cloned = config.clone();
    assert_eq!(cloned.host, "localhost");
    assert_eq!(cloned.port, 8080);
  }
}
