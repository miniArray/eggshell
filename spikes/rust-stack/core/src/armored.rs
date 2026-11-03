//! armored_walker.gd (e11): walking and jumping armor. Impacts roll it; a stomp does not
//! defeat it. The body lives in `Actor` (ActorKind::Armored).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{HitKind, Hold},
    entity::Kind,
    state::Run,
    Error, Placement, SCALE as S,
};
pub(crate) const WALK: i64 = 0;
pub(crate) const PREPARE: i64 = 1;
pub(crate) const AIR: i64 = 2;
pub(crate) const PUSH: i64 = 3;
pub(crate) const ROLL: i64 = 4;
pub(crate) const RECOVER: i64 = 5;
pub(crate) const BOX: [i64; 4] = [-14 * S, -14 * S, 14 * S, 16 * S];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}
/// moves.gd approach
fn approach(value: i64, target: i64, amount: i64) -> i64 {
    if value < target {
        (value + amount).min(target)
    } else {
        (value - amount).max(target)
    }
}

impl Actor {
    /// armored_walker.gd prepare + create.
    pub fn armored(p: &Placement) -> Result<Self, Error> {
        if !(0..=3).contains(&p.variant) || !(0..=2).contains(&p.mirror) {
            return Err(Error::Unsupported {
                requirements: vec![format!("e11 form F={} M={}", p.variant, p.mirror)],
            });
        }
        let mut a = Actor::new(ActorKind::Armored, p.variant, p.mirror, p.position);
        a.mode = if p.variant % 2 == 1 { AIR } else { WALK };
        Ok(a)
    }
    pub fn armored_valid(&self) -> bool {
        (0..=3).contains(&self.variant)
            && (WALK..=RECOVER).contains(&self.mode)
            && (0..=275).contains(&self.timer)
            && [-1, 1].contains(&self.roll_direction)
    }
    /// armored_walker.gd start_roll
    pub(crate) fn armored_roll(&mut self, body: &mut Body, direction: i64) {
        self.knock_active = 0;
        self.mode = ROLL;
        self.timer = 90;
        self.roll_direction = direction;
        body.vx = direction * 256 * 60;
        body.vy = -384 * 60;
    }
    /// armored_walker.gd hit (no element reactions are admitted).
    pub(crate) fn armored_hit(
        &mut self,
        body: &mut Body,
        status: &mut i64,
        can_respawn: &mut i64,
        kind: HitKind,
        from_x: i64,
    ) {
        match kind {
            HitKind::Shell => self.remove(status, can_respawn),
            HitKind::Egg | HitKind::Spit => {
                self.armored_roll(body, if body.x > from_x { 1 } else { -1 })
            }
        }
    }
    /// armored_walker.gd tongue: the tongue pushes it back and is blocked (2).
    pub(crate) fn armored_tongue(&mut self, body: &mut Body, facing: &mut i64, player_facing: i64) {
        self.knock_active = 0;
        self.mode = PUSH;
        self.timer = 30;
        body.vx = player_facing * 128 * 60;
        *facing = -player_facing;
    }
    /// armored_walker.gd knockback (Godot eab5a95): a nearby soft burst knocks the body
    /// away, independent of its jumping animation and queued jump.
    pub(crate) fn armored_knockback(&mut self, body: Body, status: i64, from_x: i64) {
        if self.held != 0 || self.spat != 0 || self.hidden != 0 || self.frozen != 0 || status != 1 {
            return;
        }
        self.roll_direction = if body.x > from_x { 1 } else { -1 };
        self.knock_start(self.roll_direction * 448 * 60, 60);
    }
    /// armored_walker.gd view_state animation.
    pub fn armored_animation(&self) -> String {
        let names = ["Walk", "PrepareJump", "Jump", "Pushed", "Hit", "Recover"];
        format!(
            "{}{}",
            self.variant / 2,
            names[self.mode.clamp(0, 5) as usize]
        )
    }
}

impl Run {
    /// armored_walker.gd step.
    pub(crate) fn armored_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
            ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if w.started == 0 {
            // enemy_body.gd process: the first step's initialisation.
            w.started = 1;
            w.impact_cursor = player.impact;
            if w.mirror == 2 {
                e.facing = if player.body.x > e.body.x { 1 } else { -1 };
            }
        }
        let step = ActorStep { map, player, rng };
        let action = w.process(
            token,
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &step,
        );
        if [Hold::Held, Hold::Gone].contains(&action) {
            return Ok(());
        }
        if map.lava_overlaps(world_box(e.body, BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        // element_reactions.gd frozen_step
        match w.frozen_step(&mut e.body, e.status, map, BOX) {
            crate::elements::Frozen::Free => {}
            crate::elements::Frozen::Done => return Ok(()),
            crate::elements::Frozen::Lava => return self.remove_enemy(index),
        }
        let body = &mut e.body;
        let facing = &mut e.facing;
        let grounded = body.floor(map, BOX) != 0;
        // The family event assigned this step's knock speed after the previous move.
        let knocked = w.knock_active == 1 && !w.knock_deferred();
        let old_vx = body.vx;
        match w.mode {
            ROLL => {
                body.vx = w.roll_direction * 256 * 60 * w.timer * w.timer / 8100;
                w.timer -= 1;
            }
            RECOVER => {
                body.vx = 0;
                w.timer -= 1;
            }
            PUSH => {
                body.vx = approach(body.vx, 0, 256);
                w.timer -= 1;
            }
            PREPARE => {
                body.vx = 0;
                w.timer = (w.timer - 1).max(0);
            }
            WALK => {
                let wet = i64::from(map.water_overlaps(world_box(*body, BOX)));
                body.vx = *facing * 48 * 60 / (wet + 1);
                if w.variant == 0 && grounded {
                    // enemy_motion.gd edge
                    let left = if *facing > 0 { body.x } else { body.x - 12 * S };
                    let bottom = body.y + BOX[3];
                    if !map.support_in_box([left, bottom, left + 12 * S, bottom + 28 * S]) {
                        *facing = -*facing;
                        body.vx = -body.vx;
                    }
                }
            }
            _ => body.vx = 0,
        }
        if knocked {
            body.vx = old_vx;
        }
        let distance = body.vx;
        let (actual, started) = if body.prepare(map, BOX) {
            let support = body.floor(map, BOX);
            let started = support != 0 && body.vy >= 0;
            (
                body.horizontal(map, BOX, distance, support, HorizontalMove::Actor),
                started,
            )
        } else {
            (0, false)
        };
        if actual != distance && w.mode == WALK {
            *facing = -*facing;
        }
        // A roll against a wall strikes SOLID 1 types with a `hit` (enemy_body.gd
        // strike_wall with Hits.SPIT): admitted blocks react to EGG only, so nothing
        // changes.
        let landed = body.gravity(map, BOX, started);
        let rolling = w.mode == ROLL;
        if rolling {
            self.hit_others(index, BOX, HitKind::Spit, false)?;
        }
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if rolling {
            if w.timer == 0 {
                w.mode = RECOVER;
                w.timer = if w.variant < 2 { 158 } else { 275 };
            }
        } else if [RECOVER, PUSH].contains(&w.mode) && w.timer == 0 {
            w.mode = if w.variant % 2 == 1 { AIR } else { WALK };
        }
        if w.mode == PREPARE && w.timer == 0 && landed {
            // The animation queues a jump; the event launches only when standing.
            w.mode = AIR;
            e.body.vy = -536 * 60;
        } else if w.variant % 2 == 1 && w.mode == AIR && landed {
            w.mode = PREPARE;
            w.timer = 5;
        }
        Ok(())
    }
    /// armored_walker.gd after_advance (Godot eab5a95, 024d409): after every body of the
    /// movement phase, each eligible armor reads its knock speed; a fast first-born
    /// knock against a wall rebounds it, and a fast knock hops it off the floor.
    pub(crate) fn armored_after_advance(&mut self, map: &Probe) {
        let first_speed = self.first_knock_velocity();
        for index in 0..self.entities.len() {
            let e = &mut self.entities[index];
            let Kind::Walker(w) = &mut e.kind else {
                continue;
            };
            if w.kind != ActorKind::Armored
                || e.status != 1
                || !w.knockback_active()
                || w.held != 0
                || w.spat != 0
                || w.hidden != 0
                || w.frozen != 0
            {
                continue;
            }
            e.body.vx = w.knock_value();
            let mut speed = e.body.vx.abs();
            // The native wall probe tests 2 px (plus one unit) sideways, then 3 px up.
            let wall = first_speed.signum();
            if first_speed.abs() > 64 * 60
                && e.body.overlaps(map, BOX, wall * (2 * S + 1), 0)
                && e.body.overlaps(map, BOX, wall * (2 * S + 1), -3 * S)
            {
                w.roll_direction = -wall;
                e.facing = w.roll_direction;
                w.knock_stop();
                w.knock_start(w.roll_direction * 48 * 60, 90);
                speed = 48 * 60;
            }
            if speed > 24 * 60 && e.body.floor(map, BOX) != 0 {
                e.body.vy = -speed / 2 - 160 * 60;
            }
            self.refresh_block_solid(index, map);
        }
    }
    /// armored_walker.gd contact: touching it hurts.
    pub(crate) fn armored_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        if w.hidden != 0
            || w.held != 0
            || w.spat != 0
            || e.status != 1
            || self.player.captured_by != 0
        {
            return;
        }
        if strict(world_box(e.body, BOX), world_box(p, pb)) {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
}
