//! o11 is the Bounce verification dependency, not an added target placement.
use crate::{
    body::{Body, Probe},
    player::Player,
    SCALE as S,
};
#[derive(Clone, Debug)]
pub(crate) struct Pad {
    pub squash: i64,
    pub active: bool,
}
impl Default for Pad {
    fn default() -> Self {
        Self {
            squash: 0,
            active: true,
        }
    }
}
pub(crate) fn bounds(large: bool) -> [i64; 4] {
    let width = if large { 22 } else { 14 };
    let height = if large { 46 } else { 30 };
    [-width * S, -height * S, width * S, 0]
}
impl Pad {
    pub fn advance(&mut self, body: &mut Body, map: &Probe, large: bool) {
        if !self.active {
            return;
        }
        if self.squash != 0 {
            self.squash -= 1;
            return;
        }
        let b = bounds(large);
        if !body.prepare(map, b) {
            body.vy = 0;
            return;
        }
        if body.track(map, b, true) != 0 {
            body.vy = 0;
            return;
        }
        body.vy = (body.vy + 2048).min(704 * 60);
        let distance = body.vy;
        if body.vertical(map, b, distance) != distance {
            body.vy = 0;
        }
    }
    pub fn contact(
        &mut self,
        body: Body,
        player: &mut Player,
        input: u8,
        large: bool,
        single_use: bool,
    ) {
        let b = bounds(large);
        if self.active
            && player.body.vy > body.vy
            && player.body.y < body.y
            && player.body.y > body.y + b[1]
            && (player.body.x - body.x).abs() < b[2] + 12 * S
        {
            player.body.vy = if input & 4 != 0 {
                -1216 - 544 * i64::from(large)
            } else {
                -384 - 185 * i64::from(large)
            } * 60;
            player.on_floor = 0;
            player.jump_buffer = 0;
            player.flutter_remaining = 0;
            player.flutter_ready = 1;
            self.squash = 12;
            if single_use {
                self.active = false;
            }
        }
    }
}
