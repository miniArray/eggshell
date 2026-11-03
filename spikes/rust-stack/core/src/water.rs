//! Integer buoyancy/bobbing from water.gd; terrain queries use compiled polygons.
use crate::{body::Probe, player::Player, SCALE as S};
const BOB: [i64; 31] = [
    0, 604, 1372, 2154, 2931, 3695, 4441, 5168, 5874, 6558, 7219, 7856, 8469, 9057, 9619, 10154,
    10662, 11142, 11594, 12016, 12407, 12767, 13094, 13388, 13647, 13871, 14057, 14204, 14312,
    14378, 14400,
];
fn bob(phase: i64) -> i64 {
    BOB[if phase <= 30 { phase } else { 60 - phase } as usize]
}
#[derive(Clone, Debug, Default)]
pub(crate) struct Water {
    pub swimming: i64,
    pub wait: i64,
    pub phase: i64,
    pub deep: i64,
    pub dive: i64,
    pub jump: i64,
    pub transition: i64,
}
impl Water {
    pub fn valid(&self) -> bool {
        [self.swimming, self.deep, self.dive, self.jump]
            .iter()
            .all(|v| [0, 1].contains(v))
            && (0..=16).contains(&self.wait)
            && (0..=59).contains(&self.phase)
            && (0..=9).contains(&self.transition)
    }
}
impl Player {
    pub fn liquid_body(&self, map: &Probe, b: [i64; 4]) -> bool {
        map.water_overlaps([
            self.body.x + b[0],
            self.body.y + b[1],
            self.body.x + b[2],
            self.body.y + b[3],
        ])
    }
    /// water.gd prepare; a frozen step keeps the water timers, gravity and bob still.
    pub fn prepare_water(
        &mut self,
        map: &Probe,
        input: u8,
        pressed: u8,
        frozen: bool,
    ) -> (i64, bool) {
        let (x, y) = (self.body.x, self.body.y);
        let w = &mut self.water;
        if w.swimming == 0
            && (map.water_at(x, y - 66 * S) || self.on_floor != 0 && map.water_at(x, y - 42 * S))
        {
            w.swimming = 1;
            self.life.hurt_deceleration = 128;
            w.phase = 0;
            w.wait = 0;
            w.deep = 0;
            w.jump = 0;
        }
        if w.swimming == 0 {
            return (0, false);
        }
        if w.jump != 0 && self.body.vy >= 0 {
            w.jump = 0;
        }
        let deep = map.water_at(x, y - 34 * S);
        if deep {
            if w.deep == 0 {
                self.body.vy = 0;
                w.wait = 16;
            }
            if frozen {
            } else if w.wait != 0 {
                w.wait -= 1;
            } else {
                self.body.vy -= 384;
            }
        } else {
            if !frozen && !map.water_at(x, y - 28 * S) {
                self.body.vy += 256;
            }
            if self.body.vy < 0 && w.jump == 0 {
                self.body.vy = 0;
            }
        }
        w.deep = i64::from(deep);
        // posture_allowed: not during the tongue, a spit or an emission.
        if ![4, 5, 7].contains(&self.action) {
            let dive = i64::from(input & 32 != 0 && w.jump == 0);
            if dive != w.dive {
                w.dive = dive;
                w.transition = 9;
            } else if !frozen {
                w.transition = (w.transition - 1).max(0);
            }
            if dive != 0 && self.body.vx != 0 && w.transition <= 3 {
                w.transition = 0;
            }
        }
        let phase = w.phase;
        let delta = if frozen {
            0
        } else {
            w.phase = (phase + 1) % 60;
            bob(phase + 1) - bob(phase)
        };
        let jump = pressed & 4 != 0 && self.body.vy < 96 * 60 && !map.water_at(x, y - 50 * S);
        if jump {
            w.jump = 1;
            w.dive = 0;
            (0, true)
        } else {
            (delta, false)
        }
    }
    pub fn finish_water(&mut self, map: &Probe) {
        if self.water.swimming != 0 && !self.liquid_body(map, self.bounds()) {
            self.water = Water::default();
            self.life.hurt_deceleration = 1296;
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn bob_is_closed_integer_cycle() {
        assert_eq!(bob(0), 0);
        assert_eq!(bob(30), 4 * S);
        assert_eq!(bob(60), 0);
        assert_eq!((0..60).map(|p| bob(p + 1) - bob(p)).sum::<i64>(), 0);
        for phase in 0..=60 {
            assert_eq!(bob(phase), bob(60 - phase));
        }
    }
}
