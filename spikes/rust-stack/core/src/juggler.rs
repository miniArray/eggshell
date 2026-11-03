//! needle_juggler.gd (e42): an invulnerable head that tosses a spiked hopper up and
//! catches it, three tosses a round; without a hopper it frowns, then grows a new one.
//! spike_hopper.gd (e40): the hopper, also placeable on its own. Both bodies live in
//! `Actor` (ActorKind::Juggler and ActorKind::Hopper).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::{HitKind, Hold},
    entity::{Entity, Kind},
    math::root,
    state::Run,
    Error, Placement, SCALE as S,
};
const GRAVITY: i64 = 1536;
const MAX_FALL: i64 = 704 * 60;
const MAX_SPEED: i64 = 512 * 60;
const SINK_WINDOW: i64 = 60;
pub(crate) const HOPPER_BOX: [i64; 4] = [-12 * S, -12 * S, 12 * S, 12 * S];
pub(crate) const JUGGLER_BOX: [i64; 4] = [-12 * S, -44 * S, 12 * S, 16 * S];
const DURATIONS: [i64; 5] = [1, 1, 1, 1, 2];
const LAST_FRAME: i64 = 4;
const FAST: i64 = 30;
const SLOW: i64 = 8;
const HOLD_TICKS: i64 = 6;
const PAUSE_TICKS: i64 = 18;
const FROWN_TICKS: i64 = 120;
const GROW_TICKS: i64 = 300;
const RISE_WAIT: i64 = 24;
const RISE_TICKS: i64 = 36;
const RISE_OFFSET: i64 = 20;

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Actor {
    /// spike_hopper.gd prepare + create for a placed hopper.
    pub fn hopper(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) || p.mirror != 0 || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e40 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Hopper, p.variant, 0, p.position);
        a.colour = p.variant;
        Ok(a)
    }
    /// needle_juggler.gd prepare + create.
    pub fn juggler(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || p.mirror != 0 || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e42 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::Juggler, 0, 0, p.position))
    }
    pub fn hopper_valid(&self, vx: i64) -> bool {
        (0..=1).contains(&self.variant)
            && [0, 1].contains(&self.colour)
            && (0..=SINK_WINDOW).contains(&self.sink_window)
            && [0, 1].contains(&self.hop_pending)
            && [0, 1].contains(&self.sinking)
            && [0, 1].contains(&self.thrown)
            && self.carrier >= 0
            && [0, 1].contains(&self.intangible)
            && (-MAX_SPEED..=MAX_SPEED).contains(&vx)
    }
    pub fn juggler_valid(&self) -> bool {
        self.variant == 0
            && (0..=LAST_FRAME).contains(&self.frame)
            && [0, 1].contains(&self.forward)
            && [0, 1].contains(&self.playing)
            && [0, SLOW, FAST].contains(&self.speed)
            && (0..120).contains(&self.clock)
            && (0..=2).contains(&self.cycles)
            && [0, 1].contains(&self.accepting)
            && [0, 1].contains(&self.frowning)
            && (0..=RISE_OFFSET * 60).contains(&self.offset)
            && self.needle_token >= 0
            && (0..=HOLD_TICKS).contains(&self.hold_ticks)
            && (0..=PAUSE_TICKS).contains(&self.pause_ticks)
            && (0..=FROWN_TICKS).contains(&self.frown_ticks)
            && (0..=GROW_TICKS).contains(&self.grow_ticks)
            && (0..=3).contains(&self.rise)
            && (0..=RISE_TICKS).contains(&self.rise_ticks)
            && [0, 1].contains(&self.thrown_now)
    }
}

impl Run {
    fn actor(&mut self, index: usize) -> &mut Actor {
        match &mut self.entities[index].kind {
            Kind::Walker(w) => w,
            _ => unreachable!("actor index"),
        }
    }
    /// The process/started prologue every enemy step runs (enemy_body.gd process).
    fn actor_process(&mut self, index: usize, map: &Probe) -> Hold {
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
        w.process(
            token,
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &step,
        )
    }
    /// spike_hopper.gd step.
    pub(crate) fn hopper_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let action = self.actor_process(index, map);
        if [Hold::Held, Hold::Gone].contains(&action) {
            return Ok(());
        }
        if self.actor(index).frozen != 0 {
            return Err(Error::Unsupported {
                requirements: vec!["frozen e40 hopper (ice shots are not ported)".into()],
            });
        }
        let carrier = self.actor(index).carrier;
        if carrier != 0 {
            // A carrier positions the body during its own earlier step.
            let present = self
                .entities
                .iter()
                .find(|e| e.origin.token() == carrier)
                .is_some_and(|e| e.status == 1);
            let e = &mut self.entities[index];
            let Kind::Walker(w) = &mut e.kind else {
                unreachable!()
            };
            if !present || w.held != 0 || action == Hold::Released {
                w.carrier = 0;
                w.intangible = 0;
            } else {
                e.body.vx = 0;
                e.body.vy = 0;
                return Ok(());
            }
        }
        let player_facing = self.player.facing;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if action == Hold::Released {
            w.on_spit_release(&mut e.body, &mut e.facing, player_facing, 0);
        }
        if map.lava_overlaps(world_box(e.body, HOPPER_BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        if w.sink_window != 0 {
            w.sink_window -= 1;
        }
        if w.hop_pending != 0 {
            w.hop_pending = 0;
            e.body.vy = -self.rng.ticks(384 * 60, 448 * 60);
        }
        if w.sinking != 0 {
            e.body.vy = (e.body.vy + GRAVITY).min(MAX_FALL);
            e.body.x += e.body.vx;
            e.body.y += e.body.vy;
        } else {
            let distance = e.body.vx;
            let (actual, started) = w.movement_box(&mut e.body, HOPPER_BOX, map, distance);
            if actual != distance {
                e.body.vx = 0;
            }
            if e.body
                .gravity_box(map, HOPPER_BOX, started, GRAVITY, MAX_FALL)
            {
                // spike_hopper.gd land
                if w.colour == 1 {
                    w.remove(&mut e.status, &mut e.can_respawn);
                } else if w.sink_window == 0 {
                    w.hop_pending = 1;
                    w.sink_window = SINK_WINDOW;
                } else {
                    e.body.vy = -self.rng.ticks(256 * 60, 384 * 60);
                    w.sinking = 1;
                }
            }
        }
        let e = &self.entities[index];
        if matches!(&e.kind, Kind::Walker(w) if w.thrown != 0) && e.status == 1 {
            self.hit_others(index, HOPPER_BOX, HitKind::Spit, false)?;
        }
        Ok(())
    }
    /// spike_hopper.gd contact: an untossed hopper hurts on touch.
    pub(crate) fn hopper_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        if w.intangible != 0 || w.thrown != 0 {
            return;
        }
        if w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(world_box(e.body, HOPPER_BOX), world_box(p, pb))
        {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
    /// needle_juggler.gd carried: the index of the hopper it holds.
    fn juggler_carried(&self, index: usize) -> Option<usize> {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return None;
        };
        if w.needle_token == 0 {
            return None;
        }
        let own = e.origin.token();
        let found = self
            .entities
            .iter()
            .position(|o| o.origin.token() == w.needle_token)?;
        let o = &self.entities[found];
        match &o.kind {
            Kind::Walker(n) if o.status == 1 && n.held == 0 && n.carrier == own => Some(found),
            _ => None,
        }
    }
    /// needle_juggler.gd _make_needle: registry.gd spawn_dynamic of an e40.
    fn juggler_make_needle(&mut self, x: i64, y: i64) -> Option<usize> {
        let serial = self.next_serial().ok()?;
        let hopper = Actor::new(ActorKind::Hopper, 0, 0, crate::Position { x, y });
        let family = self.entities.iter().filter(|e| e.is_enemy()).count() as i64;
        let mut row = Entity::dynamic(
            serial,
            Kind::Walker(Box::new(hopper)),
            Body {
                x,
                y,
                ..Body::default()
            },
            -1,
            8,
        );
        row.family_index = family;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Some(self.entities.len() - 1)
    }
    /// needle_juggler.gd catch
    fn juggler_catch(&mut self, index: usize, needle: usize) {
        let own = self.entities[index].origin.token();
        let token = self.entities[needle].origin.token();
        let n = &mut self.entities[needle];
        n.body.vx = 0;
        n.body.vy = 0;
        let Kind::Walker(h) = &mut n.kind else {
            unreachable!()
        };
        h.carrier = own;
        h.intangible = 0;
        h.sinking = 0;
        h.hop_pending = 0;
        let w = self.actor(index);
        w.accepting = 0;
        w.frowning = 0;
        w.offset = 0;
        w.needle_token = token;
        w.playing = 1;
        w.speed = FAST;
        w.frown_ticks = 0;
        w.grow_ticks = 0;
        w.rise = 0;
    }
    /// needle_juggler.gd step.
    pub(crate) fn juggler_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let fresh = self.actor(index).started == 0;
        if self.actor_process(index, map) == Hold::Gone {
            return Ok(());
        }
        self.actor(index).thrown_now = 0;
        self.entities[index]
            .body
            .gravity_box(map, JUGGLER_BOX, false, GRAVITY, MAX_FALL);
        let top = |run: &Run| run.entities[index].body.y - 48 * S;
        if fresh {
            let (x, y) = (self.entities[index].body.x, top(self) - 16 * S);
            if let Some(needle) = self.juggler_make_needle(x, y) {
                self.juggler_catch(index, needle);
            }
        }
        if self.actor(index).needle_token != 0 && self.juggler_carried(index).is_none() {
            self.actor(index).needle_token = 0;
        }
        self.juggler_timers(index);
        self.juggler_animate(index);
        if let Some(needle) = self.juggler_carried(index) {
            let e = &self.entities[index];
            let Kind::Walker(w) = &e.kind else {
                unreachable!()
            };
            let (x, y, facing) = (e.body.x, top(self) - 10 * S + w.offset * S / 60, e.facing);
            let n = &mut self.entities[needle];
            n.body.x = x;
            n.body.y = y;
            n.facing = facing;
        }
        Ok(())
    }
    /// needle_juggler.gd _timers
    fn juggler_timers(&mut self, index: usize) {
        let w = self.actor(index);
        if w.hold_ticks != 0 {
            w.hold_ticks -= 1;
            if w.hold_ticks == 0 && w.accepting != 0 {
                w.speed = 0;
                w.frame = 1;
                w.clock = 0;
            }
        }
        if w.pause_ticks != 0 {
            w.pause_ticks -= 1;
            if w.pause_ticks == 0 {
                w.playing = 1;
            }
        }
        if w.frown_ticks != 0 {
            w.frown_ticks -= 1;
            if w.frown_ticks == 0 {
                w.playing = 1;
                w.speed = SLOW;
                w.frowning = 1;
                w.cycles = 0;
                w.grow_ticks = GROW_TICKS;
            }
        }
        if w.grow_ticks != 0 && w.frowning != 0 {
            w.grow_ticks -= 1;
            if w.grow_ticks == 0 {
                w.offset = RISE_OFFSET * 60;
                let e = &self.entities[index];
                let (x, y) = (e.body.x, e.body.y - 48 * S + 16 * S);
                let own = e.origin.token();
                if let Some(needle) = self.juggler_make_needle(x, y) {
                    let token = self.entities[needle].origin.token();
                    if let Kind::Walker(h) = &mut self.entities[needle].kind {
                        h.carrier = own;
                        h.intangible = 1;
                    }
                    let w = self.actor(index);
                    w.needle_token = token;
                    w.rise = 1;
                    w.rise_ticks = RISE_WAIT;
                }
            }
        }
        let w = self.actor(index);
        if w.rise != 0 {
            w.rise_ticks -= 1;
            if w.rise == 2 {
                w.offset = RISE_OFFSET * 60 * w.rise_ticks / RISE_TICKS;
            }
            if w.rise_ticks == 0 {
                match w.rise {
                    1 => {
                        w.rise = 2;
                        w.rise_ticks = RISE_TICKS;
                    }
                    2 => {
                        w.rise = 3;
                        w.rise_ticks = RISE_WAIT;
                    }
                    _ => {
                        w.rise = 0;
                        if let Some(needle) = self.juggler_carried(index) {
                            self.juggler_catch(index, needle);
                        }
                    }
                }
            }
        }
    }
    /// needle_juggler.gd _animate
    fn juggler_animate(&mut self, index: usize) {
        let w = self.actor(index);
        if w.playing == 0 || w.speed == 0 {
            return;
        }
        w.clock += w.speed;
        let length = DURATIONS[w.frame as usize] * 60;
        if w.clock < length {
            return;
        }
        w.clock -= length;
        if w.forward != 0 {
            w.frame += 1;
            if w.frame > LAST_FRAME {
                w.forward = 0;
                w.frame = LAST_FRAME - 1;
            }
        } else {
            w.frame -= 1;
            if w.frame < 0 {
                // The single ping-pong pass ends back on the first frame.
                w.frame = 0;
                w.forward = 1;
                w.playing = 0;
                w.clock = 0;
                return;
            }
        }
        // needle_juggler.gd _frame_changed
        let px = self.player.body.x;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if w.frame == LAST_FRAME {
            if e.body.x != px {
                e.facing = if px > e.body.x { 1 } else { -1 };
            }
            if w.frowning != 0 {
                w.playing = 0;
            } else if w.cycles == 2 {
                w.playing = 0;
                w.pause_ticks = PAUSE_TICKS;
            }
        } else if w.frame == 0 && w.speed > 0 && w.frowning == 0 {
            self.juggler_toss(index);
        }
    }
    /// needle_juggler.gd _toss
    fn juggler_toss(&mut self, index: usize) {
        let w = self.actor(index);
        w.cycles += 1;
        w.accepting = 1;
        w.thrown_now = 1;
        w.frown_ticks = FROWN_TICKS;
        let cycles = w.cycles;
        if let Some(needle) = self.juggler_carried(index) {
            let height = if cycles < 3 { 80 } else { 176 };
            let n = &mut self.entities[needle];
            n.body.y -= 12 * S;
            n.body.vy = -root(2 * GRAVITY * height * S);
            if let Kind::Walker(h) = &mut n.kind {
                h.carrier = 0;
            }
        }
        let w = self.actor(index);
        w.needle_token = 0;
        if w.cycles != 3 {
            w.hold_ticks = HOLD_TICKS;
        } else {
            w.cycles = 0;
        }
    }
    /// needle_juggler.gd contact: catch a falling hopper; the head hurts unless frowning.
    pub(crate) fn juggler_contact(&mut self, index: usize) {
        let e = &self.entities[index];
        if e.status != 1 {
            return;
        }
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        if w.accepting != 0 && w.thrown_now == 0 {
            let b = world_box(e.body, JUGGLER_BOX);
            let y = e.body.y;
            let found = self.entities.iter().position(|o| {
                matches!(&o.kind, Kind::Walker(h) if h.kind == ActorKind::Hopper
                    && o.status == 1
                    && h.held == 0
                    && h.carrier == 0
                    && h.intangible == 0)
                    && o.body.y < y - 16 * S
                    && strict(b, world_box(o.body, HOPPER_BOX))
            });
            if let Some(needle) = found {
                self.juggler_catch(index, needle);
            }
        }
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        if w.frowning == 0
            && w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && !captured
            && strict(world_box(e.body, JUGGLER_BOX), world_box(p, pb))
        {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
}
