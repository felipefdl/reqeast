#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HttpVersion {
  Auto,
  Http1,
  Http2,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HttpMethod {
  Get,
  Post,
  Put,
  Patch,
  Delete,
  Head,
  Options,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct MultipartField {
  pub name: String,
  pub value: Vec<u8>,
  pub file_name: Option<String>,
  pub content_type: Option<String>,
  pub is_file: bool,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum HttpBody {
  None,
  Json { content: String },
  FormUrlencoded { fields: Vec<KeyValuePair> },
  Raw { content: String, content_type: String },
  Binary { data: Vec<u8>, content_type: String },
  Multipart { fields: Vec<MultipartField> },
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct KeyValuePair {
  pub key: String,
  pub value: String,
  pub enabled: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HttpCookie {
  pub name: String,
  pub value: String,
  pub domain: String,
  pub path: String,
  pub expires: Option<String>,
  pub http_only: bool,
  pub secure: bool,
  pub same_site: Option<String>,
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn http_method_clone_and_eq() {
    let method = HttpMethod::Get;
    let cloned = method;
    assert_eq!(method, cloned);
  }

  #[test]
  fn http_body_none_variant() {
    let body = HttpBody::None;
    matches!(body, HttpBody::None);
  }

  #[test]
  fn http_body_json_carries_content() {
    let body = HttpBody::Json {
      content: r#"{"key": "value"}"#.into(),
    };
    if let HttpBody::Json { content } = body {
      assert!(content.contains("key"));
    } else {
      panic!("expected Json variant");
    }
  }

  #[test]
  fn key_value_pair_equality() {
    let a = KeyValuePair {
      key: "Content-Type".into(),
      value: "application/json".into(),
      enabled: true,
    };
    let b = a.clone();
    assert_eq!(a, b);
  }

  #[test]
  fn http_body_form_urlencoded_carries_fields() {
    let body = HttpBody::FormUrlencoded {
      fields: vec![
        KeyValuePair {
          key: "name".into(),
          value: "test".into(),
          enabled: true,
        },
        KeyValuePair {
          key: "disabled".into(),
          value: "skip".into(),
          enabled: false,
        },
      ],
    };
    if let HttpBody::FormUrlencoded { fields } = body {
      assert_eq!(fields.len(), 2);
      assert!(fields[0].enabled);
      assert!(!fields[1].enabled);
    } else {
      panic!("expected FormUrlencoded variant");
    }
  }
}
