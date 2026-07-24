use tonic::Code;

use crate::error::{map_connect_error, ReqeastError};

/// Map a tonic gRPC status to `ReqeastError` for FFI callers.
pub(crate) fn map_grpc_status(status: tonic::Status) -> ReqeastError {
  let message = format_grpc_status_message(&status);
  match status.code() {
    Code::DeadlineExceeded | Code::Cancelled => ReqeastError::Timeout(message),
    Code::Unavailable => ReqeastError::ConnectionFailed(message),
    Code::NotFound | Code::Unimplemented if is_reflection_status(&status) => {
      ReqeastError::InvalidConfig(message)
    }
    Code::InvalidArgument
    | Code::FailedPrecondition
    | Code::OutOfRange
    | Code::AlreadyExists
    | Code::NotFound
    | Code::Unimplemented
    | Code::Unauthenticated
    | Code::PermissionDenied => ReqeastError::InvalidConfig(message),
    Code::ResourceExhausted => ReqeastError::InvalidConfig(message),
    _ => ReqeastError::InternalError(message),
  }
}

/// Map tonic transport errors (connect, TLS, DNS) to `ReqeastError`.
pub(crate) fn map_transport_error(err: tonic::transport::Error) -> ReqeastError {
  map_connect_error(&err)
}

fn format_grpc_status_message(status: &tonic::Status) -> String {
  let code = status.code();
  let grpc_message = status.message();
  let mut parts = vec![format!("grpc-status: {}", code as i32)];
  if !grpc_message.is_empty() {
    parts.push(format!("grpc-message: {grpc_message}"));
  }
  if !status.details().is_empty() {
    parts.push(format!("details: {}", format_status_details(status.details())));
  }
  parts.join("; ")
}

fn format_status_details(details: &[u8]) -> String {
  String::from_utf8_lossy(details).into_owned()
}

fn is_reflection_status(status: &tonic::Status) -> bool {
  let message = status.message().to_ascii_lowercase();
  message.contains("reflection")
    || message.contains("serverreflection")
    || message.contains("grpc.reflection")
}

#[cfg(test)]
mod tests {
  use super::*;
  use tonic::transport::Endpoint;
  use tonic::Code;

  #[test]
  fn deadline_exceeded_maps_to_timeout() {
    let status = tonic::Status::deadline_exceeded("timeout");
    let err = map_grpc_status(status);
    assert!(matches!(err, ReqeastError::Timeout { .. }));
    assert!(format!("{err}").contains("grpc-status: 4"));
    assert!(format!("{err}").contains("grpc-message: timeout"));
  }

  #[test]
  fn unavailable_maps_to_connection_failed() {
    let status = tonic::Status::unavailable("server down");
    let err = map_grpc_status(status);
    assert!(matches!(err, ReqeastError::ConnectionFailed { .. }));
  }

  #[test]
  fn reflection_not_found_maps_to_invalid_config() {
    let status = tonic::Status::new(Code::NotFound, "grpc.reflection service not found");
    let err = map_grpc_status(status);
    assert!(matches!(err, ReqeastError::InvalidConfig { .. }));
  }

  #[test]
  fn unimplemented_reflection_maps_to_invalid_config() {
    let status = tonic::Status::new(Code::Unimplemented, "ServerReflection unimplemented");
    let err = map_grpc_status(status);
    assert!(matches!(err, ReqeastError::InvalidConfig { .. }));
  }

  #[test]
  fn invalid_argument_maps_to_invalid_config() {
    let status = tonic::Status::invalid_argument("bad field");
    let err = map_grpc_status(status);
    assert!(matches!(err, ReqeastError::InvalidConfig { .. }));
  }

  #[test]
  fn internal_maps_to_internal_error() {
    let status = tonic::Status::internal("boom");
    let err = map_grpc_status(status);
    assert!(matches!(err, ReqeastError::InternalError { .. }));
  }

  #[test]
  fn transport_invalid_uri_maps_via_connect_classifier() {
    let transport_err = Endpoint::from_shared("http://").unwrap_err();
    let err = map_transport_error(transport_err);
    assert!(matches!(
      err,
      ReqeastError::ConnectionFailed { .. } | ReqeastError::InvalidConfig { .. }
    ));
  }
}