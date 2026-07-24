use super::client::SseEvent;

#[derive(Default)]
pub(crate) struct SseParser {
  event_type: Option<String>,
  data_buf: String,
  last_id: Option<String>,
  line_buf: String,
}

impl SseParser {
  pub fn feed(&mut self, chunk: &[u8], events: &mut Vec<SseEvent>) {
    let text = String::from_utf8_lossy(chunk);
    for ch in text.chars() {
      if ch == '\n' || ch == '\r' {
        self.process_line(events);
        self.line_buf.clear();
      } else {
        self.line_buf.push(ch);
      }
    }
  }

  fn process_line(&mut self, events: &mut Vec<SseEvent>) {
    let line = &self.line_buf;

    if line.is_empty() {
      if !self.data_buf.is_empty() {
        if self.data_buf.ends_with('\n') {
          self.data_buf.pop();
        }
        let event_type = self.event_type.take().unwrap_or_else(|| "message".to_string());
        events.push(SseEvent::EventReceived {
          event_type,
          data: std::mem::take(&mut self.data_buf),
          id: self.last_id.clone(),
        });
      }
      self.event_type = None;
      return;
    }

    if line.starts_with(':') {
      return;
    }

    let (field, value) = if let Some(pos) = line.find(':') {
      let f = &line[..pos];
      let v = line[pos + 1..].strip_prefix(' ').unwrap_or(&line[pos + 1..]);
      (f, v)
    } else {
      (line.as_str(), "")
    };

    match field {
      "event" => self.event_type = Some(value.to_string()),
      "data" => {
        self.data_buf.push_str(value);
        self.data_buf.push('\n');
      }
      "id" => self.last_id = Some(value.to_string()),
      "retry" => {
        if let Ok(ms) = value.parse::<u64>() {
          events.push(SseEvent::RetryChanged { retry_ms: ms });
        }
      }
      _ => {}
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn parse_single_event() {
    let mut parser = SseParser::default();
    let mut events = Vec::new();
    parser.feed(b"data: hello world\n\n", &mut events);
    assert_eq!(events.len(), 1);
    if let SseEvent::EventReceived { event_type, data, id } = &events[0] {
      assert_eq!(event_type, "message");
      assert_eq!(data, "hello world");
      assert!(id.is_none());
    } else {
      panic!("expected EventReceived");
    }
  }

  #[test]
  fn parse_multi_line_data() {
    let mut parser = SseParser::default();
    let mut events = Vec::new();
    parser.feed(b"data: line1\ndata: line2\n\n", &mut events);
    assert_eq!(events.len(), 1);
    if let SseEvent::EventReceived { data, .. } = &events[0] {
      assert_eq!(data, "line1\nline2");
    } else {
      panic!("expected EventReceived");
    }
  }

  #[test]
  fn parse_custom_event_type() {
    let mut parser = SseParser::default();
    let mut events = Vec::new();
    parser.feed(b"event: update\ndata: payload\n\n", &mut events);
    assert_eq!(events.len(), 1);
    if let SseEvent::EventReceived { event_type, data, .. } = &events[0] {
      assert_eq!(event_type, "update");
      assert_eq!(data, "payload");
    } else {
      panic!("expected EventReceived");
    }
  }

  #[test]
  fn parse_event_with_id() {
    let mut parser = SseParser::default();
    let mut events = Vec::new();
    parser.feed(b"id: 42\ndata: test\n\n", &mut events);
    assert_eq!(events.len(), 1);
    if let SseEvent::EventReceived { id, .. } = &events[0] {
      assert_eq!(id.as_deref(), Some("42"));
    } else {
      panic!("expected EventReceived");
    }
  }

  #[test]
  fn parse_retry_field() {
    let mut parser = SseParser::default();
    let mut events = Vec::new();
    parser.feed(b"retry: 5000\n\n", &mut events);
    assert_eq!(events.len(), 1);
    if let SseEvent::RetryChanged { retry_ms } = &events[0] {
      assert_eq!(*retry_ms, 5000);
    } else {
      panic!("expected RetryChanged");
    }
  }

  #[test]
  fn comment_lines_are_ignored() {
    let mut parser = SseParser::default();
    let mut events = Vec::new();
    parser.feed(b": this is a comment\ndata: hello\n\n", &mut events);
    assert_eq!(events.len(), 1);
    if let SseEvent::EventReceived { data, .. } = &events[0] {
      assert_eq!(data, "hello");
    } else {
      panic!("expected EventReceived");
    }
  }

  #[test]
  fn partial_chunks_reassemble() {
    let mut parser = SseParser::default();
    let mut events = Vec::new();
    parser.feed(b"data: hel", &mut events);
    assert!(events.is_empty());
    parser.feed(b"lo\n\n", &mut events);
    assert_eq!(events.len(), 1);
    if let SseEvent::EventReceived { data, .. } = &events[0] {
      assert_eq!(data, "hello");
    } else {
      panic!("expected EventReceived");
    }
  }

  #[test]
  fn id_persists_across_events() {
    let mut parser = SseParser::default();
    let mut events = Vec::new();
    parser.feed(b"id: 1\ndata: first\n\ndata: second\n\n", &mut events);
    assert_eq!(events.len(), 2);
    if let SseEvent::EventReceived { id, .. } = &events[0] {
      assert_eq!(id.as_deref(), Some("1"));
    }
    if let SseEvent::EventReceived { id, .. } = &events[1] {
      assert_eq!(id.as_deref(), Some("1"));
    }
  }
}
