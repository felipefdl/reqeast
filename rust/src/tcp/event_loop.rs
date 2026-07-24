use std::sync::Arc;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::mpsc;

use super::client::{TcpCommand, TcpConfig, TcpEvent, TcpEventHandler};
use super::tls;

pub(crate) async fn run_event_loop(
  config: TcpConfig,
  cmd_rx: mpsc::Receiver<TcpCommand>,
  handler: Arc<dyn TcpEventHandler>,
) {
  let addr = format!("{}:{}", config.host, config.port);

  let connect_result = tokio::time::timeout(
    std::time::Duration::from_secs(config.timeout_secs as u64),
    tokio::net::TcpStream::connect(&addr),
  )
  .await;

  let stream = match connect_result {
    Ok(Ok(stream)) => stream,
    Ok(Err(e)) => {
      handler.on_event(TcpEvent::Error {
        error: format!("Connection failed: {e}"),
      });
      return;
    }
    Err(_) => {
      handler.on_event(TcpEvent::Error {
        error: "Connection timed out".to_string(),
      });
      return;
    }
  };

  if let Err(e) = stream.set_nodelay(true) {
    handler.on_event(TcpEvent::Error {
      error: format!("Failed to set TCP_NODELAY: {e}"),
    });
    return;
  }

  if config.use_tls {
    match tls::upgrade_to_tls(stream, &config).await {
      Ok(tls_stream) => {
        let (reader, writer) = tokio::io::split(tls_stream);
        handler.on_event(TcpEvent::Connected);
        run_select_loop(reader, writer, cmd_rx, handler).await;
      }
      Err(event) => handler.on_event(event),
    }
  } else {
    let (reader, writer) = tokio::io::split(stream);
    handler.on_event(TcpEvent::Connected);
    run_select_loop(reader, writer, cmd_rx, handler).await;
  }
}

async fn run_select_loop<R, W>(
  mut reader: R,
  mut writer: W,
  mut cmd_rx: mpsc::Receiver<TcpCommand>,
  handler: Arc<dyn TcpEventHandler>,
) where
  R: AsyncReadExt + Unpin,
  W: AsyncWriteExt + Unpin,
{
  let mut buf = vec![0u8; 8192];

  loop {
    tokio::select! {
      biased;

      cmd = cmd_rx.recv() => {
        match cmd {
          Some(TcpCommand::Send(data)) => {
            if let Err(e) = writer.write_all(&data).await {
              handler.on_event(TcpEvent::Error { error: e.to_string() });
              break;
            }
            if let Err(e) = writer.flush().await {
              handler.on_event(TcpEvent::Error { error: e.to_string() });
              break;
            }
          }
          Some(TcpCommand::Disconnect) | None => {
            handler.on_event(TcpEvent::Disconnected {
              reason: "User disconnected".to_string(),
            });
            break;
          }
        }
      }

      result = reader.read(&mut buf) => {
        match result {
          Ok(0) => {
            handler.on_event(TcpEvent::Disconnected {
              reason: "Connection closed by remote".to_string(),
            });
            break;
          }
          Ok(n) => {
            handler.on_event(TcpEvent::DataReceived { data: buf[..n].to_vec() });
          }
          Err(e) => {
            handler.on_event(TcpEvent::Error { error: e.to_string() });
            break;
          }
        }
      }
    }
  }
}
