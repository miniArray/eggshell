//! Fire and ice: elements.gd, element_reactions.gd (burn, freeze, frozen step and
//! contact, thaw) and element_shot.gd (the fire_shot and ice_shot breath).
use crate::{
    actors::{Actor, ActorKind},
    body::{Body, Probe},
    entity::{Entity, Kind},
    math::{turn_cosine, turn_sine},
    state::Run,
    Error, SCALE as S,
};

/// elements.gd THAW_TICKS: a thawing body thaws after eight seconds.
pub(crate) const THAW_TICKS: i64 = 480;
/// element_reactions.gd HOP: a body hops up when it freezes on the ground and when it thaws.
const HOP: i64 = -384 * 60;
/// element_shot.gd: 768 px/s for 0.3 s from 16 px behind the mouth; a wall ends it 0.05 s later.
const SPEED: i64 = 768 * 60;
const BACK: i64 = 16 * S;
const LIFE_TICKS: i64 = 18;
const WALL_TICKS: i64 = 3;
pub(crate) const SHOT_BOX: [i64; 4] = [-14 * S, -14 * S, 14 * S, 14 * S];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Element {
    Fire,
    Ice,
}

/// element_shot.gd FIELDS.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ElementShot {
    pub element: Element,
    pub heading: i64,
    pub age: i64,
    pub wall_ticks: i64,
}

impl ElementShot {
    pub fn new(element: Element) -> Self {
        Self {
            element,
            heading: 0,
            age: 0,
            wall_ticks: 0,
        }
    }
    pub fn code(&self) -> &'static str {
        match self.element {
            Element::Fire => "fire_shot",
            Element::Ice => "ice_shot",
        }
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "heading" => self.heading,
            "age" => self.age,
            "wall_ticks" => self.wall_ticks,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        let target = match n {
            "heading" => &mut self.heading,
            "age" => &mut self.age,
            "wall_ticks" => &mut self.wall_ticks,
            _ => return false,
        };
        *target = value;
        true
    }
    /// element_shot.gd valid
    pub fn valid(&self) -> bool {
        (0..360_000).contains(&self.heading)
            && (0..=LIFE_TICKS + 1).contains(&self.age)
            && (0..=WALL_TICKS).contains(&self.wall_ticks)
    }
}

/// What element_reactions.gd frozen_step did.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Frozen {
    /// Not frozen (or held, spat or just thawed while spat): the body's own step runs.
    Free,
    /// The frozen step was the whole step.
    Done,
    /// The frozen body touched lava: the caller removes it (with its on_remove).
    Lava,
}

impl Actor {
    /// The type's ELEMENT_REACTIONS beyond BURNS | FREEZES: (ANCHORED, THAWS).
    /// actor.gd element_reactions: plants keep their place, fish thaw; lava_bubble.gd thaws.
    fn element_flags(&self) -> (bool, bool) {
        match self.kind {
            ActorKind::Plant => (true, false),
            ActorKind::Fish | ActorKind::LandFish | ActorKind::Bubble => (false, true),
            _ => (false, false),
        }
    }
    /// element_reactions.gd freeze; `bounds` is None when the caller passes [].
    pub(crate) fn freeze(&mut self, body: &mut Body, map: &Probe, bounds: Option<[i64; 4]>) {
        let (anchored, thaws) = self.element_flags();
        self.frozen = 1;
        self.thaw_ticks = if thaws { THAW_TICKS } else { 0 };
        body.vx = 0;
        if let Some(b) = bounds.filter(|_| !anchored) {
            body.vy = if body.floor(map, b) != 0 { HOP } else { 0 };
        }
    }
    /// element_reactions.gd frozen_step with the type's bounds `b`.
    pub(crate) fn frozen_step(
        &mut self,
        body: &mut Body,
        status: i64,
        map: &Probe,
        b: [i64; 4],
    ) -> Frozen {
        if self.frozen == 0 || status != 1 {
            return Frozen::Free;
        }
        // The thaw count pauses in the mouth and runs on while the body is spat.
        if self.held != 0 {
            return Frozen::Free;
        }
        if self.thaw_ticks > 0 {
            self.thaw_ticks -= 1;
            if self.thaw_ticks == 0 {
                self.frozen = 0;
                if self.spat != 0 {
                    return Frozen::Free;
                }
                body.vy = HOP;
                return Frozen::Done;
            }
        }
        if self.spat != 0 {
            return Frozen::Free;
        }
        body.vx = 0;
        let (anchored, _) = self.element_flags();
        if !anchored {
            // enemy_motion.gd gravity_box: e20/e21 skip the water quartering.
            if [ActorKind::Fish, ActorKind::LandFish].contains(&self.kind) {
                body.gravity_box_dry(map, b, false);
            } else {
                body.gravity(map, b, false);
            }
        }
        if map.lava_overlaps([body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]) {
            return Frozen::Lava;
        }
        Frozen::Done
    }
}

impl Run {
    /// enemy_body.gd remove with the type's on_remove: shell_walker.gd frees its origin
    /// shell; actor.gd releases a captured player from a plant.
    pub(crate) fn remove_enemy(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return Ok(());
        };
        if [ActorKind::Shell, ActorKind::Runner].contains(&w.kind) {
            self.shell_remove(index);
            return Ok(());
        }
        if e.status != 3 {
            self.plant_on_remove(index);
        }
        let e = &mut self.entities[index];
        if let Kind::Walker(w) = &mut e.kind {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        Ok(())
    }
    /// element_reactions.gd frozen_step for the enemy at `index` with bounds `b`.
    /// Returns true when it was the whole step.
    pub(crate) fn enemy_frozen_step(
        &mut self,
        index: usize,
        map: &Probe,
        b: [i64; 4],
    ) -> Result<bool, Error> {
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return Ok(false);
        };
        match w.frozen_step(&mut e.body, e.status, map, b) {
            Frozen::Free => Ok(false),
            Frozen::Done => Ok(true),
            Frozen::Lava => {
                self.remove_enemy(index)?;
                Ok(true)
            }
        }
    }
    /// element_reactions.gd frozen_contact: touching a frozen body shatters it, and a
    /// stomp (not a pound) from above also bounces the player. False when not frozen.
    pub(crate) fn frozen_contact(&mut self, index: usize, input: u8) -> Result<bool, Error> {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return Ok(false);
        };
        if w.frozen == 0 {
            return Ok(false);
        }
        let b = w.bounds(e.body, e.facing);
        let pb = self.player.bounds();
        let p = self.player.body;
        // enemy_body.gd player_overlap: open edges, nothing hidden, held, spat or captured.
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && self.player.captured_by == 0
            && e.body.x + b[0] < p.x + pb[2]
            && e.body.x + b[2] > p.x + pb[0]
            && e.body.y + b[1] < p.y + pb[3]
            && e.body.y + b[3] > p.y + pb[1];
        if touching {
            if e.body.y > p.y - 8 * S && ![2, 3].contains(&self.player.action) {
                let vy = e.body.vy;
                self.player
                    .enemy_bounce(vy, input, self.message.modal_token != 0, &mut self.sound);
            }
            self.remove_enemy(index)?;
        }
        Ok(true)
    }
    /// A fire or ice strike on entity `index` (its `hit` with Hits.FIRE or Hits.ICE).
    fn element_hit(&mut self, index: usize, element: Element, map: &Probe) -> Result<(), Error> {
        let e = &mut self.entities[index];
        let unported = match &e.kind {
            Kind::Walker(w) => match w.kind {
                ActorKind::Shooter => Some("e31"),
                ActorKind::Wing => Some("e30"),
                ActorKind::Shot => Some("enemy_shot"),
                ActorKind::Sprout => Some("e12"),
                ActorKind::Hopper => Some("e40"),
                ActorKind::Bulk => Some("e17"),
                ActorKind::Gust => Some("e33"),
                ActorKind::Spore => Some("e13"),
                ActorKind::Hang => Some("e14"),
                ActorKind::Spine => Some("e25"),
                ActorKind::Slime => Some("e15"),
                ActorKind::Petal => Some("enemy_petal"),
                ActorKind::Spitter => Some("e41"),
                _ => None,
            },
            Kind::Launcher(_) => Some("e37"),
            _ => None,
        };
        if let Some(code) = unported {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "fire or ice strike on {code} (its reactions are not ported)"
                )],
            });
        }
        let burns = match &mut e.kind {
            // lamp.gd projectile_contact: fire_shot counts as fire, ice_shot as ice.
            Kind::Lamp(l) => {
                l.touch(element == Element::Fire);
                false
            }
            // release_cloud.gd hit: fire and ice open the cache at once.
            Kind::Cache(c) => {
                c.open(e.status, e.collected);
                false
            }
            // lava_bubble.gd hit: fire only puts out the cold form; ice freezes the others
            // (with no bounds, so no hop) and stops them.
            Kind::Walker(w) if w.kind == ActorKind::Bubble => {
                let cold = w.variant == crate::bubble::COLD_FORM;
                if element == Element::Ice && !cold {
                    if e.status == 1 && w.held == 0 && w.frozen == 0 {
                        w.freeze(&mut e.body, map, None);
                    }
                    if w.frozen != 0 {
                        e.body.vy = 0;
                        w.speed = 0;
                    }
                }
                element == Element::Fire && cold && e.status == 1
            }
            // soft_giant.gd ELEMENT_REACTIONS is FREEZES only: fire does nothing.
            Kind::Walker(w) if w.kind == ActorKind::SoftGiant && element == Element::Fire => false,
            // element_reactions.gd hit: fire burns (Body.remove); ice freezes once.
            Kind::Walker(w) if e.status == 1 && w.held == 0 => {
                if element == Element::Ice && w.frozen == 0 {
                    let b = w.bounds(e.body, e.facing);
                    w.freeze(&mut e.body, map, Some(b));
                }
                element == Element::Fire
            }
            _ => false,
        };
        if burns {
            self.remove_enemy(index)?;
        }
        Ok(())
    }
    /// element_shot.gd spawn, from a heat or cold request at the mouth.
    pub(crate) fn spawn_shot(
        &mut self,
        element: Element,
        x: i64,
        y: i64,
        angle: i64,
    ) -> Result<(), Error> {
        let serial = self.next_serial()?;
        let heading = angle.rem_euclid(360_000);
        let cosine = turn_cosine(heading, S);
        let sine = turn_sine(heading, S);
        let mut shot = ElementShot::new(element);
        shot.heading = heading;
        let body = Body {
            x: x - BACK * cosine / S,
            y: y - BACK * sine / S,
            vx: SPEED * cosine / S,
            vy: SPEED * sine / S,
        };
        let mut row = Entity::dynamic(serial, Kind::ElementShot(shot), body, -1, 7);
        row.can_despawn = 1;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    /// element_shot.gd step: fly straight, stop 3 ticks after touching terrain, and strike
    /// every reacting object it overlaps on the way.
    pub(crate) fn element_shot_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let e = &mut self.entities[index];
        let Kind::ElementShot(s) = &mut e.kind else {
            return Ok(());
        };
        s.age += 1;
        if s.wall_ticks != 0 {
            s.wall_ticks -= 1;
            if s.wall_ticks == 0 {
                e.status = 3;
                return Ok(());
            }
        }
        if s.age > LIFE_TICKS {
            e.status = 3;
            return Ok(());
        }
        e.body.x += e.body.vx;
        e.body.y += e.body.vy;
        let b = SHOT_BOX;
        let area = [
            e.body.x + b[0],
            e.body.y + b[1],
            e.body.x + b[2],
            e.body.y + b[3],
        ];
        if s.wall_ticks == 0 && (map.border_overlaps(area) || map.terrain_overlaps(area)) {
            s.wall_ticks = WALL_TICKS;
        }
        let element = s.element;
        self.strike(index, element, area, map)
    }
    /// element_shot.gd strike: every active, visible, unheld object with element reactions
    /// that overlaps the shot takes the element, in table order; the shot flies on.
    fn strike(
        &mut self,
        index: usize,
        element: Element,
        area: [i64; 4],
        map: &Probe,
    ) -> Result<(), Error> {
        for other in 0..self.entities.len() {
            if other == index {
                continue;
            }
            let o = &self.entities[other];
            let b = match &o.kind {
                // sneak_thief.gd, hanging_roller.gd, needle_juggler.gd, enemy_pellet.gd,
                // petal_stem.gd and the ghosts declare no ELEMENT_REACTIONS: the shot passes.
                Kind::Walker(w)
                    if [
                        ActorKind::Thief,
                        ActorKind::Roller,
                        ActorKind::Juggler,
                        ActorKind::Pellet,
                        ActorKind::PetalStem,
                        ActorKind::Shy,
                        ActorKind::Blind,
                        ActorKind::Spike,
                        ActorKind::Helmet,
                        ActorKind::MaceBall,
                    ]
                    .contains(&w.kind) =>
                {
                    continue
                }
                Kind::Walker(w) if w.held == 0 && w.hidden == 0 => w.bounds(o.body, o.facing),
                Kind::Cache(c) => c.bounds(),
                Kind::Launcher(l) => l.bounds(),
                Kind::Lamp(l) => l.bounds(),
                _ => continue,
            };
            if o.status != 1
                || !(o.body.x + b[2] > area[0]
                    && o.body.x + b[0] < area[2]
                    && o.body.y + b[3] > area[1]
                    && o.body.y + b[1] < area[3])
            {
                continue;
            }
            self.element_hit(other, element, map)?;
            // A strike can change what the struck entity's bounds and solid boxes read.
            self.refresh_block_solid(other, map);
        }
        Ok(())
    }
    /// lava_bubble.gd _touch_lamps: every visible bubble counts as burning, the cold form
    /// and frozen ones too: it lights fire lamps and puts out ice lamps it touches.
    pub(crate) fn bubble_touch_lamps(&mut self, index: usize) {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        if e.status != 1 || w.hidden != 0 || w.held != 0 {
            return;
        }
        let b = w.bubble_bounds();
        let area = [
            e.body.x + b[0],
            e.body.y + b[1],
            e.body.x + b[2],
            e.body.y + b[3],
        ];
        for other in 0..self.entities.len() {
            let o = &mut self.entities[other];
            let Kind::Lamp(l) = &mut o.kind else {
                continue;
            };
            let lb = l.bounds();
            if o.status == 1
                && o.body.x + lb[2] > area[0]
                && o.body.x + lb[0] < area[2]
                && o.body.y + lb[3] > area[1]
                && o.body.y + lb[1] < area[3]
            {
                l.touch(true);
            }
        }
    }
}
