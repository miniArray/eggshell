//! spike_pillar.gd (o13): a full-solid block crowned with a deadly spike, turned by its
//! placement angle in quarter turns. Touching the spike edge is fatal; the other faces
//! are safe.
use crate::{
    body::Body,
    math::{turn_cosine, turn_sine},
    Error, Placement, PropertyValue, SCALE as S,
};

const HALF: i64 = 16 * S;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Pillar {
    pub turn: i64,
}

impl Pillar {
    /// spike_pillar.gd prepare + create: R in whole quarter turns.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let refuse = |why: &str| Error::Unsupported {
            requirements: vec![format!("o13 {why}")],
        };
        // registry.gd numeric_option: a number, or a string holding one.
        let angle = match p.properties.iter().find(|(k, _)| k == "R").map(|(_, v)| v) {
            None => 0.0,
            Some(PropertyValue::String(s)) if s.trim().is_empty() => {
                return Err(refuse("invalid spike angle"))
            }
            Some(PropertyValue::Number(_) | PropertyValue::String(_)) => {
                crate::clouds::option(p, "R")?
            }
            Some(_) => return Err(refuse("invalid spike angle")),
        };
        let turned = angle.rem_euclid(360.0);
        if turned != turned.floor() || turned as i64 % 90 != 0 {
            return Err(refuse(&format!(
                "spike angle R={angle} (degrades to a placeholder)"
            )));
        }
        Ok(Self {
            turn: turned as i64 / 90,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-HALF, -HALF, HALF, HALF]
    }
    /// spike_pillar.gd solid_box.
    pub fn solid(&self, status: i64, body: Body) -> Option<[i64; 4]> {
        (status == 1).then_some([
            body.x - HALF,
            body.y - HALF,
            body.x + HALF,
            body.y + HALF,
        ])
    }
    /// spike_pillar.gd spike_box: the 32 x 2 edge centred on the face the spike points
    /// out of.
    pub fn spike_box(&self, body: Body) -> [i64; 4] {
        let angle = self.turn * 90_000 - 90_000;
        let cx = body.x + HALF * turn_cosine(angle, S) / S;
        let cy = body.y + HALF * turn_sine(angle, S) / S;
        if self.turn % 2 == 0 {
            [cx - HALF, cy - S, cx + HALF, cy + S]
        } else {
            [cx - S, cy - HALF, cx + S, cy + HALF]
        }
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        (n == "turn").then_some(self.turn)
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        if n == "turn" {
            self.turn = value;
            true
        } else {
            false
        }
    }
    pub fn valid(&self) -> bool {
        (0..=3).contains(&self.turn)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn spike_edge_faces_each_quarter_turn() {
        let at = Body {
            x: 100 * S,
            y: 100 * S,
            ..Body::default()
        };
        let edge = |turn| Pillar { turn }.spike_box(at);
        assert_eq!(edge(0), [84 * S, 83 * S, 116 * S, 85 * S]);
        assert_eq!(edge(1), [115 * S, 84 * S, 117 * S, 116 * S]);
        assert_eq!(edge(2), [84 * S, 115 * S, 116 * S, 117 * S]);
        assert_eq!(edge(3), [83 * S, 84 * S, 85 * S, 116 * S]);
    }
}
