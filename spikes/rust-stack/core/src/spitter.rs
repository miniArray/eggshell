//! spitting_stem.gd (e41): a rooted, three-hit actor with a rotating head and three-shot
//! cycles, and enemy_spike.gd, its catchable ballistic shot. Both bodies live in `Actor`
//! (ActorKind::Spitter and ActorKind::Spike).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{After, HitKind, Hold},
    entity::{Entity, Kind},
    math::{angle_delta, angle_to, turn_cosine, turn_sine},
    petal::polygon_overlap,
    state::Run,
    Error, Placement, Position, SCALE as S,
};
pub(crate) const IDLE: i64 = 0;
pub(crate) const ALIGN: i64 = 1;
pub(crate) const WAIT: i64 = 2;
pub(crate) const REST: i64 = 3;
pub(crate) const HURT: i64 = 4;
pub(crate) const DEFEAT: i64 = 5;
pub(crate) const BODY_BOX: [i64; 4] = [-16 * S, -10 * S, 16 * S, 16 * S];
pub(crate) const SPIKE_BOX: [i64; 4] = [-12 * S, -12 * S, 12 * S, 12 * S];
const IDLE_HULL: [[i64; 2]; 8] = [
    [50, 16],
    [30, 28],
    [8, 20],
    [-2, 2],
    [8, -16],
    [30, -26],
    [50, -14],
    [62, 2],
];
const SPIT_HULL: [[i64; 2]; 7] = [
    [52, 28],
    [27, 32],
    [8, 24],
    [-2, 2],
    [4, -20],
    [27, -28],
    [52, -24],
];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Actor {
    /// spitting_stem.gd prepare (Options.prepare with one form and no mirror) + create.
    pub fn spitter(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || p.mirror != 0 || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e41 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Spitter, 0, 0, p.position);
        a.timer = 90;
        Ok(a)
    }
    pub fn spitter_valid(&self) -> bool {
        self.variant == 0
            && self.mirror == 0
            && self.held == 0
            && self.spat == 0
            && (IDLE..=DEFEAT).contains(&self.mode)
            && (0..=3).contains(&self.hp)
            && (0..=3).contains(&self.shots)
            && (0..=105).contains(&self.timer)
            && (0..360_000).contains(&self.head_angle)
            && (0..360_000).contains(&self.turn_to)
            && (0..=90).contains(&self.turn_left)
            && (0..=12).contains(&self.spit_ticks)
    }
    /// enemy_spike.gd valid
    pub fn spike_valid(&self) -> bool {
        self.variant == 0
    }
    /// spitting_stem.gd head_scale (per mille).
    fn head_scale(&self) -> i64 {
        if self.mode == DEFEAT {
            return 1000.min(self.timer * 1000 / 45);
        }
        if self.mode == IDLE {
            let phase = (90 - self.timer).rem_euclid(18);
            let time = if phase <= 9 { phase } else { 18 - phase };
            return 1000 - 100 * time * time / 81;
        }
        1000
    }
    /// spitting_stem.gd head_hull
    pub(crate) fn head_hull(&self, body: Body, facing: i64) -> Vec<Position> {
        let points: &[[i64; 2]] = if self.spit_ticks != 0 || self.mode == DEFEAT {
            &SPIT_HULL
        } else {
            &IDLE_HULL
        };
        let scale = self.head_scale();
        let cosine = turn_cosine(self.head_angle, S);
        let sine = turn_sine(self.head_angle, S);
        let joint_x = body.x + if facing > 0 { 2 } else { -2 } * S;
        let joint_y = body.y - 8 * S;
        points
            .iter()
            .map(|[px, py]| {
                let x = px * S * scale / 1000;
                let y = py * S * scale / 1000 * if facing > 0 { -1 } else { 1 };
                Position {
                    x: joint_x + (x * cosine - y * sine) / S,
                    y: joint_y + (x * sine + y * cosine) / S,
                }
            })
            .collect()
    }
    /// spitting_stem.gd bounds: the head's box and the body, relative to the body.
    pub(crate) fn spitter_bounds(&self, body: Body, facing: i64) -> [i64; 4] {
        let hull = self.head_hull(body, facing);
        let mut head = [hull[0].x, hull[0].y, hull[0].x, hull[0].y];
        for p in &hull {
            head = [
                head[0].min(p.x),
                head[1].min(p.y),
                head[2].max(p.x),
                head[3].max(p.y),
            ];
        }
        let b = world_box(body, BODY_BOX);
        [
            head[0].min(b[0]) - body.x,
            head[1].min(b[1]) - body.y,
            head[2].max(b[2]) - body.x,
            head[3].max(b[3]) - body.y,
        ]
    }
    /// spitting_stem.gd touches: the body box or the head hull.
    pub(crate) fn spitter_touches(&self, body: Body, facing: i64, b: [i64; 4]) -> bool {
        strict(world_box(body, BODY_BOX), b) || polygon_overlap(&self.head_hull(body, facing), b)
    }
    /// spitting_stem.gd tongue: the head blocks the tongue (2).
    pub(crate) fn spitter_tongue(&self, body: Body, facing: i64, sensor: [i64; 4]) -> i64 {
        if self.mode != DEFEAT && polygon_overlap(&self.head_hull(body, facing), sensor) {
            2
        } else {
            0
        }
    }
    /// spitting_stem.gd hit with EGG, SPIT or SHELL (CLEAR has no Rust caller; BUMP does
    /// nothing): a hit costs one of three points and turns the head away.
    pub(crate) fn spitter_hit(&mut self, body: Body, can_respawn: &mut i64, from_x: i64) {
        if self.mode == DEFEAT {
            return;
        }
        self.hp -= 1;
        self.shots = 3;
        self.spit_ticks = 0;
        self.turn_to = if from_x < body.x { 300_000 } else { 240_000 };
        self.turn_left = 15;
        self.mode = if self.hp != 0 { HURT } else { DEFEAT };
        self.timer = if self.hp != 0 { 60 } else { 105 };
        if self.hp == 0 {
            *can_respawn = 0;
        }
    }
    /// spitting_stem.gd _align
    fn spitter_align(&mut self, facing: i64) {
        self.mode = ALIGN;
        self.turn_to = if facing > 0 {
            (257 + 24 * self.shots) * 1000
        } else {
            (283 - 21 * self.shots) * 1000
        };
        self.turn_left = 1.max((angle_delta(self.head_angle, self.turn_to).abs() + 1999) / 2000);
    }
}

impl Run {
    /// spitting_stem.gd step.
    pub(crate) fn spitter_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
                requirements: vec!["frozen spitting stem (ice shots are not ported)".into()],
            });
        }
        e.body.gravity(map, BODY_BOX, false);
        if map.lava_overlaps(world_box(e.body, BODY_BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let p = step.player.body;
        if fresh {
            w.head_angle = angle_to(p.x - e.body.x, p.y - e.body.y + 8 * S);
        }
        w.spit_ticks = (w.spit_ticks - 1).max(0);
        e.facing = if w.head_angle > 270_000 || w.head_angle < 90_000 {
            1
        } else {
            -1
        };
        if w.turn_left != 0 {
            w.head_angle = (w.head_angle + angle_delta(w.head_angle, w.turn_to) / w.turn_left)
                .rem_euclid(360_000);
            w.turn_left -= 1;
            if w.mode == ALIGN {
                if w.turn_left == 0 {
                    self.spitter_shoot(index)?;
                }
                return Ok(());
            }
        }
        if w.mode == IDLE {
            let side = if e.facing > 0 { 2 } else { -2 } * S;
            let desired = angle_to(p.x - e.body.x - side, p.y - e.body.y + 8 * S);
            w.head_angle = (w.head_angle + angle_delta(w.head_angle, desired) * 37649 / 1_000_000)
                .rem_euclid(360_000);
            if w.head_angle < 90_000 {
                w.head_angle = w.head_angle.min(65_000);
            } else if w.head_angle < 115_000 {
                w.head_angle = 115_000;
            }
        }
        w.timer = (w.timer - 1).max(0);
        if w.timer != 0 {
            return Ok(());
        }
        match w.mode {
            IDLE | WAIT => w.spitter_align(e.facing),
            REST | HURT => {
                w.mode = IDLE;
                w.timer = 90;
                w.shots = 3;
            }
            DEFEAT => w.remove(&mut e.status, &mut e.can_respawn),
            _ => {}
        }
        Ok(())
    }
    /// spitting_stem.gd _shoot: a spike from the mouth along the head's angle.
    fn spitter_shoot(&mut self, index: usize) -> Result<(), Error> {
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        w.shots -= 1;
        w.spit_ticks = 12;
        w.mode = if w.shots != 0 { WAIT } else { REST };
        w.timer = if w.shots != 0 { 60 } else { 72 };
        let cosine = turn_cosine(w.head_angle, S);
        let sine = turn_sine(w.head_angle, S);
        let mouth_y = if e.facing > 0 { 3 } else { -3 };
        let x = e.body.x + if e.facing > 0 { 2 } else { -2 } * S + 37 * cosine - mouth_y * sine;
        let y = e.body.y - 8 * S + 37 * sine + mouth_y * cosine;
        let facing = e.facing;
        // registry.gd spawn_dynamic("enemy_spike", x, y, {vx, vy, facing}).
        let serial = self.next_serial()?;
        let family = self
            .entities
            .iter()
            .filter(|e| matches!(e.kind, Kind::Walker(_)))
            .count() as i64;
        let spike = Actor::new(ActorKind::Spike, 0, 0, Position { x, y });
        let mut row = Entity::dynamic(
            serial,
            Kind::Walker(spike),
            Body {
                x,
                y,
                vx: 384 * 60 * cosine / S,
                vy: 768 * 60 * sine / S,
            },
            facing,
            8,
        );
        row.family_index = family;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    /// spitting_stem.gd contact: the body or the head hurts.
    pub(crate) fn spitter_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        if w.mode != DEFEAT && w.held == 0 && w.spitter_touches(e.body, e.facing, world_box(p, pb))
        {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
    /// spitting_stem.gd projectile_contact for a non-egg projectile at `projectile_box`.
    /// e28 (`hanging`) removes it; e11 (`armored`) gets 3; anything else is consumed (1).
    pub(crate) fn spitter_projectile(
        &mut self,
        target: usize,
        projectile_box: [i64; 4],
        from_x: i64,
        hanging: bool,
        armored: bool,
    ) -> i64 {
        let o = &mut self.entities[target];
        let Kind::Walker(w) = &mut o.kind else {
            return 0;
        };
        if w.mode == DEFEAT || !w.spitter_touches(o.body, o.facing, projectile_box) {
            return 0;
        }
        if hanging {
            w.remove(&mut o.status, &mut o.can_respawn);
            return 3;
        }
        w.spitter_hit(o.body, &mut o.can_respawn, from_x);
        if armored {
            3
        } else {
            1
        }
    }
    /// enemy_spike.gd step: it flies until it lands, which destroys it.
    pub(crate) fn spike_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
        let mut step = ActorStep {
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
        if let Some(after) = w.spit_step(
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &mut step,
        ) {
            if let After::HitOthers(b) = after {
                self.hit_others(index, b, HitKind::Spit, true)?;
            }
            return Ok(());
        }
        if map.lava_overlaps(world_box(e.body, SPIKE_BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let body = &mut e.body;
        let distance = body.vx;
        // enemy_motion.gd move (horizontal)
        let started = if body.prepare(map, SPIKE_BOX) {
            let support = body.floor(map, SPIKE_BOX);
            let started = support != 0 && body.vy >= 0;
            body.horizontal(map, SPIKE_BOX, distance, support, HorizontalMove::Actor);
            started
        } else {
            false
        };
        if body.gravity_box(map, SPIKE_BOX, started, 1536, 704 * 60) {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        Ok(())
    }
    /// enemy_spike.gd contact: any touch hurts.
    pub(crate) fn spike_contact(&mut self, index: usize) {
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
        if strict(world_box(e.body, SPIKE_BOX), world_box(p, pb)) {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
}
