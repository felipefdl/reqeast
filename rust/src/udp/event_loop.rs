use std::sync::Arc;

use tokio::sync::mpsc;

use super::client::{UdpCommand, UdpConfig, UdpEvent, UdpEventHandler};

pub(crate) async fn run_event_loop(
  config: UdpConfig,
  mut cmd_rx: mpsc::Receiver<UdpCommand>,
  handler: Arc<dyn UdpEventHandler>,
) {
  let bind_addr = if let Some(bind_port) = config.bind_port {
    format!("0.0.0.0:{bind_port}")
  } else {
    "0.0.0.0:0".to_string()
  };

  let socket = match tokio::net::UdpSocket::bind(&bind_addr).await {
    Ok(s) => s,
    Err(e) => {
      handler.on_event(UdpEvent::Error {
        error: format!("Failed to bind UDP socket: {e}"),
      });
      return;
    }
  };

  let target_addr = format!("{}:{}", config.host, config.port);
  let mut buf = vec![0u8; 65535];

  loop {
    tokio::select! {
      biased;

      cmd = cmd_rx.recv() => {
        match cmd {
          Some(UdpCommand::Send(data)) => {
            if let Err(e) = socket.send_to(&data, &target_addr).await {
              handler.on_event(UdpEvent::Error { error: e.to_string() });
            }
          }
          Some(UdpCommand::Stop) | None => {
            break;
          }
        }
      }

      result = socket.recv_from(&mut buf) => {
        match result {
          Ok((n, addr)) => {
            handler.on_event(UdpEvent::DataReceived {
              data: buf[..n].to_vec(),
              from_addr: addr.to_string(),
            });
          }
          Err(e) => {
            handler.on_event(UdpEvent::Error { error: e.to_string() });
          }
        }
      }
    }
  }
}
