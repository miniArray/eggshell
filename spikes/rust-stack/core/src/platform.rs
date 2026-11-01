//! decor_platform.gd: static scenery ledges, top-only strips that must not fill the gaps
//! between them (only d6, one strip, is admitted here), and lamp.gd candles (d25).
use crate::{body::Body, Error, Placement, PropertyValue, SCALE as S};

/// decor_platform.gd solid_boxes for d6: [left, top, right, bottom] in pixels.
const D6_STRIP: [i64; 4] = [-27, -18, 23, -16];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Platform {
    pub variant: i64,
    pub mirror: i64,
}

impl Platform {
    /// decor_platform.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let platform = Self::new_options(p)?;
        let rotation = match p.properties.iter().find(|(k, _)| k == "R").map(|(_, v)| v) {
            Some(PropertyValue::Number(v)) => v.rem_euclid(360.0),
            _ => 0.0,
        };
        if rotation != 0.0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "{} rotated scenery ledge (degrades to a placeholder)",
                    p.code
                )],
            });
        }
        Ok(platform)
    }
    /// decor.gd prepare_options: integral frame and mirror within the code's range.
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
            variant: p.variant,
            mirror: p.mirror,
        })
    }
    /// decor_platform.gd solid_boxes: the strip, mirrored about the placement.
    pub fn solid(&self, status: i64, body: Body) -> Option<[i64; 4]> {
        let [l, t, r, b] = D6_STRIP;
        let (left, right) = if self.mirror != 0 { (-r, -l) } else { (l, r) };
        (status == 1).then_some([
            body.x + left * S,
            body.y + t * S,
            body.x + right * S,
            body.y + b * S,
        ])
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
        (0..crate::decor::frame_count("d6")).contains(&self.variant)
            && [0, 1].contains(&self.mirror)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn mirrored_strip_flips_about_the_placement() {
        let at = Body::default();
        let plain = Platform {
            variant: 0,
            mirror: 0,
        };
        let mirrored = Platform {
            variant: 0,
            mirror: 1,
        };
        assert_eq!(
            plain.solid(1, at),
            Some([-27 * S, -18 * S, 23 * S, -16 * S])
        );
        assert_eq!(
            mirrored.solid(1, at),
            Some([-23 * S, -18 * S, 27 * S, -16 * S])
        );
        assert_eq!(plain.solid(3, at), None);
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
