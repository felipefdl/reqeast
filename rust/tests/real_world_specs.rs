use std::path::Path;

use reqeast_core::spec_import::golden::fixture_input_path;
use reqeast_core::spec_import::types::{SpecParseOptions, SpecSourceHint, parse_spec};

struct RealWorldFixture {
  name: &'static str,
  title: &'static str,
  version: Option<&'static str>,
  icon_url: Option<&'static str>,
  min_operations: usize,
}

const FIXTURES: &[RealWorldFixture] = &[
  RealWorldFixture {
    name: "1global-connect-api",
    title: "1GLOBAL Connect API",
    version: Some("2026-02-05"),
    icon_url: Some("https://docs.connect.1global.com/img/logo.svg"),
    min_operations: 91,
  },
  RealWorldFixture {
    name: "tagoio-api",
    title: "TagoIO API",
    version: Some("1.0.0"),
    icon_url: None,
    min_operations: 107,
  },
  RealWorldFixture {
    name: "tdeploy-api",
    title: "TagoIO Deploy API",
    version: Some("1.0.0"),
    icon_url: None,
    min_operations: 5,
  },
  RealWorldFixture {
    name: "slack-api",
    title: "Slack Web API",
    version: None,
    icon_url: None,
    min_operations: 100,
  },
  RealWorldFixture {
    name: "twilio-api",
    title: "Twilio - Api",
    version: None,
    icon_url: None,
    min_operations: 100,
  },
  RealWorldFixture {
    name: "notion-api",
    title: "Notion API",
    version: None,
    icon_url: None,
    min_operations: 10,
  },
  RealWorldFixture {
    name: "kubernetes-api",
    title: "Kubernetes",
    version: None,
    icon_url: None,
    min_operations: 500,
  },
  RealWorldFixture {
    name: "box-api",
    title: "Box Platform API",
    version: None,
    icon_url: None,
    min_operations: 200,
  },
  RealWorldFixture {
    name: "asana-api",
    title: "Asana",
    version: None,
    icon_url: None,
    min_operations: 100,
  },
  RealWorldFixture {
    name: "trello-api",
    title: "Trello",
    version: None,
    icon_url: None,
    min_operations: 200,
  },
  RealWorldFixture {
    name: "httpbin-api",
    title: "httpbin.org",
    version: None,
    icon_url: None,
    min_operations: 50,
  },
  RealWorldFixture {
    name: "circleci-api",
    title: "CircleCI REST API",
    version: None,
    icon_url: None,
    min_operations: 10,
  },
  RealWorldFixture {
    name: "launchdarkly-api",
    title: "LaunchDarkly REST API",
    version: None,
    icon_url: None,
    min_operations: 50,
  },
  RealWorldFixture {
    name: "iot-account-service",
    title: "IoT Account Service API",
    version: Some("0.0.1"),
    icon_url: None,
    min_operations: 31,
  },
  RealWorldFixture {
    name: "iot-authentication-service",
    title: "Authentication Service API",
    version: Some("0.0.1"),
    icon_url: None,
    min_operations: 2,
  },
  RealWorldFixture {
    name: "iot-authorization-service",
    title: "IoT Authorization Service API",
    version: Some("0.0.1"),
    icon_url: None,
    min_operations: 12,
  },
  RealWorldFixture {
    name: "iot-background-operations-service",
    title: "IoT Background Operations Service API",
    version: Some("0.0.1"),
    icon_url: None,
    min_operations: 10,
  },
  RealWorldFixture {
    name: "iot-order-service",
    title: "IoT Order Service API",
    version: Some("0.0.1"),
    icon_url: None,
    min_operations: 6,
  },
  RealWorldFixture {
    name: "iot-product-catalog-service",
    title: "IoT Product Catalog Service API",
    version: Some("0.0.1"),
    icon_url: None,
    min_operations: 56,
  },
  RealWorldFixture {
    name: "iot-subscription-service",
    title: "IoT Subscription Service API",
    version: Some("0.0.1"),
    icon_url: None,
    min_operations: 55,
  },
];

fn parse_fixture_file(path: &Path) -> reqeast_core::spec_import::types::SpecImportResult {
  let bytes = std::fs::read(path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
  let hint = match path.extension().and_then(|ext| ext.to_str()) {
    Some("json") => SpecSourceHint::Json,
    _ => SpecSourceHint::Yaml,
  };
  parse_spec(bytes, hint, None, SpecParseOptions::default())
    .unwrap_or_else(|err| panic!("parse {}: {err:?}", path.display()))
}

#[test]
fn tagoio_skips_unused_declared_tag_folders() {
  let path = fixture_input_path("tagoio-api");
  let result = parse_fixture_file(&path);

  assert_eq!(result.project.folders.len(), 21);
  let unused_declared_tags: Vec<_> = result
    .warnings
    .iter()
    .filter(|warning| warning.code == "UNUSED_DECLARED_TAG")
    .collect();
  assert_eq!(
    unused_declared_tags.len(),
    3,
    "unexpected skipped declared tags: {:?}",
    unused_declared_tags
  );
  assert!(
    result.project.folders.iter().all(|folder| {
      result
        .project
        .operations
        .iter()
        .any(|operation| operation.folder_id.as_deref() == Some(folder.id.as_str()))
    }),
    "every folder should contain at least one operation"
  );
}

#[test]
fn parse_real_world_openapi_fixtures() {
  for fixture in FIXTURES {
    let path = fixture_input_path(fixture.name);
    let result = parse_fixture_file(&path);

    assert_eq!(
      result.project.title, fixture.title,
      "fixture `{}` title mismatch",
      fixture.name
    );
    if let Some(version) = fixture.version {
      assert_eq!(
        result.project.version.as_deref(),
        Some(version),
        "fixture `{}` version mismatch",
        fixture.name
      );
    }
    if let Some(icon_url) = fixture.icon_url {
      assert_eq!(
        result.project.icon_url.as_deref(),
        Some(icon_url),
        "fixture `{}` icon_url mismatch",
        fixture.name
      );
    }
    assert!(
      result.project.operations.len() >= fixture.min_operations,
      "fixture `{}` expected at least {} operations, got {}",
      fixture.name,
      fixture.min_operations,
      result.project.operations.len()
    );
  }
}