//! OpenAPI normalization into the spec import normalized IR.

use std::collections::{BTreeMap, HashSet};

use roas::common::reference::RefOr;
use roas::loader::Loader;
use roas::v3_0::example::Example;
use roas::v3_0::media_type::MediaType;
use roas::v3_0::operation::Operation;
use roas::v3_0::parameter::Parameter;
use roas::v3_0::request_body::RequestBody;
use roas::v3_0::schema::{ObjectSchema, Schema, SingleSchema};
use roas::v3_0::security_scheme::{OAuth2Flows, SecurityScheme};
use roas::v3_0::server::{Server, ServerVariable};
use roas::v3_0::spec::Spec as V3Spec;
use roas::v2::spec::Spec as V2Spec;
use serde_json::Value;

use crate::spec_import::bundle::{rewrite_refs_in_value, BundleContext};
use crate::spec_import::sanitize::{sanitize_openapi_value, sanitize_openapi_value_for_v30};
use crate::spec_import::fingerprint::{
  bundle_and_canonicalize_with_bundle, hash_bytes, validate_refs_with_bundle,
};
use crate::spec_import::types::{
  NormalizedAuth, NormalizedBody, NormalizedBodyCandidate, NormalizedEnvironment, NormalizedFolder,
  NormalizedFormDataEntry, NormalizedKeyValue, NormalizedOperation, NormalizedParameter,
  NormalizedProject, NormalizedSecurityScheme, OperationProtocol, ParameterLocation, SpecImportError,
  SpecParseOptions, SpecWarning, ValueSource,
};

const ENABLE_OPTIONAL_PARAMETERS: bool = false;

/// Output of the normalization stage.
#[derive(Debug)]
pub struct NormalizeOutput {
  pub project: NormalizedProject,
  pub warnings: Vec<SpecWarning>,
  pub content_fingerprint: String,
}

/// Normalize a parsed JSON OpenAPI document into [`NormalizedProject`].
pub fn normalize_openapi(value: Value, options: SpecParseOptions) -> Result<NormalizeOutput, SpecImportError> {
  normalize_openapi_with_bundle(value, None, options)
}

/// Normalize OpenAPI with optional multi-file bundle context.
pub fn normalize_openapi_with_bundle(
  value: Value,
  bundle: Option<BundleContext>,
  options: SpecParseOptions,
) -> Result<NormalizeOutput, SpecImportError> {
  validate_refs_with_bundle(&value, bundle.as_ref()).map_err(SpecImportError::InvalidSpec)?;

  let mut loader = Loader::new();
  let mut value_for_spec = value.clone();
  if let Some(ctx) = bundle.as_ref() {
    rewrite_refs_in_value(&mut value_for_spec, &ctx.entry_uri);
    ctx.configure_loader(&mut loader, value_for_spec.clone())?;
  } else {
    loader
      .preload_resource("spec.json", value_for_spec.clone())
      .map_err(|err| SpecImportError::ParseError(err.to_string()))?;
  }

  let spec = parse_typed_spec(&value_for_spec)?;
  check_duplicate_operation_ids(&spec)?;

  let mut warnings = Vec::new();
  let project = normalize_v3_spec(&spec, &mut loader, &mut warnings, options)?;
  let fingerprint = bundle_and_canonicalize_with_bundle(&value, bundle.as_ref())
    .map(|bytes| hash_bytes(&bytes))
    .map_err(SpecImportError::InvalidSpec)?;

  Ok(NormalizeOutput {
    project,
    warnings,
    content_fingerprint: fingerprint,
  })
}

fn parse_typed_spec(value: &Value) -> Result<V3Spec, SpecImportError> {
  let mut sanitized = value.clone();
  sanitize_openapi_value(&mut sanitized);

  if sanitized.get("swagger").is_some() {
    let v2: V2Spec = serde_json::from_value(sanitized)
      .map_err(|err| SpecImportError::ParseError(err.to_string()))?;
    return Ok(v2.into());
  }

  let version = sanitized
    .get("openapi")
    .and_then(Value::as_str)
    .ok_or_else(|| SpecImportError::UnsupportedFormat("Missing openapi/swagger version field".into()))?;

  if version.starts_with("3.0") {
    serde_json::from_value(sanitized).map_err(|err| SpecImportError::ParseError(err.to_string()))
  } else if version.starts_with("3.1") {
    let v31: roas::v3_1::spec::Spec = serde_json::from_value(sanitized.clone())
      .map_err(|err| SpecImportError::ParseError(err.to_string()))?;
    let mut intermediate = serde_json::to_value(v31)
      .map_err(|err| SpecImportError::ParseError(err.to_string()))?;
    sanitize_openapi_value_for_v30(&mut intermediate);
    // roas v3_0::Spec only accepts 3.0.x version strings after the v3.1 round-trip.
    if let Some(obj) = intermediate.as_object_mut() {
      obj.insert("openapi".into(), Value::String("3.0.3".into()));
    }
    serde_json::from_value(intermediate).map_err(|err| SpecImportError::ParseError(err.to_string()))
  } else {
    Err(SpecImportError::UnsupportedFormat(format!(
      "Unsupported OpenAPI version: {version}"
    )))
  }
}

fn check_duplicate_operation_ids(spec: &V3Spec) -> Result<(), SpecImportError> {
  let mut seen = HashSet::new();
  for (_path, item) in spec.paths.iter() {
    let Some(operations) = &item.operations else {
      continue;
    };
    for operation in operations.values() {
      if let Some(operation_id) = &operation.operation_id {
        if !seen.insert(operation_id.clone()) {
          return Err(SpecImportError::InvalidSpec(format!(
            "Duplicate operationId: {operation_id}"
          )));
        }
      }
    }
  }
  Ok(())
}

fn normalize_v3_spec(
  spec: &V3Spec,
  loader: &mut Loader,
  warnings: &mut Vec<SpecWarning>,
  options: SpecParseOptions,
) -> Result<NormalizedProject, SpecImportError> {
  let mut ctx = NormalizeContext::new(spec, loader, options.enable_schema_synthesis);

  let title = spec.info.title.clone();
  let description = spec.info.description.clone();
  let version = Some(spec.info.version.clone());

  let security_schemes = normalize_security_schemes(spec);
  let environments = normalize_environments(spec.servers.as_deref().unwrap_or(&[]));
  let folders = build_tag_folders(spec, warnings);
  let operations = collect_operations(spec, &mut ctx, &folders, warnings)?;

  Ok(NormalizedProject {
    title,
    description,
    version,
    icon_url: extract_icon_url(spec),
    security_schemes,
    folders,
    operations,
    environments,
  })
}

fn extract_icon_url(spec: &V3Spec) -> Option<String> {
  if let Some(logo) = &spec.info.x_logo {
    if let Some(url) = normalize_icon_url(&logo.url) {
      return Some(url);
    }
  }

  spec
    .servers
    .as_ref()
    .and_then(|servers| servers.first())
    .and_then(|server| favicon_url_for_base(&server.url))
}

fn normalize_icon_url(raw: &str) -> Option<String> {
  let trimmed = raw.trim();
  if trimmed.is_empty() || trimmed == "#" {
    return None;
  }
  let parsed = url::Url::parse(trimmed).ok()?;
  if parsed.scheme() != "https" {
    return None;
  }
  Some(parsed.to_string())
}

fn favicon_url_for_base(server_url: &str) -> Option<String> {
  let mut parsed = url::Url::parse(server_url).ok()?;
  if parsed.scheme() != "https" {
    return None;
  }
  parsed.set_path("/favicon.ico");
  parsed.set_query(None);
  parsed.set_fragment(None);
  Some(parsed.to_string())
}

struct NormalizeContext<'a> {
  spec: &'a V3Spec,
  loader: &'a mut Loader,
  schema_stack: Vec<String>,
  enable_schema_synthesis: bool,
}

impl<'a> NormalizeContext<'a> {
  fn new(spec: &'a V3Spec, loader: &'a mut Loader, enable_schema_synthesis: bool) -> Self {
    Self {
      spec,
      loader,
      schema_stack: Vec::new(),
      enable_schema_synthesis,
    }
  }
}

fn normalize_security_schemes(spec: &V3Spec) -> Vec<NormalizedSecurityScheme> {
  let Some(components) = &spec.components else {
    return vec![];
  };
  let Some(schemes) = &components.security_schemes else {
    return vec![];
  };

  schemes
    .iter()
    .map(|(name, scheme_ref)| {
      let scheme = scheme_ref
        .get_item(spec)
        .expect("validated security scheme");
      let (scheme_type, header_name, query_name, in_location) = match scheme {
        SecurityScheme::HTTP(http) => (
          format!("http:{}", http.scheme),
          None,
          None,
          None,
        ),
        SecurityScheme::ApiKey(api_key) => (
          "apiKey".into(),
          if api_key.location == roas::v3_0::security_scheme::ApiKeyLocation::Header {
            Some(api_key.name.clone())
          } else {
            None
          },
          if api_key.location == roas::v3_0::security_scheme::ApiKeyLocation::Query {
            Some(api_key.name.clone())
          } else {
            None
          },
          Some(format!("{}", api_key.location)),
        ),
        SecurityScheme::OAuth2(_) => ("oauth2".into(), None, None, None),
        SecurityScheme::OpenIdConnect(_) => ("openIdConnect".into(), None, None, None),
      };

      NormalizedSecurityScheme {
        name: name.clone(),
        scheme_type,
        description: scheme_description(scheme),
        header_name,
        query_name,
        in_location,
      }
    })
    .collect()
}

fn scheme_description(scheme: &SecurityScheme) -> Option<String> {
  match scheme {
    SecurityScheme::HTTP(http) => http.description.clone(),
    SecurityScheme::ApiKey(api_key) => api_key.description.clone(),
    SecurityScheme::OAuth2(oauth) => oauth.description.clone(),
    SecurityScheme::OpenIdConnect(oidc) => oidc.description.clone(),
  }
}

fn normalize_environments(servers: &[Server]) -> Vec<NormalizedEnvironment> {
  if servers.is_empty() {
    return vec![NormalizedEnvironment {
      name: "Default".into(),
      variables: vec![NormalizedKeyValue {
        key: "base_url".into(),
        value: "/".into(),
        enabled: true,
      }],
    }];
  }

  servers
    .iter()
    .enumerate()
    .map(|(index, server)| {
      let name = server
        .description
        .clone()
        .filter(|text| !text.is_empty())
        .unwrap_or_else(|| format!("Server {}", index + 1));

      let mut variables = vec![NormalizedKeyValue {
        key: "base_url".into(),
        value: substitute_server_url(&server.url, server.variables.as_ref()),
        enabled: true,
      }];

      if let Some(server_vars) = &server.variables {
        for (key, variable) in server_vars {
          variables.push(NormalizedKeyValue {
            key: key.clone(),
            value: server_variable_default(variable),
            enabled: true,
          });
        }
      }

      NormalizedEnvironment { name, variables }
    })
    .collect()
}

fn substitute_server_url(url: &str, variables: Option<&BTreeMap<String, ServerVariable>>) -> String {
  let Some(variables) = variables else {
    return url.to_owned();
  };

  let mut resolved = url.to_owned();
  for (name, variable) in variables {
    let value = server_variable_default(variable);
    resolved = resolved.replace(&format!("{{{name}}}"), &value);
  }
  resolved
}

fn server_variable_default(variable: &ServerVariable) -> String {
  variable.default.clone()
}

fn build_tag_folders(spec: &V3Spec, warnings: &mut Vec<SpecWarning>) -> Vec<NormalizedFolder> {
  let mut primary_tags_in_path_order = Vec::new();
  let mut primary_tags = HashSet::new();

  for (_path, item) in spec.paths.iter() {
    let Some(operations) = &item.operations else {
      continue;
    };
    for operation in operations.values() {
      let Some(tags) = &operation.tags else {
        continue;
      };
      let Some(primary) = tags.first() else {
        continue;
      };
      if primary_tags.insert(primary.clone()) {
        primary_tags_in_path_order.push(primary.clone());
      }
    }
  }

  if primary_tags.is_empty() {
    warnings.push(SpecWarning {
      code: "NO_TAGS".into(),
      message: "Spec has no tags; operations import into the project root".into(),
      operation_ref: None,
    });
    return vec![];
  }

  if let Some(declared_tags) = &spec.tags {
    for tag in declared_tags {
      if primary_tags.contains(&tag.name) {
        continue;
      }
      warnings.push(SpecWarning {
        code: "UNUSED_DECLARED_TAG".into(),
        message: format!("Declared tag '{}' has no operations; folder skipped", tag.name),
        operation_ref: None,
      });
    }
  }

  let mut folder_names = Vec::new();
  let mut folder_seen = HashSet::new();

  if let Some(declared_tags) = &spec.tags {
    for tag in declared_tags {
      if primary_tags.contains(&tag.name) && folder_seen.insert(tag.name.clone()) {
        folder_names.push(tag.name.clone());
      }
    }
  }

  for tag in primary_tags_in_path_order {
    if folder_seen.insert(tag.clone()) {
      folder_names.push(tag);
    }
  }

  folder_names
    .into_iter()
    .enumerate()
    .map(|(index, name)| NormalizedFolder {
      id: folder_id_for_tag(&name),
      parent_id: None,
      name,
      sort_hint: index as u32,
    })
    .collect()
}

fn folder_id_for_tag(tag: &str) -> String {
  format!("tag:{tag}")
}

fn collect_operations(
  spec: &V3Spec,
  ctx: &mut NormalizeContext<'_>,
  folders: &[NormalizedFolder],
  warnings: &mut Vec<SpecWarning>,
) -> Result<Vec<NormalizedOperation>, SpecImportError> {
  let mut operations = Vec::new();

  for (path, item) in spec.paths.iter() {
    let path_level_params = resolve_parameters(item.parameters.as_deref(), ctx)?;

    let Some(path_operations) = &item.operations else {
      continue;
    };

    for (method, operation) in path_operations {
      let op_ref = format!("{method} {path}");
      let mut merged_params = path_level_params.clone();
      if let Some(op_params) = &operation.parameters {
        merged_params.extend(resolve_parameters(Some(op_params), ctx)?);
      }

      if operation.servers.is_some() {
        warnings.push(SpecWarning {
          code: "OPERATION_SERVER_IGNORED".into(),
          message: "Operation-level servers are ignored in P0; use root servers as environments".into(),
          operation_ref: Some(op_ref.clone()),
        });
      }

      if let Some(tags) = &operation.tags {
        if tags.len() > 1 {
          warnings.push(SpecWarning {
            code: "MULTIPLE_TAGS".into(),
            message: format!(
              "Multiple tags found; using primary tag '{}', ignoring: {}",
              tags[0],
              tags[1..].join(", ")
            ),
            operation_ref: Some(op_ref.clone()),
          });
        }
      }

      let folder_id = operation
        .tags
        .as_ref()
        .and_then(|tags| tags.first())
        .map(|tag| folder_id_for_tag(tag))
        .or_else(|| folders.first().map(|folder| folder.id.clone()));

      let method_upper = method.to_ascii_uppercase();
      let primary_key = operation
        .operation_id
        .clone()
        .unwrap_or_else(|| format!("{method_upper} {path}"));

      let mut name = operation
        .summary
        .clone()
        .or_else(|| operation.operation_id.clone())
        .unwrap_or_else(|| format!("{method_upper} {path}"));

      let deprecated = operation.deprecated.unwrap_or(false);
      if deprecated {
        name = format!("[Deprecated] {name}");
      }

      let parameters = normalize_parameters(&merged_params, ctx, &op_ref, warnings)?;
      let (body, body_candidates) =
        normalize_request_body(operation.request_body.as_ref(), ctx, &op_ref, warnings)?;
      let auth = normalize_operation_auth(spec, operation, &primary_key);

      operations.push(NormalizedOperation {
        primary_key,
        alternate_keys: vec![],
        name,
        method: method_upper,
        path: path.clone(),
        deprecated,
        tags: operation.tags.clone().unwrap_or_default(),
        protocol: OperationProtocol::Http,
        binding: None,
        folder_id,
        parameters,
        body,
        body_candidates,
        auth,
        description: operation.description.clone(),
      });
    }
  }

  Ok(operations)
}

fn resolve_parameters(
  parameters: Option<&[RefOr<Parameter>]>,
  ctx: &mut NormalizeContext<'_>,
) -> Result<Vec<Parameter>, SpecImportError> {
  let Some(parameters) = parameters else {
    return Ok(vec![]);
  };

  let mut resolved = Vec::new();
  for parameter_ref in parameters {
    let parameter = parameter_ref
      .get_item_with_loader(ctx.spec, ctx.loader)
      .map_err(map_resolve_error)?;
    resolved.push(parameter.into_owned());
  }
  Ok(resolved)
}

fn normalize_parameters(
  parameters: &[Parameter],
  ctx: &mut NormalizeContext<'_>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<Vec<NormalizedParameter>, SpecImportError> {
  let mut out = Vec::new();

  for parameter in parameters {
    let (location, name, required, schema, example, examples, content) = match parameter {
      Parameter::Query(query) => (
        ParameterLocation::Query,
        query.name.clone(),
        query.required.unwrap_or(false),
        query.schema.as_ref(),
        query.example.as_ref(),
        query.examples.as_ref(),
        query.content.as_ref(),
      ),
      Parameter::Path(path) => (
        ParameterLocation::Path,
        path.name.clone(),
        path.required,
        path.schema.as_ref(),
        path.example.as_ref(),
        path.examples.as_ref(),
        path.content.as_ref(),
      ),
      Parameter::Header(header) => (
        ParameterLocation::Header,
        header.name.clone(),
        header.required.unwrap_or(false),
        header.schema.as_ref(),
        header.example.as_ref(),
        header.examples.as_ref(),
        header.content.as_ref(),
      ),
      Parameter::Cookie(cookie) => (
        ParameterLocation::Cookie,
        cookie.name.clone(),
        cookie.required.unwrap_or(false),
        cookie.schema.as_ref(),
        cookie.example.as_ref(),
        cookie.examples.as_ref(),
        cookie.content.as_ref(),
      ),
    };

    let enabled = required || ENABLE_OPTIONAL_PARAMETERS;
    let (value, value_source) = if matches!(location, ParameterLocation::Path) {
      (format!("{{{{{name}}}}}"), ValueSource::FromExample)
    } else {
      resolve_parameter_value(&ParameterValueInput {
        example,
        examples,
        content,
        schema,
        op_ref,
        required,
      }, ctx, warnings)?
    };

    out.push(NormalizedParameter {
      location,
      name,
      value,
      required,
      enabled,
      value_source,
    });
  }

  Ok(out)
}

struct ParameterValueInput<'a> {
  example: Option<&'a Value>,
  examples: Option<&'a BTreeMap<String, RefOr<Example>>>,
  content: Option<&'a BTreeMap<String, MediaType>>,
  schema: Option<&'a RefOr<Schema>>,
  op_ref: &'a str,
  required: bool,
}

fn resolve_parameter_value(
  input: &ParameterValueInput<'_>,
  ctx: &mut NormalizeContext<'_>,
  warnings: &mut Vec<SpecWarning>,
) -> Result<(String, ValueSource), SpecImportError> {
  if let Some(value) = input.example {
    return Ok((json_scalar_to_string(value), ValueSource::FromExample));
  }

  if let Some(media_types) = input.content {
    if let Some((_, media_type)) = media_types.iter().next() {
      if let Some(value) = media_type.example.as_ref() {
        return Ok((json_scalar_to_string(value), ValueSource::FromExample));
      }
      if let Some(example_map) = &media_type.examples {
        if let Some((_, example_ref)) = example_map.iter().next() {
          if let Ok(example) = example_ref.get_item_with_loader(ctx.spec, ctx.loader) {
            if let Some(value) = &example.value {
              return Ok((json_scalar_to_string(value), ValueSource::FromExample));
            }
          }
        }
      }
    }
  }

  if let Some(example_map) = input.examples {
    if let Some((_, example_ref)) = example_map.iter().next() {
      if let Ok(example) = example_ref.get_item_with_loader(ctx.spec, ctx.loader) {
        if let Some(value) = &example.value {
          return Ok((json_scalar_to_string(value), ValueSource::FromExample));
        }
      }
    }
  }

  if let Some(schema_ref) = input.schema {
    if let Some((value, source)) =
      resolve_schema_example(schema_ref, ctx, input.op_ref, warnings)?
    {
      return Ok((value, source));
    }
  }

  if !input.required && !ENABLE_OPTIONAL_PARAMETERS {
    return Ok((String::new(), ValueSource::Missing));
  }

  warnings.push(SpecWarning {
    code: "MISSING_EXAMPLE".into(),
    message: "No example found for parameter; using empty placeholder".into(),
    operation_ref: Some(input.op_ref.to_owned()),
  });
  Ok((String::new(), ValueSource::Missing))
}

fn normalize_request_body(
  request_body: Option<&RefOr<RequestBody>>,
  ctx: &mut NormalizeContext<'_>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<(NormalizedBody, Vec<NormalizedBodyCandidate>), SpecImportError> {
  let Some(request_body) = request_body else {
    return Ok((NormalizedBody::None, vec![]));
  };

  let body = request_body
    .get_item_with_loader(ctx.spec, ctx.loader)
    .map_err(map_resolve_error)?;

  if body.content.is_empty() {
    return Ok((NormalizedBody::None, vec![]));
  }

  let mut candidates = Vec::new();
  for (content_type, media_type) in &body.content {
    let mapped = map_media_type_body(content_type, media_type, ctx, op_ref, warnings)?;
    candidates.push(NormalizedBodyCandidate {
      content_type: content_type.clone(),
      body: mapped,
    });
  }

  let primary = candidates
    .first()
    .map(|candidate| candidate.body.clone())
    .unwrap_or(NormalizedBody::None);

  Ok((primary, candidates))
}

fn map_media_type_body(
  content_type: &str,
  media_type: &MediaType,
  ctx: &mut NormalizeContext<'_>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<NormalizedBody, SpecImportError> {
  let base_ct = content_type.split(';').next().unwrap_or(content_type).trim();

  if let Some(example) = &media_type.example {
    return map_example_to_body(base_ct, example);
  }

  if let Some(examples) = &media_type.examples {
    if let Some((_, example_ref)) = examples.iter().next() {
      if let Ok(example) = example_ref.get_item_with_loader(ctx.spec, ctx.loader) {
        if let Some(value) = &example.value {
          return map_example_to_body(base_ct, value);
        }
      }
    }
  }

  if let Some(schema_ref) = &media_type.schema {
    if let Some((value, source)) = resolve_schema_example(schema_ref, ctx, op_ref, warnings)? {
      if source == ValueSource::Synthesized {
        push_synthesized_value_warning(
          warnings,
          op_ref,
          &format!("request body ({base_ct})"),
        );
      }
      return map_example_to_body(
        base_ct,
        &serde_json::from_str(&value).unwrap_or(Value::String(value)),
      );
    }
  }

  warnings.push(SpecWarning {
    code: "MISSING_EXAMPLE".into(),
    message: format!("No example found for request body content type '{base_ct}'"),
    operation_ref: Some(op_ref.to_owned()),
  });

  Ok(NormalizedBody::None)
}

fn map_example_to_body(content_type: &str, example: &Value) -> Result<NormalizedBody, SpecImportError> {
  match content_type {
    "application/json" | "application/vnd.api+json" => Ok(NormalizedBody::Json {
      content: serde_json::to_string_pretty(example)
        .or_else(|_| serde_json::to_string(example))
        .map_err(|err| SpecImportError::ParseError(err.to_string()))?,
    }),
    "application/x-www-form-urlencoded" => {
      let fields = json_object_to_fields(example);
      Ok(NormalizedBody::Urlencoded { fields })
    }
    "multipart/form-data" => {
      let entries = json_object_to_form_data(example);
      Ok(NormalizedBody::FormData { entries })
    }
    "application/octet-stream" => Ok(NormalizedBody::Binary {
      file_name: "upload.bin".into(),
    }),
    ct if ct.starts_with("text/") || ct == "application/xml" => Ok(NormalizedBody::Raw {
      content: json_scalar_to_string(example),
      content_type: content_type.to_owned(),
    }),
    _ => Ok(NormalizedBody::Raw {
      content: json_scalar_to_string(example),
      content_type: content_type.to_owned(),
    }),
  }
}

fn json_object_to_fields(value: &Value) -> Vec<NormalizedKeyValue> {
  let Some(map) = value.as_object() else {
    return vec![];
  };

  map.iter()
    .map(|(key, value)| NormalizedKeyValue {
      key: key.clone(),
      value: json_scalar_to_string(value),
      enabled: true,
    })
    .collect()
}

fn json_object_to_form_data(value: &Value) -> Vec<NormalizedFormDataEntry> {
  let Some(map) = value.as_object() else {
    return vec![];
  };

  map.iter()
    .map(|(key, value)| NormalizedFormDataEntry {
      key: key.clone(),
      value: json_scalar_to_string(value),
      is_file: false,
      file_name: None,
      content_type: None,
    })
    .collect()
}

fn push_synthesized_value_warning(warnings: &mut Vec<SpecWarning>, op_ref: &str, detail: &str) {
  warnings.push(SpecWarning {
    code: "SYNTHESIZED_VALUE".into(),
    message: format!("Synthesized placeholder value for {detail}"),
    operation_ref: Some(op_ref.to_owned()),
  });
}

fn resolve_schema_example(
  schema_ref: &RefOr<Schema>,
  ctx: &mut NormalizeContext<'_>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<Option<(String, ValueSource)>, SpecImportError> {
  let schema = resolve_schema(schema_ref, ctx)?;
  resolve_schema_value(&schema, ctx, op_ref, warnings)
}

fn resolve_schema(
  schema_ref: &RefOr<Schema>,
  ctx: &mut NormalizeContext<'_>,
) -> Result<Schema, SpecImportError> {
  match schema_ref {
    RefOr::Item(schema) => Ok(schema.clone()),
    RefOr::Ref(reference) => {
      if ctx.schema_stack.last().is_some_and(|top| top == &reference.reference) {
        // OpenAPI discriminator stubs often use a self-$ref inside oneOf as a mapping anchor.
        return Ok(Schema::Single(Box::new(SingleSchema::Object(ObjectSchema::default()))));
      }
      if ctx.schema_stack.iter().any(|item| item == &reference.reference) {
        return Err(SpecImportError::InvalidSpec(format!(
          "Cyclic $ref detected: {}",
          reference.reference
        )));
      }
      if ctx.schema_stack.len() >= crate::spec_import::limits::MAX_REF_DEPTH {
        return Err(SpecImportError::InvalidSpec(format!(
          "$ref resolution exceeds maximum depth of {}",
          crate::spec_import::limits::MAX_REF_DEPTH
        )));
      }

      ctx.schema_stack.push(reference.reference.clone());
      let resolved = schema_ref
        .get_item_with_loader(ctx.spec, ctx.loader)
        .map_err(map_resolve_error)?
        .into_owned();
      ctx.schema_stack.pop();
      Ok(resolved)
    }
  }
}

fn resolve_schema_value(
  schema: &Schema,
  ctx: &mut NormalizeContext<'_>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<Option<(String, ValueSource)>, SpecImportError> {
  match schema {
    Schema::AllOf(all_of) => {
      let mut merged = serde_json::Map::new();
      for branch in &all_of.all_of {
        if let Some((value, _)) = resolve_schema_example(branch, ctx, op_ref, warnings)? {
          if let Ok(Value::Object(map)) = serde_json::from_str::<Value>(&value) {
            for (key, val) in map {
              merged.insert(key, val);
            }
          }
        }
      }
      if merged.is_empty() {
        warnings.push(SpecWarning {
          code: "COMPOSITE_SCHEMA_GUESS".into(),
          message: "allOf schema had no resolvable examples".into(),
          operation_ref: Some(op_ref.to_owned()),
        });
        Ok(None)
      } else {
        Ok(Some((
          serde_json::to_string(&Value::Object(merged)).unwrap_or_default(),
          ValueSource::FromExample,
        )))
      }
    }
    Schema::OneOf(one_of) => {
      for branch in &one_of.one_of {
        if let Some(result) = resolve_schema_example(branch, ctx, op_ref, warnings)? {
          warnings.push(SpecWarning {
            code: "COMPOSITE_SCHEMA_GUESS".into(),
            message: "Using first oneOf branch with a resolvable example".into(),
            operation_ref: Some(op_ref.to_owned()),
          });
          return Ok(Some(result));
        }
      }
      warnings.push(SpecWarning {
        code: "COMPOSITE_SCHEMA_GUESS".into(),
        message: "No oneOf branch had a resolvable example".into(),
        operation_ref: Some(op_ref.to_owned()),
      });
      Ok(None)
    }
    Schema::AnyOf(any_of) => {
      for branch in &any_of.any_of {
        if let Some(result) = resolve_schema_example(branch, ctx, op_ref, warnings)? {
          warnings.push(SpecWarning {
            code: "COMPOSITE_SCHEMA_GUESS".into(),
            message: "Using first anyOf branch with a resolvable example".into(),
            operation_ref: Some(op_ref.to_owned()),
          });
          return Ok(Some(result));
        }
      }
      warnings.push(SpecWarning {
        code: "COMPOSITE_SCHEMA_GUESS".into(),
        message: "No anyOf branch had a resolvable example".into(),
        operation_ref: Some(op_ref.to_owned()),
      });
      Ok(None)
    }
    Schema::Not(_) => Ok(None),
    Schema::Single(single) => resolve_single_schema_value(single, ctx, op_ref, warnings),
  }
}

fn resolve_single_schema_value(
  single: &SingleSchema,
  ctx: &mut NormalizeContext<'_>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<Option<(String, ValueSource)>, SpecImportError> {
  match single {
    SingleSchema::String(string_schema) => {
      if let Some(example) = &string_schema.example {
        return Ok(Some((json_scalar_to_string(example), ValueSource::FromExample)));
      }
      if let Some(default) = &string_schema.default {
        return Ok(Some((default.clone(), ValueSource::FromDefault)));
      }
      if let Some(values) = &string_schema.enum_values {
        if let Some(first) = values.first() {
          return Ok(Some((first.clone(), ValueSource::FromEnum)));
        }
      }
      if !ctx.enable_schema_synthesis {
        return Ok(None);
      }
      Ok(Some((String::new(), ValueSource::Synthesized)))
    }
    SingleSchema::Integer(integer_schema) => {
      if let Some(example) = &integer_schema.example {
        return Ok(Some((json_scalar_to_string(example), ValueSource::FromExample)));
      }
      if let Some(default) = integer_schema.default {
        return Ok(Some((default.to_string(), ValueSource::FromDefault)));
      }
      if let Some(values) = &integer_schema.enum_values {
        if let Some(first) = values.first() {
          return Ok(Some((first.to_string(), ValueSource::FromEnum)));
        }
      }
      if !ctx.enable_schema_synthesis {
        return Ok(None);
      }
      let fallback = integer_schema
        .minimum
        .as_ref()
        .and_then(serde_json::Number::as_i64)
        .unwrap_or(0);
      Ok(Some((fallback.to_string(), ValueSource::Synthesized)))
    }
    SingleSchema::Number(number_schema) => {
      if let Some(example) = &number_schema.example {
        return Ok(Some((json_scalar_to_string(example), ValueSource::FromExample)));
      }
      if let Some(default) = number_schema.default {
        return Ok(Some((default.to_string(), ValueSource::FromDefault)));
      }
      if let Some(values) = &number_schema.enum_values {
        if let Some(first) = values.first() {
          return Ok(Some((first.to_string(), ValueSource::FromEnum)));
        }
      }
      if !ctx.enable_schema_synthesis {
        return Ok(None);
      }
      let fallback = number_schema.minimum.unwrap_or(0.0);
      Ok(Some((fallback.to_string(), ValueSource::Synthesized)))
    }
    SingleSchema::Boolean(boolean_schema) => {
      if let Some(example) = &boolean_schema.example {
        return Ok(Some((json_scalar_to_string(example), ValueSource::FromExample)));
      }
      if let Some(default) = boolean_schema.default {
        return Ok(Some((default.to_string(), ValueSource::FromDefault)));
      }
      if !ctx.enable_schema_synthesis {
        return Ok(None);
      }
      Ok(Some(("false".into(), ValueSource::Synthesized)))
    }
    SingleSchema::Array(array_schema) => {
      if let Some(example) = &array_schema.example {
        return Ok(Some((json_scalar_to_string(example), ValueSource::FromExample)));
      }
      if let Some(items) = &array_schema.items {
        if let Some((item_value, source)) = resolve_schema_example(items, ctx, op_ref, warnings)? {
          let array = serde_json::json!([serde_json::from_str::<Value>(&item_value).unwrap_or(Value::String(item_value))]);
          return Ok(Some((serde_json::to_string(&array).unwrap_or_default(), source)));
        }
      }
      if !ctx.enable_schema_synthesis {
        return Ok(None);
      }
      Ok(Some(("[]".into(), ValueSource::Synthesized)))
    }
    SingleSchema::Object(object_schema) => resolve_object_schema_value(object_schema, ctx, op_ref, warnings),
    SingleSchema::Null(_) => {
      if !ctx.enable_schema_synthesis {
        return Ok(None);
      }
      Ok(Some(("null".into(), ValueSource::Synthesized)))
    }
  }
}

fn resolve_object_schema_value(
  object_schema: &ObjectSchema,
  ctx: &mut NormalizeContext<'_>,
  op_ref: &str,
  warnings: &mut Vec<SpecWarning>,
) -> Result<Option<(String, ValueSource)>, SpecImportError> {
  if let Some(example) = &object_schema.example {
    return Ok(Some((json_scalar_to_string(example), ValueSource::FromExample)));
  }

  let required: HashSet<&str> = object_schema
    .required
    .as_ref()
    .map(|items| items.iter().map(String::as_str).collect())
    .unwrap_or_default();

  let mut properties = serde_json::Map::new();
  let mut used_synthesis = false;
  if let Some(props) = &object_schema.properties {
    for (name, schema_ref) in props {
      let include = required.contains(name.as_str()) || ENABLE_OPTIONAL_PARAMETERS;
      if !include {
        continue;
      }
      if let Some((value, source)) = resolve_schema_example(schema_ref, ctx, op_ref, warnings)? {
        if source == ValueSource::Synthesized {
          used_synthesis = true;
        }
        properties.insert(
          name.clone(),
          serde_json::from_str(&value).unwrap_or(Value::String(value)),
        );
      }
    }
  }

  if properties.is_empty() {
    return Ok(None);
  }

  let json = serde_json::to_string(&Value::Object(properties)).unwrap_or_else(|_| "{}".into());
  if used_synthesis {
    if !ctx.enable_schema_synthesis {
      return Ok(None);
    }
    Ok(Some((json, ValueSource::Synthesized)))
  } else {
    Ok(Some((json, ValueSource::FromExample)))
  }
}

fn normalize_operation_auth(
  spec: &V3Spec,
  operation: &Operation,
  primary_key: &str,
) -> Option<NormalizedAuth> {
  let requirements = operation
    .security
    .as_ref()
    .or(spec.security.as_ref())?;

  let first_requirement = requirements.first()?;
  if first_requirement.is_empty() {
    return None;
  }

  let (scheme_name, scopes) = first_requirement.iter().next()?;
  let scheme = spec
    .components
    .as_ref()
    .and_then(|components| components.security_schemes.as_ref())
    .and_then(|schemes| schemes.get(scheme_name))
    .and_then(|scheme_ref| scheme_ref.get_item(spec).ok())?;

  Some(scaffold_auth(scheme, scheme_name, scopes, primary_key))
}

fn scaffold_auth(
  scheme: &SecurityScheme,
  scheme_name: &str,
  requested_scopes: &[String],
  _primary_key: &str,
) -> NormalizedAuth {
  match scheme {
    SecurityScheme::HTTP(http) => NormalizedAuth::without_oauth2_scaffold(
      format!("http:{}", http.scheme),
      Some("Authorization".into()),
      None,
      match http.scheme {
        roas::v3_0::security_scheme::HttpScheme::Basic => "Basic {{username}}:{{password}}",
        roas::v3_0::security_scheme::HttpScheme::Bearer => "Bearer {{token}}",
        _ => "{{token}}",
      },
    ),
    SecurityScheme::ApiKey(api_key) => NormalizedAuth::without_oauth2_scaffold(
      "apiKey",
      if api_key.location == roas::v3_0::security_scheme::ApiKeyLocation::Header {
        Some(api_key.name.clone())
      } else {
        None
      },
      if api_key.location == roas::v3_0::security_scheme::ApiKeyLocation::Query {
        Some(api_key.name.clone())
      } else {
        None
      },
      format!("{{{{{scheme_name}}}}}"),
    ),
    SecurityScheme::OAuth2(oauth) => {
      let (grant_type, auth_url, token_url) = oauth2_flow_scaffold(&oauth.flows, requested_scopes);
      let scopes = if requested_scopes.is_empty() {
        None
      } else {
        Some(requested_scopes.join(" "))
      };
      NormalizedAuth {
        scheme_type: "oauth2".into(),
        header_name: Some("Authorization".into()),
        query_name: None,
        placeholder_value: "Bearer {{token}}".into(),
        oauth2_grant_type: Some(grant_type),
        oauth2_auth_url: auth_url,
        oauth2_token_url: token_url,
        oauth2_scopes: scopes,
      }
    }
    SecurityScheme::OpenIdConnect(_) => NormalizedAuth::without_oauth2_scaffold(
      "openIdConnect",
      Some("Authorization".into()),
      None,
      "Bearer {{token}}",
    ),
  }
}

fn oauth2_flow_scaffold(
  flows: &OAuth2Flows,
  requested_scopes: &[String],
) -> (String, Option<String>, Option<String>) {
  if let Some(selection) = select_oauth2_flow(flows, requested_scopes, true) {
    return selection;
  }
  select_oauth2_flow(flows, requested_scopes, false)
    .unwrap_or_else(|| ("clientCredentials".into(), None, None))
}

fn select_oauth2_flow(
  flows: &OAuth2Flows,
  requested_scopes: &[String],
  require_scope_match: bool,
) -> Option<(String, Option<String>, Option<String>)> {
  if let Some(flow) = flows.authorization_code.as_ref() {
    if oauth2_flow_matches(&flow.scopes, requested_scopes, require_scope_match) {
      return Some((
        "authorizationCode".into(),
        Some(flow.authorization_url.clone()),
        Some(flow.token_url.clone()),
      ));
    }
  }
  if let Some(flow) = flows.implicit.as_ref() {
    if oauth2_flow_matches(&flow.scopes, requested_scopes, require_scope_match) {
      return Some((
        "implicit".into(),
        Some(flow.authorization_url.clone()),
        None,
      ));
    }
  }
  if let Some(flow) = flows.password.as_ref() {
    if oauth2_flow_matches(&flow.scopes, requested_scopes, require_scope_match) {
      return Some(("password".into(), None, Some(flow.token_url.clone())));
    }
  }
  if let Some(flow) = flows.client_credentials.as_ref() {
    if oauth2_flow_matches(&flow.scopes, requested_scopes, require_scope_match) {
      return Some((
        "clientCredentials".into(),
        None,
        Some(flow.token_url.clone()),
      ));
    }
  }

  None
}

fn oauth2_flow_matches(
  available_scopes: &BTreeMap<String, String>,
  requested_scopes: &[String],
  require_scope_match: bool,
) -> bool {
  if !require_scope_match || requested_scopes.is_empty() {
    return true;
  }
  requested_scopes
    .iter()
    .all(|scope| available_scopes.contains_key(scope))
}

fn json_scalar_to_string(value: &Value) -> String {
  match value {
    Value::String(text) => text.clone(),
    Value::Null => String::new(),
    other => other.to_string(),
  }
}

fn map_resolve_error(err: roas::common::reference::ResolveError) -> SpecImportError {
  match err {
    roas::common::reference::ResolveError::ExternalUnsupported(reference) => {
      if reference.starts_with("http://") || reference.starts_with("https://") {
        SpecImportError::InvalidSpec(format!("Remote $ref is not allowed: {reference}"))
      } else {
        SpecImportError::InvalidSpec(format!("External $ref is not allowed in P0: {reference}"))
      }
    }
    roas::common::reference::ResolveError::External { reference, source } => {
      SpecImportError::InvalidSpec(format!(
        "Failed to resolve external reference `{reference}`: {source}"
      ))
    }
    roas::common::reference::ResolveError::NotFound(reference) => {
      SpecImportError::InvalidSpec(format!("Unresolved $ref: {reference}"))
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  fn minimal_spec_json() -> Value {
    json!({
      "openapi": "3.0.0",
      "info": { "title": "Test API", "version": "1.0.0" },
      "paths": {
        "/pets": {
          "get": {
            "operationId": "listPets",
            "responses": { "200": { "description": "ok" } }
          }
        }
      }
    })
  }

  #[test]
  fn rejects_duplicate_operation_id() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "paths": {
        "/a": {
          "get": {
            "operationId": "dup",
            "responses": { "200": { "description": "ok" } }
          }
        },
        "/b": {
          "post": {
            "operationId": "dup",
            "responses": { "200": { "description": "ok" } }
          }
        }
      }
    });

    let err = normalize_openapi(spec, SpecParseOptions::default()).expect_err("duplicate operationId");
    assert!(matches!(err, SpecImportError::InvalidSpec(message) if message.contains("Duplicate operationId")));
  }

  #[test]
  fn rejects_remote_ref_during_normalize() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "paths": {
        "/pets": {
          "get": {
            "responses": { "200": { "description": "ok" } },
            "parameters": [
              { "$ref": "https://example.com/param.json" }
            ]
          }
        }
      }
    });

    let err = normalize_openapi(spec, SpecParseOptions::default()).expect_err("remote ref");
    assert!(matches!(err, SpecImportError::InvalidSpec(message) if message.contains("Remote $ref")));
  }

  #[test]
  fn rejects_cyclic_schema_ref() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "paths": {
        "/pets": {
          "post": {
            "responses": { "200": { "description": "ok" } },
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": { "$ref": "#/components/schemas/A" }
                }
              }
            }
          }
        }
      },
      "components": {
        "schemas": {
          "A": { "$ref": "#/components/schemas/B" },
          "B": { "$ref": "#/components/schemas/A" }
        }
      }
    });

    let err = normalize_openapi(spec, SpecParseOptions::default()).expect_err("cyclic ref");
    assert!(matches!(err, SpecImportError::InvalidSpec(message) if message.contains("Cyclic $ref")));
  }

  #[test]
  fn skips_declared_tags_without_primary_operations() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "tags": [
        { "name": "users" },
        { "name": "billing" },
        { "name": "admin" }
      ],
      "paths": {
        "/users": {
          "get": {
            "tags": ["users", "admin"],
            "responses": { "200": { "description": "ok" } }
          }
        },
        "/invoices": {
          "get": {
            "tags": ["billing"],
            "responses": { "200": { "description": "ok" } }
          }
        }
      }
    });

    let result = normalize_openapi(spec, SpecParseOptions::default()).expect("normalize");
    let folder_names: Vec<_> = result.project.folders.iter().map(|folder| folder.name.as_str()).collect();
    assert_eq!(folder_names, vec!["users", "billing"]);
    assert!(
      result
        .warnings
        .iter()
        .any(|warning| warning.code == "UNUSED_DECLARED_TAG" && warning.message.contains("admin")),
      "expected UNUSED_DECLARED_TAG for admin, got {:?}",
      result.warnings
    );
  }

  #[test]
  fn normalizes_minimal_openapi_project() {
    let result = normalize_openapi(minimal_spec_json(), SpecParseOptions::default()).expect("normalize");
    assert_eq!(result.project.title, "Test API");
    assert_eq!(result.project.operations.len(), 1);
    assert_eq!(result.project.operations[0].primary_key, "listPets");
    assert!(!result.content_fingerprint.is_empty());
  }

  #[test]
  fn extracts_icon_url_from_x_logo() {
    let spec = json!({
      "openapi": "3.1.0",
      "info": {
        "title": "Logo API",
        "version": "1",
        "x-logo": {
          "url": "https://docs.example.com/logo.svg"
        }
      },
      "paths": {
        "/pets": {
          "get": {
            "operationId": "listPets",
            "responses": { "200": { "description": "ok" } }
          }
        }
      }
    });

    let result = normalize_openapi(spec, SpecParseOptions::default()).expect("normalize");
    assert_eq!(
      result.project.icon_url.as_deref(),
      Some("https://docs.example.com/logo.svg")
    );
  }

  #[test]
  fn extracts_favicon_from_first_server_when_logo_missing() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "Server Icon API", "version": "1" },
      "servers": [{ "url": "https://api.example.com/v1" }],
      "paths": {
        "/pets": {
          "get": {
            "operationId": "listPets",
            "responses": { "200": { "description": "ok" } }
          }
        }
      }
    });

    let result = normalize_openapi(spec, SpecParseOptions::default()).expect("normalize");
    assert_eq!(
      result.project.icon_url.as_deref(),
      Some("https://api.example.com/favicon.ico")
    );
  }

  #[test]
  fn warns_on_operation_level_server() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "paths": {
        "/pets": {
          "get": {
            "servers": [{ "url": "https://op.example.test" }],
            "responses": { "200": { "description": "ok" } }
          }
        }
      }
    });

    let result = normalize_openapi(spec, SpecParseOptions::default()).expect("normalize");
    assert!(result
      .warnings
      .iter()
      .any(|warning| warning.code == "OPERATION_SERVER_IGNORED"));
  }

  #[test]
  fn collects_multiple_content_type_candidates() {
    let spec = json!({
      "openapi": "3.0.0",
      "info": { "title": "T", "version": "1" },
      "paths": {
        "/pets": {
          "post": {
            "responses": { "200": { "description": "ok" } },
            "requestBody": {
              "content": {
                "application/json": { "example": { "name": "Fluffy" } },
                "application/xml": { "example": "<pet/>" }
              }
            }
          }
        }
      }
    });

    let result = normalize_openapi(spec, SpecParseOptions::default()).expect("normalize");
    let operation = &result.project.operations[0];
    assert_eq!(operation.body_candidates.len(), 2);
    assert_eq!(operation.body_candidates[0].content_type, "application/json");
    assert_eq!(operation.body_candidates[1].content_type, "application/xml");
    match &operation.body {
      NormalizedBody::Json { content } => assert!(content.contains("Fluffy")),
      other => panic!("expected json body, got {other:?}"),
    }
  }
}