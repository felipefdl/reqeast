use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::{HeaderName, HeaderValue};

use super::client::{WsCommand, WsConfig, WsEvent, WsEventHandler};
use crate::tcp::tls;

pub(crate) async fn run_event_loop(
  config: WsConfig,
  mut cmd_rx: mpsc::Receiver<WsCommand>,
  handler: Arc<dyn WsEventHandler>,
) {
  let mut request = match config.url.as_str().into_client_request() {
    Ok(r) => r,
    Err(e) => {
      handler.on_event(WsEvent::Error {
        error: format!("Invalid WebSocket URL: {e}"),
      });
      return;
    }
  };

  let headers = request.headers_mut();
  for kv in &config.headers {
    if kv.enabled {
      if let Ok(val) = HeaderValue::from_str(&kv.value) {
        if let Ok(name) = kv.key.parse::<HeaderName>() {
          headers.insert(name, val);
        }
      }
    }
  }

  if !config.subprotocols.is_empty() {
    let protocols = config.subprotocols.join(", ");
    if let Ok(val) = HeaderValue::from_str(&protocols) {
      headers.insert("Sec-WebSocket-Protocol", val);
    }
  }

  let connector = if config.allow_insecure_tls {
    match tls::create_insecure_tls_config() {
      Ok(tls_config) => Some(tokio_tungstenite::Connector::Rustls(Arc::new(tls_config))),
      Err(e) => {
        handler.on_event(WsEvent::Error {
          error: format!("TLS setup failed: {e}"),
        });
        return;
      }
    }
  } else {
    None
  };

  let connect_future = tokio_tungstenite::connect_async_tls_with_config(request, None, false, connector);

  let connect_result = if config.timeout_secs > 0 {
    match tokio::time::timeout(
      std::time::Duration::from_secs(config.timeout_secs as u64),
      connect_future,
    )
    .await
    {
      Ok(result) => result,
      Err(_) => {
        handler.on_event(WsEvent::Error {
          error: "Connection timed out".to_string(),
        });
        return;
      }
    }
  } else {
    connect_future.await
  };

  let (ws_stream, response) = match connect_result {
    Ok(pair) => pair,
    Err(e) => {
      handler.on_event(WsEvent::Error {
        error: format!("Connection failed: {e}"),
      });
      return;
    }
  };

  let selected_protocol = response
    .headers()
    .get("Sec-WebSocket-Protocol")
    .and_then(|v| v.to_str().ok())
    .map(String::from);

  handler.on_event(WsEvent::Connected {
    protocol: selected_protocol,
  });

  let (mut write, mut read) = ws_stream.split();

  loop {
    tokio::select! {
      biased;

      cmd = cmd_rx.recv() => {
        match cmd {
          Some(WsCommand::SendText(text)) => {
            if let Err(e) = write.send(Message::Text(text.into())).await {
              handler.on_event(WsEvent::Error { error: e.to_string() });
              break;
            }
          }
          Some(WsCommand::SendBinary(data)) => {
            if let Err(e) = write.send(Message::Binary(data.into())).await {
              handler.on_event(WsEvent::Error { error: e.to_string() });
              break;
            }
          }
          Some(WsCommand::Ping(data)) => {
            if let Err(e) = write.send(Message::Ping(data.into())).await {
              handler.on_event(WsEvent::Error { error: e.to_string() });
              break;
            }
          }
          Some(WsCommand::Close) => {
            let _ = write.send(Message::Close(None)).await;
            handler.on_event(WsEvent::Disconnected {
              code: 1000,
              reason: "User disconnected".to_string(),
            });
            break;
          }
          None => {
            handler.on_event(WsEvent::Disconnected {
              code: 1000,
              reason: "Command channel closed".to_string(),
            });
            break;
          }
        }
      }

      msg = read.next() => {
        match msg {
          Some(Ok(Message::Text(text))) => {
            handler.on_event(WsEvent::TextReceived { text: text.to_string() });
          }
          Some(Ok(Message::Binary(data))) => {
            handler.on_event(WsEvent::BinaryReceived { data: data.to_vec() });
          }
          Some(Ok(Message::Pong(data))) => {
            handler.on_event(WsEvent::PongReceived { data: data.to_vec() });
          }
          Some(Ok(Message::Ping(_))) => {
            // tungstenite handles pong replies automatically
          }
          Some(Ok(Message::Close(frame))) => {
            let (code, reason) = frame
              .map(|f| (f.code.into(), f.reason.to_string()))
              .unwrap_or((1000, "Connection closed".to_string()));
            handler.on_event(WsEvent::Disconnected { code, reason });
            break;
          }
          Some(Ok(Message::Frame(_))) => {}
          Some(Err(e)) => {
            handler.on_event(WsEvent::Error { error: e.to_string() });
            break;
          }
          None => {
            handler.on_event(WsEvent::Disconnected {
              code: 1006,
              reason: "Connection lost".to_string(),
            });
            break;
          }
        }
      }
    }
  }
}
