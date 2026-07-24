//! JSON and hex encoding for dynamic protobuf messages.

use prost::Message;
use prost_reflect::{DescriptorPool, DeserializeOptions, DynamicMessage, MessageDescriptor, SerializeOptions};

use crate::error::ReqeastError;
use crate::grpc::limits::{MAX_JSON_OUTPUT_BYTES, MAX_MESSAGE_BYTES};

/// Parses a lowercase/uppercase hex string (optional `0x` prefix, whitespace allowed) into wire bytes.
#[uniffi::export]
pub fn hex_to_wire(hex: String) -> Result<Vec<u8>, ReqeastError> {
  hex_to_wire_str(&hex)
}

pub(crate) fn hex_to_wire_str(hex: &str) -> Result<Vec<u8>, ReqeastError> {
  let mut cleaned: String = hex.chars().filter(|ch| !ch.is_whitespace()).collect();
  if cleaned.starts_with("0x") || cleaned.starts_with("0X") {
    cleaned = cleaned[2..].to_owned();
  }

  if cleaned.is_empty() {
    return Err(ReqeastError::InvalidConfig("Hex body is empty".into()));
  }
  if !cleaned.len().is_multiple_of(2) {
    return Err(ReqeastError::InvalidConfig(
      "Hex body must have an even number of digits".into(),
    ));
  }
  if !cleaned.chars().all(|ch| ch.is_ascii_hexdigit()) {
    return Err(ReqeastError::InvalidConfig(
      "Hex body contains invalid characters".into(),
    ));
  }

  let mut bytes = Vec::with_capacity(cleaned.len() / 2);
  for index in (0..cleaned.len()).step_by(2) {
    let pair = &cleaned[index..index + 2];
    let byte = u8::from_str_radix(pair, 16)
      .map_err(|_| ReqeastError::InvalidConfig(format!("Invalid hex digit pair: {pair}")))?;
    bytes.push(byte);
  }

  if bytes.len() > MAX_MESSAGE_BYTES {
    return Err(ReqeastError::InvalidConfig(format!(
      "Hex body exceeds {MAX_MESSAGE_BYTES} byte limit"
    )));
  }
  Ok(bytes)
}

/// Encodes a JSON object into protobuf wire bytes for `message_name`.
pub fn json_to_wire(json: &str, pool: &DescriptorPool, message_name: &str) -> Result<Vec<u8>, ReqeastError> {
  if json.len() > MAX_JSON_OUTPUT_BYTES {
    return Err(ReqeastError::InvalidConfig(format!(
      "JSON input exceeds {MAX_JSON_OUTPUT_BYTES} byte limit"
    )));
  }

  let message_desc = resolve_message_descriptor(pool, message_name)?;
  let mut deserializer = serde_json::Deserializer::from_str(json);
  let options = DeserializeOptions::new();
  let message = DynamicMessage::deserialize_with_options(message_desc, &mut deserializer, &options)
    .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid message JSON: {err}")))?;
  deserializer
    .end()
    .map_err(|err| ReqeastError::InvalidConfig(format!("Invalid message JSON: {err}")))?;

  let wire = message.encode_to_vec();
  if wire.len() > MAX_MESSAGE_BYTES {
    return Err(ReqeastError::InvalidConfig(format!(
      "Encoded message exceeds {MAX_MESSAGE_BYTES} byte limit"
    )));
  }
  Ok(wire)
}

/// Serialize an already-decoded dynamic message to JSON and lowercase hex (no re-decode).
pub(crate) fn message_to_json_and_hex(message: &DynamicMessage) -> (String, String, bool) {
  let wire = message.encode_to_vec();
  let hex = encode_hex(&wire);
  if wire.len() > MAX_MESSAGE_BYTES {
    return (
      format!("Message exceeds {MAX_MESSAGE_BYTES} byte decode limit"),
      hex,
      false,
    );
  }
  let (json, truncated) = message_to_json(message);
  (json, hex, truncated)
}

/// Decodes protobuf wire bytes into JSON and lowercase hex. Returns a truncation flag for JSON output.
///
/// Prefer [`message_to_json_and_hex`] when a `DynamicMessage` is already in hand (avoids re-decode).
/// Kept for wire-only paths and unit tests.
#[allow(dead_code)] // exercised in unit tests; not required on the streaming/unary hot path
pub(crate) fn wire_to_json_and_hex(bytes: &[u8], pool: &DescriptorPool, message_name: &str) -> (String, String, bool) {
  let hex = encode_hex(bytes);

  if bytes.len() > MAX_MESSAGE_BYTES {
    return (
      format!("Message exceeds {MAX_MESSAGE_BYTES} byte decode limit"),
      hex,
      false,
    );
  }

  let message_desc = match resolve_message_descriptor(pool, message_name) {
    Ok(desc) => desc,
    Err(err) => return (err.to_string(), hex, false),
  };

  let message = match DynamicMessage::decode(message_desc, bytes) {
    Ok(msg) => msg,
    Err(err) => return (format!("Failed to decode message: {err}"), hex, false),
  };

  // Reuse JSON serialization (hex already computed from the original wire).
  let (json, truncated) = message_to_json(&message);
  (json, hex, truncated)
}

fn resolve_message_descriptor(pool: &DescriptorPool, message_name: &str) -> Result<MessageDescriptor, ReqeastError> {
  pool
    .get_message_by_name(message_name)
    .or_else(|| alternate_message_name(message_name).and_then(|alt| pool.get_message_by_name(&alt)))
    .ok_or_else(|| ReqeastError::InvalidConfig(format!("Unknown message type: {message_name}")))
}

fn alternate_message_name(message_name: &str) -> Option<String> {
  if let Some(stripped) = message_name.strip_prefix('.') {
    Some(stripped.to_owned())
  } else {
    Some(format!(".{message_name}"))
  }
}

fn message_to_json(message: &DynamicMessage) -> (String, bool) {
  let mut buffer = Vec::new();
  let mut serializer = serde_json::Serializer::new(&mut buffer);
  let options = SerializeOptions::new();
  if let Err(err) = message.serialize_with_options(&mut serializer, &options) {
    return (format!("Failed to serialize message: {err}"), false);
  }
  truncate_json_output(serializer.into_inner())
}

fn truncate_json_output(bytes: &[u8]) -> (String, bool) {
  if bytes.len() <= MAX_JSON_OUTPUT_BYTES {
    return (String::from_utf8_lossy(bytes).into_owned(), false);
  }

  let mut end = MAX_JSON_OUTPUT_BYTES;
  while end > 0 && std::str::from_utf8(&bytes[..end]).is_err() {
    end -= 1;
  }

  let mut json = String::from_utf8_lossy(&bytes[..end]).into_owned();
  json.push_str(&format!("\n... [output truncated after {end} bytes]"));
  (json, true)
}

fn encode_hex(bytes: &[u8]) -> String {
  bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
  use prost_reflect::DescriptorPool;
  use prost_types::FileDescriptorSet;

  use super::*;
  use crate::grpc::schema::compile_proto_bundle;

  fn hello_pool() -> DescriptorPool {
    let root = env!("CARGO_MANIFEST_DIR");
    let bundle =
      compile_proto_bundle(format!("{root}/tests/fixtures/grpc"), vec!["hello.proto".into()]).expect("compile");
    let set = FileDescriptorSet::decode(bundle.descriptor_bytes.as_slice()).expect("decode set");
    DescriptorPool::from_file_descriptor_set(set).expect("pool")
  }

  #[test]
  fn json_round_trip_hello_request() {
    let pool = hello_pool();
    let wire = json_to_wire(r#"{"name":"Reqeast"}"#, &pool, ".helloworld.HelloRequest").unwrap();
    let (json, hex, truncated) = wire_to_json_and_hex(&wire, &pool, ".helloworld.HelloRequest");
    assert!(json.contains("Reqeast"));
    assert!(!hex.is_empty());
    assert!(!truncated);

    let message = DynamicMessage::decode(
      pool.get_message_by_name(".helloworld.HelloRequest").expect("desc"),
      wire.as_slice(),
    )
    .expect("decode");
    let (json2, hex2, truncated2) = message_to_json_and_hex(&message);
    assert_eq!(json, json2);
    assert_eq!(hex, hex2);
    assert_eq!(truncated, truncated2);
  }

  #[test]
  fn encoded_message_exceeding_limit_is_rejected() {
    let pool = hello_pool();
    let oversized = "a".repeat(MAX_MESSAGE_BYTES + 1);
    let err = json_to_wire(
      &format!(r#"{{"name":"{oversized}"}}"#),
      &pool,
      ".helloworld.HelloRequest",
    )
    .unwrap_err();
    assert!(matches!(err, ReqeastError::InvalidConfig(_)));
  }

  #[test]
  fn hex_to_wire_parses_spaced_hex() {
    let wire = hex_to_wire_str("0a 03 66 6f 6f").expect("hex");
    assert_eq!(wire, vec![0x0a, 0x03, 0x66, 0x6f, 0x6f]);
  }

  #[test]
  fn hex_to_wire_rejects_odd_digit_count() {
    let err = hex_to_wire_str("abc").unwrap_err();
    assert!(matches!(err, ReqeastError::InvalidConfig(_)));
  }

  #[test]
  fn json_output_truncation_adds_marker() {
    let pool = hello_pool();
    let wire = json_to_wire(r#"{"name":"x"}"#, &pool, ".helloworld.HelloRequest").unwrap();
    let (json, _hex, truncated) = wire_to_json_and_hex(&wire, &pool, ".helloworld.HelloRequest");
    assert!(!truncated);
    assert!(!json.contains("truncated"));

    let (json, _hex, truncated) =
      wire_to_json_and_hex(&[0u8; MAX_JSON_OUTPUT_BYTES + 1], &pool, ".helloworld.HelloRequest");
    assert!(!truncated);
    assert!(json.contains("decode limit"));
  }
}
