//! Static scenery codes (decor.gd): no step or contact; placement facts only.

/// decor.gd CODES
pub(crate) fn is_decor(code: &str) -> bool {
    let Some(index) = code.strip_prefix('d').and_then(|n| n.parse::<i64>().ok()) else {
        return false;
    };
    code == format!("d{index}")
        && (1..=76).contains(&index)
        && ![5, 6, 7, 8, 22, 23, 25, 26].contains(&index)
}
/// GDScript `code.substr(1).to_int()`: 0 for an empty or non-numeric tail.
fn index(code: &str) -> i64 {
    code.get(1..).and_then(|n| n.parse().ok()).unwrap_or(0)
}
/// decor.gd resized: extendable scenery with an E1 height.
pub(crate) fn resized(code: &str) -> bool {
    let i = index(code);
    (14..=23).contains(&i)
        || [27, 28, 75].contains(&i)
        || (31..=54).contains(&i)
        || (56..=67).contains(&i)
}
/// decor.gd frame_count
pub(crate) fn frame_count(code: &str) -> i64 {
    let i = index(code);
    if [1, 2, 22, 23].contains(&i) {
        2
    } else if [3, 4].contains(&i) {
        5
    } else if (5..=13).contains(&i) || [25, 26].contains(&i) {
        4
    } else if (68..=72).contains(&i) {
        7
    } else if [75, 76].contains(&i) {
        6
    } else {
        1
    }
}
/// decor.gd layer_for
pub(crate) fn layer_for(code: &str) -> i64 {
    let i = index(code);
    if (14..=21).contains(&i) || (31..=54).contains(&i) {
        5
    } else if (9..=13).contains(&i) {
        12
    } else if i == 23 {
        6
    } else {
        7
    }
}

/// decor.gd MAX_PIXELS: MAX_COORD / S - 1024, MAX_COORD = int max / 16384.
const MAX_PIXELS: i64 = i64::MAX / 16384 / crate::SCALE - 1024;

/// Godot String.is_valid_float: the whole text is one decimal number.
fn valid_float(text: &str) -> Option<f64> {
    let body = text.strip_prefix(['+', '-']).unwrap_or(text);
    if body.is_empty()
        || text.contains(char::is_whitespace)
        || !body.starts_with(|c: char| c.is_ascii_digit() || c == '.')
    {
        return None;
    }
    text.parse::<f64>().ok()
}

/// decor.gd size_option of E1 as prepare_options keeps it: `float(int(value))`. A
/// missing E1 reads 0; text must be a whole decimal number; the value must be finite and
/// within 0..=MAX_PIXELS, else the level does not load.
pub(crate) fn height(p: &crate::Placement) -> Result<i64, crate::Error> {
    let invalid = || crate::Error::InvalidInput {
        context: "Invalid scenery height".into(),
    };
    let value = match p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v) {
        None => 0.0,
        Some(crate::PropertyValue::Number(v)) => *v,
        Some(crate::PropertyValue::String(s)) => valid_float(s.trim()).ok_or_else(invalid)?,
        Some(_) => return Err(invalid()),
    };
    if !value.is_finite() || value < 0.0 || value > MAX_PIXELS as f64 {
        return Err(invalid());
    }
    Ok(value as i64)
}

/// decor.gd prepare_options: extendable scenery must be neither mirrored nor turned
/// (fposmod(R, 360) == 0); otherwise it degrades.
pub(crate) fn untransformed(p: &crate::Placement) -> bool {
    let rotation = match p.properties.iter().find(|(k, _)| k == "R").map(|(_, v)| v) {
        Some(crate::PropertyValue::Number(v)) => *v,
        _ => 0.0,
    };
    p.mirror == 0 && rotation.rem_euclid(360.0) == 0.0
}

#[cfg(test)]
mod tests {
    use super::*;
    fn placement(props: serde_json::Value, mirror: i64) -> crate::Placement {
        let crate::PropertyValue::Object(properties) = crate::world::property_for_tests(&props)
        else {
            unreachable!()
        };
        crate::Placement {
            id: "1".into(),
            code: "d28".into(),
            position: crate::Position::default(),
            variant: 0,
            mirror,
            rotation: 0,
            layer: 7,
            properties,
            prepared: crate::PreparedPlacement::None,
        }
    }
    #[test]
    fn height_follows_size_option() {
        let h = |v| height(&placement(v, 0));
        assert_eq!(h(serde_json::json!({})).unwrap(), 0);
        assert_eq!(h(serde_json::json!({"E1": 96.7})).unwrap(), 96);
        assert_eq!(h(serde_json::json!({"E1": " 128 "})).unwrap(), 128);
        assert_eq!(h(serde_json::json!({"E1": "1e2"})).unwrap(), 100);
        for bad in [
            serde_json::json!({"E1": "12px"}),
            serde_json::json!({"E1": -1}),
            serde_json::json!({"E1": ""}),
            serde_json::json!({"E1": true}),
            serde_json::json!({"E1": 1e300}),
        ] {
            assert!(height(&placement(bad, 0)).is_err());
        }
    }
    #[test]
    fn transformed_extendable_scenery_degrades() {
        assert!(untransformed(&placement(serde_json::json!({"R": 360}), 0)));
        assert!(!untransformed(&placement(serde_json::json!({"R": 90}), 0)));
        assert!(!untransformed(&placement(serde_json::json!({"R": 0.5}), 0)));
        assert!(!untransformed(&placement(serde_json::json!({}), 1)));
    }
}
