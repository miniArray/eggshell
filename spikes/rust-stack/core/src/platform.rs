//! decor_platform.gd: static scenery ledges (d5, d6, d7, d8, d23), top-only strips that
//! must not fill the gaps between them, and lamp.gd candles (d25, d26).
use crate::{body::Body, Error, Placement, PropertyValue, SCALE as S};

/// decor_platform.gd CODES.
pub(crate) const CODES: [&str; 5] = ["d5", "d6", "d7", "d8", "d23"];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Platform {
    /// Index into CODES.
    pub code: usize,
    pub variant: i64,
    pub mirror: i64,
}

impl Platform {
    /// decor_platform.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let refuse = |why: String| Error::Unsupported {
            requirements: vec![format!("{} {why}", p.code)],
        };
        let mut platform = Self::new_options(p)?;
        platform.code = CODES
            .iter()
            .position(|c| *c == p.code)
            .ok_or_else(|| refuse("is not a scenery ledge".into()))?;
        let raw = |key: &str| p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v);
        let rotation = match raw("R") {
            Some(PropertyValue::Number(v)) => v.rem_euclid(360.0),
            _ => 0.0,
        };
        // decor.gd prepare_options: extendable scenery (d23) is never transformed, and its
        // E1 height must parse.
        if p.code == "d23" {
            if platform.mirror != 0 || rotation != 0.0 {
                return Err(refuse(
                    "transformed extendable scenery (degrades to a placeholder)".into(),
                ));
            }
            let height = match raw("E1") {
                None => Some(0.0),
                Some(PropertyValue::Number(v)) => Some(*v),
                Some(PropertyValue::String(s)) => s.trim().parse::<f64>().ok(),
                Some(_) => None,
            };
            if !height.is_some_and(|h| h.is_finite() && h >= 0.0) {
                return Err(refuse("invalid scenery height".into()));
            }
        }
        if rotation != 0.0 {
            return Err(refuse(
                "rotated scenery ledge (degrades to a placeholder)".into(),
            ));
        }
        Ok(platform)
    }
    /// decor.gd prepare_options: integral frame and mirror within the code's range (also
    /// lamp.gd prepare; the caller sets `code`).
    fn new_options(p: &Placement) -> Result<Self, Error> {
        let refuse = |why: String| Error::Unsupported {
            requirements: vec![format!("{} {why}", p.code)],
        };
        let raw = |key: &str| p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v);
        for key in ["F", "M"] {
            if let Some(PropertyValue::Number(v)) = raw(key) {
                if *v != v.floor() {
                    return Err(refuse("scenery frame and mirror must be integers".into()));
                }
            }
        }
        if p.variant < 0 || p.mirror < 0 {
            return Err(refuse("invalid scenery frame or mirror".into()));
        }
        if p.variant >= crate::decor::frame_count(&p.code) || p.mirror > 1 {
            return Err(refuse(format!(
                "scenery frame F={} or mirror M={} (degrades to a placeholder)",
                p.variant, p.mirror
            )));
        }
        Ok(Self {
            code: 0,
            variant: p.variant,
            mirror: p.mirror,
        })
    }
    /// decor_platform.gd solid_boxes: [left, top, right, bottom] strips in pixels.
    fn strips(&self) -> &'static [[i64; 4]] {
        match (CODES[self.code], self.variant) {
            ("d5", _) => &[[-42, -32, 38, -30]],
            ("d6", _) => &[[-27, -18, 23, -16]],
            ("d7", _) => &[[-26, -48, 54, -46], [-55, 14, -5, 16]],
            ("d8", _) => &[[-38, -80, 42, -78], [21, -18, 71, -16], [-70, 16, 10, 18]],
            ("d23", 0) => &[[-32, -16, 28, -14]],
            _ => &[[-60, -48, 56, -46]],
        }
    }
    /// decor_platform.gd solid_boxes: each strip, mirrored about the placement.
    pub fn solids(&self, status: i64, body: Body) -> Vec<[i64; 4]> {
        if status != 1 {
            return Vec::new();
        }
        self.strips()
            .iter()
            .map(|&[l, t, r, b]| {
                let (left, right) = if self.mirror != 0 { (-r, -l) } else { (l, r) };
                [
                    body.x + left * S,
                    body.y + t * S,
                    body.x + right * S,
                    body.y + b * S,
                ]
            })
            .collect()
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "decor_variant" => self.variant,
            "decor_mirror" => self.mirror,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "decor_variant" => self.variant = value,
            "decor_mirror" => self.mirror = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        let code = CODES[self.code];
        (0..crate::decor::frame_count(code)).contains(&self.variant)
            && [0, 1].contains(&self.mirror)
            && (code != "d23" || self.mirror == 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn strips_mirror_about_the_placement() {
        let at = Body::default();
        let ledge = |code, variant, mirror| Platform {
            code,
            variant,
            mirror,
        };
        assert_eq!(
            ledge(1, 0, 0).solids(1, at),
            vec![[-27 * S, -18 * S, 23 * S, -16 * S]]
        );
        assert_eq!(
            ledge(1, 0, 1).solids(1, at),
            vec![[-23 * S, -18 * S, 27 * S, -16 * S]]
        );
        assert!(ledge(1, 0, 0).solids(3, at).is_empty());
        assert_eq!(ledge(3, 0, 0).solids(1, at).len(), 3);
        assert_eq!(
            ledge(4, 1, 0).solids(1, at),
            vec![[-60 * S, -48 * S, 56 * S, -46 * S]]
        );
    }
}

/// lamp.gd (d25 burns with fire, d26 with ice): a candle lamp. Its own element lights it
/// and the other puts it out (elements.rs: shots and lava bubbles).
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Lamp {
    pub style: i64,
    pub lit: i64,
    pub color: i64,
}

impl Lamp {
    /// lamp.gd prepare (decor.gd prepare_options) + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let platform = Platform::new_options(p)?;
        Ok(Self {
            style: platform.variant % 2,
            lit: i64::from(platform.variant < 2),
            color: i64::from(p.code == "d26"),
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-8 * S, -16 * S, 8 * S, 16 * S]
    }
    /// lamp.gd projectile_contact for a fire or ice striker: lit by its own element.
    pub fn touch(&mut self, fire: bool) {
        self.lit = i64::from(fire == (self.color == 0));
    }
    /// lamp.gd view_state animation: pack_dressing.gd maps it to the candle frames.
    pub fn animation(&self) -> String {
        format!(
            "{}:{}:{}",
            if self.lit != 0 { "lit" } else { "dim" },
            self.color,
            self.style
        )
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "lamp_style" => self.style,
            "lamp_lit" => self.lit,
            "lamp_color" => self.color,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "lamp_style" => self.style = value,
            "lamp_lit" => self.lit = value,
            "lamp_color" => self.color = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        [0, 1].contains(&self.style) && [0, 1].contains(&self.lit) && [0, 1].contains(&self.color)
    }
}
