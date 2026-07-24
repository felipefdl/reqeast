//! Golden fixture tests for `diff_spec` (AC18).

use reqeast_core::spec_import::golden::{assert_or_update_diff_golden, diff_fixtures, update_goldens_enabled};

#[test]
fn spec_import_diff_goldens() {
  for fixture in diff_fixtures::all() {
    let diff = diff_fixtures::run(&fixture);
    assert_or_update_diff_golden(fixture.name, &diff);
  }
}

#[test]
#[ignore = "run via `just update-spec-goldens`"]
fn update_spec_diff_goldens() {
  assert!(update_goldens_enabled(), "set UPDATE_SPEC_GOLDENS=1");
  for fixture in diff_fixtures::all() {
    let diff = diff_fixtures::run(&fixture);
    assert_or_update_diff_golden(fixture.name, &diff);
  }
}
