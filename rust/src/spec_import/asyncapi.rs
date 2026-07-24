//! AsyncAPI 2.x/3.x normalization into the spec import normalized IR.

use std::collections::HashSet;

use serde_json::Value;

use crate::spec_import::fingerprint::{bundle_and_canonicalize, hash_bytes};
use crate::spec_import::normalize::NormalizeOutput;
use crate::spec_import::types::{
  BindingProtocol, NormalizedBinding, NormalizedBody, NormalizedEnvironment, NormalizedKeyValue,
  NormalizedOperation, NormalizedParameter, NormalizedProject, OperationProtocol, ParameterLocation,
  SpecImportError, SpecWarning, ValueSource,
};

const UNSUPPORTED_BINDINGS: &[&str] = &[
  "kafka",
  "amqp",
  "amqp1",
  "mqtt",
  "mqtt5",
  "nats",
  "jms",
  "sns",
  "sqs",
  "stomp",
  "redis",
  "ibmmq",
  "googlepubsub",
  "pulsar",
];

/// Returns true when the JSON value looks like an AsyncAPI document.
pub fn is_asyncapi_document(value: &Value) -> bool {
  value.get("asyncapi").is_some()
    && (value.get("channels").is_some() || value.get("operations").is_some())
}

/// Normalize a parsed AsyncAPI JSON document into [`NormalizedProject`].
pub fn normalize_asyncapi(value: Value) -> Result<NormalizeOutput, SpecImportError> {
  if !is_asyncapi_document(&value) {
    return Err(SpecImportError::UnsupportedFormat(
      "Not an AsyncAPI document".into(),
    ));
  }

  let info = value
    .get("info")
    .ok_or_else(|| SpecImportError::InvalidSpec("AsyncAPI document missing info".into()))?;

  let title = info
    .get("title")
    .and_then(Value::as_str)
    .unwrap_or("Imported AsyncAPI")
    .to_owned();

  let description = info.get("description").and_then(Value::as_str).map(str::to_owned);
  let version = info.get("version").and_then(Value::as_str).map(str::to_owned);

  let mut warnings = Vec::new();
  let mut operations = Vec::new();
  let mut seen_primary_keys = HashSet::new();

  let default_server = default_server_url(&value);
  let asyncapi_version = value
    .get("asyncapi")
    .and_then(Value::as_str)
    .unwrap_or("2.0.0");
  let is_v3 = asyncapi_version.starts_with('3');

  if is_v3 {
    collect_v3_operations(
      &value,
      &default_server,
      &mut operations,
      &mut seen_primary_keys,
      &mut warnings,
    )?;
  } else {
    collect_v2_channels(
      &value,
      &default_server,
      &mut operations,
      &mut seen_primary_keys,
      &mut warnings,
    )?;
  }

  if operations.is_empty() {
    return Err(SpecImportError::InvalidSpec(
      "AsyncAPI document contains no importable HTTP or WebSocket operations".into(),
    ));
  }

  let environments = normalize_servers(&value, &default_server);
  let fingerprint = bundle_and_canonicalize(&value)
    .map(|bytes| hash_bytes(&bytes))
    .map_err(SpecImportError::InvalidSpec)?;

  Ok(NormalizeOutput {
    project: NormalizedProject {
      title,
      description,
      version,
      icon_url: None,
      security_schemes: vec![],
      folders: vec![],
      operations,
      environments,
    },
    warnings,
    content_fingerprint: fingerprint,
  })
}

fn collect_v2_channels(
  value: &Value,
  default_server: &str,
  operations: &mut Vec<NormalizedOperation>,
  seen_primary_keys: &mut HashSet<String>,
  warnings: &mut Vec<SpecWarning>,
) -> Result<(), SpecImportError> {
  let Some(channels) = value.get("channels").and_then(Value::as_object) else {
    return Ok(());
  };

  for (channel_name, channel) in channels {
    let channel_bindings = channel.get("bindings").and_then(Value::as_object);
    if let Some(binding_name) = unsupported_binding_name(channel_bindings) {
      push_unsupported_binding_warning(warnings, &binding_name, channel_name);
      continue;
    }

    let protocol = detect_channel_protocol(channel_bindings, default_server);
    match protocol {
      ChannelProtocol::Http => {
        let http_binding = channel_bindings.and_then(|bindings| bindings.get("http"));
        let method = http_method(http_binding, "GET");
        let path = channel_path(channel_name, channel);
        let op_ref = format!("{method} {path}");

        if let Some(publish) = channel.get("publish") {
          push_http_operation(
            operations,
            seen_primary_keys,
            channel_name,
            channel,
            publish,
            &method,
            &path,
            &op_ref,
            "publish",
            message_body(publish.get("message")),
            None,
          )?;
        }

        if let Some(subscribe) = channel.get("subscribe") {
          let subscribe_method = if method == "GET" {
            "GET".to_owned()
          } else {
            method.clone()
          };
          let subscribe_ref = format!("{subscribe_method} {path}");
          push_http_operation(
            operations,
            seen_primary_keys,
            channel_name,
            channel,
            subscribe,
            &subscribe_method,
            &path,
            &subscribe_ref,
            "subscribe",
            NormalizedBody::None,
            Some("subscribe"),
          )?;
        }

        if channel.get("publish").is_none() && channel.get("subscribe").is_none() {
          push_http_operation(
            operations,
            seen_primary_keys,
            channel_name,
            channel,
            channel,
            &method,
            &path,
            &op_ref,
            "channel",
            NormalizedBody::None,
            None,
          )?;
        }
      }
      ChannelProtocol::WebSocket => {
        let address = websocket_address(channel_name, channel, default_server);
        for (operation_type, operation) in [
          ("publish", channel.get("publish")),
          ("subscribe", channel.get("subscribe")),
        ] {
          let Some(operation) = operation else { continue };
          push_websocket_operation(
            operations,
            seen_primary_keys,
            channel_name,
            channel,
            operation,
            operation_type,
            &address,
          )?;
        }

        if channel.get("publish").is_none() && channel.get("subscribe").is_none() {
          push_websocket_operation(
            operations,
            seen_primary_keys,
            channel_name,
            channel,
            channel,
            "channel",
            &address,
          )?;
        }
      }
      ChannelProtocol::Unsupported(binding) => {
        push_unsupported_binding_warning(warnings, &binding, channel_name);
      }
    }
  }

  Ok(())
}

fn collect_v3_operations(
  value: &Value,
  default_server: &str,
  operations: &mut Vec<NormalizedOperation>,
  seen_primary_keys: &mut HashSet<String>,
  warnings: &mut Vec<SpecWarning>,
) -> Result<(), SpecImportError> {
  let channels = value.get("channels").and_then(Value::as_object);
  let Some(operations_obj) = value.get("operations").and_then(Value::as_object) else {
    return Ok(());
  };

  for (operation_name, operation) in operations_obj {
    let channel_ref = operation
      .get("channel")
      .and_then(channel_reference)
      .unwrap_or_else(|| operation_name.clone());
    let channel = channels
      .and_then(|map| map.get(&channel_ref))
      .or_else(|| channels.and_then(|map| map.get(operation_name)));

    let channel_bindings = channel
      .and_then(|ch| ch.get("bindings"))
      .and_then(Value::as_object)
      .or_else(|| operation.get("bindings").and_then(Value::as_object));

    if let Some(binding_name) = unsupported_binding_name(channel_bindings) {
      push_unsupported_binding_warning(warnings, &binding_name, operation_name);
      continue;
    }

    let action = operation
      .get("action")
      .and_then(Value::as_str)
      .unwrap_or("send");
    let operation_type = match action {
      "receive" => "subscribe",
      _ => "publish",
    };

    let protocol = detect_channel_protocol(channel_bindings, default_server);
    match protocol {
      ChannelProtocol::Http => {
        let http_binding = channel_bindings.and_then(|bindings| bindings.get("http"));
        let method = http_method(http_binding, "POST");
        let path = channel
          .map(|ch| channel_path(&channel_ref, ch))
          .unwrap_or_else(|| normalize_channel_path(&channel_ref));
        let op_ref = format!("{method} {path}");
        let message = operation
          .get("messages")
          .and_then(|messages| messages.as_array())
          .and_then(|messages| messages.first())
          .or_else(|| channel.and_then(|ch| ch.get("messages")).and_then(first_message_from_messages));
        let body = message_body(message);
        push_http_operation(
          operations,
          seen_primary_keys,
          &channel_ref,
          channel.unwrap_or(operation),
          operation,
          &method,
          &path,
          &op_ref,
          operation_type,
          body,
          Some(operation_name),
        )?;
      }
      ChannelProtocol::WebSocket => {
        let address = channel
          .map(|ch| websocket_address(&channel_ref, ch, default_server))
          .unwrap_or_else(|| join_server_and_path(default_server, &channel_ref));
        push_websocket_operation(
          operations,
          seen_primary_keys,
          &channel_ref,
          channel.unwrap_or(operation),
          operation,
          operation_type,
          &address,
        )?;
      }
      ChannelProtocol::Unsupported(binding) => {
        push_unsupported_binding_warning(warnings, &binding, operation_name);
      }
    }
  }

  Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum ChannelProtocol {
  Http,
  WebSocket,
  Unsupported(String),
}

fn detect_channel_protocol(
  bindings: Option<&serde_json::Map<String, Value>>,
  default_server: &str,
) -> ChannelProtocol {
  if let Some(bindings) = bindings {
    if bindings.contains_key("http") {
      return ChannelProtocol::Http;
    }
    if bindings.contains_key("ws") || bindings.contains_key("wss") {
      return ChannelProtocol::WebSocket;
    }
    for binding in UNSUPPORTED_BINDINGS {
      if bindings.contains_key(*binding) {
        return ChannelProtocol::Unsupported(binding.to_string());
      }
    }
  }

  if default_server.starts_with("ws://") || default_server.starts_with("wss://") {
    return ChannelProtocol::WebSocket;
  }

  ChannelProtocol::Http
}

fn unsupported_binding_name(bindings: Option<&serde_json::Map<String, Value>>) -> Option<String> {
  let bindings = bindings?;
  for binding in UNSUPPORTED_BINDINGS {
    if bindings.contains_key(*binding) {
      return Some(binding.to_string());
    }
  }
  None
}

fn push_unsupported_binding_warning(warnings: &mut Vec<SpecWarning>, binding: &str, channel: &str) {
  warnings.push(SpecWarning {
    code: "UNSUPPORTED_BINDING".into(),
    message: format!("Unsupported AsyncAPI binding `{binding}` on channel `{channel}`; operation skipped"),
    operation_ref: Some(channel.into()),
  });
}

#[allow(clippy::too_many_arguments)]
fn push_http_operation(
  operations: &mut Vec<NormalizedOperation>,
  seen_primary_keys: &mut HashSet<String>,
  channel_name: &str,
  channel: &Value,
  operation: &Value,
  method: &str,
  path: &str,
  op_ref: &str,
  operation_type: &str,
  body: NormalizedBody,
  fallback_name: Option<&str>,
) -> Result<(), SpecImportError> {
  let primary_key = operation
    .get("operationId")
    .and_then(Value::as_str)
    .map(str::to_owned)
    .unwrap_or_else(|| format!("{method} {path}"));

  if !seen_primary_keys.insert(primary_key.clone()) {
    return Err(SpecImportError::InvalidSpec(format!(
      "Duplicate AsyncAPI operation key `{primary_key}`"
    )));
  }

  let name = operation
    .get("summary")
    .or_else(|| operation.get("title"))
    .and_then(Value::as_str)
    .or_else(|| channel.get("description").and_then(Value::as_str))
    .or(fallback_name)
    .unwrap_or(channel_name)
    .to_owned();

  let message_template = message_template_from_body(&body);
  let binding = NormalizedBinding {
    protocol: BindingProtocol::Http,
    address: path.to_owned(),
    operation_type: operation_type.to_owned(),
    message_template,
  };

  operations.push(NormalizedOperation {
    primary_key,
    alternate_keys: vec![],
    name,
    method: method.to_owned(),
    path: path.to_owned(),
    deprecated: false,
    tags: operation_tags(operation, channel_name),
    protocol: OperationProtocol::Http,
    binding: Some(binding),
    folder_id: None,
    parameters: normalize_http_parameters(operation, channel),
    body,
    body_candidates: vec![],
    auth: None,
    description: channel.get("description").and_then(Value::as_str).map(str::to_owned),
  });

  let _ = op_ref;
  Ok(())
}

fn push_websocket_operation(
  operations: &mut Vec<NormalizedOperation>,
  seen_primary_keys: &mut HashSet<String>,
  channel_name: &str,
  channel: &Value,
  operation: &Value,
  operation_type: &str,
  address: &str,
) -> Result<(), SpecImportError> {
  let method = operation_type.to_ascii_uppercase();
  let primary_key = operation
    .get("operationId")
    .and_then(Value::as_str)
    .map(str::to_owned)
    .unwrap_or_else(|| format!("{method} {address}"));

  if !seen_primary_keys.insert(primary_key.clone()) {
    return Err(SpecImportError::InvalidSpec(format!(
      "Duplicate AsyncAPI operation key `{primary_key}`"
    )));
  }

  let name = operation
    .get("summary")
    .or_else(|| operation.get("title"))
    .and_then(Value::as_str)
    .or_else(|| channel.get("description").and_then(Value::as_str))
    .unwrap_or(channel_name)
    .to_owned();

  let message = operation.get("message").or_else(|| {
    operation
      .get("messages")
      .and_then(|messages| messages.as_array())
      .and_then(|messages| messages.first())
  });
  let body = message_body(message);
  let message_template = message_template_from_body(&body);

  let binding = NormalizedBinding {
    protocol: BindingProtocol::WebSocket,
    address: address.to_owned(),
    operation_type: operation_type.to_owned(),
    message_template,
  };

  operations.push(NormalizedOperation {
    primary_key,
    alternate_keys: vec![],
    name,
    method,
    path: address.to_owned(),
    deprecated: false,
    tags: operation_tags(operation, channel_name),
    protocol: OperationProtocol::WebSocket,
    binding: Some(binding),
    folder_id: None,
    parameters: vec![],
    body,
    body_candidates: vec![],
    auth: None,
    description: channel.get("description").and_then(Value::as_str).map(str::to_owned),
  });

  Ok(())
}

fn operation_tags(operation: &Value, channel_name: &str) -> Vec<String> {
  if let Some(tags) = operation.get("tags").and_then(Value::as_array) {
    let values = tags
      .iter()
      .filter_map(Value::as_str)
      .map(str::to_owned)
      .collect::<Vec<_>>();
    if !values.is_empty() {
      return values;
    }
  }

  vec![channel_name.to_owned()]
}

fn normalize_http_parameters(operation: &Value, channel: &Value) -> Vec<NormalizedParameter> {
  let mut parameters = Vec::new();
  let http_binding = channel
    .get("bindings")
    .and_then(|bindings| bindings.get("http"));

  if let Some(Value::Object(fields)) = http_binding
    .and_then(|binding| binding.get("query"))
    .and_then(schema_example)
  {
    for (name, value) in fields {
      parameters.push(NormalizedParameter {
        location: ParameterLocation::Query,
        name: name.clone(),
        value: json_scalar_to_string(&value),
        required: false,
        enabled: false,
        value_source: ValueSource::FromExample,
      });
    }
  }

  if let Some(Value::Object(fields)) = operation
    .get("bindings")
    .and_then(|bindings| bindings.get("http"))
    .and_then(|binding| binding.get("headers"))
    .and_then(schema_example)
    .or_else(|| {
      http_binding
        .and_then(|binding| binding.get("headers"))
        .and_then(schema_example)
    })
  {
    for (name, value) in fields {
      parameters.push(NormalizedParameter {
        location: ParameterLocation::Header,
        name: name.clone(),
        value: json_scalar_to_string(&value),
        required: false,
        enabled: false,
        value_source: ValueSource::FromExample,
      });
    }
  }

  parameters
}

fn message_body(message: Option<&Value>) -> NormalizedBody {
  let Some(message) = message else {
    return NormalizedBody::None;
  };

  let payload = message.get("payload").or_else(|| message.get("schema"));
  let Some(example) = payload.and_then(schema_example) else {
    return NormalizedBody::None;
  };

  match serde_json::to_string_pretty(&example) {
    Ok(content) => NormalizedBody::Json { content },
    Err(_) => NormalizedBody::None,
  }
}

fn message_template_from_body(body: &NormalizedBody) -> String {
  match body {
    NormalizedBody::Json { content } => content.clone(),
    NormalizedBody::Raw { content, .. } => content.clone(),
    _ => String::new(),
  }
}

fn schema_example(schema: &Value) -> Option<Value> {
  if let Some(example) = schema.get("example") {
    return Some(example.clone());
  }
  if let Some(example) = schema
    .get("examples")
    .and_then(Value::as_array)
    .and_then(|examples| examples.first())
  {
    return Some(example.clone());
  }

  let properties = schema.get("properties").and_then(Value::as_object)?;
  let mut object = serde_json::Map::new();
  for (key, property) in properties {
    if let Some(example) = property.get("example").or_else(|| property.get("default")) {
      object.insert(key.clone(), example.clone());
    }
  }
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn json_scalar_to_string(value: &Value) -> String {
  match value {
    Value::String(text) => text.clone(),
    Value::Number(number) => number.to_string(),
    Value::Bool(flag) => flag.to_string(),
    other => other.to_string(),
  }
}

fn http_method(http_binding: Option<&Value>, fallback: &str) -> String {
  http_binding
    .and_then(|binding| binding.get("method"))
    .and_then(Value::as_str)
    .unwrap_or(fallback)
    .to_ascii_uppercase()
}

fn channel_path(channel_name: &str, channel: &Value) -> String {
  channel
    .get("address")
    .and_then(Value::as_str)
    .map(normalize_channel_path)
    .unwrap_or_else(|| normalize_channel_path(channel_name))
}

fn normalize_channel_path(path: &str) -> String {
  if path.starts_with("http://")
    || path.starts_with("https://")
    || path.starts_with("ws://")
    || path.starts_with("wss://")
  {
    return path.to_owned();
  }

  let trimmed = path.trim_start_matches('/');
  if trimmed.is_empty() {
    "/".into()
  } else {
    format!("/{trimmed}")
  }
}

fn websocket_address(channel_name: &str, channel: &Value, default_server: &str) -> String {
  if let Some(address) = channel.get("address").and_then(Value::as_str) {
    if address.starts_with("ws://") || address.starts_with("wss://") {
      return address.to_owned();
    }
    return join_server_and_path(default_server, address);
  }

  join_server_and_path(default_server, channel_name)
}

fn join_server_and_path(server: &str, path: &str) -> String {
  if path.starts_with("ws://") || path.starts_with("wss://") {
    return path.to_owned();
  }

  let server = server.trim_end_matches('/');
  let path = normalize_channel_path(path);
  format!("{server}{path}")
}

fn default_server_url(value: &Value) -> String {
  let Some(servers) = value.get("servers").and_then(Value::as_object) else {
    return "/".into();
  };

  let Some((_, server)) = servers.iter().next() else {
    return "/".into();
  };

  let url = server.get("url").and_then(Value::as_str).unwrap_or("/");
  let protocol = server.get("protocol").and_then(Value::as_str).unwrap_or("");

  if url.starts_with("http://")
    || url.starts_with("https://")
    || url.starts_with("ws://")
    || url.starts_with("wss://")
  {
    return url.to_owned();
  }

  match protocol {
    "https" | "http" => format!("https://{url}"),
    "wss" | "ws" => format!("wss://{url}"),
    "kafka" | "amqp" | "mqtt" => url.to_owned(),
    _ if protocol.contains("websocket") => format!("wss://{url}"),
    _ => url.to_owned(),
  }
}

fn normalize_servers(value: &Value, default_server: &str) -> Vec<NormalizedEnvironment> {
  let Some(servers) = value.get("servers").and_then(Value::as_object) else {
    return vec![NormalizedEnvironment {
      name: "Default".into(),
      variables: vec![NormalizedKeyValue {
        key: "base_url".into(),
        value: default_server.to_owned(),
        enabled: true,
      }],
    }];
  };

  servers
    .iter()
    .enumerate()
    .map(|(index, (name, server))| {
      let description = server.get("description").and_then(Value::as_str);
      let env_name = description
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
        .unwrap_or_else(|| name.to_owned());

      let url = server.get("url").and_then(Value::as_str).unwrap_or(default_server);
      let protocol = server.get("protocol").and_then(Value::as_str).unwrap_or("");
      let base_url = if url.starts_with("http://")
        || url.starts_with("https://")
        || url.starts_with("ws://")
        || url.starts_with("wss://")
      {
        url.to_owned()
      } else {
        match protocol {
          "https" | "http" => format!("https://{url}"),
          "wss" | "ws" => format!("wss://{url}"),
          _ => url.to_owned(),
        }
      };

      let variable_key = if base_url.starts_with("ws://") || base_url.starts_with("wss://") {
        "ws_url"
      } else {
        "base_url"
      };

      NormalizedEnvironment {
        name: if env_name.is_empty() {
          format!("Server {}", index + 1)
        } else {
          env_name
        },
        variables: vec![NormalizedKeyValue {
          key: variable_key.into(),
          value: base_url,
          enabled: true,
        }],
      }
    })
    .collect()
}

fn channel_reference(channel: &Value) -> Option<String> {
  if let Some(text) = channel.as_str() {
    return Some(text.rsplit('/').next_back()?.to_owned());
  }

  channel
    .get("$ref")
    .and_then(Value::as_str)
    .and_then(|reference| reference.rsplit('/').next())
    .map(str::to_owned)
}

fn first_message_from_messages(messages: &Value) -> Option<&Value> {
  if let Some(array) = messages.as_array() {
    return array.first();
  }

  messages.as_object().and_then(|map| map.values().next())
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::spec_import::types::{SpecSourceHint, parse_spec};

  #[test]
  fn detects_asyncapi_document() {
    let value = serde_json::json!({
      "asyncapi": "2.6.0",
      "channels": {}
    });
    assert!(is_asyncapi_document(&value));
  }

  #[test]
  fn normalizes_http_channel() {
    let spec = serde_json::json!({
      "asyncapi": "2.6.0",
      "info": { "title": "HTTP API", "version": "1.0.0" },
      "servers": {
        "production": {
          "url": "api.example.com/v1",
          "protocol": "https"
        }
      },
      "channels": {
        "/users": {
          "bindings": {
            "http": { "method": "GET", "type": "request" }
          },
          "subscribe": {
            "message": {
              "payload": { "type": "array" }
            }
          }
        },
        "/users/create": {
          "bindings": {
            "http": { "method": "POST", "type": "request" }
          },
          "publish": {
            "operationId": "createUser",
            "message": {
              "payload": {
                "type": "object",
                "example": { "name": "Ada" }
              }
            }
          }
        },
        "events/orders": {
          "bindings": { "kafka": { "bindingVersion": "0.4.0" } },
          "publish": {
            "message": { "payload": { "type": "object" } }
          }
        }
      }
    });

    let result = normalize_asyncapi(spec).expect("normalize");
    assert_eq!(result.project.title, "HTTP API");
    assert_eq!(result.project.operations.len(), 2);
    assert!(result.project.operations.iter().any(|op| op.primary_key == "GET /users"));
    assert!(result.project.operations.iter().any(|op| op.primary_key == "createUser"));
    assert!(result
      .warnings
      .iter()
      .any(|warning| warning.code == "UNSUPPORTED_BINDING"));
  }

  #[test]
  fn normalizes_websocket_channel() {
    let spec = serde_json::json!({
      "asyncapi": "2.6.0",
      "info": { "title": "WS API", "version": "1.0.0" },
      "servers": {
        "production": {
          "url": "echo.websocket.org",
          "protocol": "wss"
        }
      },
      "channels": {
        "/chat": {
          "bindings": { "ws": { "method": "GET" } },
          "publish": {
            "operationId": "sendChatMessage",
            "message": {
              "payload": {
                "type": "object",
                "example": { "text": "hello" }
              }
            }
          }
        }
      }
    });

    let result = normalize_asyncapi(spec).expect("normalize");
    assert_eq!(result.project.operations.len(), 1);
    let operation = &result.project.operations[0];
    assert_eq!(operation.protocol, OperationProtocol::WebSocket);
    assert_eq!(operation.primary_key, "sendChatMessage");
    assert_eq!(operation.path, "wss://echo.websocket.org/chat");
    let binding = operation.binding.as_ref().expect("binding");
    assert_eq!(binding.protocol, BindingProtocol::WebSocket);
    assert!(binding.message_template.contains("hello"));
  }

  #[test]
  fn parse_spec_accepts_asyncapi_fixture_shape() {
    let yaml = r#"
asyncapi: '2.6.0'
info:
  title: AsyncAPI HTTP Demo
  version: '1.0.0'
servers:
  production:
    url: api.example.com/v1
    protocol: https
channels:
  /users:
    bindings:
      http:
        method: GET
        type: request
    subscribe:
      message:
        payload:
          type: array
"#;

    let result = parse_spec(
      yaml.as_bytes().to_vec(),
      SpecSourceHint::Yaml,
      None,
      crate::spec_import::types::SpecParseOptions::default(),
    )
    .expect("parse");
    assert_eq!(result.project.title, "AsyncAPI HTTP Demo");
    assert_eq!(result.project.operations.len(), 1);
  }
}