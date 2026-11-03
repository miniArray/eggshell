//! snow_tree.gd (d22): extendable snowy scenery. Player contact emits cosmetic puffs
//! whose birth records are saved state. The player does not draw the puffs yet.
use crate::{
    entity::Kind, math::screen_centre, state::Run, Error, Placement, Position, PropertyValue,
    SCALE as S,
};
/// decor.gd MAX_COORD and MAX_PIXELS.
const MAX_COORD: i64 = i64::MAX / 16384;
const MAX_PIXELS: i64 = MAX_COORD / S - 1024;

fn refuse(what: String) -> Error {
    Error::Unsupported {
        requirements: vec![format!("d22 {what}")],
    }
}

/// snow_tree.gd FIELDS.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SnowTree {
    pub variant: i64,
    pub height: i64,
    /// (x, y, birth tick) of the eight puff slots; tick -1 is empty.
    pub puffs: [[i64; 3]; 8],
}

impl SnowTree {
    /// snow_tree.gd prepare (decor.gd prepare_options) + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) || p.mirror != 0 || p.rotation != 0 {
            // Larger forms, mirrored or turned extendable scenery degrade to a
            // placeholder (not ported).
            return Err(refuse(format!(
                "form F={} M={} R={}",
                p.variant, p.mirror, p.rotation
            )));
        }
        // decor.gd size_option: a number or numeric text, 0..MAX_PIXELS.
        let height = match p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v) {
            None => 0.0,
            Some(PropertyValue::Number(v)) => *v,
            Some(PropertyValue::String(s)) => s
                .trim()
                .parse::<f64>()
                .map_err(|_| refuse("height E1".into()))?,
            Some(_) => return Err(refuse("height E1".into())),
        };
        if !height.is_finite() || height < 0.0 || height > MAX_PIXELS as f64 {
            return Err(refuse("height E1".into()));
        }
        Ok(Self {
            variant: p.variant,
            height: height as i64 * S,
            puffs: [[0, 0, -1]; 8],
        })
    }
    /// snow_tree.gd crown: the snowy triangle (apex, right foot, left foot).
    fn crown(&self, x: i64, y: i64) -> [Position; 3] {
        let large = self.variant == 1;
        let center_y = y + if large { 290 } else { 144 } * S - self.height;
        let half = if large { 80 } else { 48 } * S;
        let top = center_y - if large { 268 } else { 138 } * S;
        let bottom = center_y - if large { 48 } else { 18 } * S;
        [
            Position { x, y: top },
            Position {
                x: x + half,
                y: bottom,
            },
            Position {
                x: x - half,
                y: bottom,
            },
        ]
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "decor_variant" => self.variant,
            "decor_height" => self.height,
            _ => {
                let rest = n.strip_prefix("puff_")?;
                let (slot, axis) = rest.split_once('_')?;
                let slot: usize = slot.parse().ok().filter(|s| *s < 8)?;
                self.puffs[slot][["x", "y", "tick"].iter().position(|a| *a == axis)?]
            }
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "decor_variant" => self.variant = value,
            "decor_height" => self.height = value,
            _ => {
                let Some((slot, axis)) = n.strip_prefix("puff_").and_then(|r| r.split_once('_'))
                else {
                    return false;
                };
                let Some(slot) = slot.parse::<usize>().ok().filter(|s| *s < 8) else {
                    return false;
                };
                let Some(axis) = ["x", "y", "tick"].iter().position(|a| *a == axis) else {
                    return false;
                };
                self.puffs[slot][axis] = value;
            }
        }
        true
    }
    pub fn valid(&self) -> bool {
        [0, 1].contains(&self.variant)
            && (0..=MAX_COORD).contains(&self.height)
            && self.height % S == 0
            && self.puffs.iter().all(|p| {
                p[2] >= -1
                    && (-MAX_COORD..=MAX_COORD).contains(&p[0])
                    && (-MAX_COORD..=MAX_COORD).contains(&p[1])
            })
    }
}

impl Run {
    /// snow_tree.gd contact (contact phase 0): every sixth tick, a moving player inside
    /// the on-screen crown leaves a puff.
    pub(crate) fn snow_tree_contact(&mut self, index: usize, map: &crate::body::Probe) {
        let frame = self.frame;
        let p = self.player.body;
        if frame % 6 != 0 || (p.vx == 0 && p.vy == 0) {
            return;
        }
        let centre = screen_centre(self.camera, map.width_pixels * S, map.height_pixels * S);
        let screen = [
            centre.x - 416 * S,
            centre.y - 224 * S,
            centre.x + 416 * S,
            centre.y + 224 * S,
        ];
        let body = self.player.bounds();
        let e = &mut self.entities[index];
        let Kind::SnowTree(t) = &mut e.kind else {
            return;
        };
        let points = t.crown(e.body.x, e.body.y);
        let left = e.body.x - if t.variant == 1 { 80 } else { 48 } * S;
        if left + 160 * S < screen[0]
            || left > screen[2]
            || points[0].y > screen[3]
            || points[0].y + 316 * S < screen[1]
        {
            return;
        }
        let pbox = [p.x + body[0], p.y + body[1], p.x + body[2], p.y + body[3]];
        if pbox[2] < points[2].x
            || pbox[0] > points[1].x
            || pbox[3] < points[0].y
            || pbox[1] > points[1].y
        {
            return;
        }
        if !crate::polygon::overlaps_box(&points, pbox) {
            return;
        }
        let dx = p.x - e.body.x;
        let mut x = 0;
        if dx > -16 * S && dx < 16 * S {
            x = e.body.x;
        } else if dx > -48 * S && dx < -16 * S {
            x -= 32 * S;
        } else if dx > 16 * S && dx < 48 * S {
            x += 32 * S;
        } else if t.variant == 1 && dx > -80 * S && dx < -48 * S {
            x -= 64 * S;
        } else if t.variant == 1 && dx > 48 * S && dx < 80 * S {
            x += 64 * S;
        }
        let (top, bottom) = (points[0].y, points[1].y);
        let mut y = 0;
        if p.y < top {
            y = top + 16 * S;
        } else if p.y > top && p.y < bottom {
            y = p.y;
        } else if p.y > bottom {
            y = bottom - 16 * S;
        }
        if x <= 0 || y <= 0 {
            return;
        }
        let slot = (frame / 6 % 8) as usize;
        t.puffs[slot] = [x, y, frame];
    }
}
