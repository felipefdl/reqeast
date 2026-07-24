pub(crate) trait Pipe: Sized {
  fn pipe<T>(self, f: impl FnOnce(Self) -> T) -> T {
    f(self)
  }
}

impl<T> Pipe for T {}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn pipe_transforms_value() {
    assert_eq!(5.pipe(|x| x * 2), 10);
  }

  #[test]
  fn pipe_chains() {
    assert!("hello".pipe(|s| s.len()).pipe(|n| n > 3));
  }
}
