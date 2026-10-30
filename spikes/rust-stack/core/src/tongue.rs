//! Typed empty-mouth tongue motion and terrain blocking. Food/request consumers are separate gates.
use crate::{
    body::Probe,
    player::{Player, Sound},
    SCALE as S,
};
#[derive(Clone, Debug)]
pub(crate) struct Tongue {
    pub axis: i64,
    pub length: i64,
    pub phase: i64,
    pub block_tick: i64,
    pub hold: i64,
}
impl Default for Tongue {
    fn default() -> Self {
        Self {
            axis: 0,
            length: 16 * S,
            phase: 0,
            block_tick: 0,
            hold: 16 * S,
        }
    }
}
impl Tongue {
    pub fn valid(&self, action: i64) -> bool {
        (0..=1).contains(&self.axis)
            && (0..=128 * S).contains(&self.length)
            && (0..=3).contains(&self.phase)
            && (0..=12).contains(&self.block_tick)
            && (0..=128 * S).contains(&self.hold)
            && ((action == 4) == (self.phase != 0))
    }
}
fn overlaps(map: &Probe, b: [i64; 4]) -> bool {
    map.border_overlaps(b) || map.terrain_overlaps(b)
}
impl Player {
    pub fn tongue_end_tick(&self) -> i64 {
        match self.tongue.phase {
            3 => 5,
            2 => 18 + self.tongue.block_tick,
            _ => 12,
        }
    }
    fn mouth(&self) -> [i64; 2] {
        [
            self.body.x
                + self.facing
                    * if self.tongue.axis != 0 {
                        14 * S
                    } else {
                        24 * S
                    },
            self.body.y
                - if self.tongue.axis != 0 {
                    38 * S
                } else {
                    24 * S
                },
        ]
    }
    fn tongue_sensor(&self, length: i64) -> [i64; 4] {
        let [x, y] = self.mouth();
        if self.tongue.axis != 0 {
            [
                x - 7 * S,
                y - length - 4 * S,
                x + 7 * S,
                y - length + 44 * S,
            ]
        } else {
            let tip = x + self.facing * length;
            [
                tip - if self.facing > 0 { 40 * S } else { 8 * S },
                y - 7 * S,
                tip + if self.facing > 0 { 8 * S } else { 40 * S },
                y + 7 * S,
            ]
        }
    }
    pub fn tongue_box(&self) -> Option<[i64; 4]> {
        (self.action == 4 && [1, 2].contains(&self.tongue.phase))
            .then(|| self.tongue_sensor(self.tongue.length))
    }
    pub fn tongue_reach(&self) -> Option<[i64; 4]> {
        let mut b = self.tongue_box()?;
        let [x, y] = self.mouth();
        if self.tongue.axis != 0 {
            b[3] = b[3].max(y);
        } else {
            b[0] = b[0].min(x);
            b[2] = b[2].max(x);
        }
        Some(b)
    }
    pub fn start_tongue(&mut self, map: &Probe, sound: &mut Sound) {
        self.set_action(4, sound);
        self.tongue = Tongue {
            phase: 1,
            ..Tongue::default()
        };
        let x = self.body.x + self.facing * 32 * S;
        let y = self.body.y - 24 * S;
        if overlaps(map, [x - 12 * S, y - 12 * S, x + 12 * S, y + 12 * S]) {
            self.tongue.phase = 3;
        }
    }
    pub fn advance_tongue(&mut self, map: &Probe) {
        if self.action != 4 || self.tongue.phase == 3 {
            return;
        }
        let tick = self.action_tick;
        let reach = if self.tongue.axis != 0 {
            120 * S
        } else {
            128 * S
        };
        let mut desired =
            16 * S + (reach - 16 * S) * if tick < 6 { tick } else { (12 - tick).max(0) } / 6;
        if self.tongue.phase == 2 {
            desired = self.tongue.hold;
            if tick >= 18 {
                desired = 24 * S
                    + (self.tongue.hold - 24 * S) * (self.tongue.block_tick - tick + 18).max(0)
                        / self.tongue.block_tick.max(1);
            }
        }
        let mut last_clear = (16 * S).min(desired);
        let mut candidate = last_clear;
        while candidate < desired + S {
            let length = candidate.min(desired);
            if overlaps(map, self.tongue_sensor(length)) {
                desired = last_clear;
                self.tongue.length = desired;
                if self.tongue.phase == 1 {
                    self.tongue.phase = 2;
                    self.tongue.block_tick = self.action_tick.min(12);
                    self.tongue.hold = self.tongue.length;
                }
                break;
            }
            last_clear = length;
            candidate += S;
        }
        self.tongue.length = desired;
    }
}
