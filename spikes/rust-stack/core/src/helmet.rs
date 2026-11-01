//! helmet_walker.gd (e29): with its helmet on any touch hurts; a strike knocks the helmet
//! off, it looks around, blushes and runs. bump_walker.gd (e19): a round bumper that
//! shoves the player aside and bounces a landing; it idles and waddles, hops and
//! belly-slides (F=1) or flies (F=2). Both bodies live in `Actor` (ActorKind::Helmet and
//! ActorKind::Bumper).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{After, HitKind, Hold},
    elements::Frozen,
    entity::Kind,
    state::Run,
    Error, Placement, SCALE as S,
};
// helmet_walker.gd phases.
pub(crate) const H_WALK: i64 = 0;
pub(crate) const H_STOMP: i64 = 1;
pub(crate) const H_FALL: i64 = 2;
pub(crate) const H_LAND: i64 = 3;
pub(crate) const H_LOOK: i64 = 4;
pub(crate) const H_BLUSH: i64 = 5;
pub(crate) const H_RUN: i64 = 6;
pub(crate) const HELMET_BOX: [i64; 4] = [-14 * S, -34 * S, 14 * S, 16 * S];
// bump_walker.gd phases.
pub(crate) const B_IDLE: i64 = 0;
pub(crate) const B_STEP: i64 = 1;
pub(crate) const B_HOP: i64 = 2;
pub(crate) const B_SLIDE: i64 = 3;
pub(crate) const B_GET_UP: i64 = 4;
pub(crate) const B_RISE: i64 = 5;
pub(crate) const B_LOOK: i64 = 6;
pub(crate) const B_AIM: i64 = 7;
pub(crate) const B_FLY: i64 = 8;
const STEP_TICKS: i64 = 9;
const SLIDE_TICKS: i64 = 150;
const FLY_SWEEP: i64 = 150;
const FLY_BOB: i64 = 75;
const DECELERATION: i64 = 256;
const MAX_AGE: i64 = 1_000_000;
pub(crate) const BUMPER_BOX: [i64; 4] = [-14 * S, -10 * S, 14 * S, 16 * S];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}
/// enemy_motion.gd move (horizontal): (actual distance, started on a floor).
fn move_horizontal(body: &mut Body, map: &Probe, b: [i64; 4], distance: i64) -> (i64, bool) {
    if !body.prepare(map, b) {
        return (0, false);
    }
    let support = body.floor(map, b);
    let started = support != 0 && body.vy >= 0;
    (
        body.horizontal(map, b, distance, support, HorizontalMove::Actor),
        started,
    )
}
/// enemy_motion.gd edge
fn edge(body: Body, facing: i64, map: &Probe, b: [i64; 4]) -> bool {
    let left = if facing > 0 { body.x } else { body.x - 12 * S };
    let bottom = body.y + b[3];
    !map.support_in_box([left, bottom, left + 12 * S, bottom + 28 * S])
}
/// helmet_walker.gd TICKS
fn helmet_ticks(phase: i64) -> i64 {
    match phase {
        H_STOMP => 15,
        H_LAND => 10,
        H_LOOK => 8,
        H_BLUSH => 24,
        _ => 0,
    }
}
/// bump_walker.gd sweep_speed: a smoothstep ping-pong from `from` to `to` over `span`.
fn sweep_speed(tick: i64, span: i64, from: i64, to: i64) -> i64 {
    let t = if tick < span { tick } else { 2 * span - tick };
    let eased = (3 * t * t * span - 2 * t * t * t) * 1000 / (span * span * span);
    from + (to - from) * eased / 1000
}

impl Actor {
    /// helmet_walker.gd prepare (Options.prepare with two forms) + create.
    pub fn helmet(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e29 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Helmet, p.variant, p.mirror, p.position);
        a.speed = if p.variant == 1 { 144 } else { 48 };
        a.helmet = 1;
        Ok(a)
    }
    pub fn helmet_valid(&self) -> bool {
        (0..=1).contains(&self.variant)
            && (H_WALK..=H_RUN).contains(&self.phase)
            && (0..=24).contains(&self.timer)
            && [48, 144].contains(&self.speed)
            && [0, 1].contains(&self.helmet)
            && (0..=1_000_000).contains(&self.run_age)
    }
    /// helmet_walker.gd set_phase
    fn helmet_phase(&mut self, phase: i64) {
        self.phase = phase;
        self.timer = helmet_ticks(phase);
    }
    /// helmet_walker.gd view_state animation.
    pub fn helmet_animation(&self) -> String {
        match self.phase {
            H_STOMP => "HelmetStomp".into(),
            H_FALL => "LostHelmetFall".into(),
            H_LAND => "LostHelmetLand".into(),
            H_LOOK => "LookAround".into(),
            H_BLUSH => "Blush".into(),
            H_RUN => "BlushRun".into(),
            _ => format!("Move{}", i64::from(self.speed == 144 && self.helmet != 0)),
        }
    }
    /// bump_walker.gd prepare (Options.prepare with three forms) + create.
    pub fn bumper(p: &Placement) -> Result<Self, Error> {
        if !(0..=2).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e19 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Bumper, p.variant, p.mirror, p.position);
        a.phase = [B_IDLE, B_AIM, B_FLY][p.variant as usize];
        a.flip_timer = 30;
        Ok(a)
    }
    pub fn bumper_valid(&self) -> bool {
        (0..=2).contains(&self.variant)
            && (B_IDLE..=B_FLY).contains(&self.phase)
            && (0..=SLIDE_TICKS).contains(&self.timer)
            && (0..=30).contains(&self.flip_timer)
            && (0..=8).contains(&self.cycles)
            && (0..=MAX_AGE).contains(&self.age)
    }
    /// bump_walker.gd view_state animation.
    pub fn bumper_animation(&self) -> &'static str {
        match self.phase {
            B_STEP => "Walk",
            B_HOP | B_RISE => "Jump",
            B_SLIDE | B_GET_UP => "Slide",
            B_FLY => "Fly1",
            _ => "Idle",
        }
    }
}

impl Run {
    /// enemy_body.gd process for these two types: true when the step is over.
    fn helmet_process(&mut self, index: usize, map: &Probe) -> Result<Option<Hold>, Error> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
            frame,
            camera,
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
        let step = ActorStep {
            map,
            frame: *frame,
            camera: *camera,
            player,
            rng,
        };
        let action = w.process(
            token,
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &step,
        );
        Ok(([Hold::Held, Hold::Gone].contains(&action)).then_some(action))
    }
    /// enemy_body.gd spit_step and hazards with box `b`: true when the step is over.
    fn spit_or_lava(&mut self, index: usize, map: &Probe, b: [i64; 4]) -> Result<bool, Error> {
        let Run {
            entities,
            player,
            rng,
            frame,
            camera,
            ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let mut step = ActorStep {
            map,
            frame: *frame,
            camera: *camera,
            player,
            rng,
        };
        if let Some(after) = w.spit_step(
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &mut step,
        ) {
            if let After::HitOthers(hb) = after {
                self.hit_others(index, hb, HitKind::Spit, true)?;
            }
            return Ok(true);
        }
        if map.lava_overlaps(world_box(e.body, b)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(true);
        }
        Ok(false)
    }
    /// helmet_walker.gd step.
    pub(crate) fn helmet_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        if self.helmet_process(index, map)?.is_some() {
            return Ok(());
        }
        let b = HELMET_BOX;
        if self.spit_or_lava(index, map, b)? {
            return Ok(());
        }
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let body = &mut e.body;
        let grounded = body.floor(map, b) != 0;
        match w.phase {
            H_WALK | H_RUN => {
                let wet = i64::from(map.water_overlaps(world_box(*body, b)));
                body.vx = e.facing * (w.speed * 60 - w.speed * 30 * wet);
                if grounded && edge(*body, e.facing, map, b) {
                    e.facing = -e.facing;
                    body.vx = -body.vx;
                }
                if w.phase == H_RUN {
                    w.run_age = (w.run_age + 1).min(1_000_000);
                    if [30, 60].contains(&w.run_age) {
                        // It looks back over its shoulder twice.
                        e.facing = -e.facing;
                    }
                }
            }
            H_STOMP | H_LAND | H_LOOK | H_BLUSH => {
                body.vx = 0;
                w.timer -= 1;
                if w.timer <= 0 {
                    match w.phase {
                        H_STOMP => w.phase = H_WALK,
                        H_LAND => w.helmet_phase(H_LOOK),
                        H_LOOK => w.helmet_phase(H_BLUSH),
                        _ => {
                            w.phase = H_RUN;
                            e.facing = -e.facing;
                            w.speed = 144;
                            w.run_age = 0;
                        }
                    }
                }
            }
            _ => {
                if grounded && body.vy >= 0 {
                    w.helmet_phase(H_LAND);
                    body.vx = 0;
                }
            }
        }
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            let (actual, on_floor) = move_horizontal(body, map, b, distance);
            started = on_floor;
            if actual != distance {
                e.facing = -e.facing;
            }
        }
        body.gravity(map, b, started);
        Ok(())
    }
    /// helmet_walker.gd strike: the helmet comes off; a second strike defeats it.
    pub(crate) fn helmet_strike(&mut self, index: usize, from_x: i64) {
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        if w.helmet != 0 {
            w.helmet = 0;
            w.phase = H_FALL;
            w.timer = 0;
            e.body.vy = -256 * 60;
            e.body.vx = if e.body.x > from_x { 144 } else { -144 } * 60;
        } else if w.phase != H_FALL {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
    }
    /// helmet_walker.gd projectile_contact (`egg`: an egg projectile).
    pub(crate) fn helmet_projectile(&mut self, index: usize, from_x: i64, egg: bool) -> i64 {
        if matches!(&self.entities[index].kind, Kind::Walker(w) if w.phase == H_FALL) {
            return 0;
        }
        self.helmet_strike(index, from_x);
        if egg {
            1
        } else {
            3
        }
    }
    /// helmet_walker.gd contact.
    pub(crate) fn helmet_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, HELMET_BOX), world_box(p, pb));
        let (mut hurt, mut bounce) = (false, false);
        if touching && w.phase != H_FALL {
            let above = e.body.y > p.y - 8 * S;
            if w.helmet != 0 {
                hurt = true;
                if above && w.phase == H_WALK {
                    w.helmet_phase(H_STOMP);
                    e.body.vx = 0;
                }
            } else if above && w.contact == 0 {
                bounce = !pounding;
                w.remove(&mut e.status, &mut e.can_respawn);
            } else if !above {
                hurt = true;
            }
        }
        w.contact = i64::from(touching);
        let (x, vy) = (e.body.x, e.body.vy);
        if hurt {
            self.player.hurt(x, &mut self.sound);
        }
        if bounce {
            self.player.stomp(vy, input, &mut self.sound);
        }
    }
    /// bump_walker.gd step.
    pub(crate) fn bumper_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        if self.helmet_process(index, map)?.is_some() {
            return Ok(());
        }
        let b = BUMPER_BOX;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        // element_reactions.gd frozen_step
        match w.frozen_step(&mut e.body, e.status, map, b) {
            Frozen::Free => {}
            Frozen::Done => return Ok(()),
            Frozen::Lava => return self.remove_enemy(index),
        }
        if self.spit_or_lava(index, map, b)? {
            return Ok(());
        }
        let player_x = self.player.body.x;
        let Run { entities, rng, .. } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let body = &mut e.body;
        w.age = (w.age + 1).min(MAX_AGE);
        if w.phase == B_FLY {
            // bump_walker.gd fly: ping-pong sweeps with an in-out ease.
            let sweep = w.age % (2 * FLY_SWEEP);
            let start = if w.mirror == 0 { -144 } else { 144 };
            let across = sweep_speed(sweep, FLY_SWEEP, start, -start);
            let bob = sweep_speed(w.age % (2 * FLY_BOB), FLY_BOB, -48, 48);
            body.vx = across * 60;
            body.vy = bob * 60;
            e.facing = if body.vx > 0 { 1 } else { -1 };
            let dx = body.vx;
            move_horizontal(body, map, b, dx);
            if body.prepare(map, b) {
                let support = body.floor(map, b);
                let vy = body.vy;
                body.vertical_support(map, b, vy, support);
            }
            return Ok(());
        }
        let grounded = body.floor(map, b) != 0;
        match w.phase {
            B_IDLE => {
                // Standing still sets no speed: a shove slides out under the deceleration.
                if body.vx > 0 {
                    body.vx = (body.vx - DECELERATION).max(0);
                } else {
                    body.vx = (body.vx + DECELERATION).min(0);
                }
                if w.timer == 0 {
                    w.timer = rng.ticks(60, 150);
                    w.cycles = rng.cycles() + 2;
                    w.flip_timer = 30;
                } else {
                    w.flip_timer -= 1;
                    if w.flip_timer == 0 {
                        e.facing = -e.facing;
                        w.flip_timer = 30;
                    }
                    w.timer -= 1;
                    if w.timer == 0 {
                        w.phase = B_STEP;
                        w.timer = STEP_TICKS;
                    }
                }
            }
            B_STEP => {
                body.vx = e.facing * 64 * 60;
                if grounded && edge(*body, e.facing, map, b) {
                    e.facing = -e.facing;
                    body.vx = -body.vx;
                }
                w.timer -= 1;
                if w.timer == 0 {
                    if w.cycles > 0 {
                        w.cycles -= 1;
                        w.timer = STEP_TICKS;
                    } else {
                        w.phase = B_IDLE;
                        body.vx = 0;
                    }
                }
            }
            B_AIM => {
                e.facing = if player_x > body.x { 1 } else { -1 };
                w.phase = B_HOP;
                body.vy = -192 * 60;
            }
            B_HOP => {
                body.vx = e.facing * 256 * 60;
                if grounded && body.vy >= 0 {
                    w.phase = B_SLIDE;
                    w.timer = SLIDE_TICKS;
                }
            }
            B_SLIDE => {
                w.timer -= 1;
                let eased = 290 * w.timer * w.timer / (SLIDE_TICKS * SLIDE_TICKS);
                let snow = crate::flow::named_overlaps(
                    map,
                    "snow64",
                    [
                        body.x + b[0],
                        body.y + b[3],
                        body.x + b[2],
                        body.y + b[3] + 4 * S,
                    ],
                );
                body.vx = e.facing * eased * 60 / if snow { 1 } else { 2 };
                if w.timer <= 0 {
                    w.phase = B_GET_UP;
                    w.timer = 12;
                    body.vx = 0;
                }
            }
            B_GET_UP => {
                w.timer -= 1;
                if w.timer <= 0 {
                    w.phase = B_RISE;
                    body.vy = -192 * 60;
                }
            }
            B_RISE => {
                body.vx = 0;
                if grounded && body.vy >= 0 {
                    w.phase = B_LOOK;
                    w.cycles = 3;
                    w.timer = 12;
                }
            }
            _ => {
                body.vx = 0;
                w.timer -= 1;
                if w.timer <= 0 {
                    w.cycles = (w.cycles - 1).max(0);
                    e.facing = -e.facing;
                    w.timer = 3;
                    let toward = (player_x > body.x) == (e.facing > 0);
                    if w.cycles <= 0 && toward {
                        w.phase = B_AIM;
                    }
                }
            }
        }
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            let (actual, on_floor) = move_horizontal(body, map, b, distance);
            started = on_floor;
            if actual != distance {
                e.facing = -e.facing;
            }
        }
        body.gravity(map, b, started);
        Ok(())
    }
    /// bump_walker.gd contact: it never hurts; it shoves and bounces the player.
    pub(crate) fn bumper_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let on_floor = self.player.on_floor != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, BUMPER_BOX), world_box(p, pb));
        w.contact = i64::from(touching);
        if !touching {
            return;
        }
        let away = if p.x < e.body.x { -1 } else { 1 };
        let centred = (p.x - e.body.x).abs() < 16 * S;
        let velocity = -(e.body.vy / 2).abs() - 256 * 60;
        if !on_floor {
            if p.y < e.body.y {
                self.player.bounce(velocity, input, &mut self.sound);
            } else {
                self.player.body.vy = self.player.body.vy.abs();
            }
        } else if centred {
            e.body.vx = -away * 96 * 60;
            self.player.bounce(velocity, input, &mut self.sound);
            self.player.body.vx = away * 224 * 60;
        } else {
            if w.phase == B_SLIDE {
                w.timer = 0;
            }
            e.body.vx = -away * 96 * 60;
            self.player.body.vx = away * 224 * 60;
        }
    }
}
