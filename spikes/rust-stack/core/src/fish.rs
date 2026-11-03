//! enemy_fish.gd (actor.gd e20/e21): water patrol, vertical jumps, arcs and dry-ground
//! movement. e20 passes through terrain; e21 collides and flops on dry ground.
use crate::{
    actors::{Actor, ActorKind},
    body::{Body, HorizontalMove, Probe},
    math::{sine, Rng},
    Error, SCALE as S,
};
/// A turn: the 0.15 s wait and the 0.4 s turn picture (33 ticks), plus one tick because
/// a simulated control press reaches the Platform movement on the next tick.
const TURN_TICKS: i64 = 34;

/// enemy_motion.gd box for e20/e21.
pub(crate) fn bounds(mode: i64, facing: i64) -> [i64; 4] {
    match mode {
        2 => [-14 * S, -12 * S, 14 * S, 16 * S],
        3 => [-14 * S, -14 * S, 14 * S, 14 * S],
        _ if facing < 0 => [-12 * S, -16 * S, 24 * S, 14 * S],
        _ => [-24 * S, -16 * S, 12 * S, 14 * S],
    }
}
/// enemy_fish.gd approach
fn approach(value: i64, target: i64, amount: i64) -> i64 {
    if value < target {
        (value + amount).min(target)
    } else {
        (value - amount).max(target)
    }
}

impl Actor {
    /// actor.gd activate for fish form 2: the patrol's reach either side of home.
    pub(crate) fn fish_activate(&mut self, facing: i64) {
        if self.variant == 2 {
            self.fish_left = if facing < 0 { 232 } else { -24 } * S;
            self.fish_right = if facing < 0 { -24 } else { 232 } * S;
        }
    }
    pub fn fish_valid(&self) -> bool {
        (0..=3).contains(&self.variant)
            && (0..=3).contains(&self.fish_finish)
            && [0, 1].contains(&self.fish_dry)
            && [3, 60].contains(&self.rise_duration)
            && (0..=3).contains(&self.fish_jumps)
            && [0, 1].contains(&self.fish_ready)
            && [0, 1].contains(&self.fish_exhausted)
    }
    /// enemy_fish.gd _translate with the step's box `b`. True when the horizontal move
    /// started on a floor (enemy_motion.gd floor_at_start).
    #[allow(clippy::too_many_arguments)]
    fn fish_translate(
        &mut self,
        body: &mut Body,
        facing: i64,
        map: &Probe,
        b: [i64; 4],
        dx: i64,
        dy: i64,
    ) -> bool {
        if self.kind == ActorKind::Fish {
            body.x += dx;
            body.y += dy;
            return false;
        }
        let mut started = false;
        if dx != 0 {
            let actual = if body.prepare(map, b) {
                let support = body.floor(map, b);
                started = support != 0 && body.vy >= 0;
                body.horizontal(map, b, dx, support, HorizontalMove::Actor)
            } else {
                0
            };
            if actual != dx {
                if [3, 4].contains(&self.mode) {
                    body.vx = -dx;
                } else if self.mode != 1 {
                    if self.variant <= 1 {
                        self.home_x = body.x - facing * 64 * S;
                    } else if self.variant == 2 {
                        self.home_x = body.x - facing * 128 * S;
                        self.fish_left = if facing < 0 { -24 } else { 232 } * S;
                        self.fish_right = if facing < 0 { 232 } else { -24 } * S;
                    }
                    self.mode = 1;
                    self.timer = TURN_TICKS;
                }
            }
        }
        if dy != 0 {
            let actual = if body.prepare(map, b) {
                let support = body.floor(map, b);
                body.vertical_support(map, b, dy, support)
            } else {
                0
            };
            if actual != dy {
                body.vy = 0;
            }
        }
        started
    }
    /// enemy_fish.gd _flop
    fn fish_flop(body: &mut Body, facing: &mut i64, rng: &mut Rng) {
        *facing = if rng.ticks(0, 2) == 1 { 1 } else { -1 };
        body.vy = if rng.ticks(0, 2) == 1 { -256 } else { -384 } * 60;
    }
    /// enemy_fish.gd advance.
    pub(crate) fn fish_advance(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        map: &Probe,
        rng: &mut Rng,
    ) -> Result<(), Error> {
        if self.fish_exhausted != 0 {
            return Ok(());
        }
        if self.fish_finish != 0 {
            self.fish_finish -= 1;
            if self.fish_finish == 0 {
                self.fish_exhausted = 1;
                self.hidden = 1;
                body.vx = 0;
                body.vy = 0;
                return Ok(());
            }
        }
        let deep = map.water_at(body.x, body.y - 8 * S);
        let origin_wet = map.water_at(body.x, body.y);
        let b = bounds(self.mode, *facing);
        let wet = map.water_overlaps([body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]);
        if [3, 4].contains(&self.mode) {
            body.vy = (body.vy + 2048).min(704 * 60);
            let falling = body.vy > 0;
            let (vx, vy) = (body.vx, body.vy);
            self.fish_translate(body, *facing, map, b, vx, vy);
            if origin_wet && falling {
                self.mode = 0;
                self.phase = 0;
                body.vx = *facing * 128 * 60;
                if self.variant == 1 {
                    self.cycles = rng.ticks(60, 180);
                } else {
                    self.rise_ticks = 3;
                    self.rise_duration = 3;
                    self.rise_velocity = body.vy / 4;
                    if self.variant == 3 && self.fish_jumps == 0 {
                        self.fish_finish = 3;
                    }
                }
            }
            return Ok(());
        }
        if self.mode == 2 {
            self.timer -= 1;
            if self.timer == 0 {
                body.vy = -944 * 60;
                self.mode = 3;
            }
            return Ok(());
        }
        if !wet {
            self.water = 0;
            body.vx = if self.fish_dry != 0 {
                *facing * 128 * 60
            } else {
                0
            };
            if self.kind == ActorKind::LandFish {
                let vx = body.vx;
                let started = self.fish_translate(body, *facing, map, b, vx, 0);
                // enemy_motion.gd gravity_box: fish skip the water quartering.
                if body.gravity_box_dry(map, b, started) {
                    self.fish_dry = 1;
                    Self::fish_flop(body, facing, rng);
                }
            } else {
                body.vy = (body.vy + 2048).min(704 * 60);
                body.x += body.vx;
                body.y += body.vy;
            }
            return Ok(());
        }
        self.fish_dry = 0;
        if deep {
            if self.rise_ticks != 0 {
                self.rise_ticks -= 1;
                let duration = self.rise_duration;
                body.vy =
                    self.rise_velocity * self.rise_ticks * self.rise_ticks / (duration * duration);
            } else {
                body.vy -= 384;
                if body.vy > 0 {
                    self.rise_ticks = 60;
                    self.rise_duration = 60;
                    self.rise_velocity = body.vy / 6;
                    body.vy = self.rise_velocity;
                }
            }
            if self.water != 0 {
                self.home_y += body.vy;
            } else {
                let vy = body.vy;
                self.fish_translate(body, *facing, map, b, 0, vy);
            }
        } else {
            if body.vy <= 0 {
                body.vy = 0;
            }
            if self.water == 0 {
                self.water = 1;
                self.home_y = body.y;
                self.phase = 0;
            }
            self.home_y += body.vy;
        }
        if self.water != 0 {
            self.phase = (self.phase + 1) % 60;
            let next_y = self.home_y + sine(self.phase, 60, 6 * S)?;
            let dy = next_y - body.y;
            self.fish_translate(body, *facing, map, b, 0, dy);
        }
        // Platform order: an accelerating body moves by the mean of its old and new speed
        // (only when it already moves); a braking body moves by its old speed.
        let braking = self.mode == 1 && self.timer < TURN_TICKS;
        let old_vx = body.vx;
        if self.mode == 1 {
            self.timer -= 1;
            // The last control press still accelerates on the turn's first tick.
            let target = if braking { 0 } else { *facing * 128 * 60 };
            body.vx = approach(body.vx, target, 512);
            if self.timer == 0 {
                *facing = -*facing;
                self.mode = 0;
                self.fish_ready = 1;
            }
        } else {
            body.vx = approach(body.vx, *facing * 128 * 60, 512);
            if self.variant == 1 && self.water != 0 {
                if self.cycles == 0 {
                    self.cycles = rng.ticks(60, 180);
                }
                self.cycles -= 1;
                if self.cycles == 0 {
                    self.mode = 2;
                    self.water = 0;
                    self.timer = 10;
                    body.vx = 0;
                }
            } else if self.variant >= 2 && self.water != 0 && self.fish_ready != 0 {
                let mut jump = self.variant == 3 && self.fish_jumps > 0;
                if self.variant == 2 {
                    jump = if *facing < 0 {
                        body.x < self.home_x + if self.fish_left > 0 { -64 } else { 192 } * S
                    } else {
                        body.x > self.home_x + if self.fish_left > 0 { -192 } else { 64 } * S
                    };
                }
                if jump {
                    self.mode = 4;
                    self.water = 0;
                    body.vy = -800 * 60;
                    body.vx = *facing * 128 * 60;
                    if self.variant == 2 {
                        self.fish_ready = 0;
                    } else {
                        self.fish_jumps -= 1;
                    }
                }
            }
        }
        let dx = if braking {
            old_vx
        } else if [0, 1].contains(&self.mode) {
            if old_vx != 0 {
                (old_vx + body.vx) / 2
            } else {
                0
            }
        } else {
            body.vx
        };
        self.fish_translate(body, *facing, map, b, dx, 0);
        // The patrol turn is tested in the events, after this frame's move.
        if self.mode == 0
            && self.variant <= 2
            && (body.x < self.home_x - self.fish_left && *facing < 0
                || body.x > self.home_x + self.fish_right && *facing > 0)
        {
            self.mode = 1;
            self.timer = TURN_TICKS;
        }
        Ok(())
    }
    /// actor.gd view_state for e20/e21.
    pub fn fish_animation(&self, body: Body, facing: i64) -> &'static str {
        match self.mode {
            1 if facing < 0 => "TurnRight",
            1 => "TurnLeft",
            2 => "PrepareJump",
            3 if body.vy < 0 => "Jump",
            3 => "Fall",
            4 => "JumpArc",
            _ if self.fish_dry != 0 => "OutOfWater",
            _ => "Swim",
        }
    }
}

impl Body {
    /// enemy_motion.gd gravity_box for e20/e21: no water quartering.
    pub fn gravity_box_dry(&mut self, map: &Probe, b: [i64; 4], started_on_floor: bool) -> bool {
        if !self.prepare(map, b) {
            self.vy = 0;
            return false;
        }
        let support = self.track(map, b, true);
        if support != 0 && self.vy >= 0 {
            self.vy = 0;
            return true;
        }
        if self.vy == 0 && started_on_floor {
            return false;
        }
        let distance = if self.vy != 0 {
            (self.vy + 1024).min(704 * 60)
        } else {
            0
        };
        let actual = self.vertical_support(map, b, distance, support);
        let landed = distance >= 0 && (actual != distance || self.floor(map, b) != 0);
        if landed || actual != distance {
            self.vy = 0;
        }
        if !landed && support == 0 {
            self.vy = (self.vy + 2048).min(704 * 60);
        }
        landed
    }
}
