//! Eating: the tongue's catch, held bodies, spat and rolling enemies, and the item
//! request consumers (registry.gd tongue_contact, enemy_body.gd, actor.gd roll,
//! pickup.gd and item_star.gd consume_requests).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    entity::{Entity, Kind},
    food::{Since, CONSUME, SPIT},
    items::PickupKind,
    state::Run,
    Error, Position, SCALE as S,
};

impl Run {
    /// stilt_walker.gd unseat: the rider becomes a dynamic e1 and the stilt is removed.
    pub(crate) fn unseat_stilt(&mut self, index: usize) -> Result<(), Error> {
        let e = &mut self.entities[index];
        if e.status != 1 {
            return Ok(());
        }
        let Kind::Walker(w) = &mut e.kind else {
            return Ok(());
        };
        let position = Position {
            x: e.body.x,
            y: e.body.y - w.height + 34 * S,
        };
        let (variant, facing, layer) = (w.variant, e.facing, e.layer);
        w.remove(&mut e.status, &mut e.can_respawn);
        self.spawn_walker(position, variant, facing, layer)
    }
}

/// hits.gd kinds that reach enemy hit rules here.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum HitKind {
    Egg,
    /// A spinning shell (shell_walker.gd HIT_KIND).
    Shell,
    /// A spat or rolling body.
    Spit,
}

/// Body.process outcome (enemy_body.gd FREE/HELD/RELEASED/GONE).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Hold {
    Free,
    Held,
    Released,
    Gone,
}

/// What an actor step asks the run to do with other entities afterwards.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum After {
    Nothing,
    /// enemy_body.gd hit_others with Hits.SPIT and self_breaks, from this box offset.
    HitOthers([i64; 4]),
    /// A held pickup or star: run its consume_requests now.
    ConsumeItem,
    /// item_egg.gd step, which reaches other entities.
    EggStep,
    /// release_cloud.gd step, which can release items.
    CacheStep,
    /// item_block.gd step, which moves the block and can spawn eggs.
    BlockStep,
    /// falling_span.gd step, which drops the span.
    FallStep,
    /// A solid that changed shape in its step (grow_block.gd): collision.gd refresh.
    RefreshSolid,
    /// one_way_gate.gd step, which reads other bodies.
    GateStep,
    /// item_stem.gd step, which can release items.
    StemStep,
    /// star_flower.gd step, which swallows spat bodies and releases items.
    FlowerStep,
    /// shell_walker.gd step, which reads and spawns other bodies.
    ShellStep,
    /// armored_walker.gd step, which hits other bodies while rolling.
    ArmoredStep,
    /// spear_guard.gd step, which hits other bodies while spat.
    SpearStep,
    /// sneak_thief.gd step, which reads the companion and other thieves.
    ThiefStep,
    /// hanging_roller.gd step, which strikes other bodies while rolling.
    RollerStep,
    /// enemy_overlap.gd step, which reads the paired bodies.
    OverlapStep,
    /// masked_shooter.gd step, which spawns its shot.
    ShooterStep,
    /// enemy_pellet.gd step.
    PelletStep,
    /// wing_drifter.gd step, which hits other bodies while spat.
    WingStep,
    /// launcher_shot.gd step.
    ShotStep,
    /// hop_sprout.gd step, which hits other bodies while spat.
    SproutStep,
    /// spike_hopper.gd step, which hits other bodies once thrown.
    HopperStep,
    /// needle_juggler.gd step, which spawns and moves its hopper.
    JugglerStep,
    /// leap_bulk.gd step, which moves a top-only deck.
    BulkStep,
    /// gust_flyer.gd step.
    GustStep,
    /// drift_spore.gd step, which grows a sprout into the table.
    SporeStep,
    /// hang_flyer.gd step.
    HangStep,
    /// shot_launcher.gd step, which fires shots into the table.
    LauncherStep,
    /// timed_switch.gd step, which runs the shared interval.
    SwitchStep,
    /// arrow_lift.gd step, which moves a top-only deck.
    LiftStep,
    /// seed_melon.gd step, which falls with the solids.
    MelonStep,
    /// seed_shot.gd step, which strikes other bodies.
    SeedStep,
    /// ride_hound.gd step, which carries riders, destroys enemies and kicks eggs.
    HoundStep,
    /// egg_block.gd step, which moves the block and can spawn an egg.
    EggBlockStep,
    /// rise_balloon.gd step, which moves a top-only deck.
    BalloonStep,
}

/// A body that strikes others: its position, contact box offset and what it is.
pub(crate) struct Projectile {
    pub body: Body,
    pub bounds: [i64; 4],
    /// An e11 (armored_walker.gd: a spit from another e11 removes it).
    pub armored: bool,
    /// A spinning e6/e8 shell.
    pub spins: bool,
    /// A rolling e1/e2.
    pub rolls: bool,
    /// A spat or rolling body (actor.gd e5 head: consumed).
    pub breaks: bool,
    /// The projectile's token (enemy_overlap.gd pairs).
    pub token: i64,
    /// An e6/e8, e11 or e28 weapon that is not spat (hanging_roller.gd: one strike per
    /// entry).
    pub weapon: bool,
    /// Spat, or an actor.gd roll (hanging_roller.gd projectile_contact: consumed).
    pub spat_or_roll: bool,
}
impl Projectile {
    fn box_(&self) -> [i64; 4] {
        world_box(self.body, self.bounds)
    }
}

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Actor {
    /// enemy_body.gd remove (no actor in the admitted set has on_remove side effects
    /// that can run here: a plant can never be held, spat or rolled), with
    /// sneak_thief.gd on_remove: a removed thief drops the bubble.
    pub(crate) fn remove(&mut self, status: &mut i64, can_respawn: &mut i64) {
        if self.kind == ActorKind::Thief && *status != 3 {
            self.carrying = 0;
        }
        *status = 3;
        self.held = 0;
        self.spat = 0;
        *can_respawn = 0;
    }
    /// enemy_body.gd process, after the `started` initialisation the caller already ran.
    pub(crate) fn process(
        &mut self,
        token: i64,
        body: &mut Body,
        facing: &mut i64,
        status: &mut i64,
        can_respawn: &mut i64,
        step: &ActorStep,
    ) -> Hold {
        let mut released = false;
        let requests = &step.player.food.requests;
        if let Since::Requests(list) = requests.since(self.request_cursor) {
            for r in list {
                if r.item != token {
                    continue;
                }
                if r.kind == CONSUME {
                    self.remove(status, can_respawn);
                } else if r.kind == SPIT && self.held != 0 {
                    self.held = 0;
                    self.spat = 1;
                    self.spit_age = 0;
                    self.spit_wall = 0;
                    body.x = r.x;
                    body.y = r.y;
                    body.vx = r.vx;
                    body.vy = r.vy;
                    self.spit_speed = r.vx.abs();
                    if r.vx != 0 {
                        *facing = r.vx.signum();
                    }
                    released = true;
                }
            }
        }
        self.request_cursor = requests.serial();
        if *status == 3 {
            return Hold::Gone;
        }
        if self.held != 0 {
            let p = &step.player;
            body.x = p.body.x + p.facing * 24 * S;
            body.y = p.body.y - 24 * S;
            body.vx = 0;
            body.vy = 0;
            return Hold::Held;
        }
        if released {
            Hold::Released
        } else {
            Hold::Free
        }
    }
    /// actor.gd start_roll
    pub(crate) fn start_roll(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        direction: i64,
        vy: i64,
        upward: bool,
    ) {
        self.roll = 1;
        self.ground_form = 1;
        self.roll_up = i64::from(upward);
        self.roll_ticks = if upward { 90 } else { 0 };
        self.roll_grace = if upward { 0 } else { 15 };
        self.roll_bounce = if upward { 0 } else { 1 };
        *facing = direction;
        body.vx = if upward { 0 } else { direction * 432 * 60 };
        body.vy = vy;
    }
    /// actor.gd on_spit_release: e1/e2 roll off; others keep flying as spat food.
    pub(crate) fn on_spit_release(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        player_facing: i64,
    ) {
        if ![ActorKind::Walker, ActorKind::Flyer].contains(&self.kind) {
            return;
        }
        let (vy, upward) = (body.vy, body.vx == 0);
        self.start_roll(body, facing, player_facing, vy, upward);
        self.spat = 0;
    }
    fn hazards(
        &mut self,
        body: Body,
        b: [i64; 4],
        status: &mut i64,
        can_respawn: &mut i64,
        map: &Probe,
    ) -> bool {
        if map.lava_overlaps(world_box(body, b)) {
            self.remove(status, can_respawn);
            return true;
        }
        false
    }
    /// actor.gd roll_step; `None` when it ended or removed the body.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn roll_step(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        status: &mut i64,
        can_respawn: &mut i64,
        step: &mut ActorStep,
    ) -> After {
        self.roll_grace = (self.roll_grace - 1).max(0);
        if self.roll_up != 0 {
            self.roll_ticks = (self.roll_ticks - 1).max(0);
            body.vx = 0;
            if self.roll_ticks == 0 {
                self.roll = 0;
                self.mode = 0;
                self.timer = step.rng.ticks(60, 150);
                return After::Nothing;
            }
        } else {
            body.vx = *facing * 432 * 60;
        }
        let distance = body.vx;
        let (actual, grounded) = self.movement(body, *facing, step.map, distance);
        if actual != distance && self.roll_up == 0 {
            self.remove(status, can_respawn);
            return After::Nothing;
        }
        let b = self.body_bounds(*facing);
        if body.gravity(step.map, b, grounded) && self.roll_up != 0 {
            body.vy = if self.roll_bounce == 0 { -384 } else { -256 } * 60;
            self.roll_bounce = 1;
        }
        if self.hazards(*body, b, status, can_respawn, step.map) {
            return After::Nothing;
        }
        After::HitOthers(b)
    }
    /// enemy_body.gd spit_step; `None` when the body is not spat.
    pub(crate) fn spit_step(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        status: &mut i64,
        can_respawn: &mut i64,
        step: &mut ActorStep,
    ) -> Option<After> {
        if self.spat == 0 {
            return None;
        }
        // The caller passes bounds(entity) once, before the step can turn the body.
        let b = self.bounds(*body, *facing);
        self.spit_age += 1;
        body.vx = *facing * self.spit_speed;
        let distance = body.vx;
        let (actual, grounded) = self.movement_box(body, b, step.map, distance);
        if actual != distance {
            *facing = -*facing;
            self.spit_speed = 48 * 60;
            self.spit_wall = 1;
            self.spit_age = 0;
        }
        // enemy_motion.gd gravity_box: e20/e21 skip the water quartering.
        let landed = if [ActorKind::Fish, ActorKind::LandFish].contains(&self.kind) {
            body.gravity_box_dry(step.map, b, grounded)
        } else {
            body.gravity(step.map, b, grounded)
        };
        let duration = if self.spit_wall != 0 { 42 } else { 60 };
        if landed {
            if self.spit_age < duration {
                let remaining = duration - self.spit_age;
                let high = if self.spit_wall != 0 { 256 } else { 512 };
                let low = if self.spit_wall != 0 { 96 } else { 128 };
                let bounce =
                    low * 60 + (high - low) * 60 * remaining * remaining / (duration * duration);
                body.vy = -bounce / 2 - 128 * 60;
            } else {
                self.spat = 0;
                body.vx = 0;
                *facing = if body.x < step.player.body.x { 1 } else { -1 };
            }
        }
        if self.hazards(*body, b, status, can_respawn, step.map) {
            return Some(After::Nothing);
        }
        Some(After::HitOthers(b))
    }
}

impl Run {
    /// registry.gd tongue_contact over the whole table, in table order. The first entity
    /// whose tongue rule returns 1 (caught) or 2 (blocks) ends the search.
    pub(crate) fn tongue_contact(&mut self, sensor: [i64; 4]) {
        if self.player.food.held_id != 0 {
            return;
        }
        for index in 0..self.entities.len() {
            let e = &self.entities[index];
            if e.status != 1 || held(e) || hidden(e) {
                continue;
            }
            let b = crate::egg::entity_bounds(e);
            let reach = e.body.x + b[2] > sensor[0]
                && e.body.x + b[0] < sensor[2]
                && e.body.y + b[3] > sensor[1]
                && e.body.y + b[1] < sensor[3];
            if !reach {
                continue;
            }
            let token = e.origin.token();
            let blocks_step = self.player.blocks_step();
            if matches!(e.kind, Kind::Melon(_)) {
                if self.melon_tongue(index) == 1 {
                    return;
                }
                continue;
            }
            if matches!(e.kind, Kind::Egg(_)) {
                if self.egg_tongue(index) == 2 {
                    self.player.block_tongue();
                    return;
                }
                continue;
            }
            // registry.gd tongue_contact: a SOLID 1 type with no tongue rule (item, colour,
            // thorn and grow blocks) stops the tongue where the sensor overlaps its solid.
            let plain_solid = match &e.kind {
                Kind::Block(bl) => Some(bl.solid(e)),
                Kind::Hard(h) if h.kind != crate::blocks::HardKind::Rock => Some(h.solid(e)),
                Kind::Grow(g) => Some(g.solid(e)),
                Kind::Launcher(l) => Some(l.solid(e)),
                Kind::EggBlock(b) => Some(b.solid(e.status, e.body)),
                Kind::Pillar(p) => Some(p.solid(e.status, e.body)),
                _ => None,
            };
            if let Some(solid) = plain_solid {
                if solid.is_some_and(|s| strict(sensor, s)) {
                    self.player.block_tongue();
                    return;
                }
                continue;
            }
            let e = &mut self.entities[index];
            let result = match &mut e.kind {
                Kind::Post(p) => {
                    if p.solid(e.body, e.status).is_some() {
                        2
                    } else {
                        0
                    }
                }
                // hard_block.gd tongue: a standing block stops the tongue.
                Kind::Hard(h) if h.kind == crate::blocks::HardKind::Rock => 2,
                // one_way_gate.gd tongue: the closed barrier (sensor = tongue_box here).
                Kind::Gate(g) => g.tongue(e.status, e.body, sensor),
                Kind::Walker(w) if w.kind == ActorKind::Stilt => {
                    w.stilt_knock(&mut e.body, &mut e.facing, self.player.body.x);
                    2
                }
                Kind::Walker(w) if w.kind == ActorKind::Plant => {
                    if strict(sensor, w.head_box(e.body, e.facing)) && w.mode != 0 {
                        2
                    } else {
                        0
                    }
                }
                // spear_guard.gd tongue: the spear side knocks it back and blocks the
                // tongue; otherwise the spear drops and it is caught as food.
                Kind::Walker(w)
                    if w.kind == ActorKind::Spear
                        && w.held == 0
                        && e.status == 1
                        && w.has_spear != 0
                        && self.player.facing == -e.facing =>
                {
                    w.spear_knock(self.player.facing);
                    2
                }
                Kind::Walker(w) if w.kind == ActorKind::Spear && (w.held != 0 || e.status != 1) => {
                    0
                }
                Kind::Walker(w) if w.kind == ActorKind::Spear => {
                    w.has_spear = 0;
                    if w.hidden != 0 {
                        0
                    } else if self.player.catch_item(token, 1, 0, 0, 0, 256 * 60) {
                        w.held = 1;
                        w.spat = 0;
                        e.body.vx = 0;
                        e.body.vy = 0;
                        w.request_cursor = self.player.food.requests.serial();
                        1
                    } else {
                        0
                    }
                }
                // hanging_roller.gd has no tongue rule and is not solid.
                Kind::Walker(w) if w.kind == ActorKind::Roller => 0,
                // enemy_pellet.gd has no tongue rule and is not solid.
                Kind::Walker(w) if w.kind == ActorKind::Pellet => 0,
                // sneak_thief.gd tongue: the tongue bounces off and shoves the thief away.
                Kind::Walker(w) if w.kind == ActorKind::Thief => {
                    if w.held != 0 || e.status != 1 {
                        0
                    } else {
                        e.body.vx = if e.body.x > self.player.body.x {
                            128
                        } else {
                            -128
                        } * 60;
                        w.thief_pose(crate::thief::SIT);
                        2
                    }
                }
                // needle_juggler.gd tongue and an intangible spike_hopper.gd: nothing.
                Kind::Walker(w)
                    if w.kind == ActorKind::Juggler
                        || (w.kind == ActorKind::Hopper && w.intangible != 0) =>
                {
                    0
                }
                // leap_bulk.gd has no tongue rule and is not SOLID 1.
                Kind::Walker(w) if w.kind == ActorKind::Bulk => 0,
                // armored_walker.gd tongue: pushed back; the tongue is blocked.
                Kind::Walker(w) if w.kind == ActorKind::Armored => {
                    w.armored_tongue(&mut e.body, &mut e.facing, self.player.facing);
                    2
                }
                // shell_walker.gd tongue: a shell stops and is caught whole (not
                // digestible); a bare runner is food.
                Kind::Walker(w) if [ActorKind::Shell, ActorKind::Runner].contains(&w.kind) => {
                    let bare = crate::shell::bare(w.mode);
                    if !bare {
                        w.mode = crate::shell::IDLE;
                        e.body.vx = 0;
                    }
                    if w.hidden != 0 || w.held != 0 || e.status != 1 {
                        0
                    } else if self
                        .player
                        .catch_item(token, i64::from(bare), 0, 0, 0, 256 * 60)
                    {
                        w.held = 1;
                        w.spat = 0;
                        e.body.vx = 0;
                        e.body.vy = 0;
                        w.request_cursor = self.player.food.requests.serial();
                        1
                    } else {
                        0
                    }
                }
                Kind::Walker(w) => {
                    // enemy_body.gd tongue (digestible, not instant for this family).
                    if w.hidden != 0 || w.held != 0 || e.status != 1 {
                        0
                    } else if self.player.catch_item(
                        token,
                        1,
                        0,
                        0,
                        // actor.gd tongue: fish are swallowed at once; so are
                        // drift_spore.gd spores.
                        i64::from(
                            [ActorKind::Fish, ActorKind::LandFish, ActorKind::Spore]
                                .contains(&w.kind),
                        ),
                        256 * 60,
                    ) {
                        w.held = 1;
                        w.spat = 0;
                        e.body.vx = 0;
                        e.body.vy = 0;
                        w.request_cursor = self.player.food.requests.serial();
                        if w.kind == ActorKind::Flyer {
                            w.ground_form = 1;
                            w.mode = 0;
                            w.timer = 0;
                        }
                        // masked_shooter.gd tongue: a caught shooter restarts its cycle.
                        if w.kind == ActorKind::Shooter {
                            w.shooter_caught();
                        }
                        1
                    } else {
                        0
                    }
                }
                Kind::Pickup(p) => {
                    if p.moving == 0 || e.collected != 0 || p.pickup_delay != 0 || blocks_step {
                        0
                    } else if self.player.catch_item(token, 0, 0, 0, 1, 256 * 60) {
                        p.held = 1;
                        p.request_cursor = self.player.food.requests.serial();
                        1
                    } else {
                        0
                    }
                }
                Kind::Star(p) => {
                    if e.collected != 0 || p.pickup_delay != 0 || blocks_step {
                        0
                    } else if self.player.catch_item(token, 0, 0, 0, 1, 256 * 60) {
                        p.held = 1;
                        p.request_cursor = self.player.food.requests.serial();
                        1
                    } else {
                        0
                    }
                }
                _ => 0,
            };
            if result == 1 {
                return;
            }
            if result == 2 {
                self.player.block_tongue();
                return;
            }
        }
    }
    /// pickup.gd and item_star.gd consume_requests, in table order (registry.gd
    /// consume_requests runs the entity consumers after the level-wide ones).
    pub(crate) fn consume_item_requests(&mut self) {
        for index in 0..self.entities.len() {
            self.consume_item(index);
        }
    }
    /// One held pickup or star: its consume_requests (also run by its own step).
    pub(crate) fn consume_item(&mut self, index: usize) {
        // item_stem.gd consume_requests runs for every producer, whatever its status.
        if matches!(self.entities[index].kind, Kind::Stem(_)) {
            self.stem_consume(index);
            return;
        }
        if matches!(self.entities[index].kind, Kind::Melon(_)) {
            self.melon_consume(index);
            return;
        }
        let serial = self.player.food.requests.serial();
        let token = self.entities[index].origin.token();
        let list = match &self.entities[index].kind {
            Kind::Pickup(p) if p.held != 0 => self.player.food.requests.since(p.request_cursor),
            Kind::Star(p) if p.held != 0 => self.player.food.requests.since(p.request_cursor),
            _ => return,
        };
        {
            let Since::Requests(list) = list else {
                match &mut self.entities[index].kind {
                    Kind::Pickup(p) => p.request_cursor = serial,
                    Kind::Star(p) => p.request_cursor = serial,
                    _ => {}
                }
                return;
            };
            for r in list {
                if r.item != token {
                    continue;
                }
                if r.kind == CONSUME {
                    self.collect_item(index);
                } else if r.kind == SPIT {
                    let e = &mut self.entities[index];
                    e.body.x = r.x;
                    e.body.y = r.y;
                    e.body.vx = r.vx;
                    e.body.vy = r.vy;
                    match &mut e.kind {
                        Kind::Pickup(p) => p.held = 0,
                        Kind::Star(p) => {
                            p.held = 0;
                            p.pickup_delay = 6;
                        }
                        _ => {}
                    }
                }
            }
            match &mut self.entities[index].kind {
                Kind::Pickup(p) => p.request_cursor = serial,
                Kind::Star(p) => p.request_cursor = serial,
                _ => {}
            }
        }
    }
    /// pickup.gd / item_star.gd collect (Life.collect with the entity's own flag).
    pub(crate) fn collect_item(&mut self, index: usize) {
        if self.player.life_phase != 0 {
            return;
        }
        let mut origin = 0;
        let e = &mut self.entities[index];
        match &mut e.kind {
            Kind::Pickup(p) => {
                if e.collected != 0 || p.enabled == 0 || p.pickup_delay != 0 {
                    return;
                }
                e.collected = 1;
                origin = p.origin_token;
                match p.kind {
                    PickupKind::Coin => self.coins = self.coins.saturating_add(1),
                    PickupKind::RedCoin => self.redcoins = self.redcoins.saturating_add(1),
                    PickupKind::Flower => self.flowers = self.flowers.saturating_add(1),
                }
                self.sound.emit(2, e.body.x, e.body.y);
                p.held = 0;
                if p.kind == PickupKind::RedCoin {
                    p.phase = 0;
                    p.collect_y = e.body.y;
                    p.collect_ticks = 60;
                } else {
                    e.status = 3;
                }
            }
            Kind::Star(p) => {
                if e.collected != 0 {
                    return;
                }
                e.collected = 1;
                self.player.life.health = (self.player.life.health + 1).min(30);
                self.sound.emit(2, e.body.x, e.body.y);
                p.held = 0;
                e.status = 3;
            }
            _ => {}
        }
        // pickup.gd collect: the cache that released this flower is spent.
        if let Some(i) = self.find_token(origin) {
            self.entities[i].collected = 1;
        }
    }
    /// enemy_body.gd hit_others for the body at `index` with contact box offset `b`:
    /// Hits.SPIT with self_breaks (spat and rolling bodies), or Hits.SHELL without it
    /// (a spinning shell).
    pub(crate) fn hit_others(
        &mut self,
        index: usize,
        b: [i64; 4],
        kind: HitKind,
        self_breaks: bool,
    ) -> Result<(), Error> {
        let projectile = Projectile {
            body: self.entities[index].body,
            bounds: b,
            armored: matches!(
                &self.entities[index].kind,
                Kind::Walker(w) if w.kind == ActorKind::Armored
            ),
            spins: matches!(
                &self.entities[index].kind,
                Kind::Walker(w) if w.kind == ActorKind::Shell && w.mode == crate::shell::SPIN
            ),
            rolls: matches!(
                &self.entities[index].kind,
                Kind::Walker(w) if w.roll != 0 && [ActorKind::Walker, ActorKind::Flyer].contains(&w.kind)
            ),
            breaks: matches!(
                &self.entities[index].kind,
                Kind::Walker(w) if w.spat != 0 || w.roll != 0
            ),
            token: self.entities[index].origin.token(),
            weapon: matches!(
                &self.entities[index].kind,
                Kind::Walker(w) if w.spat == 0
                    && [ActorKind::Shell, ActorKind::Armored, ActorKind::Roller].contains(&w.kind)
            ),
            spat_or_roll: matches!(
                &self.entities[index].kind,
                Kind::Walker(w) if w.spat != 0 || w.roll != 0
            ),
        };
        let mut other = 0;
        while other < self.entities.len() {
            let current = other;
            other += 1;
            if current == index || !self.spit_candidate(current, &projectile) {
                continue;
            }
            let reaction = self.spit_contact(current, &projectile, kind)?;
            if self.entities[index].status != 1 {
                return Ok(());
            }
            if reaction == 1 || (self_breaks && reaction == 3) {
                self.shell_remove(index);
                return Ok(());
            }
        }
        Ok(())
    }
    /// Whether another entity takes part in a spit or shell strike: active, not held or
    /// hidden, a kind with a hit or projectile rule, and strictly overlapping the box.
    pub(crate) fn spit_candidate(&self, other: usize, projectile: &Projectile) -> bool {
        let o = &self.entities[other];
        if o.status != 1 || held(o) || hidden(o) {
            return false;
        }
        let ob = match &o.kind {
            Kind::Walker(_)
            | Kind::Pickup(_)
            | Kind::Star(_)
            | Kind::Egg(_)
            | Kind::Cache(_)
            | Kind::Redirect(_)
            | Kind::Hard(_)
            | Kind::Block(_)
            | Kind::Stem(_) => crate::egg::entity_bounds(o),
            // Posts, pads, bridges, goals, checkpoints, spans, gates and melons have no hit
            // rule (one_way_gate.gd projectile_contact runs for ENEMY types only).
            _ => return false,
        };
        strict(projectile.box_(), world_box(o.body, ob))
    }
    /// The struck entity's reaction to a spit or a spinning shell (enemy_body.gd
    /// hit_others, seed_shot.gd strike): ENEMY types run projectile_contact, other types
    /// with a hit rule take the hit (3). 0 passes, 1 consumes, 3 is solid.
    pub(crate) fn spit_contact(
        &mut self,
        current: usize,
        projectile: &Projectile,
        kind: HitKind,
    ) -> Result<i64, Error> {
        let projectile_box = projectile.box_();
        let projectile_armored = projectile.armored;
        let projectile_spins = projectile.spins;
        let projectile_rolls = projectile.rolls;
        let projectile_breaks = projectile.breaks;
        let (projectile_token, projectile_weapon, projectile_consumed) =
            (projectile.token, projectile.weapon, projectile.spat_or_roll);
        let projectile = projectile.body;
        enum Target {
            StiltRider,
            StiltBody,
            PlantHead,
            PlantMiss,
            Actor,
            RollingPair,
            Shell,
            Armored,
            Spear,
            Thief,
            Roller,
            Wing,
            Hopper,
            Bulk,
            Pickup,
            Inert,
            Egg,
            Cache,
            Nothing,
        }
        let target = {
            let o = &self.entities[current];
            match &o.kind {
                // stilt_walker.gd projectile_contact: the rider is struck near the top.
                Kind::Walker(w) if w.kind == ActorKind::Stilt => {
                    if projectile.y < o.body.y - w.height + 50 * S {
                        Target::StiltRider
                    } else {
                        Target::StiltBody
                    }
                }
                // actor.gd projectile_contact for e5: a spit hits only the head; a
                // shell hits it anywhere.
                Kind::Walker(w) if w.kind == ActorKind::Plant => {
                    if w.head_size != 0 && strict(w.head_box(o.body, o.facing), projectile_box) {
                        Target::PlantHead
                    } else if kind == HitKind::Shell {
                        Target::Actor
                    } else {
                        Target::PlantMiss
                    }
                }
                Kind::Walker(w) if kind == HitKind::Spit && w.roll != 0 && projectile_rolls => {
                    Target::RollingPair
                }
                // shell_walker.gd projectile_contact.
                Kind::Walker(w) if [ActorKind::Shell, ActorKind::Runner].contains(&w.kind) => {
                    Target::Shell
                }
                // armored_walker.gd projectile_contact.
                Kind::Walker(w) if w.kind == ActorKind::Armored => Target::Armored,
                // spear_guard.gd projectile_contact: any non-egg hit drops the spear
                // and defeats it.
                Kind::Walker(w) if w.kind == ActorKind::Spear => Target::Spear,
                // wing_drifter.gd projectile_contact.
                Kind::Walker(w) if w.kind == ActorKind::Wing => Target::Wing,
                // needle_juggler.gd and an intangible spike_hopper.gd absorb nothing (0).
                Kind::Walker(w)
                    if w.kind == ActorKind::Juggler
                        || (w.kind == ActorKind::Hopper && w.intangible != 0) =>
                {
                    Target::Nothing
                }
                Kind::Walker(w) if w.kind == ActorKind::Hopper => Target::Hopper,
                // leap_bulk.gd projectile_contact: defeat; a non-egg strike counts (3).
                Kind::Walker(w) if w.kind == ActorKind::Bulk => Target::Bulk,
                // sneak_thief.gd projectile_contact: struck; the projectile is used up.
                Kind::Walker(w) if w.kind == ActorKind::Thief => Target::Thief,
                // hanging_roller.gd projectile_contact.
                Kind::Walker(w) if w.kind == ActorKind::Roller => Target::Roller,
                // enemy_pellet.gd projectile_contact returns 0.
                Kind::Walker(w) if w.kind == ActorKind::Pellet => Target::Nothing,
                // masked_shooter.gd projectile_contact: removed (hit), reaction 3.
                Kind::Walker(_) => Target::Actor,
                // pickup.gd is not an ENEMY: its `hit` collects (SPIT is a collecting hit).
                Kind::Pickup(_) => Target::Pickup,
                // item_egg.gd is not an ENEMY: its `hit` reacts to BUMP only, but counts.
                Kind::Egg(_) => Target::Egg,
                // release_cloud.gd hit (SPIT reveals or opens); redirect_cloud.gd has no hit.
                Kind::Cache(_) => Target::Cache,
                // hard/colour/thorn/item blocks are not ENEMY: their `hit` ignores
                // SPIT but still counts as reaction 3, which breaks the projectile.
                // item_stem.gd hit reacts to BUMP only.
                Kind::Hard(_) | Kind::Block(_) | Kind::Stem(_) => Target::Inert,
                // item_star.gd has projectile_contact only and is not an ENEMY.
                _ => Target::Nothing,
            }
        };
        Ok(match target {
            Target::StiltRider => {
                self.unseat_stilt(current)?;
                3
            }
            Target::StiltBody => {
                let o = &mut self.entities[current];
                if let Kind::Walker(w) = &mut o.kind {
                    w.stilt_knock(&mut o.body, &mut o.facing, projectile.x);
                }
                3
            }
            Target::PlantHead => {
                self.hit_actor(current)?;
                if projectile_breaks || kind == HitKind::Shell {
                    1
                } else {
                    3
                }
            }
            Target::Spear => {
                let o = &mut self.entities[current];
                if let Kind::Walker(w) = &mut o.kind {
                    w.has_spear = 0;
                    w.remove(&mut o.status, &mut o.can_respawn);
                }
                3
            }
            Target::Thief => {
                self.thief_struck(current, projectile.x)?;
                1
            }
            Target::Roller => self.roller_projectile(
                current,
                projectile_token,
                projectile_weapon,
                projectile_consumed,
            )?,
            Target::Bulk => {
                self.bulk_defeat(current)?;
                3
            }
            // spike_hopper.gd hit: removed; the strike counts (3).
            Target::Hopper => {
                let o = &mut self.entities[current];
                if let Kind::Walker(w) = &mut o.kind {
                    w.remove(&mut o.status, &mut o.can_respawn);
                }
                3
            }
            Target::Wing => {
                let o = &mut self.entities[current];
                let Kind::Walker(w) = &mut o.kind else {
                    unreachable!()
                };
                w.wing_struck(o.body, projectile)
            }
            Target::Armored => {
                // A spit from another e11 removes it; a shell removes it; any other
                // spit rolls it away from the projectile.
                if kind == HitKind::Shell || projectile_armored {
                    self.shell_remove(current);
                } else {
                    let o = &mut self.entities[current];
                    if let Kind::Walker(w) = &mut o.kind {
                        w.armored_hit(
                            &mut o.body,
                            &mut o.status,
                            &mut o.can_respawn,
                            kind,
                            projectile.x,
                        );
                    }
                }
                3
            }
            Target::Shell => {
                let o = &self.entities[current];
                let Kind::Walker(w) = &o.kind else {
                    unreachable!()
                };
                if kind == HitKind::Spit && w.mode == crate::shell::SPIN {
                    0
                } else {
                    let both_spin = kind == HitKind::Shell
                        && w.mode == crate::shell::SPIN
                        && w.kind == ActorKind::Shell
                        && projectile_spins;
                    // hit with SPIT or SHELL removes it.
                    self.shell_remove(current);
                    if both_spin {
                        1
                    } else {
                        3
                    }
                }
            }
            Target::Actor => {
                self.hit_actor(current)?;
                3
            }
            Target::Pickup => {
                self.collect_item(current);
                3
            }
            Target::Egg | Target::Inert => 3,
            Target::Cache => {
                let o = &mut self.entities[current];
                if let Kind::Cache(c) = &mut o.kind {
                    c.hit(o.status, o.collected);
                }
                3
            }
            Target::PlantMiss | Target::RollingPair | Target::Nothing => 0,
        })
    }
    /// actor.gd hit with a spit (no element, not an egg): remove the body.
    fn hit_actor(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        if e.status != 1 {
            return Ok(());
        }
        if let Kind::Walker(w) = &e.kind {
            if w.held != 0 {
                return Ok(());
            }
            // Body.remove runs actor.gd on_remove first (the capturing e5 lets go).
            self.plant_on_remove(index);
            let e = &mut self.entities[index];
            if let Kind::Walker(w) = &mut e.kind {
                w.remove(&mut e.status, &mut e.can_respawn);
            }
        }
        Ok(())
    }
}

fn held(e: &Entity) -> bool {
    match &e.kind {
        Kind::Walker(w) => w.held == 1,
        Kind::Pickup(p) => p.held == 1,
        Kind::Star(p) => p.held == 1,
        Kind::Melon(m) => m.held == 1,
        _ => false,
    }
}
fn hidden(e: &Entity) -> bool {
    matches!(&e.kind, Kind::Walker(w) if w.hidden == 1)
}
