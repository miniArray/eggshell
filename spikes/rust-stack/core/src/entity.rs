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
    /// editor_blank.gd ("empty" or ""): no body, no contact, never drawn.
    Blank,
    Post(crate::post::Post),
    Checkpoint(crate::checkpoint::Marker),
    Decor,
    Pickup(Pickup),
    Star(Star),
    Bridge,
    Pad(Pad),
    /// Boxed: an Actor is about 1.4 KB, the other kinds at most 208 bytes.
    Walker(Box<Actor>),
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
    Sack(crate::sack::Sack),
    EggBlock(crate::egg_block::EggBlock),
    Pillar(crate::pillar::Pillar),
    Balloon(crate::balloon::Balloon),
    Dice(crate::dice::Dice),
    SpinSpan(crate::spin::SpinSpan),
    SpinBlock(crate::spin::SpinBlock),
    Platform(crate::platform::Platform),
    Lamp(crate::platform::Lamp),
    /// element_shot.gd fire_shot / ice_shot (runtime only).
    ElementShot(crate::elements::ElementShot),
    /// disc_block.gd e38.
    DiscBlock(crate::disc::DiscBlock),
    /// orbit_disc.gd enemy_disc (runtime only).
    Disc(crate::disc::Disc),
    /// snow_tree.gd d22.
    SnowTree(crate::snow_tree::SnowTree),
}
/// entity_lifecycle.gd BIRTH_PHASES: the native phase that created a row.
/// TICK_BIRTH (1) is only item_stem.gd's, whose payloads have no birth fields.
pub(crate) const INITIAL_BIRTH: i64 = 0;
pub(crate) const EVENTS_BIRTH: i64 = 2;
pub(crate) const TICK2_BIRTH: i64 = 3;
/// The frame and native phase of one creation (entity_lifecycle.gd created).
#[derive(Clone, Copy, Debug)]
pub(crate) struct Birth {
    pub frame: i64,
    pub phase: i64,
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
                | Kind::Sack(_)
                | Kind::Balloon(_)
                | Kind::DiscBlock(_)
        ));
        // star_flower.gd create: a flower that left the screen never respawns.
        let respawns = lifecycle != 0 && !matches!(kind, Kind::StarFlower(_));
        let layer = if matches!(kind, Kind::Post(_)) {
            9
        } else if matches!(kind, Kind::Walker(_)) {
            8
        } else if matches!(kind, Kind::Decor | Kind::Lamp(_) | Kind::Platform(_)) {
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
            body: match &kind {
                // lava_bubble.gd create: it waits at home, 16 px behind its placement.
                Kind::Walker(a) if a.kind == ActorKind::Bubble => Body {
                    x: a.home_x,
                    y: a.home_y,
                    ..Body::default()
                },
                // spike_sack.gd create: it starts at full speed along its heading.
                Kind::Sack(sack) => Body {
                    x: p.position.x,
                    y: p.position.y,
                    vx: sack.velocity().0,
                    vy: sack.velocity().1,
                },
                _ => Body {
                    x: p.position.x,
                    y: p.position.y,
                    ..Body::default()
                },
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
                    ActorKind::PetalStem => "e18",
                    ActorKind::Petal => "enemy_petal",
                    ActorKind::Spitter => "e41",
                    ActorKind::Spike => "enemy_spike",
                    ActorKind::SoftWalker => "e23",
                    ActorKind::SoftGiant => "e24",
                    ActorKind::Helmet => "e29",
                    ActorKind::Bumper => "e19",
                    ActorKind::Mace => "e27",
                    ActorKind::MaceBall => "enemy_mace",
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
                    ActorKind::Spine => "e25",
                    ActorKind::Slime => "e15",
                    ActorKind::Bubble => "e16",
                    ActorKind::Thorn => "e36",
                    ActorKind::Bee => "e43",
                    ActorKind::Shy => "e26",
                    ActorKind::Blind => "e39",
                },
                Kind::ElementShot(s) => s.code(),
                Kind::Disc(_) => "enemy_disc",
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
    /// entity_lifecycle.gd created: rows with birth fields take the next level birth
    /// serial with this frame and phase (INITIAL_BIRTH on the initial map), then the
    /// opt-in birth cull runs around `centre`.
    pub(crate) fn created(&mut self, birth: Birth, serial: &mut i64, centre: crate::Position) {
        self.born(birth, serial);
        // actor.gd created: only the initial map ran the hidden intro ticks before play.
        if let (Kind::Walker(a), Origin::Placed(_)) = (&mut self.kind, self.origin) {
            if a.kind == ActorKind::Flyer && a.ground_form == 0 {
                a.timer = if birth.phase == INITIAL_BIRTH { 150 } else { 0 };
            }
        }
        self.creation_cull(centre);
    }
    /// The birth identity part of entity_lifecycle.gd created.
    pub(crate) fn born(&mut self, birth: Birth, serial: &mut i64) {
        if let Kind::Walker(a) = &mut self.kind {
            if a.has_birth() {
                *serial += 1;
                a.birth_serial = *serial;
                a.birth_frame = birth.frame;
                a.birth_phase = birth.phase;
            }
        }
    }
    /// entity_lifecycle.gd created: only e2, e20, e21 (actor.gd creation_cull), e11 and
    /// e23 (CREATION_CULL) are culled at birth when their origin is outside the despawn
    /// radius of the screen centre. Waiting motion never repeats this check.
    pub(crate) fn creation_cull(&mut self, centre: crate::Position) {
        let opted_in = matches!(
            &self.kind,
            Kind::Walker(a) if matches!(
                a.kind,
                ActorKind::Flyer
                    | ActorKind::Fish
                    | ActorKind::LandFish
                    | ActorKind::Armored
                    | ActorKind::SoftWalker
            )
        );
        if !opted_in || self.can_despawn == 0 {
            return;
        }
        if (self.body.x - centre.x).abs() > self.despawn_radius
            || (self.body.y - centre.y).abs() > self.despawn_radius
        {
            self.status = if self.origin.placed().is_some() { 2 } else { 3 };
            self.offscreen = 0;
        }
    }
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn lifecycle(
        &mut self,
        map: &crate::body::Probe,
        centre: crate::Position,
        player: crate::Position,
        impact: i64,
        rng: &mut crate::math::Rng,
        frame: i64,
        birth_serial: &mut i64,
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
        // actor.gd waiting_step: an inactive airborne flyer keeps bobbing; the birth-only
        // distance cull is not repeated here.
        if self.status == 0 {
            if let Kind::Walker(a) = &mut self.kind {
                if a.kind == ActorKind::Flyer && a.ground_form == 0 {
                    a.flyer_bob(&mut self.body)?;
                }
            }
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
                        Kind::Walker(Box::new(Actor::shell(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Armored => {
                        Kind::Walker(Box::new(Actor::armored(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Spear => {
                        Kind::Walker(Box::new(Actor::spear_guard(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Thief => {
                        Kind::Walker(Box::new(Actor::thief(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Roller => {
                        Kind::Walker(Box::new(Actor::roller(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Shooter => {
                        Kind::Walker(Box::new(Actor::shooter(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::PetalStem => {
                        Kind::Walker(Box::new(Actor::petal_stem(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Spitter => {
                        Kind::Walker(Box::new(Actor::spitter(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::SoftWalker => {
                        Kind::Walker(Box::new(Actor::soft_walker(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::SoftGiant => {
                        Kind::Walker(Box::new(Actor::soft_giant(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Helmet => {
                        Kind::Walker(Box::new(Actor::helmet(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Bumper => {
                        Kind::Walker(Box::new(Actor::bumper(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Mace => {
                        Kind::Walker(Box::new(Actor::mace(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Wing => {
                        Kind::Walker(Box::new(Actor::wing(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Sprout => {
                        Kind::Walker(Box::new(Actor::sprout(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Hopper => {
                        Kind::Walker(Box::new(Actor::hopper(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Juggler => {
                        Kind::Walker(Box::new(Actor::juggler(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Bulk => {
                        Kind::Walker(Box::new(Actor::bulk(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Gust => {
                        Kind::Walker(Box::new(Actor::gust(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Spore => {
                        Kind::Walker(Box::new(Actor::spore(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Slime => {
                        Kind::Walker(Box::new(Actor::slime(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Spine => {
                        Kind::Walker(Box::new(Actor::spine(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Hang => {
                        Kind::Walker(Box::new(Actor::hang(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Bubble => {
                        Kind::Walker(Box::new(Actor::bubble(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Thorn => {
                        Kind::Walker(Box::new(Actor::thorn(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Bee => {
                        Kind::Walker(Box::new(Actor::bee(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Runner => {
                        Kind::Walker(Box::new(Actor::bare_runner(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Shy => {
                        Kind::Walker(Box::new(Actor::shy(source)?))
                    }
                    Kind::Walker(a) if a.kind == ActorKind::Blind => {
                        Kind::Walker(Box::new(Actor::blind(source)?))
                    }
                    Kind::Walker(a) => {
                        let look = a.look;
                        let mut a =
                            Actor::new(a.kind, source.variant, source.mirror, source.position);
                        a.look = look;
                        if a.kind == ActorKind::Stilt {
                            a.height = crate::stilt::height(source)?;
                        }
                        Kind::Walker(Box::new(a))
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
                    Kind::Sack(_) => Kind::Sack(crate::sack::Sack::new(source)?),
                    Kind::Balloon(_) => Kind::Balloon(crate::balloon::Balloon::new(source)?),
                    Kind::DiscBlock(_) => Kind::DiscBlock(crate::disc::DiscBlock::new(source)?),
                    other => other.clone(),
                };
                let mut fresh = Self::placed(index, source, kind, self.family_index);
                fresh.collected = self.collected;
                fresh.checkpoint_collected = self.checkpoint_collected;
                *self = fresh;
                self.created(
                    Birth {
                        frame,
                        phase: EVENTS_BIRTH,
                    },
                    birth_serial,
                    centre,
                );
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
                Kind::DiscBlock(p) => p.bounds(),
                Kind::Melon(p) => p.bounds(),
                Kind::Launcher(p) => p.bounds(),
                Kind::Sack(p) => p.bounds(),
                Kind::Balloon(p) => p.bounds(),
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

#[cfg(test)]
mod creation_cull_tests {
    use crate::{state::Run, Stats, World};

    #[test]
    fn entity_lifecycle_created_culls_only_opted_in_codes_outside_the_despawn_radius() {
        let level = serde_json::json!({
            "version":"s3.8", "name":"creation cull", "desc":"", "author":"test",
            "startpoint":{"map":1, "X":128, "Y":128},
            "maps":{"map1":{"width":8192, "height":2048, "objects":{
                "a":{"A":"e2", "X":4000, "Y":128},
                "b":{"A":"e11", "X":4000, "Y":128},
                "c":{"A":"e23", "X":4000, "Y":128},
                "d":{"A":"e1", "X":4000, "Y":128},
                "e":{"A":"e2", "X":1200, "Y":128}
            }}}
        })
        .to_string();
        let world = World::compile(
            &level,
            include_str!("../../../../data/collision_table.json"),
        )
        .unwrap();
        let run = Run::create(&world, &mut Stats::default()).unwrap();
        let rows: Vec<(&str, i64, i64, i64)> = run
            .entities
            .iter()
            .map(|e| {
                (
                    e.code(&world),
                    e.body.x / crate::SCALE,
                    e.status,
                    e.offscreen,
                )
            })
            .collect();
        // Culled placed rows queue for respawn and are off screen after the two
        // level-start steps; the far e1 and the e2 inside 832 px keep waiting.
        assert!(rows.contains(&("e2", 4000, 2, 1)), "{rows:?}");
        assert!(rows.contains(&("e11", 4000, 2, 1)), "{rows:?}");
        assert!(rows.contains(&("e23", 4000, 2, 1)), "{rows:?}");
        assert!(rows.contains(&("e1", 4000, 0, 0)), "{rows:?}");
        assert!(
            rows.iter()
                .any(|r| r.0 == "e2" && (1100..1300).contains(&r.1) && r.2 != 2),
            "{rows:?}"
        );
    }

    #[test]
    fn actor_flyer_wave_counts_from_creation_while_waiting() {
        let level = serde_json::json!({
            "version":"s3.8", "name":"flyer", "desc":"", "author":"test",
            "startpoint":{"map":1, "X":128, "Y":128},
            "maps":{"map1":{"width":8192, "height":2048, "objects":{
                "f":{"A":"e2", "X":1000, "Y":128}
            }}}
        })
        .to_string();
        let world = World::compile(
            &level,
            include_str!("../../../../data/collision_table.json"),
        )
        .unwrap();
        let run = Run::create(&world, &mut Stats::default()).unwrap();
        let flyer = &run.entities[0];
        let super::Kind::Walker(a) = &flyer.kind else {
            unreachable!()
        };
        // Created at 150 on the initial map, then two waiting bobs in the level-start steps.
        assert_eq!((flyer.status, a.timer), (0, 152));
        assert_eq!(
            flyer.body.y,
            128 * crate::SCALE + crate::math::sine(152, 180, 12 * crate::SCALE).unwrap()
        );
        assert_eq!(a.body_bounds(-1)[2], 8 * crate::SCALE);
        let mut later = a.clone();
        later.timer = 153;
        assert_eq!(later.body_bounds(-1)[2], 10 * crate::SCALE);
        assert_eq!(later.body_bounds(1)[0], -10 * crate::SCALE);
    }

    #[test]
    fn entity_lifecycle_created_numbers_initial_births_in_native_key_order() {
        let level = serde_json::json!({
            "version":"s3.8", "name":"births", "desc":"", "author":"test",
            "startpoint":{"map":1, "X":128, "Y":128},
            "maps":{"map1":{"width":8192, "height":2048, "objects":{
                "w":{"A":"e1", "X":600, "Y":128},
                "5":{"A":"o1", "X":700, "Y":128},
                "2":{"A":"e11", "X":800, "Y":128}
            }}}
        })
        .to_string();
        let world = World::compile(
            &level,
            include_str!("../../../../data/collision_table.json"),
        )
        .unwrap();
        let ids: Vec<&str> = world.maps[0]
            .placements
            .iter()
            .map(|p| p.id.as_str())
            .collect();
        assert_eq!(ids, ["2", "5", "w"]);
        let run = Run::create(&world, &mut Stats::default()).unwrap();
        let births: Vec<(i64, i64, i64)> = run
            .entities
            .iter()
            .filter_map(|e| match &e.kind {
                super::Kind::Walker(a) => Some((a.birth_serial, a.birth_frame, a.birth_phase)),
                _ => None,
            })
            .collect();
        assert_eq!(
            births,
            [(1, 0, super::INITIAL_BIRTH), (2, 0, super::INITIAL_BIRTH)]
        );
        assert_eq!(run.birth_serial, 2);
    }
}
