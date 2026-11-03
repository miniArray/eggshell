//! The level list entries of level_list.gd: file, display name, author, and whether the
//! level can be opened, with the reason when it cannot. Pure functions, no files.
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::cmp::Ordering;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub file: String,
    pub name: String,
    pub author: String,
    pub ok: bool,
    pub error: String,
}

/// level_list.gd _text: a string as is, a finite number without a ".0" fraction; line
/// breaks and tabs become spaces; edges stripped.
pub fn text(value: Option<&Value>) -> String {
    let raw = match value {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => match n.as_f64() {
            Some(v) if v.is_finite() => {
                if v.fract() == 0.0 && v.abs() < 1e15 {
                    format!("{}", v as i64)
                } else {
                    format!("{v}")
                }
            }
            _ => String::new(),
        },
        _ => String::new(),
    };
    let mut out = raw;
    for separator in ["\r\n", "\n", "\r", "\t"] {
        out = out.replace(separator, " ");
    }
    out.trim().to_owned()
}

/// level_list.gd entry: the list entry for one file whose text is `code`.
pub fn entry(file: &str, code: &str) -> Entry {
    let failed = |error: &str| Entry {
        file: file.to_owned(),
        name: file.to_owned(),
        author: String::new(),
        ok: false,
        error: error.to_owned(),
    };
    if code.is_empty() {
        return failed("Empty or unreadable");
    }
    let parsed: Value = match serde_json::from_str(code) {
        Ok(v) => v,
        Err(_) => return failed("Not a level code"),
    };
    if !parsed.get("maps").is_some_and(Value::is_object) {
        return failed("Not a level code");
    }
    let mut name = text(parsed.get("name"));
    if name.is_empty() {
        name = file.to_owned();
    }
    // An absent author can be exported as numeric zero; show no author then.
    let author = match parsed.get("author") {
        Some(Value::Number(n)) if n.as_f64() == Some(0.0) => String::new(),
        other => text(other),
    };
    Entry {
        file: file.to_owned(),
        name,
        author,
        ok: true,
        error: String::new(),
    }
}

/// Godot String.naturalnocasecmp_to: case-insensitive, digit runs compared as numbers.
pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let a: Vec<char> = a.to_lowercase().chars().collect();
    let b: Vec<char> = b.to_lowercase().chars().collect();
    let (mut i, mut j) = (0, 0);
    while i < a.len() && j < b.len() {
        if a[i].is_ascii_digit() && b[j].is_ascii_digit() {
            let si = i;
            while i < a.len() && a[i].is_ascii_digit() {
                i += 1;
            }
            let sj = j;
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
            let x: String = a[si..i].iter().collect::<String>();
            let y: String = b[sj..j].iter().collect::<String>();
            let x = x.trim_start_matches('0');
            let y = y.trim_start_matches('0');
            let order = x.len().cmp(&y.len()).then_with(|| x.cmp(y));
            if order != Ordering::Equal {
                return order;
            }
        } else {
            let order = a[i].cmp(&b[j]);
            if order != Ordering::Equal {
                return order;
            }
            i += 1;
            j += 1;
        }
    }
    (a.len() - i).cmp(&(b.len() - j))
}

/// Level list order: by shown title (natural, case-insensitive), then by file name.
/// Eggshell order, not level_list.gd's file order: titles put fan series in sequence
/// ("1-1 …", "1-2 …"), while corpus file names are numeric level IDs.
pub fn sort_by_title(levels: &mut [Entry]) {
    levels
        .sort_by(|a, b| natural_cmp(&a.name, &b.name).then_with(|| natural_cmp(&a.file, &b.file)));
}

/// The user-facing reason a level cannot be opened, from a core refusal.
pub fn refusal_reason(error: &eggshell_spike_core::Error) -> String {
    use eggshell_spike_core::Error;
    match error {
        Error::Unsupported { requirements } => {
            format!("Not supported yet: {}", requirements.join(", "))
        }
        Error::InvalidInput { context } => format!("Not a valid level: {context}"),
        Error::NotImplemented { operation } => format!("Not supported yet: {operation}"),
        Error::Snapshot { reason } => format!("Save problem: {reason}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn list_sorts_by_title_then_file() {
        let mut v = vec![
            entry("c.json", r#"{"name":"1-10 Castle","maps":{}}"#),
            entry("a.json", r#"{"name":"1-2 Cave","maps":{}}"#),
            entry("d.json", r#"{"name":"1-2 cave","maps":{}}"#),
            entry("b.json", r#"{"name":"1-1 Start","maps":{}}"#),
        ];
        sort_by_title(&mut v);
        let files: Vec<&str> = v.iter().map(|e| e.file.as_str()).collect();
        assert_eq!(files, ["b.json", "a.json", "d.json", "c.json"]);
    }
    #[test]
    fn entries_follow_level_list_rules() {
        let e = entry("a.json", r#"{"name":" Two\nlines ","author":0,"maps":{}}"#);
        assert_eq!(
            (e.name.as_str(), e.author.as_str(), e.ok),
            ("Two lines", "", true)
        );
        let e = entry("b.json", r#"{"name":"","author":12.0,"maps":{}}"#);
        assert_eq!((e.name.as_str(), e.author.as_str()), ("b.json", "12"));
        let e = entry("c.json", r#"{"name":"x"}"#);
        assert_eq!(
            (e.ok, e.error.as_str(), e.name.as_str()),
            (false, "Not a level code", "c.json")
        );
        assert_eq!(entry("d.json", "").error, "Empty or unreadable");
        assert_eq!(entry("e.json", "{").error, "Not a level code");
    }
    #[test]
    fn natural_order_is_case_insensitive_and_numeric() {
        let mut v = vec![
            "level10.json",
            "Level2.json",
            "level1.json",
            "b.json",
            "A.json",
        ];
        v.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(
            v,
            [
                "A.json",
                "b.json",
                "level1.json",
                "Level2.json",
                "level10.json"
            ]
        );
    }
}
