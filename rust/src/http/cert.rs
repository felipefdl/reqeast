use x509_parser::prelude::*;

pub(crate) struct CertInfo {
  pub subject_cn: Option<String>,
  pub issuer_cn: Option<String>,
  pub valid_until: Option<String>,
}

pub(crate) fn parse_certificate(der: &[u8]) -> Option<CertInfo> {
  let (_, cert) = X509Certificate::from_der(der).ok()?;

  let subject_cn = cert
    .subject()
    .iter_common_name()
    .next()
    .and_then(|cn| cn.as_str().ok())
    .map(|s| s.to_string());

  let issuer_cn = cert
    .issuer()
    .iter_common_name()
    .next()
    .and_then(|cn| cn.as_str().ok())
    .map(|s| s.to_string());

  let valid_until = Some(
    cert
      .validity()
      .not_after
      .to_rfc2822()
      .unwrap_or_else(|_| format!("{}", cert.validity().not_after)),
  );

  Some(CertInfo {
    subject_cn,
    issuer_cn,
    valid_until,
  })
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn parse_certificate_invalid_der() {
    let garbage = b"this is not valid DER data at all";
    assert!(parse_certificate(garbage).is_none());
  }

  #[test]
  fn parse_certificate_empty_input() {
    assert!(parse_certificate(b"").is_none());
  }
}
