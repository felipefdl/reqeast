//! Criterion benchmarks for spec import normalization.

use std::fs;
use std::time::Duration;

use criterion::{Criterion, criterion_group, criterion_main};
use reqeast_core::spec_import::golden::fixtures_dir;
use reqeast_core::spec_import::types::{SpecParseOptions, SpecSourceHint, parse_spec};

fn bench_stress_500(c: &mut Criterion) {
  let bytes = fs::read(fixtures_dir().join("stress-500.input.yaml")).expect("stress-500 fixture");

  let mut group = c.benchmark_group("spec_import");
  group.sample_size(20);
  group.warm_up_time(Duration::from_millis(500));
  group.measurement_time(Duration::from_secs(5));
  group.bench_function("stress_500_parse_spec", |bencher| {
    bencher.iter(|| {
      let result = parse_spec(bytes.clone(), SpecSourceHint::Yaml, None, SpecParseOptions::default())
        .expect("stress-500 should parse");
      assert_eq!(result.project.operations.len(), 500);
    });
  });
  group.finish();
}

criterion_group!(benches, bench_stress_500);
criterion_main!(benches);
