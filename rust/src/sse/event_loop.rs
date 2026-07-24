use std::sync::Arc;

use futures_util::StreamExt;
use tokio::sync::mpsc;

use super::client::{SseCommand, SseConfig, SseEvent, SseEventHandler};
use super::parser::SseParser;

pub(crate) async fn run_event_loop(
  config: SseConfig,
  mut cmd_rx: mpsc::Receiver<SseCommand>,
  handler: Arc<dyn SseEventHandler>,
) {
  let mut client_builder = reqwest::Client::builder();
  if !config.ssl_verify {
    client_builder = client_builder.danger_accept_invalid_certs(true);
  }

  let client = match client_builder.build() {
    Ok(c) => c,
    Err(e) => {
      handler.on_event(SseEvent::Error {
        error: format!("Failed to create HTTP client: {e}"),
      });
      return;
    }
  };

  let mut request = client.get(&config.url).header("Accept", "text/event-stream");

  for kv in &config.headers {
    if kv.enabled {
      request = request.header(&kv.key, &kv.value);
    }
  }

  if let Some(ref last_id) = config.last_event_id {
    request = request.header("Last-Event-ID", last_id);
  }

  let send_future = request.send();
  let response = if config.timeout_secs > 0 {
    match tokio::time::timeout(std::time::Duration::from_secs(config.timeout_secs as u64), send_future).await {
      Ok(result) => result,
      Err(_) => {
        handler.on_event(SseEvent::Error {
          error: "Connection timed out".to_string(),
        });
        return;
      }
    }
  } else {
    send_future.await
  };

  let response = match response {
    Ok(r) => r,
    Err(e) => {
      handler.on_event(SseEvent::Error {
        error: format!("Connection failed: {e}"),
      });
      return;
    }
  };

  if !response.status().is_success() {
    handler.on_event(SseEvent::Error {
      error: format!("Server returned status {}", response.status()),
    });
    return;
  }

  handler.on_event(SseEvent::Connected);

  let mut stream = response.bytes_stream();
  let mut parser = SseParser::default();

  loop {
    tokio::select! {
      biased;

      cmd = cmd_rx.recv() => {
        match cmd {
          Some(SseCommand::Disconnect) | None => {
            handler.on_event(SseEvent::Disconnected {
              reason: "User disconnected".to_string(),
            });
            break;
          }
        }
      }

      chunk = stream.next() => {
        match chunk {
          Some(Ok(bytes)) => {
            let mut events = Vec::new();
            parser.feed(&bytes, &mut events);
            for event in events {
              handler.on_event(event);
            }
          }
          Some(Err(e)) => {
            handler.on_event(SseEvent::Error { error: e.to_string() });
            break;
          }
          None => {
            handler.on_event(SseEvent::Disconnected {
              reason: "Stream ended".to_string(),
            });
            break;
          }
        }
      }
    }
  }
}
