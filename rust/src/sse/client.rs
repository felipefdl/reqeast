use std::sync::Arc;

use tokio::sync::mpsc;

use crate::error::ReqeastError;
use crate::types::KeyValuePair;

#[derive(Debug, Clone, uniffi::Record)]
pub struct SseConfig {
  pub url: String,
  pub headers: Vec<KeyValuePair>,
  pub timeout_secs: u32,
  pub ssl_verify: bool,
  pub last_event_id: Option<String>,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum SseEvent {
  Connected,
  EventReceived {
    event_type: String,
    data: String,
    id: Option<String>,
  },
  RetryChanged {
    retry_ms: u64,
  },
  Disconnected {
    reason: String,
  },
  Error {
    error: String,
  },
}

#[uniffi::export(callback_interface)]
pub trait SseEventHandler: Send + Sync {
  fn on_event(&self, event: SseEvent);
}

pub(crate) enum SseCommand {
  Disconnect,
}

#[derive(uniffi::Object)]
pub struct SseClient {
  runtime: Arc<tokio::runtime::Runtime>,
  command_tx: std::sync::Mutex<Option<mpsc::Sender<SseCommand>>>,
}

#[uniffi::export]
impl SseClient {
  #[uniffi::constructor]
  pub fn new() -> Result<Self, ReqeastError> {
    let runtime = tokio::runtime::Runtime::new()
      .map_err(|e| ReqeastError::InternalError(format!("Failed to create runtime: {e}")))?;

    Ok(Self {
      runtime: Arc::new(runtime),
      command_tx: std::sync::Mutex::new(None),
    })
  }

  pub fn connect(&self, config: SseConfig, handler: Box<dyn SseEventHandler>) -> Result<(), ReqeastError> {
    let handler: Arc<dyn SseEventHandler> = Arc::from(handler);
    let (cmd_tx, cmd_rx) = mpsc::channel::<SseCommand>(4);

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

  pub fn disconnect(&self) -> Result<(), ReqeastError> {
    let tx = self
      .command_tx
      .lock()
      .map_err(|e| ReqeastError::InternalError(e.to_string()))?;

    if let Some(ref tx) = *tx {
      let _ = tx.blocking_send(SseCommand::Disconnect);
    }
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn sse_client_new_succeeds() {
    let client = SseClient::new();
    assert!(client.is_ok());
  }

  #[test]
  fn sse_config_clone() {
    let config = SseConfig {
      url: "https://example.com/events".into(),
      headers: vec![],
      timeout_secs: 0,
      ssl_verify: true,
      last_event_id: None,
    };
    let cloned = config.clone();
    assert_eq!(cloned.url, "https://example.com/events");
    assert!(cloned.ssl_verify);
  }
}
