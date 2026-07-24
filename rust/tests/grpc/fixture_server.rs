//! Local tonic Greeter server for unary integration tests.

use std::net::SocketAddr;
use std::sync::mpsc::{self as std_mpsc, SyncSender};
use std::thread::{self, JoinHandle};

use tokio::net::TcpListener;
use tokio::sync::{mpsc as tokio_mpsc, oneshot};
use tokio_stream;
use tokio_stream::wrappers::{ReceiverStream, TcpListenerStream};
use tonic::transport::Server;
use tonic::{Request, Response, Status};

pub mod hello {
  tonic::include_proto!("helloworld");
}

use hello::greeter_server::{Greeter, GreeterServer};
use hello::{HelloRequest, HelloResponse};

struct GreeterService;

#[tonic::async_trait]
impl Greeter for GreeterService {
  async fn say_hello(&self, request: Request<HelloRequest>) -> Result<Response<HelloResponse>, Status> {
    let name = request.into_inner().name;
    Ok(Response::new(HelloResponse {
      message: format!("Hello, {name}!"),
    }))
  }

  type StreamHelloStream = std::pin::Pin<Box<dyn tokio_stream::Stream<Item = Result<HelloResponse, Status>> + Send>>;

  async fn stream_hello(&self, request: Request<HelloRequest>) -> Result<Response<Self::StreamHelloStream>, Status> {
    let name = request.into_inner().name;
    let messages = (1..=3).map(move |index| {
      Ok(HelloResponse {
        message: format!("Stream {index}, {name}!"),
      })
    });
    Ok(Response::new(Box::pin(tokio_stream::iter(messages))))
  }

  async fn collect_names(
    &self,
    request: Request<tonic::Streaming<HelloRequest>>,
  ) -> Result<Response<HelloResponse>, Status> {
    let mut stream = request.into_inner();
    let mut names = Vec::new();
    while let Some(req) = stream.message().await? {
      names.push(req.name);
    }
    Ok(Response::new(HelloResponse {
      message: format!("Collected: {}", names.join(", ")),
    }))
  }

  type ChatHelloStream = std::pin::Pin<Box<dyn tokio_stream::Stream<Item = Result<HelloResponse, Status>> + Send>>;

  async fn chat_hello(
    &self,
    request: Request<tonic::Streaming<HelloRequest>>,
  ) -> Result<Response<Self::ChatHelloStream>, Status> {
    let mut inbound = request.into_inner();
    let (tx, rx) = tokio_mpsc::channel(8);

    tokio::spawn(async move {
      loop {
        match inbound.message().await {
          Ok(Some(req)) => {
            if tx
              .send(Ok(HelloResponse {
                message: format!("Echo: {}", req.name),
              }))
              .await
              .is_err()
            {
              break;
            }
          }
          Ok(None) => break,
          Err(status) => {
            let _ = tx.send(Err(status)).await;
            break;
          }
        }
      }
    });

    Ok(Response::new(Box::pin(ReceiverStream::new(rx))))
  }
}

/// Starts the fixture server on a dedicated thread/runtime and returns its address.
pub fn spawn() -> (SocketAddr, FixtureServerGuard) {
  let (addr_tx, addr_rx) = std_mpsc::sync_channel(1);
  let (shutdown_tx, shutdown_rx) = std_mpsc::sync_channel(0);

  let join = thread::spawn(move || {
    let runtime = tokio::runtime::Runtime::new().expect("fixture server runtime");
    runtime.block_on(async move {
      let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind fixture server");
      let addr = listener.local_addr().expect("fixture server listen address");
      addr_tx.send(addr).expect("fixture server address");

      let (stop_tx, stop_rx) = oneshot::channel::<()>();
      let service = GreeterServer::new(GreeterService);

      let server = tokio::spawn(async move {
        Server::builder()
          .add_service(service)
          .serve_with_incoming_shutdown(TcpListenerStream::new(listener), async {
            let _ = stop_rx.await;
          })
          .await
          .expect("fixture server");
      });

      let _ = shutdown_rx.recv();
      let _ = stop_tx.send(());
      let _ = server.await;
    });
  });

  let addr = addr_rx.recv().expect("fixture server address");
  (
    addr,
    FixtureServerGuard {
      shutdown_tx: Some(shutdown_tx),
      join: Some(join),
    },
  )
}

pub struct FixtureServerGuard {
  shutdown_tx: Option<SyncSender<()>>,
  join: Option<JoinHandle<()>>,
}

impl Drop for FixtureServerGuard {
  fn drop(&mut self) {
    if let Some(shutdown_tx) = self.shutdown_tx.take() {
      let _ = shutdown_tx.send(());
    }
    if let Some(join) = self.join.take() {
      let _ = join.join();
    }
  }
}
