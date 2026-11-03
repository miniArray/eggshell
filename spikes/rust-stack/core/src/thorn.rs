//! thorn_bush.gd (e36): a thorny bush that settles on the ground and hurts on every
//! touch, swapping spikes out and in every second; and bee_flyer.gd (e43): a flyer that
//! crosses the level at its speed through terrain, bobbing on a sine. Both live in
//! `Actor` (ActorKind::Thorn and ActorKind::Bee).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::Hold,
    entity::Kind,
    math::turn_sine,
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
pub(crate) const THORN_BOX: [i64; 4] = [-12 * S, -12 * S, 12 * S, 12 * S];
/// thorn_bush.gd BEAT: one second per spike phase, shared by every bush.
const BEAT: i64 = 60;
/// bee_flyer.gd MAX_OPTION.
const BEE_MAX_OPTION: i64 = 100_000;

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}
fn refuse(what: String) -> Error {
    Error::Unsupported {
        requirements: vec![what],
    }
}
/// registry.gd numeric_option with bee_flyer.gd's default for a missing or blank option.
fn number(p: &Placement, key: &str, default: f64) -> Result<f64, Error> {
    let value = match p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v) {
        None => default,
        Some(PropertyValue::String(s)) if s.trim().is_empty() => default,
        Some(PropertyValue::String(s)) => s
            .trim()
            .parse::<f64>()
            .map_err(|_| refuse(format!("e43 option {key}")))?,
        Some(PropertyValue::Number(v)) => *v,
        Some(_) => return Err(refuse(format!("e43 option {key}"))),
    };
    if !value.is_finite() || value.abs() > BEE_MAX_OPTION as f64 {
        // Bad data fails; values past the limit degrade to a placeholder (not ported).
        return Err(refuse(format!("e43 option {key} out of range")));
    }
    Ok(value)
}

impl Actor {
    /// thorn_bush.gd prepare (enemy_options.gd, forms 0..1) + create.
    pub fn thorn(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(refuse(format!(
                "e36 form F={} M={} R={}",
                p.variant, p.mirror, p.rotation
            )));
        }
        Ok(Actor::new(
            ActorKind::Thorn,
            p.variant,
            p.mirror,
            p.position,
        ))
    }
    /// thorn_bush.gd spikes_out: the shared beat follows the level clock; the second
    /// form is in the opposite beat.
    pub(crate) fn thorn_spikes_out(&self, frame: i64) -> bool {
        ((frame / BEAT) % 2 == 1) != (self.variant == 1)
    }
    /// bee_flyer.gd prepare (enemy_options.gd, form 0) + create.
    pub fn bee(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(refuse(format!(
                "e43 form F={} M={} R={}",
                p.variant, p.mirror, p.rotation
            )));
        }
        let bob = number(p, "E1", 2.0)?;
        let period = number(p, "E2", 0.5)?;
        let speed = number(p, "E3", 192.0)?;
        // enemy_options.gd MAX_SPEED / 60.
        if speed.abs() > 1000.0 {
            return Err(refuse("e43 speed E3 out of range".into()));
        }
        let mut a = Actor::new(ActorKind::Bee, 0, p.mirror, p.position);
        a.bob = bob as i64;
        a.bob_period = ((period * 60.0 - 0.000001).ceil() as i64).max(1);
        a.speed = speed as i64;
        Ok(a)
    }
    pub fn bee_valid(&self) -> bool {
        self.variant == 0
            && self.speed.abs() <= BEE_MAX_OPTION
            && self.bob.abs() <= BEE_MAX_OPTION
            && self.bob_period >= 1
            && (0..self.bob_period).contains(&self.age)
    }
    /// bee_flyer.gd bounds, by facing.
    pub(crate) fn bee_bounds(facing: i64) -> [i64; 4] {
        if facing < 0 {
            [-16 * S, -8 * S, 14 * S, 12 * S]
        } else {
            [-14 * S, -8 * S, 16 * S, 12 * S]
        }
    }
    /// bee_flyer.gd bob_offset
    fn bee_bob(&self, age: i64) -> i64 {
        let phase = age.rem_euclid(self.bob_period) * 360_000 / self.bob_period;
        self.bob * turn_sine(phase, S)
    }
}

impl Run {
    /// enemy_body.gd process for the actor at `index`, with the first step's
    /// initialisation; `None` when the body is held or gone.
    pub(crate) fn process_actor(&mut self, index: usize, map: &Probe) -> Option<Hold> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
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
        (![Hold::Held, Hold::Gone].contains(&action)).then_some(action)
    }
    /// thorn_bush.gd step: frozen step, lava, then settle under gravity.
    pub(crate) fn thorn_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        if self.process_actor(index, map).is_none() {
            return Ok(());
        }
        if self.enemy_frozen_step(index, map, THORN_BOX)? {
            return Ok(());
        }
        let e = &mut self.entities[index];
        if map.lava_overlaps(world_box(e.body, THORN_BOX)) {
            return self.remove_enemy(index);
        }
        e.body.vx = 0;
        e.body.gravity(map, THORN_BOX, false);
        Ok(())
    }
    /// thorn_bush.gd contact: frozen contact first; any touch hurts.
    pub(crate) fn thorn_contact(&mut self, index: usize, input: u8) -> Result<(), Error> {
        if self.frozen_contact(index, input)? {
            return Ok(());
        }
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return Ok(());
        };
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(world_box(e.body, THORN_BOX), world_box(p, pb));
        w.contact = i64::from(touching);
        if touching {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        Ok(())
    }
    /// thorn_bush.gd projectile_contact: any projectile destroys it; the projectile is
    /// spent (1) only on spikes, otherwise it bounces on (3).
    pub(crate) fn thorn_projectile(&mut self, index: usize) -> Result<i64, Error> {
        let spent = match &self.entities[index].kind {
            Kind::Walker(w) => w.thorn_spikes_out(self.frame),
            _ => false,
        };
        let e = &self.entities[index];
        if e.status == 1 && matches!(&e.kind, Kind::Walker(w) if w.held == 0) {
            self.remove_enemy(index)?;
        }
        Ok(if spent { 1 } else { 3 })
    }
    /// bee_flyer.gd step: straight flight through terrain with a bob.
    pub(crate) fn bee_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let Some(action) = self.process_actor(index, map) else {
            return Ok(());
        };
        let facing = self.entities[index].facing;
        if self.enemy_frozen_step(index, map, Actor::bee_bounds(facing))? {
            return Ok(());
        }
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if action == Hold::Released {
            w.on_spit_release(&mut e.body, &mut e.facing, 0, 0);
        }
        e.body.vx = e.facing * w.speed * 60;
        e.body.x += e.body.vx;
        e.body.y += w.bee_bob(w.age + 1) - w.bee_bob(w.age);
        w.age = (w.age + 1).rem_euclid(w.bob_period);
        Ok(())
    }
    /// bee_flyer.gd contact: landing on it defeats it (and bounces unless pounding);
    /// touching it from below hurts.
    pub(crate) fn bee_contact(&mut self, index: usize, input: u8) -> Result<(), Error> {
        if self.frozen_contact(index, input)? {
            return Ok(());
        }
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return Ok(());
        };
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(
                world_box(e.body, Actor::bee_bounds(e.facing)),
                world_box(p, pb),
            );
        let was = w.contact;
        let above = e.body.y > p.y - 8 * S;
        let below = e.body.y < p.y - 8 * S;
        if touching && was == 0 && above {
            if !pounding {
                self.player.stomp(0, input, &mut self.sound);
            }
            self.remove_enemy(index)?;
        } else if touching && below {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
        Ok(())
    }
}
