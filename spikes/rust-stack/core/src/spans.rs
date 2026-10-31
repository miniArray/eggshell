//! Fixed top-only spans (collision SOLID 2): plank_bridge.gd (p2), ledge_span.gd (p4, p5)
//! and wide_span.gd (p6..p10, p13..p21). They never step; their 2 px top strip supports
//! bodies from above only.
use crate::{entity::Entity, Error, Placement, PropertyValue, SCALE as S};

const MAX_WIDTH: i64 = 1_000_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum SpanKind {
    /// plank_bridge.gd and ledge_span.gd (the Plank geometry).
    Plank,
    /// wide_span.gd: drawn height and support offset from the top, in pixels.
    Wide { height: i64, offset: i64 },
    /// cloud_span.gd (p3): 48 px drawn, the strip 16 px above the centre.
    Cloud,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Span {
    pub kind: SpanKind,
    pub width: i64,
    pub stalk: i64,
}

fn property<'a>(p: &'a Placement, key: &str) -> Option<&'a PropertyValue> {
    p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn refuse(reason: &str) -> Error {
    Error::Unsupported {
        requirements: vec![reason.into()],
    }
}

/// plank_bridge.gd width_option: a finite number or numeric text, 0..MAX, rounded units.
fn plank_width(value: Option<&PropertyValue>) -> Result<i64, Error> {
    let number = match value {
        None => 96.0,
        Some(PropertyValue::Number(n)) => *n,
        Some(PropertyValue::String(s)) => s
            .trim()
            .parse::<f64>()
            .map_err(|_| refuse("invalid bridge width"))?,
        _ => return Err(refuse("invalid bridge width")),
    };
    if !number.is_finite() || !(0.0..=MAX_WIDTH as f64).contains(&number) {
        return Err(refuse("invalid bridge width"));
    }
    // GDScript roundi: half away from zero.
    Ok((number * S as f64).round() as i64)
}

/// registry.gd numeric_option for wide_span.gd E1: integer pixels.
fn wide_width(value: Option<&PropertyValue>, default: i64) -> Result<i64, Error> {
    let number = match value {
        None => default as f64,
        Some(PropertyValue::Number(n)) => *n,
        Some(PropertyValue::String(s)) => s
            .trim()
            .parse::<f64>()
            .map_err(|_| refuse("invalid span width"))?,
        _ => return Err(refuse("invalid span width")),
    };
    if !number.is_finite() || !(0.0..=MAX_WIDTH as f64).contains(&number) {
        return Err(refuse("invalid span width"));
    }
    Ok(number as i64 * S)
}

impl Span {
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let wide = |w: i64, height: i64, offset: i64| -> Result<Self, Error> {
            Ok(Self {
                kind: SpanKind::Wide { height, offset },
                width: wide_width(property(p, "E1"), w)?,
                stalk: 0,
            })
        };
        match p.code.as_str() {
            "p2" | "p4" => Ok(Self {
                kind: SpanKind::Plank,
                width: plank_width(property(p, "E1"))?,
                stalk: 0,
            }),
            "p5" => {
                // ledge_span.gd prepare: the stalk is E2's leading integer, capped.
                let stalk = match property(p, "E2") {
                    None => 0,
                    Some(PropertyValue::String(s)) => {
                        let digits: String =
                            s.trim().chars().take_while(char::is_ascii_digit).collect();
                        if digits.is_empty() {
                            0
                        } else {
                            digits.parse::<i64>().unwrap_or(MAX_WIDTH).min(MAX_WIDTH) * S
                        }
                    }
                    Some(PropertyValue::Number(n)) if n.is_finite() && *n >= 0.0 => {
                        (*n as i64).min(MAX_WIDTH) * S
                    }
                    _ => return Err(refuse("invalid ledge stalk height")),
                };
                Ok(Self {
                    kind: SpanKind::Plank,
                    width: plank_width(property(p, "E1"))?,
                    stalk,
                })
            }
            "p6" | "p7" | "p8" | "p14" | "p15" | "p16" | "p17" | "p18" | "p20" | "p21" => {
                wide(96, 32, 0)
            }
            "p9" => wide(96, 56, 12),
            "p3" => Ok(Self {
                kind: SpanKind::Cloud,
                width: wide_width(property(p, "E1"), 128)?,
                stalk: 0,
            }),
            "p10" => wide(128, 32, 0),
            "p13" => wide(80, 32, 0),
            "p19" => wide(64, 32, 0),
            other => Err(refuse(&format!("span {other}"))),
        }
    }
    pub fn height(&self) -> i64 {
        match self.kind {
            SpanKind::Plank => 32 * S,
            SpanKind::Wide { height, .. } => height * S,
            SpanKind::Cloud => 48 * S,
        }
    }
    pub fn bounds(&self) -> [i64; 4] {
        let h = self.height();
        [-self.width / 2, -h / 2, self.width / 2, h / 2]
    }
    /// The top-only 2 px support strip.
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        match self.kind {
            SpanKind::Cloud => (e.status == 1 && self.width != 0).then(|| {
                [
                    e.body.x - self.width / 2,
                    e.body.y - 16 * S,
                    e.body.x + self.width / 2,
                    e.body.y - 14 * S,
                ]
            }),
            SpanKind::Plank => (e.status == 1 && self.width > 0).then(|| {
                [
                    e.body.x - self.width / 2,
                    e.body.y - 16 * S,
                    e.body.x + self.width / 2,
                    e.body.y - 14 * S,
                ]
            }),
            SpanKind::Wide { height, offset } => (e.status == 1 && self.width != 0).then(|| {
                let top = e.body.y - height * S / 2 + offset * S;
                [
                    e.body.x - self.width / 2,
                    top,
                    e.body.x + self.width / 2,
                    top + 2 * S,
                ]
            }),
        }
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        match n {
            "width" => Some(self.width),
            "stalk" => Some(self.stalk),
            _ => None,
        }
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "width" => self.width = value,
            "stalk" => self.stalk = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        (0..=MAX_WIDTH * S).contains(&self.width) && (0..=MAX_WIDTH * S).contains(&self.stalk)
    }
}
