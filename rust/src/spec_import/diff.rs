//! Spec-to-spec diff for linked spec sync review (P2).

use std::collections::{HashMap, HashSet};

use crate::spec_import::types::{
  NormalizedBody, NormalizedOperation, NormalizedParameter, NormalizedProject, ParameterLocation,
  SpecImportError,
};

/// Sync-relevant field kinds aligned with Swift `hasLocalModifications` deltas.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SpecSyncField {
  Method,
  Url,
  Params,
  Headers,
  Body,
  Name,
}

/// Per-field change between old and new spec operations.
///
/// `is_conflict` is always `false` from Rust; Swift sets it after snapshot comparison.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SpecFieldDelta {
  pub field: SpecSyncField,
  pub old_value: String,
  pub new_value: String,
  pub is_conflict: bool,
}

/// Links an app request to spec operation identity keys.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SpecOperationBinding {
  pub request_id: String,
  pub primary_key: String,
  pub alternate_keys: Vec<String>,
}

/// Operation matched to an existing linked request.
#[derive(Debug, Clone, uniffi::Record)]
pub struct MatchedOperation {
  pub request_id: String,
  pub primary_key: String,
  pub operation: NormalizedOperation,
}

/// Spec-to-spec changes for a linked request.
#[derive(Debug, Clone, uniffi::Record)]
pub struct OperationDiff {
  pub request_id: String,
  pub primary_key: String,
  pub old_operation: NormalizedOperation,
  pub new_operation: NormalizedOperation,
  pub field_deltas: Vec<SpecFieldDelta>,
}

/// Operation identity key changed while method/path stayed aligned.
#[derive(Debug, Clone, uniffi::Record)]
pub struct IdentityChangeDiff {
  pub request_id: String,
  pub old_primary_key: String,
  pub new_primary_key: String,
  pub old_operation: NormalizedOperation,
  pub new_operation: NormalizedOperation,
  pub field_deltas: Vec<SpecFieldDelta>,
}

/// Full diff between on-disk and fetched normalized spec IR.
#[derive(Debug, Clone, uniffi::Record)]
pub struct SpecSyncDiff {
  pub added: Vec<NormalizedOperation>,
  pub removed: Vec<MatchedOperation>,
  pub modified: Vec<OperationDiff>,
  pub unchanged: Vec<MatchedOperation>,
  pub identity_changed: Vec<IdentityChangeDiff>,
}

/// Options for [`diff_spec`]; reserved for future tuning.
#[derive(Debug, Clone, Default, PartialEq, Eq, uniffi::Record)]
pub struct DiffOptions {}

struct OperationIndex<'a> {
  operations: &'a [NormalizedOperation],
  by_primary: HashMap<String, usize>,
  by_alternate: HashMap<String, usize>,
  by_method_path: HashMap<String, usize>,
}

impl<'a> OperationIndex<'a> {
  fn new(operations: &'a [NormalizedOperation]) -> Self {
    let mut by_primary = HashMap::new();
    let mut by_alternate = HashMap::new();
    let mut by_method_path = HashMap::new();

    for (index, operation) in operations.iter().enumerate() {
      if by_primary.insert(operation.primary_key.clone(), index).is_some() {
        // Duplicate keys are blocked at parse time; keep first match for diff resilience.
      }
      for key in &operation.alternate_keys {
        by_alternate.entry(key.clone()).or_insert(index);
      }
      by_method_path
        .entry(method_path_key(operation))
        .or_insert(index);
    }

    Self {
      operations,
      by_primary,
      by_alternate,
      by_method_path,
    }
  }

  fn lookup_by_keys(&self, primary_key: &str, alternate_keys: &[String]) -> Option<&NormalizedOperation> {
    self
      .lookup_index_by_keys(primary_key, alternate_keys)
      .map(|index| &self.operations[index])
  }

  fn lookup_index_by_keys(&self, primary_key: &str, alternate_keys: &[String]) -> Option<usize> {
    if let Some(index) = self.by_primary.get(primary_key) {
      return Some(*index);
    }
    for key in alternate_keys {
      if let Some(index) = self.by_primary.get(key) {
        return Some(*index);
      }
      if let Some(index) = self.by_alternate.get(key) {
        return Some(*index);
      }
    }
    None
  }

  fn lookup_index_by_method_path(&self, operation: &NormalizedOperation) -> Option<usize> {
    self.by_method_path.get(&method_path_key(operation)).copied()
  }
}

/// Compares two normalized spec snapshots and classifies operation changes.
#[uniffi::export]
pub fn diff_spec(
  old: NormalizedProject,
  new: NormalizedProject,
  bindings: Vec<SpecOperationBinding>,
  _options: DiffOptions,
) -> Result<SpecSyncDiff, SpecImportError> {
  let old_index = OperationIndex::new(&old.operations);
  let new_index = OperationIndex::new(&new.operations);

  let mut added = Vec::new();
  let mut removed = Vec::new();
  let mut modified = Vec::new();
  let mut unchanged = Vec::new();
  let mut identity_changed = Vec::new();
  let mut claimed_new_indices = HashSet::new();

  for binding in bindings {
    let Some(old_operation) = old_index.lookup_by_keys(&binding.primary_key, &binding.alternate_keys) else {
      continue;
    };

    let new_match = new_index
      .lookup_index_by_keys(&binding.primary_key, &binding.alternate_keys)
      .or_else(|| new_index.lookup_index_by_method_path(old_operation));

    let Some(new_index_value) = new_match else {
      removed.push(MatchedOperation {
        request_id: binding.request_id.clone(),
        primary_key: binding.primary_key.clone(),
        operation: old_operation.clone(),
      });
      continue;
    };

    if claimed_new_indices.contains(&new_index_value) {
      return Err(SpecImportError::InvalidSpec(format!(
        "Ambiguous spec match for request `{}`",
        binding.request_id
      )));
    }
    claimed_new_indices.insert(new_index_value);

    let new_operation = &new.operations[new_index_value];
    let field_deltas = field_deltas_between(old_operation, new_operation);

    if old_operation.primary_key != new_operation.primary_key {
      identity_changed.push(IdentityChangeDiff {
        request_id: binding.request_id.clone(),
        old_primary_key: old_operation.primary_key.clone(),
        new_primary_key: new_operation.primary_key.clone(),
        old_operation: old_operation.clone(),
        new_operation: new_operation.clone(),
        field_deltas,
      });
      continue;
    }

    if field_deltas.is_empty() {
      unchanged.push(MatchedOperation {
        request_id: binding.request_id.clone(),
        primary_key: new_operation.primary_key.clone(),
        operation: new_operation.clone(),
      });
    } else {
      modified.push(OperationDiff {
        request_id: binding.request_id.clone(),
        primary_key: new_operation.primary_key.clone(),
        old_operation: old_operation.clone(),
        new_operation: new_operation.clone(),
        field_deltas,
      });
    }
  }

  for (index, operation) in new.operations.iter().enumerate() {
    if !claimed_new_indices.contains(&index) {
      added.push(operation.clone());
    }
  }

  sort_diff_lists(&mut added, &mut removed, &mut modified, &mut unchanged, &mut identity_changed);

  Ok(SpecSyncDiff {
    added,
    removed,
    modified,
    unchanged,
    identity_changed,
  })
}

fn sort_diff_lists(
  added: &mut [NormalizedOperation],
  removed: &mut [MatchedOperation],
  modified: &mut [OperationDiff],
  unchanged: &mut [MatchedOperation],
  identity_changed: &mut [IdentityChangeDiff],
) {
  added.sort_by(|left, right| left.primary_key.cmp(&right.primary_key));
  removed.sort_by(|left, right| left.primary_key.cmp(&right.primary_key));
  modified.sort_by(|left, right| left.primary_key.cmp(&right.primary_key));
  unchanged.sort_by(|left, right| left.primary_key.cmp(&right.primary_key));
  identity_changed.sort_by(|left, right| left.old_primary_key.cmp(&right.old_primary_key));
}

fn method_path_key(operation: &NormalizedOperation) -> String {
  format!("{} {}", operation.method, operation.path)
}

fn field_deltas_between(old: &NormalizedOperation, new: &NormalizedOperation) -> Vec<SpecFieldDelta> {
  let mut deltas = Vec::new();
  push_delta_if_changed(&mut deltas, SpecSyncField::Method, &old.method, &new.method);
  push_delta_if_changed(&mut deltas, SpecSyncField::Url, &old.path, &new.path);
  push_delta_if_changed(
    &mut deltas,
    SpecSyncField::Params,
    &canonical_params(&old.parameters, PARAM_LOCATIONS),
    &canonical_params(&new.parameters, PARAM_LOCATIONS),
  );
  push_delta_if_changed(
    &mut deltas,
    SpecSyncField::Headers,
    &canonical_params(&old.parameters, HEADER_LOCATIONS),
    &canonical_params(&new.parameters, HEADER_LOCATIONS),
  );
  push_delta_if_changed(
    &mut deltas,
    SpecSyncField::Body,
    &canonical_body(&old.body),
    &canonical_body(&new.body),
  );
  push_delta_if_changed(&mut deltas, SpecSyncField::Name, &old.name, &new.name);
  deltas
}

const PARAM_LOCATIONS: &[ParameterLocation] = &[
  ParameterLocation::Query,
  ParameterLocation::Path,
  ParameterLocation::Cookie,
];

const HEADER_LOCATIONS: &[ParameterLocation] = &[ParameterLocation::Header];

fn push_delta_if_changed(
  deltas: &mut Vec<SpecFieldDelta>,
  field: SpecSyncField,
  old_value: &str,
  new_value: &str,
) {
  if old_value == new_value {
    return;
  }
  deltas.push(SpecFieldDelta {
    field,
    old_value: old_value.into(),
    new_value: new_value.into(),
    is_conflict: false,
  });
}

fn canonical_params(parameters: &[NormalizedParameter], locations: &[ParameterLocation]) -> String {
  let mut selected: Vec<&NormalizedParameter> = parameters
    .iter()
    .filter(|parameter| locations.contains(&parameter.location))
    .collect();
  selected.sort_by(|left, right| {
    location_rank(left.location)
      .cmp(&location_rank(right.location))
      .then(left.name.cmp(&right.name))
  });

  let parts: Vec<String> = selected
    .iter()
    .map(|parameter| {
      format!(
        "{}:{}={}:req={}:en={}",
        location_label(parameter.location),
        parameter.name,
        parameter.value,
        parameter.required,
        parameter.enabled
      )
    })
    .collect();
  parts.join("|")
}

fn location_rank(location: ParameterLocation) -> u8 {
  match location {
    ParameterLocation::Path => 0,
    ParameterLocation::Query => 1,
    ParameterLocation::Header => 2,
    ParameterLocation::Cookie => 3,
  }
}

fn location_label(location: ParameterLocation) -> &'static str {
  match location {
    ParameterLocation::Query => "query",
    ParameterLocation::Path => "path",
    ParameterLocation::Header => "header",
    ParameterLocation::Cookie => "cookie",
  }
}

fn canonical_body(body: &NormalizedBody) -> String {
  match body {
    NormalizedBody::None => "none".into(),
    NormalizedBody::Json { content } => format!("json:{content}"),
    NormalizedBody::Urlencoded { fields } => {
      let mut pairs = fields.clone();
      pairs.sort_by(|left, right| left.key.cmp(&right.key));
      let serialized = pairs
        .iter()
        .map(|field| format!("{}={}:en={}", field.key, field.value, field.enabled))
        .collect::<Vec<_>>()
        .join("|");
      format!("urlencoded:{serialized}")
    }
    NormalizedBody::FormData { entries } => {
      let mut items = entries.clone();
      items.sort_by(|left, right| left.key.cmp(&right.key));
      let serialized = items
        .iter()
        .map(|entry| {
          format!(
            "{}={}:file={}",
            entry.key, entry.value, entry.is_file
          )
        })
        .collect::<Vec<_>>()
        .join("|");
      format!("form:{serialized}")
    }
    NormalizedBody::Raw { content, content_type } => {
      format!("raw:{content_type}:{content}")
    }
    NormalizedBody::Binary { file_name } => format!("binary:{file_name}"),
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::spec_import::types::{
    NormalizedBody, NormalizedFormDataEntry, NormalizedKeyValue, OperationProtocol, ValueSource,
  };

  fn sample_operation(primary_key: &str, method: &str, path: &str, name: &str) -> NormalizedOperation {
    NormalizedOperation {
      primary_key: primary_key.into(),
      alternate_keys: vec![],
      name: name.into(),
      method: method.into(),
      path: path.into(),
      deprecated: false,
      tags: vec![],
      protocol: OperationProtocol::Http,
      binding: None,
      folder_id: None,
      parameters: vec![],
      body: NormalizedBody::None,
      body_candidates: vec![],
      auth: None,
      description: None,
    }
  }

  fn empty_project() -> NormalizedProject {
    NormalizedProject {
      title: "Test".into(),
      description: None,
      version: None,
      icon_url: None,
      security_schemes: vec![],
      folders: vec![],
      operations: vec![],
      environments: vec![],
    }
  }

  #[test]
  fn diff_detects_added_operation() {
    let old = empty_project();
    let mut new = empty_project();
    new.operations.push(sample_operation("listPets", "GET", "/pet", "List pets"));

    let diff = diff_spec(old, new, vec![], DiffOptions::default()).expect("diff");
    assert_eq!(diff.added.len(), 1);
    assert_eq!(diff.added[0].primary_key, "listPets");
    assert!(diff.removed.is_empty());
    assert!(diff.modified.is_empty());
    assert!(diff.unchanged.is_empty());
    assert!(diff.identity_changed.is_empty());
  }

  #[test]
  fn diff_detects_removed_operation() {
    let mut old = empty_project();
    old.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));
    let new = empty_project();

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "listPets".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.removed.len(), 1);
    assert_eq!(diff.removed[0].request_id, "req-1");
    assert_eq!(diff.removed[0].primary_key, "listPets");
    assert!(diff.added.is_empty());
  }

  #[test]
  fn diff_detects_modified_params() {
    let mut old = empty_project();
    let mut new = empty_project();

    let mut old_op = sample_operation("listPets", "GET", "/pet", "List pets");
    old_op.parameters.push(NormalizedParameter {
      location: ParameterLocation::Query,
      name: "limit".into(),
      value: "10".into(),
      required: false,
      enabled: false,
      value_source: ValueSource::FromExample,
    });
    let mut new_op = old_op.clone();
    new_op.parameters[0].value = "20".into();

    old.operations.push(old_op);
    new.operations.push(new_op);

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "listPets".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.modified.len(), 1);
    assert_eq!(diff.modified[0].field_deltas.len(), 1);
    assert_eq!(diff.modified[0].field_deltas[0].field, SpecSyncField::Params);
    assert_eq!(diff.modified[0].field_deltas[0].old_value, "query:limit=10:req=false:en=false");
    assert_eq!(diff.modified[0].field_deltas[0].new_value, "query:limit=20:req=false:en=false");
    assert!(!diff.modified[0].field_deltas[0].is_conflict);
  }

  #[test]
  fn diff_detects_identity_change_by_method_path() {
    let mut old = empty_project();
    let mut new = empty_project();

    old.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));
    new.operations
      .push(sample_operation("listAllPets", "GET", "/pet", "List all pets"));

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "listPets".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.identity_changed.len(), 1);
    assert_eq!(diff.identity_changed[0].old_primary_key, "listPets");
    assert_eq!(diff.identity_changed[0].new_primary_key, "listAllPets");
    assert_eq!(diff.identity_changed[0].field_deltas.len(), 1);
    assert_eq!(diff.identity_changed[0].field_deltas[0].field, SpecSyncField::Name);
    assert!(diff.modified.is_empty());
    assert!(diff.added.is_empty());
  }

  #[test]
  fn diff_reports_unchanged_operation() {
    let mut old = empty_project();
    let mut new = empty_project();
    let operation = sample_operation("listPets", "GET", "/pet", "List pets");
    old.operations.push(operation.clone());
    new.operations.push(operation);

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "listPets".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.unchanged.len(), 1);
    assert_eq!(diff.unchanged[0].request_id, "req-1");
    assert!(diff.modified.is_empty());
  }

  #[test]
  fn diff_matches_via_alternate_key() {
    let mut old = empty_project();
    let mut new = empty_project();

    old.operations
      .push(sample_operation("legacyKey", "GET", "/pet", "List pets"));
    new.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "listPets".into(),
      alternate_keys: vec!["legacyKey".into()],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.identity_changed.len(), 1);
    assert_eq!(diff.identity_changed[0].old_primary_key, "legacyKey");
    assert_eq!(diff.identity_changed[0].new_primary_key, "listPets");
    assert!(diff.unchanged.is_empty());
  }

  #[test]
  fn diff_returns_invalid_spec_on_ambiguous_new_match() {
    let mut old = empty_project();
    let mut new = empty_project();

    old.operations
      .push(sample_operation("opA", "GET", "/pet", "List pets A"));
    old.operations
      .push(sample_operation("opB", "GET", "/pet", "List pets B"));
    new.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));

    let bindings = vec![
      SpecOperationBinding {
        request_id: "req-1".into(),
        primary_key: "opA".into(),
        alternate_keys: vec![],
      },
      SpecOperationBinding {
        request_id: "req-2".into(),
        primary_key: "opB".into(),
        alternate_keys: vec![],
      },
    ];

    let err = diff_spec(old, new, bindings, DiffOptions::default()).expect_err("ambiguous match");
    assert!(matches!(err, SpecImportError::InvalidSpec(message) if message.contains("req-2")));
  }

  #[test]
  fn diff_skips_bindings_when_old_operation_missing() {
    let mut old = empty_project();
    let mut new = empty_project();

    old.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));
    new.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));

    let bindings = vec![SpecOperationBinding {
      request_id: "req-unknown".into(),
      primary_key: "missingKey".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert!(diff.removed.is_empty());
    assert!(diff.modified.is_empty());
    assert!(diff.unchanged.is_empty());
    assert!(diff.identity_changed.is_empty());
    assert_eq!(diff.added.len(), 1);
    assert_eq!(diff.added[0].primary_key, "listPets");
  }

  #[test]
  fn diff_detects_header_field_delta() {
    let mut old = empty_project();
    let mut new = empty_project();

    let mut old_op = sample_operation("listPets", "GET", "/pet", "List pets");
    old_op.parameters.push(NormalizedParameter {
      location: ParameterLocation::Header,
      name: "X-Api-Key".into(),
      value: "old-key".into(),
      required: true,
      enabled: true,
      value_source: ValueSource::FromExample,
    });
    let mut new_op = old_op.clone();
    new_op.parameters[0].value = "new-key".into();

    old.operations.push(old_op);
    new.operations.push(new_op);

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "listPets".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.modified.len(), 1);
    assert_eq!(diff.modified[0].field_deltas.len(), 1);
    assert_eq!(diff.modified[0].field_deltas[0].field, SpecSyncField::Headers);
    assert_eq!(
      diff.modified[0].field_deltas[0].old_value,
      "header:X-Api-Key=old-key:req=true:en=true"
    );
    assert_eq!(
      diff.modified[0].field_deltas[0].new_value,
      "header:X-Api-Key=new-key:req=true:en=true"
    );
    assert!(!diff.modified[0].field_deltas[0].is_conflict);
  }

  #[test]
  fn diff_detects_body_field_delta() {
    let mut old = empty_project();
    let mut new = empty_project();

    let mut old_op = sample_operation("createPet", "POST", "/pet", "Create pet");
    old_op.body = NormalizedBody::Json {
      content: r#"{"name":"Fluffy"}"#.into(),
    };
    let mut new_op = old_op.clone();
    new_op.body = NormalizedBody::Json {
      content: r#"{"name":"Mittens"}"#.into(),
    };

    old.operations.push(old_op);
    new.operations.push(new_op);

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "createPet".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.modified.len(), 1);
    assert_eq!(diff.modified[0].field_deltas.len(), 1);
    assert_eq!(diff.modified[0].field_deltas[0].field, SpecSyncField::Body);
    assert_eq!(
      diff.modified[0].field_deltas[0].old_value,
      r#"json:{"name":"Fluffy"}"#
    );
    assert_eq!(
      diff.modified[0].field_deltas[0].new_value,
      r#"json:{"name":"Mittens"}"#
    );
    assert!(!diff.modified[0].field_deltas[0].is_conflict);
  }

  #[test]
  fn diff_detects_method_and_url_field_deltas() {
    let mut old = empty_project();
    let mut new = empty_project();

    old.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));
    new.operations
      .push(sample_operation("listPets", "POST", "/pets", "List pets"));

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "listPets".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.modified.len(), 1);
    assert!(diff.identity_changed.is_empty());

    let fields: Vec<SpecSyncField> = diff.modified[0]
      .field_deltas
      .iter()
      .map(|delta| delta.field)
      .collect();
    assert!(fields.contains(&SpecSyncField::Method));
    assert!(fields.contains(&SpecSyncField::Url));

    let method_delta = diff
      .modified[0]
      .field_deltas
      .iter()
      .find(|delta| delta.field == SpecSyncField::Method)
      .expect("method delta");
    assert_eq!(method_delta.old_value, "GET");
    assert_eq!(method_delta.new_value, "POST");

    let url_delta = diff
      .modified[0]
      .field_deltas
      .iter()
      .find(|delta| delta.field == SpecSyncField::Url)
      .expect("url delta");
    assert_eq!(url_delta.old_value, "/pet");
    assert_eq!(url_delta.new_value, "/pets");
  }

  #[test]
  fn diff_detects_name_change_without_identity_change() {
    let mut old = empty_project();
    let mut new = empty_project();

    old.operations
      .push(sample_operation("listPets", "GET", "/pet", "List pets"));
    new.operations
      .push(sample_operation("listPets", "GET", "/pet", "List all pets"));

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "listPets".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.modified.len(), 1);
    assert!(diff.identity_changed.is_empty());
    assert_eq!(diff.modified[0].field_deltas.len(), 1);
    assert_eq!(diff.modified[0].field_deltas[0].field, SpecSyncField::Name);
    assert_eq!(diff.modified[0].field_deltas[0].old_value, "List pets");
    assert_eq!(diff.modified[0].field_deltas[0].new_value, "List all pets");
  }

  #[test]
  fn diff_canonical_body_urlencoded_form_raw_and_binary() {
    let scenarios = [
      (
        "urlencodedDelta",
        NormalizedBody::None,
        NormalizedBody::Urlencoded {
          fields: vec![NormalizedKeyValue {
            key: "name".into(),
            value: "Fluffy".into(),
            enabled: true,
          }],
        },
        "none",
        "urlencoded:name=Fluffy:en=true",
      ),
      (
        "formDelta",
        NormalizedBody::Urlencoded {
          fields: vec![NormalizedKeyValue {
            key: "name".into(),
            value: "Fluffy".into(),
            enabled: true,
          }],
        },
        NormalizedBody::FormData {
          entries: vec![NormalizedFormDataEntry {
            key: "name".into(),
            value: "Fluffy".into(),
            is_file: false,
            file_name: None,
            content_type: None,
          }],
        },
        "urlencoded:name=Fluffy:en=true",
        "form:name=Fluffy:file=false",
      ),
      (
        "rawDelta",
        NormalizedBody::FormData {
          entries: vec![NormalizedFormDataEntry {
            key: "name".into(),
            value: "Fluffy".into(),
            is_file: false,
            file_name: None,
            content_type: None,
          }],
        },
        NormalizedBody::Raw {
          content: "plain text".into(),
          content_type: "text/plain".into(),
        },
        "form:name=Fluffy:file=false",
        "raw:text/plain:plain text",
      ),
      (
        "binaryDelta",
        NormalizedBody::Raw {
          content: "plain text".into(),
          content_type: "text/plain".into(),
        },
        NormalizedBody::Binary {
          file_name: "upload.bin".into(),
        },
        "raw:text/plain:plain text",
        "binary:upload.bin",
      ),
    ];

    for (primary_key, old_body, new_body, expected_old, expected_new) in scenarios {
      let mut old = empty_project();
      let mut new = empty_project();

      let mut old_op = sample_operation(primary_key, "POST", "/pet", "Create pet");
      old_op.body = old_body;
      let mut new_op = old_op.clone();
      new_op.body = new_body;

      old.operations.push(old_op);
      new.operations.push(new_op);

      let bindings = vec![SpecOperationBinding {
        request_id: format!("req-{primary_key}"),
        primary_key: primary_key.into(),
        alternate_keys: vec![],
      }];

      let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
      assert_eq!(diff.modified.len(), 1, "expected modified for {primary_key}");
      assert_eq!(diff.modified[0].field_deltas.len(), 1);
      assert_eq!(diff.modified[0].field_deltas[0].field, SpecSyncField::Body);
      assert_eq!(diff.modified[0].field_deltas[0].old_value, expected_old);
      assert_eq!(diff.modified[0].field_deltas[0].new_value, expected_new);
    }
  }

  #[test]
  fn diff_detects_path_and_cookie_param_deltas() {
    let mut old = empty_project();
    let mut new = empty_project();

    let mut old_op = sample_operation("getPet", "GET", "/pet/{id}", "Get pet");
    old_op.parameters.push(NormalizedParameter {
      location: ParameterLocation::Path,
      name: "id".into(),
      value: "1".into(),
      required: true,
      enabled: true,
      value_source: ValueSource::FromExample,
    });
    old_op.parameters.push(NormalizedParameter {
      location: ParameterLocation::Cookie,
      name: "session".into(),
      value: "abc".into(),
      required: false,
      enabled: true,
      value_source: ValueSource::FromExample,
    });

    let mut new_op = old_op.clone();
    new_op.parameters[0].value = "42".into();
    new_op.parameters[1].value = "xyz".into();

    old.operations.push(old_op);
    new.operations.push(new_op);

    let bindings = vec![SpecOperationBinding {
      request_id: "req-1".into(),
      primary_key: "getPet".into(),
      alternate_keys: vec![],
    }];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");
    assert_eq!(diff.modified.len(), 1);
    assert_eq!(diff.modified[0].field_deltas.len(), 1);
    assert_eq!(diff.modified[0].field_deltas[0].field, SpecSyncField::Params);
    assert_eq!(
      diff.modified[0].field_deltas[0].old_value,
      "path:id=1:req=true:en=true|cookie:session=abc:req=false:en=true"
    );
    assert_eq!(
      diff.modified[0].field_deltas[0].new_value,
      "path:id=42:req=true:en=true|cookie:session=xyz:req=false:en=true"
    );
  }

  #[test]
  fn diff_sorts_lists_by_primary_key() {
    let mut old = empty_project();
    let mut new = empty_project();

    // Removed (bindings present, missing in new) — insert unsorted.
    old.operations
      .push(sample_operation("rem_z", "GET", "/rem-z", "Rem Z"));
    old.operations
      .push(sample_operation("rem_a", "GET", "/rem-a", "Rem A"));

    // Modified — insert unsorted.
    let mut mod_z_old = sample_operation("mod_z", "GET", "/mod-z", "Mod Z");
    mod_z_old.parameters.push(NormalizedParameter {
      location: ParameterLocation::Query,
      name: "q".into(),
      value: "old".into(),
      required: false,
      enabled: true,
      value_source: ValueSource::FromExample,
    });
    let mut mod_z_new = mod_z_old.clone();
    mod_z_new.parameters[0].value = "new".into();
    let mut mod_a_old = sample_operation("mod_a", "GET", "/mod-a", "Mod A");
    mod_a_old.parameters.push(NormalizedParameter {
      location: ParameterLocation::Query,
      name: "q".into(),
      value: "old".into(),
      required: false,
      enabled: true,
      value_source: ValueSource::FromExample,
    });
    let mut mod_a_new = mod_a_old.clone();
    mod_a_new.parameters[0].value = "new".into();
    old.operations.push(mod_z_old);
    old.operations.push(mod_a_old);
    new.operations.push(mod_z_new);
    new.operations.push(mod_a_new);

    // Unchanged — insert unsorted.
    old.operations
      .push(sample_operation("unch_z", "GET", "/unch-z", "Unch Z"));
    old.operations
      .push(sample_operation("unch_a", "GET", "/unch-a", "Unch A"));
    new.operations
      .push(sample_operation("unch_z", "GET", "/unch-z", "Unch Z"));
    new.operations
      .push(sample_operation("unch_a", "GET", "/unch-a", "Unch A"));

    // Identity changed — insert unsorted.
    old.operations
      .push(sample_operation("id_z_old", "GET", "/id-z", "Id Z"));
    old.operations
      .push(sample_operation("id_a_old", "GET", "/id-a", "Id A"));
    new.operations
      .push(sample_operation("id_z_new", "GET", "/id-z", "Id Z"));
    new.operations
      .push(sample_operation("id_a_new", "GET", "/id-a", "Id A"));

    // Added — no bindings, insert unsorted.
    new.operations
      .push(sample_operation("add_z", "GET", "/add-z", "Add Z"));
    new.operations
      .push(sample_operation("add_a", "GET", "/add-a", "Add A"));
    new.operations
      .push(sample_operation("add_m", "GET", "/add-m", "Add M"));

    let bindings = vec![
      SpecOperationBinding {
        request_id: "req-rem-z".into(),
        primary_key: "rem_z".into(),
        alternate_keys: vec![],
      },
      SpecOperationBinding {
        request_id: "req-rem-a".into(),
        primary_key: "rem_a".into(),
        alternate_keys: vec![],
      },
      SpecOperationBinding {
        request_id: "req-mod-z".into(),
        primary_key: "mod_z".into(),
        alternate_keys: vec![],
      },
      SpecOperationBinding {
        request_id: "req-mod-a".into(),
        primary_key: "mod_a".into(),
        alternate_keys: vec![],
      },
      SpecOperationBinding {
        request_id: "req-unch-z".into(),
        primary_key: "unch_z".into(),
        alternate_keys: vec![],
      },
      SpecOperationBinding {
        request_id: "req-unch-a".into(),
        primary_key: "unch_a".into(),
        alternate_keys: vec![],
      },
      SpecOperationBinding {
        request_id: "req-id-z".into(),
        primary_key: "id_z_old".into(),
        alternate_keys: vec![],
      },
      SpecOperationBinding {
        request_id: "req-id-a".into(),
        primary_key: "id_a_old".into(),
        alternate_keys: vec![],
      },
    ];

    let diff = diff_spec(old, new, bindings, DiffOptions::default()).expect("diff");

    assert_eq!(
      diff.added
        .iter()
        .map(|operation| operation.primary_key.as_str())
        .collect::<Vec<_>>(),
      vec!["add_a", "add_m", "add_z"]
    );
    assert_eq!(
      diff.removed
        .iter()
        .map(|operation| operation.primary_key.as_str())
        .collect::<Vec<_>>(),
      vec!["rem_a", "rem_z"]
    );
    assert_eq!(
      diff.modified
        .iter()
        .map(|operation| operation.primary_key.as_str())
        .collect::<Vec<_>>(),
      vec!["mod_a", "mod_z"]
    );
    assert_eq!(
      diff.unchanged
        .iter()
        .map(|operation| operation.primary_key.as_str())
        .collect::<Vec<_>>(),
      vec!["unch_a", "unch_z"]
    );
    assert_eq!(
      diff.identity_changed
        .iter()
        .map(|change| change.old_primary_key.as_str())
        .collect::<Vec<_>>(),
      vec!["id_a_old", "id_z_old"]
    );
  }
}