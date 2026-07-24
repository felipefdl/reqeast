use std::sync::Arc;

use tokio::sync::mpsc;

use crate::error::ReqeastError;

#[derive(Debug, Clone, uniffi::Record)]
pub struct UdpConfig {
  pub host: String,
  pub port: u16,
  pub bind_port: Option<u16>,
  pub timeout_secs: u32,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum UdpEvent {
  DataReceived { data: Vec<u8>, from_addr: String },
  Error { error: String },
}

#[uniffi::export(callback_interface)]
pub trait UdpEventHandler: Send + Sync {
  fn on_event(&self, event: UdpEvent);
}

pub(crate) enum UdpCommand {
  Send(Vec<u8>),
  Stop,
}

#[derive(uniffi::Object)]
pub struct UdpClient {
  runtime: Arc<tokio::runtime::Runtime>,
  command_tx: std::sync::Mutex<Option<mpsc::Sender<UdpCommand>>>,
}

#[uniffi::export]
impl UdpClient {
  #[uniffi::constructor]
  pub fn new() -> Result<Self, ReqeastError> {
    let runtime = tokio::runtime::Runtime::new()
      .map_err(|e| ReqeastError::InternalError(format!("Failed to create runtime: {e}")))?;

    Ok(Self {
      runtime: Arc::new(runtime),
      command_tx: std::sync::Mutex::new(None),
    })
  }

  pub fn start(&self, config: UdpConfig, handler: Box<dyn UdpEventHandler>) -> Result<(), ReqeastError> {
    let handler: Arc<dyn UdpEventHandler> = Arc::from(handler);
    let (cmd_tx, cmd_rx) = mpsc::channel::<UdpCommand>(32);

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
      tx.blocking_send(UdpCommand::Send(data))
        .map_err(|_| ReqeastError::NotConnected)?;
      Ok(())
    } else {
      Err(ReqeastError::NotConnected)
    }
  }

  pub fn stop(&self) -> Result<(), ReqeastError> {
    let tx = self
      .command_tx
      .lock()
      .map_err(|e| ReqeastError::InternalError(e.to_string()))?;

    if let Some(ref tx) = *tx {
      let _ = tx.blocking_send(UdpCommand::Stop);
    }
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn udp_client_new_succeeds() {
    let client = UdpClient::new();
    assert!(client.is_ok());
  }

  #[test]
  fn udp_config_clone() {
    let config = UdpConfig {
      host: "localhost".into(),
      port: 8080,
      bind_port: None,
      timeout_secs: 10,
    };
    let cloned = config.clone();
    assert_eq!(cloned.host, "localhost");
    assert_eq!(cloned.port, 8080);
    assert!(cloned.bind_port.is_none());
  }
}
