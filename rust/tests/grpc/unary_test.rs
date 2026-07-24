mod fixture_server;

use reqeast_core::{
  compile_proto_bundle, invoke_unary, GrpcConfig, GrpcRpcKind, KeyValuePair,
};

#[test]
fn invoke_unary_smoke_against_fixture_server() {
  let (addr, _server) = fixture_server::spawn();

  let root = env!("CARGO_MANIFEST_DIR");
  let bundle = compile_proto_bundle(format!("{root}/tests/fixtures/grpc"), vec!["hello.proto".into()])
    .expect("compile hello.proto bundle");

  let config = GrpcConfig {
    authority: addr.to_string(),
    use_tls: false,
    allow_insecure_tls: false,
    metadata: vec![KeyValuePair {
      key: "x-test".into(),
      value: "1".into(),
      enabled: true,
    }],
    service: "helloworld.Greeter".into(),
    method: "SayHello".into(),
    rpc_kind: GrpcRpcKind::Unary,
    deadline_ms: 5_000,
    timeout_secs: 10,
  };

  let response = invoke_unary(
    config,
    bundle.descriptor_bytes,
    r#"{"name":"Reqeast"}"#.into(),
    false,
  )
    .expect("invoke_unary");

  assert_eq!(response.status_code, 0, "expected OK status, got {:?}", response);
  assert!(response.status_message.is_empty());
  assert!(
    response.response_json.contains("Hello"),
    "expected Hello greeting in JSON, got {}",
    response.response_json
  );
  assert!(
    response.response_json.contains("Reqeast"),
    "expected request name echoed in JSON, got {}",
    response.response_json
  );
}