//! masked_shooter.gd (e31): a ledge-aware walker with a saved wind-up, shot and recoil
//! cycle, and enemy_pellet.gd, its straight terrain-independent shot. Both bodies live in
//! `Actor` (ActorKind::Shooter and ActorKind::Pellet).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{After, HitKind, Hold},
    entity::{Entity, Kind},
    math::approach,
    state::Run,
    Error, Placement, Position, SCALE as S,
};
pub(crate) const WALK: i64 = 0;
pub(crate) const PREPARE: i64 = 1;
pub(crate) const INHALE: i64 = 2;
pub(crate) const SHOOT: i64 = 3;
pub(crate) const BOX: [i64; 4] = [-16 * S, -24 * S, 16 * S, 16 * S];
pub(crate) const PELLET_BOX: [i64; 4] = [-8 * S, -4 * S, 8 * S, 4 * S];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Actor {
    /// masked_shooter.gd prepare (Options.prepare with one form) + create.
    pub fn shooter(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e31 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::Shooter, 0, p.mirror, p.position))
    }
    pub fn shooter_valid(&self) -> bool {
        self.variant == 0
            && (WALK..=SHOOT).contains(&self.mode)
            && (0..=36).contains(&self.timer)
            && (0..=120).contains(&self.cooldown)
            && [0, 1].contains(&self.queued)
    }
    /// enemy_pellet.gd valid
    pub fn pellet_valid(&self) -> bool {
        self.variant == 0 && self.held == 0 && self.spat == 0
    }
    /// masked_shooter.gd view_state animation.
    pub fn shooter_animation(&self) -> &'static str {
        ["Walk", "PrepShoot1", "PrepShoot2", "Shoot"][self.mode.clamp(WALK, SHOOT) as usize]
    }
    /// masked_shooter.gd tongue after a catch: the cycle restarts.
    pub(crate) fn shooter_caught(&mut self) {
        self.mode = WALK;
        self.timer = 0;
        self.cooldown = 0;
        self.queued = 1;
    }
}

impl Run {
    /// masked_shooter.gd step.
    pub(crate) fn shooter_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
        if w.frozen != 0 {
            return Err(Error::Unsupported {
                requirements: vec!["frozen masked shooter (ice shots are not ported)".into()],
            });
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
        if map.lava_overlaps(world_box(e.body, BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let body = &mut e.body;
        let facing = &mut e.facing;
        if w.cooldown != 0 {
            w.cooldown -= 1;
            if w.cooldown == 0 {
                w.queued = 1;
            }
        }
        let mut shot = None;
        if w.mode == WALK {
            if w.queued != 0 {
                w.queued = 0;
                w.mode = PREPARE;
                w.timer = 15;
                body.vx = 0;
            } else {
                if w.cooldown == 0 {
                    w.cooldown = 120;
                }
                let wet = i64::from(map.water_overlaps(world_box(*body, BOX)));
                body.vx = *facing * 48 * 60 / (wet + 1);
                if body.floor(map, BOX) != 0 {
                    // enemy_motion.gd edge
                    let left = if *facing > 0 { body.x } else { body.x - 12 * S };
                    let bottom = body.y + BOX[3];
                    if !map.support_in_box([left, bottom, left + 12 * S, bottom + 28 * S]) {
                        *facing = -*facing;
                        body.vx = -body.vx;
                    }
                }
            }
        } else {
            w.timer -= 1;
            if w.mode == SHOOT {
                body.vx = approach(body.vx, 0, 368);
            }
            if w.timer == 0 {
                match w.mode {
                    PREPARE => {
                        w.mode = INHALE;
                        w.timer = 36;
                    }
                    INHALE => {
                        w.mode = SHOOT;
                        w.timer = 35;
                        body.vx = -*facing * 6072;
                        shot = Some((
                            Position {
                                x: body.x + *facing * 18 * S,
                                y: body.y - 8 * S,
                            },
                            *facing,
                        ));
                    }
                    _ => w.mode = WALK,
                }
            }
        }
        if let Some((at, direction)) = shot {
            // registry.gd spawn_dynamic("enemy_pellet", ..., {"facing": facing}).
            self.spawn_pellet(at, direction)?;
        }
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let body = &mut e.body;
        let distance = body.vx;
        // enemy_motion.gd move (horizontal), always called.
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
            e.facing = -e.facing;
        }
        body.gravity(map, BOX, started);
        Ok(())
    }
    /// registry.gd spawn_dynamic for an enemy_pellet: an enemy row with the next family
    /// index; enemy_pellet.gd create sets its speed.
    fn spawn_pellet(&mut self, at: Position, facing: i64) -> Result<(), Error> {
        let serial = self.next_serial()?;
        let family = self
            .entities
            .iter()
            .filter(|e| matches!(e.kind, Kind::Walker(_)))
            .count() as i64;
        let pellet = Actor::new(ActorKind::Pellet, 0, 0, at);
        let mut row = Entity::dynamic(
            serial,
            Kind::Walker(pellet),
            Body {
                x: at.x,
                y: at.y,
                vx: facing * 256 * 60,
                vy: 0,
            },
            facing,
            8,
        );
        row.family_index = family;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    /// enemy_pellet.gd step: it flies straight on, through terrain.
    pub(crate) fn pellet_step(&mut self, index: usize, map: &Probe) {
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
        if action == Hold::Gone {
            return;
        }
        e.body.vx = e.facing * 256 * 60;
        e.body.x += e.body.vx;
    }
    /// masked_shooter.gd contact: a stomp removes it; a touch from below or the side hurts.
    pub(crate) fn shooter_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, BOX), world_box(p, pb));
        if touching {
            if e.body.y > p.y - 8 * S && w.contact == 0 {
                if !pounding {
                    self.player.stomp(e.body.vy, input, &mut self.sound);
                }
                w.remove(&mut e.status, &mut e.can_respawn);
            } else if e.body.y < p.y - 8 * S {
                let x = e.body.x;
                self.player.hurt(x, &mut self.sound);
            }
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
    }
    /// enemy_pellet.gd contact: any touch hurts.
    pub(crate) fn pellet_contact(&mut self, index: usize) {
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
        if strict(world_box(e.body, PELLET_BOX), world_box(p, pb)) {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
}
