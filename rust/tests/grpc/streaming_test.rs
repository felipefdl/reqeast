mod fixture_server;

use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use reqeast_core::{GrpcClient, GrpcConfig, GrpcEvent, GrpcEventHandler, GrpcRpcKind, compile_proto_bundle};

#[derive(Clone)]
struct TestHandler {
  events: Arc<Mutex<Vec<GrpcEvent>>>,
  done: Arc<(Mutex<bool>, Condvar)>,
}

impl TestHandler {
  fn new() -> Self {
    Self {
      events: Arc::new(Mutex::new(Vec::new())),
      done: Arc::new((Mutex::new(false), Condvar::new())),
    }
  }

  fn wait_for_terminal_event(&self, timeout: Duration) {
    let (lock, cvar) = &*self.done;
    let mut done = lock.lock().expect("lock");
    let deadline = std::time::Instant::now() + timeout;
    while !*done {
      let remaining = deadline.saturating_duration_since(std::time::Instant::now());
      if remaining.is_zero() {
        break;
      }
      done = cvar.wait_timeout(done, remaining).expect("wait").0;
    }
  }

  fn snapshot(&self) -> Vec<GrpcEvent> {
    self.events.lock().expect("lock").clone()
  }

  fn wait_for_message_count(&self, count: usize, timeout: Duration) {
    let deadline = std::time::Instant::now() + timeout;
    loop {
      let messages = self
        .snapshot()
        .iter()
        .filter(|event| matches!(event, GrpcEvent::MessageReceived { .. }))
        .count();
      if messages >= count || std::time::Instant::now() >= deadline {
        break;
      }
      std::thread::sleep(Duration::from_millis(10));
    }
  }
}

fn compile_fixture_bundle() -> Vec<u8> {
  let root = env!("CARGO_MANIFEST_DIR");
  compile_proto_bundle(format!("{root}/tests/fixtures/grpc"), vec!["hello.proto".into()])
    .expect("compile hello.proto bundle")
    .descriptor_bytes
}

fn streaming_config(addr: std::net::SocketAddr, method: &str, rpc_kind: GrpcRpcKind) -> GrpcConfig {
  GrpcConfig {
    authority: addr.to_string(),
    use_tls: false,
    allow_insecure_tls: false,
    metadata: vec![],
    service: "helloworld.Greeter".into(),
    method: method.into(),
    rpc_kind,
    deadline_ms: 5_000,
    timeout_secs: 10,
  }
}

impl GrpcEventHandler for TestHandler {
  fn on_event(&self, event: GrpcEvent) {
    let terminal = matches!(event, GrpcEvent::Completed { .. } | GrpcEvent::Error { .. });
    self.events.lock().expect("lock").push(event);
    if terminal {
      let (lock, cvar) = &*self.done;
      *lock.lock().expect("lock") = true;
      cvar.notify_all();
    }
  }
}

#[test]
fn server_streaming_receives_multiple_messages() {
  let (addr, _server) = fixture_server::spawn();
  let bundle = compile_fixture_bundle();
  let config = streaming_config(addr, "StreamHello", GrpcRpcKind::ServerStreaming);

  let handler = TestHandler::new();
  let client = GrpcClient::new().expect("client");
  client
    .start_stream(
      config,
      bundle,
      r#"{"name":"Reqeast"}"#.into(),
      false,
      Box::new(handler.clone()),
    )
    .expect("start_stream");

  handler.wait_for_terminal_event(Duration::from_secs(5));

  let events = handler.snapshot();
  let messages: Vec<_> = events
    .iter()
    .filter_map(|event| match event {
      GrpcEvent::MessageReceived { json, .. } => Some(json.as_str()),
      _ => None,
    })
    .collect();

  assert!(
    events.iter().any(|event| matches!(event, GrpcEvent::Connected)),
    "expected Connected event, got {events:?}"
  );
  assert_eq!(messages.len(), 3, "expected 3 stream messages, got {messages:?}");
  assert!(
    messages.iter().all(|json| json.contains("Reqeast")),
    "expected name echoed in stream messages, got {messages:?}"
  );
  assert!(
    events
      .iter()
      .any(|event| matches!(event, GrpcEvent::Completed { status_code: 0, .. })),
    "expected OK Completed event, got {events:?}"
  );
}

#[test]
fn client_streaming_aggregates_messages_after_half_close() {
  let (addr, _server) = fixture_server::spawn();
  let bundle = compile_fixture_bundle();
  let config = streaming_config(addr, "CollectNames", GrpcRpcKind::ClientStreaming);

  let handler = TestHandler::new();
  let client = GrpcClient::new().expect("client");
  client
    .start_stream(
      config,
      bundle,
      r#"{"name":"First"}"#.into(),
      false,
      Box::new(handler.clone()),
    )
    .expect("start_stream");

  client
    .send_message(r#"{"name":"Second"}"#.into(), false)
    .expect("send_message");
  client.half_close().expect("half_close");

  handler.wait_for_terminal_event(Duration::from_secs(5));

  let events = handler.snapshot();
  let messages: Vec<_> = events
    .iter()
    .filter_map(|event| match event {
      GrpcEvent::MessageReceived { json, .. } => Some(json.as_str()),
      _ => None,
    })
    .collect();

  assert!(
    events.iter().any(|event| matches!(event, GrpcEvent::Connected)),
    "expected Connected event, got {events:?}"
  );
  assert!(
    events.iter().any(|event| matches!(event, GrpcEvent::StreamHalfClosed)),
    "expected StreamHalfClosed event, got {events:?}"
  );
  assert_eq!(
    messages.len(),
    1,
    "expected single aggregated response, got {messages:?}"
  );
  assert!(
    messages[0].contains("First") && messages[0].contains("Second"),
    "expected both names in aggregated response, got {messages:?}"
  );
  assert!(
    events
      .iter()
      .any(|event| matches!(event, GrpcEvent::Completed { status_code: 0, .. })),
    "expected OK Completed event, got {events:?}"
  );
}

#[test]
fn bidirectional_echoes_each_message() {
  let (addr, _server) = fixture_server::spawn();
  let bundle = compile_fixture_bundle();
  let config = streaming_config(addr, "ChatHello", GrpcRpcKind::Bidirectional);

  let handler = TestHandler::new();
  let client = GrpcClient::new().expect("client");
  client
    .start_stream(
      config,
      bundle,
      r#"{"name":"One"}"#.into(),
      false,
      Box::new(handler.clone()),
    )
    .expect("start_stream");

  handler.wait_for_message_count(1, Duration::from_secs(2));

  client
    .send_message(r#"{"name":"Two"}"#.into(), false)
    .expect("send_message");
  handler.wait_for_message_count(2, Duration::from_secs(2));

  client.half_close().expect("half_close");
  handler.wait_for_terminal_event(Duration::from_secs(5));

  let events = handler.snapshot();
  let messages: Vec<_> = events
    .iter()
    .filter_map(|event| match event {
      GrpcEvent::MessageReceived { json, .. } => Some(json.as_str()),
      _ => None,
    })
    .collect();

  assert!(
    events.iter().any(|event| matches!(event, GrpcEvent::Connected)),
    "expected Connected event, got {events:?}"
  );
  assert_eq!(messages.len(), 2, "expected 2 echo messages, got {messages:?}");
  assert!(
    messages.iter().any(|json| json.contains("One")),
    "expected echo for first message, got {messages:?}"
  );
  assert!(
    messages.iter().any(|json| json.contains("Two")),
    "expected echo for second message, got {messages:?}"
  );
  assert!(
    events
      .iter()
      .any(|event| matches!(event, GrpcEvent::Completed { status_code: 0, .. })),
    "expected OK Completed event, got {events:?}"
  );
}
