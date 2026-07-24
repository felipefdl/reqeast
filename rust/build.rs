fn main() {
  // UniFFI proc-macro mode: no UDL scaffolding generation needed.
  // All types use #[derive(uniffi::...)] proc macros as the source of truth.

  println!("cargo:rerun-if-changed=tests/fixtures/grpc/hello.proto");

  let manifest_dir = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
  let proto_root = manifest_dir.join("tests/fixtures/grpc");
  let well_known_root = manifest_dir.join("assets/protobuf");

  tonic_prost_build::configure()
    .build_client(false)
    .compile_protos(&[proto_root.join("hello.proto")], &[proto_root, well_known_root])
    .expect("compile hello.proto for gRPC fixture server");
}
