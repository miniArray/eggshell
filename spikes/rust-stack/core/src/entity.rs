//! Typed row identity/common fields. The placed prefix and runtime suffix share one table.
use crate::{
    actors::{Actor, ActorKind},
    body::Body,
    items::{Pickup, PickupKind, Star},
    pad::Pad,
    Placement, World, SCALE as S,
};
use std::borrow::Cow;
pub(crate) const TOKEN_BASE: i64 = 1_000_000;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Origin {
    Placed(usize),
    Runtime(i64),
}
impl Origin {
    pub fn placed(self) -> Option<usize> {
        if let Self::Placed(index) = self {
            Some(index)
        } else {
            None
        }
    }
    pub fn index(self) -> i64 {
        self.placed().map(|v| v as i64).unwrap_or(-1)
    }
    pub fn token(self) -> i64 {
        match self {
            Self::Placed(i) => i as i64 + 1,
            Self::Runtime(serial) => TOKEN_BASE + serial,
        }
    }
}
// Actor carries every enemy family's saved fields; rows stay inline in one table so
// stepping walks contiguous memory (boxing would add a pointer chase per enemy).
#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug)]
pub(crate) enum Kind {
    Goal,
    Post(crate::post::Post),
    Checkpoint(crate::checkpoint::Marker),
    Decor,
    Pickup(Pickup),
    Star(Star),
    Bridge,
    Pad(Pad),
    Walker(Actor),
    Egg(crate::egg::Egg),
    Cache(crate::clouds::Cache),
    Redirect(crate::clouds::Redirect),
    Block(crate::blocks::Block),
    Span(crate::spans::Span),
    Hard(crate::blocks::Hard),
    Fall(crate::blocks::Fall),
    Grow(crate::blocks::Grow),
    Gate(crate::gate::Gate),
    Ledge(crate::ledge::Ledge),
    Stem(crate::stem::Stem),
    StarFlower(crate::flower::Flower),
    Switch(crate::switch::Switch),
    Lift(crate::lift::Lift),
    Melon(crate::melon::Melon),
    Seed(crate::melon::Seed),
    /// enemy_overlap.gd: runtime only, never drawn.
    Overlap(crate::roller::Overlap),
    Hound(crate::hound::Hound),
    Launcher(crate::launcher::Launcher),
}
#[derive(Clone, Debug)]
pub(crate) struct Entity {
    pub origin: Origin,
    pub family_index: i64,
    pub body: Body,
    pub facing: i64,
    pub status: i64,
    pub offscreen: i64,
    pub collected: i64,
    pub checkpoint_collected: i64,
    pub spawn_mode: i64,
    pub can_despawn: i64,
    pub can_respawn: i64,
    pub layer: i64,
    pub activation_x: i64,
    pub activation_y: i64,
    pub despawn_radius: i64,
    pub respawn_radius: i64,
    pub kind: Kind,
}
impl Entity {
    pub fn placed(source: usize, p: &Placement, kind: Kind, family_index: i64) -> Self {
        let lifecycle = i64::from(matches!(
            kind,
            Kind::Walker(_)
                | Kind::Star(_)
                | Kind::Egg(_)
                | Kind::Stem(_)
                | Kind::StarFlower(_)
                | Kind::Switch(_)
                | Kind::Lift(_)
                | Kind::Hound(_)
                | Kind::Melon(_)
                | Kind::Launcher(_)
        ));
        // star_flower.gd create: a flower that left the screen never respawns.
        let respawns = lifecycle != 0 && !matches!(kind, Kind::StarFlower(_));
        let layer = if matches!(kind, Kind::Post(_)) {
            9
        } else if matches!(kind, Kind::Walker(_)) {
            8
        } else if matches!(kind, Kind::Decor) {
            // decor.gd prepare: source.layer = layer_for(code).
            p.layer
        } else if matches!(kind, Kind::Redirect(_) | Kind::Gate(_)) {
            // redirect_cloud.gd and one_way_gate.gd create: "layer": 9.
            9
        } else {
            7
        };
        Self {
            origin: Origin::Placed(source),
            family_index,
            body: Body {
                x: p.position.x,
                y: p.position.y,
                ..Body::default()
            },
            // gust_flyer.gd prepare clears the mirror (M only turns it toward the player).
            facing: if p.mirror == 1
                && !matches!(&kind, Kind::Walker(a) if a.kind == ActorKind::Gust)
            {
                1
            } else {
                -1
            },
            status: if lifecycle != 0 { 0 } else { 1 },
            offscreen: 0,
            collected: 0,
            checkpoint_collected: 0,
            spawn_mode: lifecycle,
            // ride_hound.gd create: E1 "1" keeps a runner from despawning.
            can_despawn: if matches!(&kind, Kind::Hound(h) if h.stays) {
                0
            } else {
                lifecycle
            },
            can_respawn: i64::from(respawns),
            layer,
            activation_x: 416 * S,
            activation_y: 224 * S,
            despawn_radius: 832 * S,
            respawn_radius: 624 * S,
            kind,
        }
    }
    pub fn dynamic(serial: i64, kind: Kind, body: Body, facing: i64, layer: i64) -> Self {
        let can_despawn = i64::from(matches!(kind, Kind::Walker(_)));
        Self {
            origin: Origin::Runtime(serial),
            family_index: 0,
            body,
            facing,
            status: 1,
            offscreen: 0,
            collected: 0,
            checkpoint_collected: 0,
            spawn_mode: 0,
            can_despawn,
            can_respawn: 0,
            layer,
            activation_x: 416 * S,
            activation_y: 224 * S,
            despawn_radius: 832 * S,
            respawn_radius: 624 * S,
            kind,
        }
    }
    /// registry.gd is_enemy: actor rows count in the enemy family (index, capture);
    /// gust_flyer.gd (e33) is an actor body outside the family.
    pub fn is_enemy(&self) -> bool {
        matches!(&self.kind, Kind::Walker(a) if a.kind != ActorKind::Gust)
    }
    pub fn source<'a>(&self, world: &'a World) -> Option<&'a Placement> {
        self.origin.placed().map(|i| &world.maps[0].placements[i])
    }
    pub fn code<'a>(&'a self, world: &'a World) -> &'a str {
        if let Some(p) = self.source(world) {
            &p.code
        } else {
            match &self.kind {
                Kind::Walker(a) => match a.kind {
                    ActorKind::Walker => "e1",
                    ActorKind::Flyer => "e2",
                    ActorKind::Flower => "e3",
                    ActorKind::Plant => "e5",
                    ActorKind::Stilt => "e35",
                    ActorKind::Flat => "e4",
                    ActorKind::Shell if a.colour != 0 => "e8",
                    ActorKind::Shell => "e6",
                    ActorKind::Runner => "enemy_runner",
                    ActorKind::Armored => "e11",
                    ActorKind::Spear => "e22",
                    ActorKind::Thief => "e10",
                    ActorKind::Roller => "e28",
                    ActorKind::Shooter => "e31",
                    ActorKind::Pellet => "enemy_pellet",
                    ActorKind::Fish => "e20",
                    ActorKind::LandFish => "e21",
                    ActorKind::Wing => "e30",
                    ActorKind::Shot => "enemy_shot",
                    ActorKind::Sprout => "e12",
                    ActorKind::Hopper => "e40",
                    ActorKind::Juggler => "e42",
                    ActorKind::Bulk => "e17",
                    ActorKind::Gust => "e33",
                    ActorKind::Spore => "e13",
                    ActorKind::Hang => "e14",
                },
                Kind::Pickup(p) => match p.kind {
                    PickupKind::Coin => "o1",
                    PickupKind::RedCoin => "o2",
                    PickupKind::Flower => "o3",
                },
                Kind::Star(_) => "o4",
                Kind::Switch(_) => "o14",
                Kind::Egg(_) => "o7",
                Kind::Seed(_) => "seed_shot",
                Kind::Overlap(_) => "enemy_overlap",
                _ => unreachable!("runtime constructors admit only dynamic types"),
            }
        }
    }
    pub fn id<'a>(&'a self, world: &'a World) -> Cow<'a, str> {
        match self.origin {
            Origin::Placed(i) => Cow::Borrowed(&world.maps[0].placements[i].id),
            Origin::Runtime(serial) => Cow::Owned(format!("+{serial}")),
        }
    }
    pub fn position_at_spawn(&self, world: &World) -> crate::Position {
        if let Some(p) = self.source(world) {
            p.position
        } else if let Kind::Walker(a) = &self.kind {
            crate::Position {
                x: a.spawn_x,
                y: a.spawn_y,
            }
        } else {
            crate::Position {
                x: self.body.x,
                y: self.body.y,
            }
        }
    }
    pub(crate) fn lifecycle(
        &mut self,
        map: &crate::body::Probe,
        centre: crate::Position,
        player: crate::Position,
        impact: i64,
        rng: &mut crate::math::Rng,
    ) -> Result<bool, crate::Error> {
        let awake = self.status == 1;
        let held = match &self.kind {
            Kind::Walker(a) => a.held,
            Kind::Pickup(p) => p.held,
            Kind::Star(p) => p.held,
            Kind::Melon(m) => m.held,
            _ => 0,
        };
        if self.status == 3 || held == 1 || (awake && self.can_despawn == 0) {
            return Ok(awake && self.status == 1);
        }
        let far = (self.body.x - centre.x).abs() > self.despawn_radius
            || (self.body.y - centre.y).abs() > self.despawn_radius;
        let Origin::Placed(index) = self.origin else {
            if awake && self.can_despawn != 0 && far {
                self.status = 3;
            }
            return Ok(awake && self.status == 1);
        };
        let source = &map.placements[index];
        if awake && self.can_despawn != 0 && far {
            self.status = 2;
            self.offscreen = 0;
        }
        if self.status == 2 && self.can_respawn != 0 {
            if (source.position.x - centre.x).abs() > self.activation_x
                || (source.position.y - centre.y).abs() > self.activation_y
            {
                self.offscreen = 1;
            }
            if self.offscreen != 0
                && (source.position.x - centre.x).abs() < self.respawn_radius
                && (source.position.y - centre.y).abs() < self.respawn_radius
            {
                let kind = match &self.kind {
                    Kind::Walker(a) if a.kind == ActorKind::Shell => {
                        Kind::Walker(Actor::shell(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Armored => {
                        Kind::Walker(Actor::armored(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Spear => {
                        Kind::Walker(Actor::spear_guard(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Thief => {
                        Kind::Walker(Actor::thief(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Roller => {
                        Kind::Walker(Actor::roller(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Shooter => {
                        Kind::Walker(Actor::shooter(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Wing => {
                        Kind::Walker(Actor::wing(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Sprout => {
                        Kind::Walker(Actor::sprout(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Hopper => {
                        Kind::Walker(Actor::hopper(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Juggler => {
                        Kind::Walker(Actor::juggler(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Bulk => {
                        Kind::Walker(Actor::bulk(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Gust => {
                        Kind::Walker(Actor::gust(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Spore => {
                        Kind::Walker(Actor::spore(source)?)
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Hang => {
                        Kind::Walker(Actor::hang(source)?)
                    }
                    Kind::Walker(a) => {
                        let mut a =
                            Actor::new(a.kind, source.variant, source.mirror, source.position);
                        if a.kind == ActorKind::Stilt {
                            a.height = crate::stilt::height(source)?;
                        }
                        Kind::Walker(a)
                    }
                    Kind::Star(_) => Kind::Star(Star::default()),
                    Kind::Egg(_) => Kind::Egg(crate::egg::Egg::new(source.variant)),
                    Kind::Hound(_) => {
                        let ordinal = map.placements[..=index]
                            .iter()
                            .filter(|p| p.code == "o16")
                            .count() as i64;
                        Kind::Hound(crate::hound::Hound::new(source, ordinal)?)
                    }
                    Kind::Pickup(p) => {
                        Kind::Pickup(Pickup::new(p.kind, source.variant, source.position.y))
                    }
                    Kind::Pad(_) => Kind::Pad(Pad::default()),
                    Kind::Stem(_) => Kind::Stem(crate::stem::Stem::new(source)?),
                    Kind::StarFlower(_) => Kind::StarFlower(crate::flower::Flower::new(source)?),
                    Kind::Switch(_) => Kind::Switch(crate::switch::Switch::new(source)?),
                    Kind::Lift(_) => Kind::Lift(crate::lift::Lift::new(source)?),
                    Kind::Melon(_) => Kind::Melon(crate::melon::Melon::new(source)?),
                    Kind::Launcher(_) => Kind::Launcher(crate::launcher::Launcher::new(source)?),
                    other => other.clone(),
                };
                let mut fresh = Self::placed(index, source, kind, self.family_index);
                fresh.collected = self.collected;
                fresh.checkpoint_collected = self.checkpoint_collected;
                *self = fresh;
            }
        }
        if self.status == 0 {
            let b = match &self.kind {
                Kind::Hound(p) => p.activation_bounds(self.facing),
                Kind::Walker(a) => a.activation_bounds(self.facing),
                Kind::Star(p) => p.bounds(),
                Kind::Post(p) => p.bounds(),
                Kind::Pickup(p) => p.bounds(),
                Kind::Egg(p) => p.bounds(),
                Kind::Stem(p) => p.bounds(),
                Kind::StarFlower(p) => p.bounds(),
                Kind::Switch(p) => p.bounds(),
                Kind::Lift(p) => p.bounds(),
                Kind::Melon(p) => p.bounds(),
                Kind::Launcher(p) => p.bounds(),
                Kind::Pad(_) => {
                    let crate::PreparedPlacement::Pad { large, .. } = source.prepared else {
                        unreachable!("placed pad")
                    };
                    crate::pad::bounds(large)
                }
                _ => [0; 4],
            };
            if self.body.x + b[2] > centre.x - self.activation_x
                && self.body.x + b[0] < centre.x + self.activation_x
                && self.body.y + b[3] > centre.y - self.activation_y
                && self.body.y + b[1] < centre.y + self.activation_y
            {
                self.status = 1;
                let gust = matches!(&self.kind, Kind::Walker(a) if a.kind == ActorKind::Gust);
                if source.mirror == 2 && !gust {
                    self.facing = if player.x < self.body.x { -1 } else { 1 };
                }
                if let Kind::Walker(a) = &mut self.kind {
                    a.activate(self.facing, rng);
                    if gust {
                        a.gust_activate(self.body, player);
                    }
                }
                if let Kind::Stem(s) = &mut self.kind {
                    s.activate(impact);
                }
            }
        }
        Ok(awake && self.status == 1)
    }
    pub fn common_field(&self, name: &str) -> Option<i64> {
        Some(match name {
            "source_index" => self.origin.index(),
            "token" => self.origin.token(),
            "map_index" => 1,
            "family_index" => self.family_index,
            "x" => self.body.x,
            "y" => self.body.y,
            "vx" => self.body.vx,
            "vy" => self.body.vy,
            "facing" => self.facing,
            "status" => self.status,
            "offscreen" => self.offscreen,
            "collected" => self.collected,
            "checkpoint_collected" => self.checkpoint_collected,
            "spawn_mode" => self.spawn_mode,
            "can_despawn" => self.can_despawn,
            "can_respawn" => self.can_respawn,
            "layer" => self.layer,
            "activation_x" => self.activation_x,
            "activation_y" => self.activation_y,
            "despawn_radius" => self.despawn_radius,
            "respawn_radius" => self.respawn_radius,
            _ => return None,
        })
    }
    pub fn set_common(&mut self, name: &str, value: i64) -> bool {
        let target = match name {
            "x" => &mut self.body.x,
            "y" => &mut self.body.y,
            "vx" => &mut self.body.vx,
            "vy" => &mut self.body.vy,
            "facing" => &mut self.facing,
            "status" => &mut self.status,
            "offscreen" => &mut self.offscreen,
            "collected" => &mut self.collected,
            "checkpoint_collected" => &mut self.checkpoint_collected,
            "spawn_mode" => &mut self.spawn_mode,
            "can_despawn" => &mut self.can_despawn,
            "can_respawn" => &mut self.can_respawn,
            "layer" => &mut self.layer,
            "activation_x" => &mut self.activation_x,
            "activation_y" => &mut self.activation_y,
            "despawn_radius" => &mut self.despawn_radius,
            "respawn_radius" => &mut self.respawn_radius,
            _ => return false,
        };
        *target = value;
        true
    }
}
