//! DOWN posture and the original fixed-tick ground-pound phases.
use crate::{
    body::Probe,
    player::{Player, Sound, NORMAL},
};
impl Player {
    /// The POUND_LAND release after moves.gd _tick_action (the pound start's fall is there).
    pub(crate) fn tick_pound(&mut self, input: u8, sound: &mut Sound) {
        if self.action == 3 && input & 32 == 0 {
            self.set_action(0, sound);
            self.pound_delay = 6;
        }
    }
    /// moves.gd _posture
    pub(crate) fn update_posture(&mut self, map: &Probe, input: u8, sound: &mut Sound) {
        let previous = (self.duck, self.look);
        let down = input & 32 != 0;
        let mut duck = self.on_floor != 0
            && down
            && self.water.swimming == 0
            && self.turn == 0
            && [0, 9, 8].contains(&self.action);
        if self.duck != 0 && !duck {
            // Keep the compact collider until standing is safe; never push through a low roof.
            duck = self.body.overlaps(map, NORMAL, 0, 0);
        }
        self.duck = i64::from(duck);
        if duck {
            self.body.vx = 0;
            self.food.aim = 0;
            if [9, 8].contains(&self.action) {
                self.set_action(0, sound);
            }
        }
        self.look = i64::from(
            self.on_floor != 0
                && !down
                && input & 16 != 0
                && self.body.vx == 0
                && [0, 6, 11, 9].contains(&self.action)
                && self.food.aim == 0
                && self.turn == 0
                && self.water.swimming == 0,
        );
        if self.look != 0 && self.action != 0 {
            self.set_action(0, sound);
        }
        self.posture_tick = if previous == (self.duck, self.look) && (duck || self.look != 0) {
            (self.posture_tick + 1).min(9)
        } else {
            0
        };
    }
}
