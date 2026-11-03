//! petal_stem.gd (e18): an indestructible stem whose face grows five orbiting petals and
//! fires them outward; a ground-pound landing anywhere drops every attached petal.
//! stem_petal.gd (enemy_petal): the runtime petal. Both bodies live in `Actor`
//! (ActorKind::PetalStem and ActorKind::Petal).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{HitKind, Hold},
    entity::{Entity, Kind},
    math::{turn_cosine, turn_sine},
    state::Run,
    Error, Placement, Position, SCALE as S,
};
// petal_stem.gd phases.
pub(crate) const GROW: i64 = 0;
pub(crate) const SHOOT: i64 = 1;
pub(crate) const FADE: i64 = 2;
pub(crate) const REGAIN: i64 = 3;
const GROW_TICKS: i64 = 18;
const PETAL_TICK: i64 = 18;
const DANCE_TICK: i64 = 78;
const FREEZE_TICK: i64 = 9;
const LAUNCH_TICK: i64 = 27;
const FADE_TICKS: i64 = 78;
const REGAIN_TICKS: i64 = 180;
const PETALS: i64 = 5;
const ORBIT_STEP: i64 = -3200;
const PETAL_SPEED: i64 = 256 * 60;
pub(crate) const STEM_BOX: [i64; 4] = [-12 * S, -16 * S, 12 * S, 16 * S];
// stem_petal.gd modes.
pub(crate) const ORBIT: i64 = 0;
pub(crate) const FLY: i64 = 1;
pub(crate) const FALL: i64 = 2;
pub(crate) const THROWN: i64 = 3;
const RADIUS: i64 = 32;
const RADIUS_TICKS: i64 = 18;
const MAX_FALL: i64 = 704 * 60;
pub(crate) const PETAL_BOX: [i64; 4] = [-16 * S, -16 * S, 16 * S, 16 * S];
const HULL: [[i64; 2]; 8] = [
    [-12, -12],
    [0, -16],
    [12, -12],
    [16, 0],
    [12, 12],
    [0, 16],
    [-12, 12],
    [-16, 0],
];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}

impl Actor {
    /// petal_stem.gd prepare (Options.prepare with one form and no mirror) + create.
    pub fn petal_stem(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || p.mirror != 0 || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e18 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::PetalStem, 0, 0, p.position))
    }
    pub fn petal_stem_valid(&self) -> bool {
        self.variant == 0
            && (GROW..=REGAIN).contains(&self.phase)
            && (0..=DANCE_TICK + 240).contains(&self.timer)
            && (0..=DANCE_TICK + 240).contains(&self.shoot_at)
            && (0..360_000).contains(&self.orbit)
            && [0, 1].contains(&self.dancing)
            && [0, 1].contains(&self.has_petals)
    }
    pub fn petal_valid(&self) -> bool {
        self.variant == 0
            && (ORBIT..=THROWN).contains(&self.mode)
            && self.stem_token >= 0
            && (0..PETALS).contains(&self.slot)
            && (0..=RADIUS_TICKS).contains(&self.age)
    }
    /// petal_stem.gd face_center
    fn face_center(&self, body: Body) -> Position {
        let rise = if self.phase != GROW {
            16 * S
        } else {
            16 * S * self.timer.min(GROW_TICKS) / GROW_TICKS
        };
        Position {
            x: body.x,
            y: body.y - 16 * S - rise,
        }
    }
    /// petal_stem.gd petal_angle
    fn petal_angle(&self, slot: i64) -> i64 {
        (-90_000 + slot * 72_000 + self.orbit).rem_euclid(360_000)
    }
    /// petal_stem.gd _regain
    fn petal_regain(&mut self) {
        self.phase = REGAIN;
        self.timer = 0;
        self.dancing = 0;
        self.has_petals = 0;
    }
}

/// enemy_body.gd polygon_overlap: a separating-axis test of a hull and a box (open).
pub(crate) fn polygon_overlap(hull: &[Position], b: [i64; 4]) -> bool {
    if hull.len() < 3 {
        return false;
    }
    let mut axes = vec![[1, 0], [0, 1]];
    for index in 0..hull.len() {
        let a = hull[index];
        let c = hull[(index + 1) % hull.len()];
        axes.push([a.y - c.y, c.x - a.x]);
    }
    for axis in axes {
        let dot = |p: Position| p.x * axis[0] + p.y * axis[1];
        let mut minimum = dot(hull[0]);
        let mut maximum = minimum;
        for &p in hull {
            minimum = minimum.min(dot(p));
            maximum = maximum.max(dot(p));
        }
        let low = b[if axis[0] >= 0 { 0 } else { 2 }] * axis[0]
            + b[if axis[1] >= 0 { 1 } else { 3 }] * axis[1];
        let high = b[if axis[0] >= 0 { 2 } else { 0 }] * axis[0]
            + b[if axis[1] >= 0 { 3 } else { 1 }] * axis[1];
        if maximum <= low || high <= minimum {
            return false;
        }
    }
    true
}

impl Run {
    /// petal_stem.gd attached: active, unheld, orbiting petals of this stem, table order.
    fn attached_petals(&self, stem_token: i64) -> Vec<usize> {
        self.entities
            .iter()
            .enumerate()
            .filter(|(_, e)| {
                e.status == 1
                    && matches!(&e.kind, Kind::Walker(p) if p.kind == ActorKind::Petal
                        && p.held == 0 && p.stem_token == stem_token && p.mode == ORBIT)
            })
            .map(|(i, _)| i)
            .collect()
    }
    fn petal_stem_actor(&mut self, index: usize) -> &mut Actor {
        match &mut self.entities[index].kind {
            Kind::Walker(w) => w,
            _ => unreachable!("stem index"),
        }
    }
    /// petal_stem.gd step.
    pub(crate) fn petal_stem_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
        let fresh = w.started == 0;
        if fresh {
            // enemy_body.gd process: the first step's initialisation (mirror is always 0).
            w.started = 1;
            w.impact_cursor = player.impact;
        }
        let step = ActorStep {
            map,
            frame: *frame,
            camera: *camera,
            player,
            rng,
        };
        if w.process(
            token,
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &step,
        ) == Hold::Gone
        {
            return Ok(());
        }
        if fresh {
            // petal_stem.gd _drop_old: a fresh stem removes the petals it left behind.
            for i in self.attached_petals(token) {
                let p = &mut self.entities[i];
                if let Kind::Walker(w) = &mut p.kind {
                    w.remove(&mut p.status, &mut p.can_respawn);
                }
            }
        }
        self.entities[index].body.gravity(map, STEM_BOX, false);
        let impact = self.player.impact;
        if impact > self.petal_stem_actor(index).impact_cursor {
            self.petal_stem_actor(index).impact_cursor = impact;
            if [GROW, SHOOT].contains(&self.petal_stem_actor(index).phase) {
                self.fall_petals(index, token);
                let w = self.petal_stem_actor(index);
                w.phase = FADE;
                w.timer = 0;
                w.dancing = 0;
            }
        }
        let w = self.petal_stem_actor(index);
        w.timer += 1;
        match w.phase {
            GROW => {
                if w.timer == PETAL_TICK {
                    self.spawn_petals(index, token)?;
                }
                let w = self.petal_stem_actor(index);
                if w.timer == DANCE_TICK {
                    w.dancing = 1;
                    let wait = self.rng.ticks(222, 240);
                    self.petal_stem_actor(index).shoot_at = DANCE_TICK + wait;
                }
                let w = self.petal_stem_actor(index);
                if w.dancing != 0 {
                    w.orbit = (w.orbit + ORBIT_STEP).rem_euclid(360_000);
                }
                if w.shoot_at != 0 && w.timer >= w.shoot_at {
                    w.phase = SHOOT;
                    w.timer = 0;
                }
            }
            SHOOT => {
                if w.timer < FREEZE_TICK {
                    w.orbit = (w.orbit + ORBIT_STEP).rem_euclid(360_000);
                }
                if w.timer >= LAUNCH_TICK {
                    self.launch_petals(index, token);
                    self.petal_stem_actor(index).petal_regain();
                }
            }
            FADE => {
                if w.timer >= FADE_TICKS {
                    w.petal_regain();
                }
            }
            _ => {
                if w.timer >= REGAIN_TICKS {
                    w.phase = GROW;
                    w.timer = 0;
                    w.shoot_at = 0;
                    w.orbit = 0;
                }
            }
        }
        Ok(())
    }
    /// petal_stem.gd _spawn_petals: registry.gd spawn_dynamic of five enemy_petal rows.
    fn spawn_petals(&mut self, index: usize, token: i64) -> Result<(), Error> {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            unreachable!()
        };
        let center = w.face_center(e.body);
        for slot in 0..PETALS {
            let serial = self.next_serial()?;
            let family = self.entities.iter().filter(|e| e.is_enemy()).count() as i64;
            let mut petal = Actor::new(ActorKind::Petal, 0, 0, center);
            petal.stem_token = token;
            petal.slot = slot;
            let mut row = Entity::dynamic(
                serial,
                Kind::Walker(Box::new(petal)),
                Body {
                    x: center.x,
                    y: center.y,
                    ..Body::default()
                },
                -1,
                8,
            );
            row.family_index = family;
            row.can_despawn = 1;
            self.dynamic_serial = serial + 1;
            self.entities.push(row);
        }
        self.petal_stem_actor(index).has_petals = 1;
        Ok(())
    }
    /// petal_stem.gd _launch: attached petals fly straight out.
    fn launch_petals(&mut self, index: usize, token: i64) {
        let stem = self.petal_stem_actor(index).clone();
        for i in self.attached_petals(token) {
            let p = &mut self.entities[i];
            if let Kind::Walker(w) = &mut p.kind {
                let angle = stem.petal_angle(w.slot);
                w.mode = FLY;
                p.body.vx = turn_cosine(angle, PETAL_SPEED);
                p.body.vy = turn_sine(angle, PETAL_SPEED);
            }
        }
    }
    /// petal_stem.gd fall_petals: attached petals drop off and slide outward.
    fn fall_petals(&mut self, index: usize, token: i64) {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            unreachable!()
        };
        let center = w.face_center(e.body);
        for i in self.attached_petals(token) {
            let p = &mut self.entities[i];
            if let Kind::Walker(w) = &mut p.kind {
                w.mode = FALL;
                // Source: vectorX = 16 * offset, then the 128 px/s maximum applies.
                p.body.vx = (16 * (p.body.x - center.x)).clamp(-128 * 60, 128 * 60);
                p.body.vy = -128 * 60;
            }
        }
        self.petal_stem_actor(index).has_petals = 0;
    }
    /// stem_petal.gd step.
    pub(crate) fn petal_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
        if [Hold::Held, Hold::Gone].contains(&action) {
            return Ok(());
        }
        if w.frozen != 0 {
            return Err(Error::Unsupported {
                requirements: vec!["frozen petal (ice shots are not ported)".into()],
            });
        }
        if action == Hold::Released {
            // Mouth release is the same plain throw as the spiked hopper.
            let upward = e.body.vx == 0;
            let direction = if upward {
                step.player.facing
            } else {
                e.body.vx.signum()
            };
            w.spat = 0;
            w.mode = THROWN;
            e.facing = direction;
            e.body.vx = direction * if upward { 200 } else { 320 } * 60;
            e.body.vy = if upward { -768 } else { -256 } * 60;
        }
        w.age = (w.age + 1).min(RADIUS_TICKS);
        let mode = w.mode;
        match mode {
            ORBIT => {
                let stem_token = w.stem_token;
                let stem = self.find_token(stem_token).and_then(|i| {
                    let s = &self.entities[i];
                    match &s.kind {
                        Kind::Walker(sw) if s.status == 1 && sw.kind == ActorKind::PetalStem => {
                            Some((sw.clone(), s.body))
                        }
                        _ => None,
                    }
                });
                let e = &mut self.entities[index];
                let Kind::Walker(w) = &mut e.kind else {
                    unreachable!()
                };
                let Some((stem, stem_body)) = stem else {
                    w.mode = FALL;
                    e.body.vy = -128 * 60;
                    return Ok(());
                };
                let center = stem.face_center(stem_body);
                let angle = stem.petal_angle(w.slot);
                let radius = RADIUS * S * w.age / RADIUS_TICKS;
                e.body.x = center.x + turn_cosine(angle, radius);
                e.body.y = center.y + turn_sine(angle, radius);
            }
            FLY => {
                e.body.x += e.body.vx;
                e.body.y += e.body.vy;
            }
            _ => {
                let body = &mut e.body;
                let distance = body.vx;
                // enemy_motion.gd move (horizontal)
                let (actual, started) = if body.prepare(map, PETAL_BOX) {
                    let support = body.floor(map, PETAL_BOX);
                    let started = support != 0 && body.vy >= 0;
                    (
                        body.horizontal(map, PETAL_BOX, distance, support, HorizontalMove::Actor),
                        started,
                    )
                } else {
                    (0, false)
                };
                if actual != distance {
                    body.vx = 0;
                }
                body.gravity_box(map, PETAL_BOX, started, 2048, MAX_FALL);
                if mode == THROWN && e.status == 1 {
                    self.hit_others(index, PETAL_BOX, HitKind::Spit, false)?;
                }
            }
        }
        // enemy_body.gd hazards
        let e = &mut self.entities[index];
        if map.lava_overlaps(world_box(e.body, PETAL_BOX)) {
            if let Kind::Walker(w) = &mut e.kind {
                w.remove(&mut e.status, &mut e.can_respawn);
            }
        }
        Ok(())
    }
    /// stem_petal.gd contact: the petal's hull hurts, unless it was thrown.
    pub(crate) fn petal_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        if w.mode == THROWN || w.hidden != 0 || w.held != 0 || e.status != 1 {
            return;
        }
        if self.player.captured_by != 0 {
            return;
        }
        let hull: Vec<Position> = HULL
            .iter()
            .map(|[x, y]| Position {
                x: e.body.x + x * S,
                y: e.body.y + y * S,
            })
            .collect();
        if polygon_overlap(&hull, world_box(p, pb)) {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
}
