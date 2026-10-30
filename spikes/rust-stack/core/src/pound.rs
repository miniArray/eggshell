//! DOWN posture and the original fixed-tick ground-pound phases.
use crate::{
    body::Probe,
    player::{Player, Sound, NORMAL},
    SCALE as S,
};
impl Player {
    pub(crate) fn tick_pound(&mut self, input: u8, sound: &mut Sound) {
        if self.action == 1 && self.action_tick >= 24 {
            self.set_action(2, sound);
            self.body.vy = 4096 * 60;
        } else if self.action == 3 && input & 32 == 0 {
            self.set_action(0, sound);
            self.pound_delay = 6;
        }
    }
    pub(crate) fn start_pound(&mut self, input: u8, sound: &mut Sound) -> bool {
        if input & 32 != 0
            && self.on_floor == 0
            && self.water.swimming == 0
            && self.pound_delay == 0
            && ![1, 2, 3, 4].contains(&self.action)
        {
            self.cancel_flutter();
            self.set_action(1, sound);
            self.body.vx = 0;
            self.body.vy = 0;
            true
        } else {
            false
        }
    }
    pub(crate) fn update_posture(&mut self, map: &Probe, input: u8, sound: &mut Sound) {
        let previous = (self.duck, self.look);
        let mut duck = self.on_floor != 0
            && input & 32 != 0
            && self.water.swimming == 0
            && self.turn == 0
            && [0, 9, 8].contains(&self.action);
        if self.duck != 0 && !duck {
            duck = self.body.overlaps(map, NORMAL, 0, 0);
        }
        self.duck = i64::from(duck);
        if duck {
            self.body.vx = 0;
            if [9, 8].contains(&self.action) {
                self.set_action(0, sound);
            }
        }
        self.look = 0;
        self.posture_tick = if previous == (self.duck, self.look) && (duck || self.look != 0) {
            (self.posture_tick + 1).min(9)
        } else {
            0
        };
    }
    pub(crate) fn pound_bounds(&self) -> Option<[i64; 4]> {
        let height = if self.duck != 0 {
            [52, 48, 32][(self.posture_tick * 24 / 60).min(2) as usize]
        } else if [1, 2].contains(&self.action) {
            let frame = if self.action == 2 {
                6
            } else {
                (self.action_tick * 36 / 60).min(6)
            };
            [52, 52, 56, 50, 48, 54, 50][frame as usize]
        } else if self.action == 3 {
            if self.action_tick < 4 {
                40
            } else {
                36
            }
        } else {
            return None;
        };
        Some([-12 * S, -height * S, 12 * S, 0])
    }
}
