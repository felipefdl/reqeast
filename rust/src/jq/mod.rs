use crate::error::ReqeastError;
use jaq_core::data;
use jaq_core::load::{Arena, Error as LoadError, File, Loader};
use jaq_core::{Compiler, Ctx, Vars, defs, funs, unwrap_valr};
use jaq_json::read;
use jaq_json::Val;

mod limits;
#[cfg(test)]
mod tests;

use limits::{MAX_JSON_DEPTH, MAX_OUTPUT_BYTES, MAX_OUTPUT_VALUES, exceeds_depth};

/// Walks a `load::Error<&str>` tree and emits a human-readable message. We do this manually
/// because `load::Error` only implements Debug, which leaks internal types like `Span { .. }`
/// and `File { .. }` to end users.
fn format_load_error(error: &LoadError<&str>) -> String {
  match error {
    LoadError::Io(pairs) => pairs.iter().map(|(_, msg)| msg.clone()).collect::<Vec<_>>().join("; "),
    LoadError::Lex(inner) => format_span_pairs("lex", inner),
    LoadError::Parse(inner) => format_span_pairs("parse", inner),
  }
}

fn format_span_pairs<E: core::fmt::Debug, S: core::fmt::Display>(prefix: &str, pairs: &[(E, S)]) -> String {
  let parts: Vec<String> = pairs
    .iter()
    .map(|(expect, span)| format!("{expect:?} near `{span}`"))
    .collect();
  format!("{prefix}: {}", parts.join("; "))
}

fn format_loader_errors(errs: &[(File<&str, ()>, LoadError<&str>)]) -> String {
  errs
    .iter()
    .map(|(_, e)| format_load_error(e))
    .collect::<Vec<_>>()
    .join("; ")
}

type CompileError<'a> = (File<&'a str, ()>, Vec<(&'a str, jaq_core::compile::Undefined)>);

fn format_compile_errors(errs: &[CompileError]) -> String {
  errs
    .iter()
    .flat_map(|(_, inner)| inner.iter())
    .map(|(name, und)| format!("`{name}`: {und:?}"))
    .collect::<Vec<_>>()
    .join("; ")
}

fn parse_json(input: &str) -> Result<Val, ReqeastError> {
  read::parse_single(input.as_bytes()).map_err(|e| ReqeastError::InvalidConfig(format!("Invalid JSON: {e}")))
}

#[uniffi::export]
pub fn jq_filter(json_input: String, filter_expression: String) -> Result<String, ReqeastError> {
  if exceeds_depth(&json_input, MAX_JSON_DEPTH) {
    return Err(ReqeastError::InvalidConfig(format!(
      "Invalid JSON: nesting deeper than {MAX_JSON_DEPTH} levels"
    )));
  }

  let input = parse_json(&json_input)?;

  let arena = Arena::default();
  let loader = Loader::new(defs().chain(jaq_std::defs()).chain(jaq_json::defs()));
  let modules = loader
    .load(
      &arena,
      File {
        path: (),
        code: &filter_expression,
      },
    )
    .map_err(|errs| ReqeastError::InvalidConfig(format!("Filter parse error: {}", format_loader_errors(&errs))))?;

  let filter = Compiler::default()
    .with_funs(funs().chain(jaq_std::funs()).chain(jaq_json::funs()))
    .compile(modules)
    .map_err(|errs| ReqeastError::InvalidConfig(format!("Filter compile error: {}", format_compile_errors(&errs))))?;

  let ctx = Ctx::<data::JustLut<Val>>::new(&filter.lut, Vars::new([]));
  let mut successes = Vec::new();
  let mut first_error: Option<String> = None;
  let mut total_bytes = 0usize;
  let mut truncated = false;

  // jq filters can emit multiple outputs per input. If any output succeeds, we return the joined
  // successes and discard errors (matches jq CLI behavior: `.[] | select(...)` over mixed data).
  // If every output failed, surface the first error so the user gets something actionable.
  // The caps bound user-typed programs with unbounded streams (`repeat(.)`); breaking out drops
  // the lazy iterator chain, which stops further evaluation.
  for v in filter.id.run((ctx, input)).map(unwrap_valr) {
    match v {
      Ok(val) => {
        let rendered = val.to_string();
        total_bytes += rendered.len();
        successes.push(rendered);
        if successes.len() >= MAX_OUTPUT_VALUES || total_bytes >= MAX_OUTPUT_BYTES {
          truncated = true;
          break;
        }
      }
      Err(e) => {
        if first_error.is_none() {
          first_error = Some(e.to_string());
        }
      }
    }
  }

  if successes.is_empty() {
    if let Some(err) = first_error {
      return Err(ReqeastError::InvalidConfig(err));
    }
  }

  if truncated {
    let count = successes.len();
    successes.push(format!(
      "... [output truncated after {count} values / {total_bytes} bytes]"
    ));
  }

  Ok(successes.join("\n"))
}