//! Golden fixture tests for spec import normalization.

use std::fs;

use reqeast_core::spec_import::export_postman::export_input_from_normalized;
use reqeast_core::{
  export_openapi, export_postman, ExportFormat, ExportOpenApiOptions, ExportPostmanOptions,
};
use reqeast_core::spec_import::golden::{
  assert_or_update_error_golden, assert_or_update_success_golden, fixtures_dir, parse_fixture,
  result_to_json, update_goldens_enabled,
};
use reqeast_core::spec_import::types::{SpecParseOptions, SpecSourceHint, parse_spec};

const SUCCESS_FIXTURES: &[&str] = &[
  "petstore-2.0",
  "petstore-3.0",
  "petstore-3.1",
  "stripe-like",
  "servers-multi",
  "auth-schemes",
  "folder-tags",
  "folder-paths",
  "folder-flat",
  "stress-500",
  "postman-nested",
  "postman-vars",
  "insomnia-nested",
  "insomnia-vars",
  "bruno-nested",
  "bruno-vars",
  "bundle-multi-file",
  "har-capture",
  "asyncapi-http",
  "asyncapi-ws",
  "graphql-simple",
  // Recursive schemas are valid OpenAPI (self $ref in properties). Example synthesis
  // stops at the self-ref instead of treating the document as InvalidSpec.
  "cyclic-ref",
];

const ERROR_FIXTURES: &[&str] = &[
  "remote-ref-denied",
  "duplicate-operation-id",
  "billion-laughs",
];

#[test]
fn spec_import_success_goldens() {
  for fixture in SUCCESS_FIXTURES {
    let result = parse_fixture(fixture).unwrap_or_else(|err| {
      panic!("fixture `{fixture}` should parse successfully, got {err:?}");
    });
    assert_or_update_success_golden(fixture, &result);
  }
}

#[test]
fn spec_import_error_goldens() {
  for fixture in ERROR_FIXTURES {
    let err = parse_fixture(fixture).unwrap_err();
    assert_or_update_error_golden(fixture, &err);
  }
}

#[test]
fn petstore_export_round_trip_ac19() {
  for fixture in ["petstore-2.0", "petstore-3.0", "petstore-3.1"] {
    let imported = parse_fixture(fixture).expect("petstore should import");
    let export_input = export_input_from_normalized(&imported.project);
    let exported = export_openapi(
      export_input,
      ExportFormat::Yaml,
      ExportOpenApiOptions::default(),
    )
    .expect("export");

    let roundtrip = parse_spec(
      exported,
      SpecSourceHint::Yaml,
      None,
      SpecParseOptions::default(),
    )
    .expect("re-import");

    let imported_project = result_to_json(&imported).get("project").cloned().expect("project");
    let roundtrip_project = result_to_json(&roundtrip).get("project").cloned().expect("project");
    assert_eq!(imported_project, roundtrip_project, "{fixture} AC19 round-trip mismatch");
  }
}

#[test]
fn postman_nested_export_round_trip_ac20() {
  let imported = parse_fixture("postman-nested").expect("postman-nested should import");
  let export_input = export_input_from_normalized(&imported.project);
  let exported = export_postman(export_input, ExportPostmanOptions::default()).expect("export");
  let roundtrip = parse_spec(
    exported,
    SpecSourceHint::Postman,
    None,
    SpecParseOptions::default(),
  )
  .expect("re-import");

  let imported_project = result_to_json(&imported).get("project").cloned().expect("project");
  let roundtrip_project = result_to_json(&roundtrip).get("project").cloned().expect("project");
  assert_eq!(imported_project, roundtrip_project, "postman-nested AC20 round-trip mismatch");
}

#[test]
fn petstore_json_yaml_parity() {
  for version in ["petstore-2.0", "petstore-3.0", "petstore-3.1"] {
    let yaml = fs::read(fixtures_dir().join(format!("{version}.input.yaml"))).expect("yaml fixture");
    let json = fs::read(fixtures_dir().join(format!("{version}.input.json"))).expect("json fixture");

    let yaml_result = parse_spec(
      yaml,
      SpecSourceHint::Yaml,
      None,
      reqeast_core::spec_import::types::SpecParseOptions::default(),
    )
    .expect("yaml should parse");
    let json_result = parse_spec(
      json,
      SpecSourceHint::Json,
      None,
      reqeast_core::spec_import::types::SpecParseOptions::default(),
    )
    .expect("json should parse");

    assert_eq!(
      result_to_json(&yaml_result),
      result_to_json(&json_result),
      "yaml/json parity failed for {version}"
    );
  }
}

#[test]
#[ignore = "run via `just update-spec-goldens`"]
fn update_spec_goldens() {
  assert!(update_goldens_enabled(), "set UPDATE_SPEC_GOLDENS=1");

  for fixture in SUCCESS_FIXTURES {
    let result = parse_fixture(fixture).expect("success fixture should parse");
    assert_or_update_success_golden(fixture, &result);
  }

  for fixture in ERROR_FIXTURES {
    let err = parse_fixture(fixture).expect_err("error fixture should fail");
    assert_or_update_error_golden(fixture, &err);
  }

  for fixture in reqeast_core::spec_import::golden::diff_fixtures::all() {
    let diff = reqeast_core::spec_import::golden::diff_fixtures::run(&fixture);
    reqeast_core::spec_import::golden::assert_or_update_diff_golden(fixture.name, &diff);
  }
}