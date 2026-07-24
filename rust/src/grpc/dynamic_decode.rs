//! Decode adapter for `ProstCodec` when using dynamic protobuf messages.
//!
//! `tonic_prost::ProstCodec` requires the decode type to implement `Default`, but
//! `prost_reflect::DynamicMessage` needs a `MessageDescriptor`. This wrapper stores the
//! output descriptor in thread-local storage for the duration of a unary RPC.

use std::cell::RefCell;
use std::sync::OnceLock;

use prost::bytes::{Buf, BufMut};
use prost::encoding::{DecodeContext, WireType};
use prost::{DecodeError, Message};
use prost_reflect::{DescriptorPool, DynamicMessage, MessageDescriptor};
use prost_types::{DescriptorProto, FileDescriptorProto, FileDescriptorSet};

thread_local! {
  static RESPONSE_DESCRIPTOR: RefCell<Option<MessageDescriptor>> = const { RefCell::new(None) };
}

fn set_response_descriptor(descriptor: MessageDescriptor) {
  RESPONSE_DESCRIPTOR.with(|cell| *cell.borrow_mut() = Some(descriptor));
}

fn clear_response_descriptor() {
  RESPONSE_DESCRIPTOR.with(|cell| *cell.borrow_mut() = None);
}

/// Keeps the output message descriptor installed for an entire streaming session.
pub(crate) struct ResponseDescriptorScope {
  _hold: MessageDescriptor,
}

impl ResponseDescriptorScope {
  pub(crate) fn new(descriptor: MessageDescriptor) -> Self {
    set_response_descriptor(descriptor.clone());
    Self { _hold: descriptor }
  }
}

impl Drop for ResponseDescriptorScope {
  fn drop(&mut self) {
    clear_response_descriptor();
  }
}

/// Run `operation` while the output message descriptor is installed for `DynamicDecode`.
#[cfg(test)]
pub(crate) fn with_response_descriptor<R>(descriptor: MessageDescriptor, operation: impl FnOnce() -> R) -> R {
  set_response_descriptor(descriptor);
  let result = operation();
  clear_response_descriptor();
  result
}

/// Run an async `operation` while the output descriptor remains installed through `.await`.
pub(crate) async fn with_response_descriptor_async<R>(
  descriptor: MessageDescriptor,
  operation: impl std::future::Future<Output = R>,
) -> R {
  set_response_descriptor(descriptor);
  let result = operation.await;
  clear_response_descriptor();
  result
}

#[derive(Clone, Debug)]
pub(crate) struct DynamicDecode(DynamicMessage);

impl DynamicDecode {
  pub(crate) fn into_inner(self) -> DynamicMessage {
    self.0
  }
}

impl Default for DynamicDecode {
  fn default() -> Self {
    let descriptor = RESPONSE_DESCRIPTOR.with(|cell| cell.borrow().clone());
    match descriptor {
      Some(descriptor) => DynamicDecode(DynamicMessage::new(descriptor)),
      None => {
        // Programming error (scope not installed). Do not abort the process across UniFFI;
        // return a typed empty fallback so decode/merge fails as a normal Status/error path.
        tracing::error!("response descriptor not set for dynamic gRPC decode; using fallback");
        DynamicDecode(DynamicMessage::new(fallback_response_descriptor()))
      }
    }
  }
}

/// Minimal empty message type used only when `ResponseDescriptorScope` was not installed.
fn fallback_response_descriptor() -> MessageDescriptor {
  static POOL: OnceLock<DescriptorPool> = OnceLock::new();
  let pool = POOL.get_or_init(|| {
    let file = FileDescriptorProto {
      name: Some("reqeast_internal_fallback.proto".into()),
      package: Some("reqeast.internal".into()),
      message_type: vec![DescriptorProto {
        name: Some("UnsetResponseDescriptor".into()),
        ..Default::default()
      }],
      syntax: Some("proto3".into()),
      ..Default::default()
    };
    let set = FileDescriptorSet { file: vec![file] };
    DescriptorPool::from_file_descriptor_set(set)
      .unwrap_or_else(|err| panic!("fallback descriptor pool must be valid: {err}"))
  });
  pool
    .get_message_by_name("reqeast.internal.UnsetResponseDescriptor")
    .or_else(|| pool.get_message_by_name(".reqeast.internal.UnsetResponseDescriptor"))
    .unwrap_or_else(|| panic!("fallback UnsetResponseDescriptor must exist in pool"))
}

impl Message for DynamicDecode {
  fn encode_raw(&self, buf: &mut impl BufMut)
  where
    Self: Sized,
  {
    self.0.encode_raw(buf);
  }

  fn merge_field(
    &mut self,
    tag: u32,
    wire_type: WireType,
    buf: &mut impl Buf,
    ctx: DecodeContext,
  ) -> Result<(), DecodeError>
  where
    Self: Sized,
  {
    self.0.merge_field(tag, wire_type, buf, ctx)
  }

  fn encoded_len(&self) -> usize {
    self.0.encoded_len()
  }

  fn clear(&mut self) {
    self.0.clear();
  }
}
