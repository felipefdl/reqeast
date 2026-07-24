# Agents — `reqeast-core`

`reqeast-core` (`rust/`, crate `reqeast_core`) is the networking and spec-processing library behind Reqeast. SwiftUI calls into it via UniFFI: stateless HTTP, synchronous gRPC unary RPCs, persistent TCP/TLS/UDP/WebSocket/SSE/gRPC-streaming sessions with callback event handlers, synchronous `jq_filter`, and (with `spec-openapi`) OpenAPI/Postman/Insomnia/Bruno/HAR/AsyncAPI/GraphQL import, fingerprinting, diff, and export. All user-supplied input must fail with typed errors, never panic across the FFI boundary.

## Commands

Run from repo root via `just` (preferred) or `cd rust`:

```sh
just build-rust          # ./build-xcframework.sh → ReqeastCore/reqeast_core.xcframework + Swift bindings
just check-rust          # cargo check
just test-rust           # cargo test (set TZ=UTC for deterministic timestamps)
just lint-rust           # cargo clippy -- -D warnings  (warnings are errors)
just fmt-rust            # cargo fmt (rustfmt.toml: max_width=120, tab_spaces=2)
just update-spec-goldens # UPDATE_SPEC_GOLDENS=1 cargo test update_spec_goldens -- --ignored --nocapture
just bench-spec-import   # cargo bench --bench spec_import (requires spec-openapi)
just rebuild             # clean-rust + build-rust
```

**Gotchas**

- After any public API change: `just build-rust`, then copy `ReqeastCore/Sources/reqeast_core.swift` → `Reqeast/Services/reqeast_core.swift`. Never hand-edit either file.
- `cargo test`: use `TZ=UTC` (project-wide test convention).
- `lint-rust` must pass with zero warnings (`-D warnings`).
- `spec-openapi` is a default feature; disabling it removes `spec_import` and its UniFFI exports.
- Golden fixtures live in `ReqeastTests/Fixtures/SpecImport/` (shared Rust/Swift).

## Conventions

- **Edition / toolchain**: Rust 2024, `rust-version = "1.88"`. Use latest stable idioms.
- **Formatting**: `rustfmt.toml` — 120 cols, 2-space indent.
- **File size**: Keep modules ~150 lines; split by responsibility (`mod.rs` + subfiles). `normalize.rs` is the known exception.
- **Errors**: `thiserror` + `#[derive(uniffi::Error)]`. Networking uses `ReqeastError`; spec import uses `SpecImportError` / `SpecExportError`.
- **Logging**: `tracing` + `init_logging()` in `lib.rs` (`RUST_LOG`, default `reqeast_core=debug`, no ANSI).
- **Async pattern**: Each protocol client owns `Arc<tokio::runtime::Runtime>`. HTTP/SSE/gRPC unary one-shots use `runtime.block_on()`. TCP/UDP/WS/SSE/gRPC streaming sessions spawn event loops on `runtime.spawn()`.
- **Event loops**: `tokio::select! { biased; ... }` — command channel polled before I/O for responsive send/disconnect.
- **User input**: Return `Result` with descriptive strings. No `unwrap()`/`expect()` on paths reachable from UniFFI. Panics abort the app through FFI.
- **Tests**: `#[cfg(test)]` in-module; integration goldens in `rust/tests/`. Panics in tests are fine; not in production paths for user data.

## Rules (from real code)

### Error classification

- `ReqeastError::from(reqwest::Error)`: check `is_timeout()`, `is_builder()`, `is_redirect()`, `is_connect()`, `is_body()`, `is_decode()`, `is_request()` **before** generic `HttpError`.
- On connect errors, walk `full_error_chain()` to distinguish TLS vs DNS vs connection refused.
- Ingress/spec parse failures → `InvalidConfig` or `SpecImportError::ParseError` / `InvalidSpec`, not `InternalError`.
- Event-loop failures deliver `*Event::Error { error }` to the handler; do not panic.

### Resource limits (user-supplied data)

| Constant | Value | Module |
|----------|-------|--------|
| `MAX_SPEC_BYTES` | 5 MiB | `spec_import/limits.rs` |
| `MAX_YAML_DEPTH` | 128 | `spec_import/limits.rs` (must match `serde_yaml_ng`) |
| `MAX_YAML_ALIASES` | 128 | `spec_import/limits.rs` |
| `MAX_YAML_NODES` | 100_000 | `spec_import/limits.rs` |
| `MAX_REF_DEPTH` | 256 | `spec_import/limits.rs` |
| `MAX_JSON_DEPTH` | 256 | `jq/limits.rs` |
| `MAX_OUTPUT_VALUES` | 10_000 | `jq/limits.rs` |
| `MAX_OUTPUT_BYTES` | 8 MiB | `jq/limits.rs` |
| `MAX_PROTO_FILE_BYTES` | 1 MiB | `grpc/limits.rs` |
| `MAX_PROTO_BUNDLE_BYTES` | 5 MiB | `grpc/limits.rs` |
| `MAX_DESCRIPTOR_DEPTH` | 128 | `grpc/limits.rs` |
| `MAX_STREAM_MESSAGES` | 10_000 | `grpc/limits.rs` |
| `MAX_MESSAGE_BYTES` | 4 MiB | `grpc/limits.rs` |
| `MAX_JSON_OUTPUT_BYTES` | 8 MiB | `grpc/limits.rs` |

jq output truncates with a marker instead of failing. Stack overflow from deep JSON or unbounded `repeat(.)` is a process killer; depth caps exist to prevent that.

### UniFFI

- Proc-macro mode only (`uniffi::setup_scaffolding!()` in `lib.rs`). No UDL.
- `build.rs` does **not** generate UniFFI scaffolding. It compiles the gRPC fixture proto (`tests/fixtures/grpc/hello.proto` via `tonic_prost_build`) so integration tests can run an in-process fixture server. UniFFI types still come only from `#[derive(uniffi::…)]` proc macros.
- Exported types: `#[derive(uniffi::Record)]`, `#[derive(uniffi::Enum)]`, `#[derive(uniffi::Error)]`.
- Clients: `#[derive(uniffi::Object)]` + `#[uniffi::export] impl` with `#[uniffi::constructor] fn new()`.
- Callbacks: `#[uniffi::export(callback_interface)] trait …EventHandler: Send + Sync`.
- Free functions: `#[uniffi::export] pub fn …` (e.g. `jq_filter`, `parse_spec`, `diff_spec`, `export_openapi`).
- Re-export public API from `lib.rs` for Swift discoverability.

## Module map

```
src/
  lib.rs           Entry, init_logging, re-exports, uniffi scaffolding
  error.rs         ReqeastError + reqwest/io/tungstenite From impls
  types.rs         HttpMethod, HttpBody, KeyValuePair, HttpVersion, HttpCookie
  util.rs          Pipe trait (method chaining)
  http/
    client.rs      HttpClient + HttpRequestConfig/HttpResponse records
    request.rs     send_async: reqwest build, body, redirects, cookies, timing
    cert.rs        TLS cert extraction for responses
    timing.rs      HttpTimingBreakdown
  tcp/
    client.rs      TcpClient, TcpConfig, TcpCommand channel API
    event_loop.rs  connect, biased select, read/write
    tls.rs         tokio-rustls upgrade (uses tls/insecure.rs)
  tls/
    insecure.rs    InsecureCertVerifier for allow-insecure TLS
  udp/
    client.rs      UdpClient start/send/stop
    event_loop.rs  datagram recv + biased select
  ws/
    client.rs      WsClient connect/send/ping/close
    event_loop.rs  tungstenite stream + biased select
  sse/
    client.rs      SseClient connect/disconnect
    event_loop.rs  reqwest streaming body
    parser.rs      SSE frame parsing
  jq/
    mod.rs         jq_filter() — sync, jaq-core + hifijson
    limits.rs      depth + output caps
  grpc/            Proto compile, reflection, dynamic RPC
    mod.rs         Module root, re-exports
    limits.rs      proto bundle + streaming caps
    config.rs      GrpcConfig, GrpcRpcKind, UniFFI records
    schema.rs      protox compile, list_grpc_services
    codec.rs       JSON/hex ↔ wire protobuf
    dynamic_decode.rs  Dynamic message decoding for responses
    error.rs       tonic transport/status → ReqeastError
    transport.rs   tonic Endpoint builder, TLS secure/insecure
    client.rs      GrpcClient object, runtime, start_stream/cancel
    unary.rs       invoke_unary sync block_on
    event_loop.rs  Streaming RPC biased select + command channel
    reflection.rs  Server reflection v1/v1alpha fallback
  spec_import/     Feature-gated (spec-openapi)
    ingress.rs     parse_ingress: sniff JSON/YAML, size checks
    limits.rs      MAX_* constants
    bundle.rs      Multi-file $ref resolution (local only; remote refs fatal)
    normalize.rs   OpenAPI v2/v3 → NormalizedProject (roas)
    postman.rs     insomnia.rs  bruno.rs  har.rs  asyncapi.rs  graphql.rs
    fingerprint.rs bundle + sort keys + SHA-256
    diff.rs        diff_spec: added/removed/modified/unchanged/identity_changed
    export_openapi.rs / export_postman.rs / export_types.rs
    types.rs       Normalized* IR, parse_spec, canonical_fingerprint
    golden.rs      Fixture serialization for integration tests
```

## spec_import pipeline

```
bytes + SpecSourceHint + optional bundle_entry_path
  → [GraphQL SDL?] normalize_graphql (bypasses JSON ingress)
  → parse_ingress (size → sniff → JSON/YAML → serde_json::Value)
  → detect_spec_format (hint + heuristics: openapi/swagger, postman, insomnia, bruno, har, asyncapi)
  → format-specific normalize_* → NormalizedProject + warnings
  → fingerprint: bundle $refs (MAX_REF_DEPTH) → canonical JSON (sorted keys) → SHA-256 hex
  → SpecImportResult { project, warnings, content_fingerprint }
```

**Downstream**

- `canonical_fingerprint(resolved_bytes)` — hash only, for already-resolved bytes.
- `diff_spec(old, new, bindings, options)` — compares normalized IR; `is_conflict` always `false` from Rust (Swift sets after snapshot compare).
- **Export**: `export_openapi` / `export_postman` from `ExportProjectInput`; `export_input_from_normalized` bridges normalized IR → export input (same defaults as Swift `SpecImportMapper`).

**Dependencies**: `roas =0.17.2`, `roas-file-fetcher =0.1.1`, `serde_yaml_ng`, `indexmap` (preserve_order), `sha2`, `graphql-parser`. Pin versions when touching OpenAPI parsing.

## Adding or changing APIs

1. Add Rust types/functions with UniFFI derives in the appropriate module.
2. Re-export from `lib.rs` if part of the public contract.
3. `just lint-rust && just test-rust` (with `TZ=UTC`).
4. `just build-rust`; sync `reqeast_core.swift` to `Reqeast/Services/`.
5. For spec import: update goldens via `just update-spec-goldens` when normalized output changes intentionally.
6. Add Swift service/wrapper + `ReqeastTests/` coverage on the Swift side.

## Context7

Query Context7 for `reqwest`, `tokio`, `uniffi`, `rustls`, `roas`, `jaq-core`, `thiserror`, `tracing` before changing unfamiliar APIs. Do not rely on stale signatures.