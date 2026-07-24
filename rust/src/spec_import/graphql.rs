//! GraphQL SDL normalization into the spec import normalized IR.

use graphql_parser::schema::{
  Definition, Document, Field, InputValue, ObjectType, ObjectTypeExtension, Type, TypeDefinition, TypeExtension, Value,
  parse_schema,
};

use crate::spec_import::fingerprint::hash_bytes;
use crate::spec_import::limits::MAX_SPEC_BYTES;
use crate::spec_import::normalize::NormalizeOutput;
use crate::spec_import::types::{
  NormalizedBody, NormalizedEnvironment, NormalizedFolder, NormalizedKeyValue, NormalizedOperation,
  NormalizedParameter, NormalizedProject, OperationProtocol, ParameterLocation, SpecImportError, SpecWarning,
  ValueSource,
};

const DEFAULT_QUERY_TYPE: &str = "Query";
const DEFAULT_MUTATION_TYPE: &str = "Mutation";

/// Returns true when raw bytes look like GraphQL SDL (not JSON/YAML).
pub fn is_graphql_sdl(bytes: &[u8]) -> bool {
  let trimmed = trim_leading(bytes);
  if trimmed.is_empty() {
    return false;
  }

  if trimmed[0] == b'{' || trimmed[0] == b'[' {
    return false;
  }

  if trimmed.starts_with(b"---") || trimmed.starts_with(b"%YAML") {
    return false;
  }

  let Ok(text) = std::str::from_utf8(bytes) else {
    return false;
  };

  text.contains("type Query")
    || text.contains("type Mutation")
    || text.contains("schema {")
    || text.contains("extend type Query")
    || text.contains("extend type Mutation")
}

/// Normalize GraphQL SDL bytes into [`NormalizedProject`].
pub fn normalize_graphql(bytes: &[u8]) -> Result<NormalizeOutput, SpecImportError> {
  if bytes.len() > MAX_SPEC_BYTES {
    return Err(SpecImportError::ParseError(format!(
      "Spec exceeds maximum size of {MAX_SPEC_BYTES} bytes"
    )));
  }

  let text = std::str::from_utf8(bytes)
    .map_err(|err| SpecImportError::ParseError(format!("Invalid UTF-8 in GraphQL SDL: {err}")))?;

  let document = parse_schema::<String>(text)
    .map_err(|err| SpecImportError::ParseError(format!("Invalid GraphQL SDL: {err}")))?
    .into_static();

  let (query_type, mutation_type) = resolve_root_types(&document);
  let mut warnings = Vec::new();
  let mut folders = Vec::new();
  let mut operations = Vec::new();
  let mut sort_hint = 0u32;

  if let Some(query_type) = query_type.as_deref() {
    let folder_id = format!("folder:{DEFAULT_QUERY_TYPE}");
    folders.push(NormalizedFolder {
      id: folder_id.clone(),
      parent_id: None,
      name: DEFAULT_QUERY_TYPE.to_owned(),
      sort_hint: 0,
    });

    for field in collect_object_fields(&document, query_type) {
      operations.push(normalize_field_operation(
        "query",
        DEFAULT_QUERY_TYPE,
        &folder_id,
        &field,
        &mut sort_hint,
      )?);
    }
  }

  if let Some(mutation_type) = mutation_type.as_deref() {
    let folder_id = format!("folder:{DEFAULT_MUTATION_TYPE}");
    folders.push(NormalizedFolder {
      id: folder_id.clone(),
      parent_id: None,
      name: DEFAULT_MUTATION_TYPE.to_owned(),
      sort_hint: 1,
    });

    for field in collect_object_fields(&document, mutation_type) {
      operations.push(normalize_field_operation(
        "mutation",
        DEFAULT_MUTATION_TYPE,
        &folder_id,
        &field,
        &mut sort_hint,
      )?);
    }
  }

  if operations.is_empty() {
    return Err(SpecImportError::InvalidSpec(
      "GraphQL SDL contains no Query or Mutation fields".into(),
    ));
  }

  warnings.push(SpecWarning {
    code: "GRAPHQL_SDL_IMPORT".into(),
    message: "Imported GraphQL SDL as HTTP POST operations with JSON query bodies".into(),
    operation_ref: None,
  });

  let project = NormalizedProject {
    title: "Imported GraphQL Schema".into(),
    description: None,
    version: None,
    icon_url: None,
    security_schemes: vec![],
    folders,
    operations,
    environments: vec![NormalizedEnvironment {
      name: "Default".into(),
      variables: vec![NormalizedKeyValue {
        key: "base_url".into(),
        value: "https://api.example.com/graphql".into(),
        enabled: true,
      }],
    }],
  };

  Ok(NormalizeOutput {
    project,
    warnings,
    content_fingerprint: hash_bytes(bytes),
  })
}

fn trim_leading(bytes: &[u8]) -> &[u8] {
  let mut start = 0;
  if bytes.len() >= 3 && bytes[0..3] == [0xEF, 0xBB, 0xBF] {
    start = 3;
  }
  while start < bytes.len() && bytes[start].is_ascii_whitespace() {
    start += 1;
  }
  &bytes[start..]
}

fn resolve_root_types(document: &Document<'static, String>) -> (Option<String>, Option<String>) {
  let mut query_type = Some(DEFAULT_QUERY_TYPE.to_owned());
  let mut mutation_type = Some(DEFAULT_MUTATION_TYPE.to_owned());

  for definition in &document.definitions {
    if let Definition::SchemaDefinition(schema) = definition {
      if let Some(name) = schema.query.as_deref() {
        query_type = Some(name.to_owned());
      }
      if let Some(name) = schema.mutation.as_deref() {
        mutation_type = Some(name.to_owned());
      } else {
        mutation_type = None;
      }
    }
  }

  let has_query = object_type_exists(document, query_type.as_deref().unwrap_or(DEFAULT_QUERY_TYPE));
  let has_mutation = mutation_type
    .as_deref()
    .is_some_and(|name| object_type_exists(document, name));

  if !has_query {
    query_type = None;
  }
  if !has_mutation {
    mutation_type = None;
  }

  (query_type, mutation_type)
}

fn object_type_exists(document: &Document<'static, String>, type_name: &str) -> bool {
  !collect_object_fields(document, type_name).is_empty()
}

fn collect_object_fields(document: &Document<'static, String>, type_name: &str) -> Vec<Field<'static, String>> {
  let mut fields = Vec::new();
  for definition in &document.definitions {
    match definition {
      Definition::TypeDefinition(TypeDefinition::Object(ObjectType {
        name,
        fields: object_fields,
        ..
      }))
        if name == type_name =>
      {
        fields.extend(object_fields.iter().cloned());
      }
      Definition::TypeExtension(TypeExtension::Object(ObjectTypeExtension {
        name,
        fields: object_fields,
        ..
      }))
        if name == type_name =>
      {
        fields.extend(object_fields.iter().cloned());
      }
      _ => {}
    }
  }
  fields
}

fn normalize_field_operation(
  operation_type: &str,
  folder_name: &str,
  folder_id: &str,
  field: &Field<'static, String>,
  sort_hint: &mut u32,
) -> Result<NormalizedOperation, SpecImportError> {
  let field_name = field.name.clone();
  let primary_key = format!("{operation_type} {field_name}");
  let name = field
    .description
    .as_deref()
    .map(str::trim)
    .filter(|text| !text.is_empty())
    .map(str::to_owned)
    .unwrap_or_else(|| to_title_case(&field_name));

  let parameters = field
    .arguments
    .iter()
    .map(normalize_argument)
    .collect::<Result<Vec<_>, _>>()?;

  let query_document = build_operation_document(operation_type, &field_name, field)?;
  let variables_json = build_variables_json(&parameters);
  let body_content = if variables_json == "{}" {
    format!("{{\n  \"query\": {query_document}\n}}")
  } else {
    format!("{{\n  \"query\": {query_document},\n  \"variables\": {variables_json}\n}}")
  };

  let operation = NormalizedOperation {
    primary_key,
    alternate_keys: vec![],
    name,
    method: "POST".into(),
    path: String::new(),
    deprecated: false,
    tags: vec!["graphql".into(), folder_name.to_owned()],
    protocol: OperationProtocol::Http,
    binding: None,
    folder_id: Some(folder_id.to_owned()),
    parameters,
    body: NormalizedBody::Json { content: body_content },
    body_candidates: vec![],
    auth: None,
    description: field.description.clone(),
  };

  *sort_hint += 1;
  let _ = sort_hint;
  Ok(operation)
}

fn normalize_argument(argument: &InputValue<'static, String>) -> Result<NormalizedParameter, SpecImportError> {
  let required = matches!(argument.value_type, Type::NonNullType(_));
  let (value, value_source) = argument_value(argument);
  let enabled = required || argument.default_value.is_some();

  Ok(NormalizedParameter {
    location: ParameterLocation::Query,
    name: argument.name.clone(),
    value,
    required,
    enabled,
    value_source,
  })
}

fn argument_value(argument: &InputValue<'static, String>) -> (String, ValueSource) {
  if let Some(default_value) = argument.default_value.as_ref() {
    return (graphql_value_to_string(default_value), ValueSource::FromDefault);
  }

  let placeholder = placeholder_for_type(&argument.value_type);
  let source = if placeholder.is_empty() {
    ValueSource::Missing
  } else {
    ValueSource::Synthesized
  };
  (placeholder, source)
}

fn placeholder_for_type(value_type: &Type<'static, String>) -> String {
  match value_type {
    Type::NonNullType(inner) => placeholder_for_type(inner),
    Type::ListType(_) => "[]".into(),
    Type::NamedType(name) => match name.as_str() {
      "String" | "ID" => String::new(),
      "Int" | "Float" => "0".into(),
      "Boolean" => "false".into(),
      _ => String::new(),
    },
  }
}

fn graphql_value_to_string(value: &Value<'static, String>) -> String {
  match value {
    Value::String(text) => text.clone(),
    Value::Int(number) => number.as_i64().map(|n| n.to_string()).unwrap_or_default(),
    Value::Float(number) => number.to_string(),
    Value::Boolean(flag) => flag.to_string(),
    Value::Null => "null".into(),
    Value::Enum(name) => name.clone(),
    Value::Variable(name) => format!("{{{{{name}}}}}"),
    Value::List(items) => {
      let entries = items.iter().map(graphql_value_to_string).collect::<Vec<_>>().join(", ");
      format!("[{entries}]")
    }
    Value::Object(fields) => {
      let entries = fields
        .iter()
        .map(|(key, value)| format!("\"{key}\": {}", graphql_value_to_string(value)))
        .collect::<Vec<_>>()
        .join(", ");
      format!("{{{entries}}}")
    }
  }
}

fn build_operation_document(
  operation_type: &str,
  field_name: &str,
  field: &Field<'static, String>,
) -> Result<String, SpecImportError> {
  let variable_definitions = field
    .arguments
    .iter()
    .map(format_variable_definition)
    .collect::<Result<Vec<_>, _>>()?;
  let variable_list = if variable_definitions.is_empty() {
    String::new()
  } else {
    format!("({})", variable_definitions.join(", "))
  };

  let argument_list = field
    .arguments
    .iter()
    .map(|argument| format!("{}: ${}", argument.name, argument.name))
    .collect::<Vec<_>>()
    .join(", ");
  let argument_section = if argument_list.is_empty() {
    String::new()
  } else {
    format!("({argument_list})")
  };

  let selection_set = selection_set_for_type(&field.field_type);
  let operation_name = to_title_case(field_name);
  let document =
    format!("{operation_type} {operation_name}{variable_list} {{ {field_name}{argument_section} {selection_set} }}");
  Ok(serde_json::to_string(&document).expect("graphql query document should serialize"))
}

fn format_variable_definition(argument: &InputValue<'static, String>) -> Result<String, SpecImportError> {
  Ok(format!("${}: {}", argument.name, format_type(&argument.value_type)))
}

fn format_type(value_type: &Type<'static, String>) -> String {
  match value_type {
    Type::NamedType(name) => name.clone(),
    Type::ListType(inner) => format!("[{}]", format_type(inner)),
    Type::NonNullType(inner) => format!("{}!", format_type(inner)),
  }
}

fn selection_set_for_type(value_type: &Type<'static, String>) -> String {
  if is_scalar_type(value_type) {
    String::new()
  } else {
    "{ __typename }".into()
  }
}

fn is_scalar_type(value_type: &Type<'static, String>) -> bool {
  match value_type {
    Type::NonNullType(inner) => is_scalar_type(inner),
    Type::ListType(_) => false,
    Type::NamedType(name) => {
      matches!(name.as_str(), "String" | "ID" | "Int" | "Float" | "Boolean")
    }
  }
}

fn build_variables_json(parameters: &[NormalizedParameter]) -> String {
  if parameters.is_empty() {
    return "{}".into();
  }

  let entries = parameters
    .iter()
    .map(|parameter| {
      let value = serde_json::to_string(&parameter.value).expect("parameter value should serialize");
      format!("\"{}\": {value}", parameter.name)
    })
    .collect::<Vec<_>>()
    .join(", ");
  format!("{{{entries}}}")
}

fn to_title_case(name: &str) -> String {
  let mut chars = name.chars();
  match chars.next() {
    None => String::new(),
    Some(first) => first.to_ascii_uppercase().to_string() + chars.as_str(),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  const SIMPLE_SDL: &str = r#"
    """Simple GraphQL API for testing imports."""
    type Query {
      """Fetch a user by ID"""
      user(id: ID!): User
      """List users with optional limit"""
      users(limit: Int = 10): [User!]!
    }

    type Mutation {
      """Create a new user"""
      createUser(name: String!, email: String!): User!
    }

    type User {
      id: ID!
      name: String!
      email: String!
    }
  "#;

  #[test]
  fn is_graphql_sdl_detects_schema_types() {
    assert!(is_graphql_sdl(SIMPLE_SDL.as_bytes()));
    assert!(!is_graphql_sdl(br#"{"openapi":"3.0.0"}"#));
  }

  #[test]
  fn normalize_graphql_maps_query_and_mutation_fields() {
    let output = normalize_graphql(SIMPLE_SDL.as_bytes()).expect("graphql normalize");
    assert_eq!(output.project.operations.len(), 3);
    assert!(
      output
        .project
        .operations
        .iter()
        .any(|op| op.primary_key == "query user")
    );
    assert!(
      output
        .project
        .operations
        .iter()
        .any(|op| op.primary_key == "mutation createUser")
    );
    assert_eq!(output.project.folders.len(), 2);
    assert!(
      output
        .warnings
        .iter()
        .any(|warning| warning.code == "GRAPHQL_SDL_IMPORT")
    );
  }

  #[test]
  fn normalize_graphql_maps_arguments_to_parameters() {
    let output = normalize_graphql(SIMPLE_SDL.as_bytes()).expect("graphql normalize");
    let user = output
      .project
      .operations
      .iter()
      .find(|op| op.primary_key == "query user")
      .expect("user query");

    assert_eq!(user.parameters.len(), 1);
    assert_eq!(user.parameters[0].name, "id");
    assert!(user.parameters[0].required);
    assert!(user.content_contains_query_field());
  }

  #[test]
  fn normalize_graphql_uses_default_argument_values() {
    let output = normalize_graphql(SIMPLE_SDL.as_bytes()).expect("graphql normalize");
    let users = output
      .project
      .operations
      .iter()
      .find(|op| op.primary_key == "query users")
      .expect("users query");

    assert_eq!(users.parameters.len(), 1);
    assert_eq!(users.parameters[0].name, "limit");
    assert_eq!(users.parameters[0].value, "10");
    assert_eq!(users.parameters[0].value_source, ValueSource::FromDefault);
  }

  trait GraphQLBodyAssertions {
    fn content_contains_query_field(&self) -> bool;
  }

  impl GraphQLBodyAssertions for NormalizedOperation {
    fn content_contains_query_field(&self) -> bool {
      matches!(&self.body, NormalizedBody::Json { content } if content.contains("\"query\""))
    }
  }
}
