//! One typed authoritative table. Schema-indexed arrays exist only at codec boundaries.
use crate::{
    body::Body,
    entity::{Entity, Kind, Origin},
    math::{screen_centre, Rng},
    player::{Player, Sound},
    schema::{Field, Schema},
    wire::{WireEntity, WireSnapshot},
    Error, Position, World, SCALE as S,
};
#[derive(Clone, Debug)]
pub(crate) struct Run {
    pub frame: i64,
    pub camera: Position,
    pub rng: Rng,
    pub player: Player,
    pub entities: Vec<Entity>,
    pub sound: Sound,
    pub play_ticks: i64,
    pub total_play_ticks: i64,
    pub attempt_ticks: i64,
    pub coins: i64,
    pub redcoins: i64,
    pub flowers: i64,
    pub goal_reached: i64,
    pub deaths: i64,
    pub dynamic_serial: i64,
    pub checkpoint: crate::checkpoint::Memory,
    pub consumers: crate::consumers::Consumers,
    #[cfg(test)]
    pub solid_trace: crate::solids::SolidTrace,
}
fn unsupported(reason: &str) -> Error {
    Error::Unsupported {
        requirements: vec![reason.into()],
    }
}
fn overlap(a: Body, ab: [i64; 4], b: Body, bb: [i64; 4]) -> bool {
    a.x + ab[2] > b.x + bb[0]
        && a.x + ab[0] < b.x + bb[2]
        && a.y + ab[3] > b.y + bb[1]
        && a.y + ab[1] < b.y + bb[3]
}
impl Run {
    pub fn create(world: &World, stats: &mut crate::Stats) -> Result<Self, Error> {
        let identity = crate::schema::decode_hash(
            "75c8a5af059df0550d21119c4bcd962a46c1549839da6d09da9aa74cf7b0e0fd",
        )?;
        let bounce_identity = crate::schema::hash(
            include_str!("../../../../tests/fixtures/bounce.level.json").as_bytes(),
        );
        let lagoon_identity = crate::schema::hash(
            include_str!("../../../../tests/fixtures/lagoon.level.json").as_bytes(),
        );
        let collections_identity = crate::schema::hash(
            include_str!("../tests/fixtures/collections.level.json").as_bytes(),
        );
        let actors_identity = crate::schema::hash(
            include_str!("../tests/fixtures/actors_target.level.json").as_bytes(),
        );
        let stilts_identity = crate::schema::hash(
            include_str!("../tests/fixtures/stilts_target.level.json").as_bytes(),
        );
        let checkpoint_identity = crate::schema::hash(
            include_str!("../tests/fixtures/checkpoint_target.level.json").as_bytes(),
        );
        let posts_identity = crate::schema::hash(
            include_str!("../tests/fixtures/posts_target.level.json").as_bytes(),
        );
        if world.identity != identity
            && world.identity != posts_identity
            && world.identity != checkpoint_identity
            && world.identity != stilts_identity
            && world.identity != actors_identity
            && world.identity != bounce_identity
            && world.identity != lagoon_identity
            && world.identity != collections_identity
        {
            return Err(unsupported("Only admitted public/verification worlds are supported; selected target runtime closure is not implemented"));
        }
        Self::create_after_fixture_identity(world, stats)
    }
    /// Benchmark-only: only the fixture identity gate above is bypassed.
    pub fn create_benchmark_unverified(
        world: &World,
        stats: &mut crate::Stats,
    ) -> Result<Self, Error> {
        Self::create_after_fixture_identity(world, stats)
    }
    fn create_after_fixture_identity(
        world: &World,
        stats: &mut crate::Stats,
    ) -> Result<Self, Error> {
        let entities = Self::spawn_rows(world)?;
        let player = Player::new(
            Body {
                x: world.spawn.x,
                y: world.spawn.y,
                ..Body::default()
            },
            world.spawn_facing,
        );
        let mut run = Self {
            frame: 0,
            camera: Position {
                x: world.spawn.x,
                y: world.spawn.y - 28 * S,
            },
            rng: Rng::from_saved(1)?,
            player,
            entities,
            sound: Sound::default(),
            play_ticks: 0,
            total_play_ticks: 0,
            attempt_ticks: 0,
            coins: 0,
            redcoins: 0,
            flowers: 0,
            goal_reached: 0,
            deaths: 0,
            dynamic_serial: 1,
            checkpoint: crate::checkpoint::Memory::default(),
            consumers: crate::consumers::Consumers::default(),
            #[cfg(test)]
            solid_trace: crate::solids::SolidTrace::default(),
        };
        let solids = std::cell::RefCell::new(crate::solids::SolidFrame::default());
        let map = crate::body::Probe::with_solids(&world.maps[0], &solids);
        for _ in 0..2 {
            solids.borrow_mut().begin(&run.entities);
            run.entities_step(&map, stats)?;
            run.player
                .advance(&map, 0, 0, 0, 0, &mut run.rng, &mut run.sound);
            run.apply_post_updates(map.post_updates())?;
            if run.player.after_life(&map, &mut run.sound) {
                run.deaths = run.deaths.saturating_add(1);
            }
            run.player.finish(&map, 0);
            #[cfg(test)]
            {
                run.solid_trace = map.solid_trace(run.frame, run.player.body, run.player.bounds());
            }
        }
        stats.terrain_queries += map.terrain_queries.get();
        run.camera = Position {
            x: run.player.body.x,
            y: run.player.body.y - 28 * S,
        };
        Ok(run)
    }
    fn spawn_rows(world: &World) -> Result<Vec<Entity>, Error> {
        let mut next_family = 0;
        world.maps[0]
            .placements
            .iter()
            .enumerate()
            .map(|(source, p)| {
                let kind = match p.code.as_str() {
                    "o5" => Kind::Goal,
                    "o23" => Kind::Post(crate::post::Post::new(p)?),
                    "o6" => Kind::Checkpoint(crate::checkpoint::Marker::new(p)?),
                    "d1" | "d2" | "d4" if p.variant == 0 && p.mirror == 0 && p.rotation == 0 => {
                        Kind::Decor
                    }
                    "o1" => Kind::Pickup(crate::items::Pickup::new(
                        crate::items::PickupKind::Coin,
                        p.variant,
                        p.position.y,
                    )),
                    "o2" => Kind::Pickup(crate::items::Pickup::new(
                        crate::items::PickupKind::RedCoin,
                        p.variant,
                        p.position.y,
                    )),
                    "o3" => Kind::Pickup(crate::items::Pickup::new(
                        crate::items::PickupKind::Flower,
                        p.variant,
                        p.position.y,
                    )),
                    "o4" => Kind::Star(crate::items::Star::default()),
                    "p1" if matches!(p.prepared, crate::PreparedPlacement::Bridge { .. }) => {
                        Kind::Bridge
                    }
                    "o11" if matches!(p.prepared, crate::PreparedPlacement::Pad { .. }) => {
                        Kind::Pad(crate::pad::Pad::default())
                    }
                    "e1" | "e2" | "e3" | "e5" | "e35"
                        if p.variant >= 0
                            && p.variant
                                <= if ["e1", "e2", "e35"].contains(&p.code.as_str()) {
                                    4
                                } else {
                                    1
                                }
                            && (0..=2).contains(&p.mirror)
                            && p.rotation == 0 =>
                    {
                        let kind = match p.code.as_str() {
                            "e1" => crate::actors::ActorKind::Walker,
                            "e2" => crate::actors::ActorKind::Flyer,
                            "e3" => crate::actors::ActorKind::Flower,
                            "e35" => crate::actors::ActorKind::Stilt,
                            _ => crate::actors::ActorKind::Plant,
                        };
                        let mut actor =
                            crate::actors::Actor::new(kind, p.variant, p.mirror, p.position);
                        if kind == crate::actors::ActorKind::Stilt {
                            actor.height = crate::stilt::height(p)?;
                        }
                        Kind::Walker(actor)
                    }
                    _ => return Err(unsupported("fixture entity form")),
                };
                let family_index = if matches!(kind, Kind::Walker(_)) {
                    let index = next_family;
                    next_family += 1;
                    index
                } else {
                    0
                };
                Ok(Entity::placed(source, p, kind, family_index))
            })
            .collect()
    }
    fn respawn(&mut self, world: &World) -> Result<(), Error> {
        let flags: Vec<i64> = self
            .entities
            .iter()
            .take(world.maps[0].placements.len())
            .map(|e| e.checkpoint_collected)
            .collect();
        self.entities = Self::spawn_rows(world)?;
        for (entity, flag) in self.entities.iter_mut().zip(flags) {
            entity.collected = flag;
            entity.checkpoint_collected = flag;
        }
        let spawn = if self.checkpoint.id != 0 {
            self.checkpoint.position
        } else {
            world.spawn
        };
        // item_egg/seed/element reset_map run in spawn_map, before Moves.reset clears
        // the request history, so they keep the serial from before the reset.
        self.consumers.reset_map(self.player.food.requests.serial());
        let previous = self.player.previous_input;
        let pressed = self.player.pressed_input;
        let hits = self.player.life.hits;
        let quick = self.player.life.quick_death;
        self.player = Player::new(
            Body {
                x: spawn.x,
                y: spawn.y,
                ..Body::default()
            },
            world.spawn_facing,
        );
        self.player.life.health = if self.checkpoint.id != 0 {
            self.checkpoint.health
        } else {
            10
        };
        self.player.previous_input = previous;
        self.player.pressed_input = pressed;
        self.player.life.hits = hits;
        self.player.life.quick_death = quick;
        self.player.flutter_ready = 1;
        self.player.life_phase = 5;
        self.player.life_ticks = 3;
        self.player.attach();
        self.attempt_ticks = 0;
        self.play_ticks = self.checkpoint.play_ticks;
        self.redcoins = self.checkpoint.redcoins;
        self.flowers = self.checkpoint.flowers;
        self.goal_reached = 0;
        self.camera = Position {
            x: spawn.x,
            y: spawn.y - 28 * S,
        };
        Ok(())
    }
    fn entities_step(
        &mut self,
        map: &crate::body::Probe,
        stats: &mut crate::Stats,
    ) -> Result<(), Error> {
        let centre = screen_centre(self.camera, map.width_pixels * S, map.height_pixels * S);
        let mut next = 0;
        while next < self.entities.len() {
            let e = &mut self.entities[next];
            next += 1;
            if !matches!(
                e.kind,
                Kind::Pickup(_) | Kind::Star(_) | Kind::Walker(_) | Kind::Post(_)
            ) {
                continue;
            }
            if !e.lifecycle(map, centre, self.player.body.x, &mut self.rng)? {
                continue;
            }
            stats.entity_steps += 1;
            #[cfg(feature = "benchmark-work-counters")]
            stats.benchmark_stepped_source_rows.push(e.origin.placed());
            let token = e.origin.token();
            let after = match &mut e.kind {
                Kind::Post(_) => crate::eating::After::Nothing,
                // pickup.gd / item_star.gd step: a held item only consumes its requests.
                Kind::Pickup(p) if p.held != 0 => {
                    p.phase = (p.phase + 1) % 60;
                    crate::eating::After::ConsumeItem
                }
                Kind::Star(p) if p.held != 0 => crate::eating::After::ConsumeItem,
                Kind::Pickup(p) => {
                    p.advance(&mut e.body, &mut e.status, e.collected, map);
                    crate::eating::After::Nothing
                }
                Kind::Star(p) => {
                    p.advance(
                        &mut e.body,
                        &mut e.facing,
                        &mut e.status,
                        self.player.body.x,
                        map,
                    );
                    crate::eating::After::Nothing
                }
                Kind::Walker(w) => {
                    #[cfg(debug_assertions)]
                    {
                        use crate::actors::ActorKind;
                        let index = match w.kind {
                            ActorKind::Walker => 0,
                            ActorKind::Flyer => 1,
                            ActorKind::Flower => 2,
                            ActorKind::Plant => 3,
                            ActorKind::Stilt => 4,
                        };
                        stats.benchmark_actor_steps[index] += 1;
                    }
                    let mut context = crate::actors::ActorStep {
                        map,
                        frame: self.frame,
                        camera: self.camera,
                        player: &mut self.player,
                        rng: &mut self.rng,
                    };
                    w.advance(
                        token,
                        &mut e.body,
                        &mut e.facing,
                        &mut e.status,
                        &mut e.can_respawn,
                        &mut context,
                    )?
                }
                _ => unreachable!("phase 0 members"),
            };
            match after {
                crate::eating::After::HitOthers(b) => self.hit_others(next - 1, b)?,
                crate::eating::After::ConsumeItem => self.consume_item(next - 1),
                crate::eating::After::Nothing => {}
            }
        }
        // Captures skip phase 1 exactly as DispatchLoops.advance does.
        if self.player.captured_by != 0 {
            return Ok(());
        }
        // Step phase 1, still in saved table order. Pad has no activation lifecycle.
        for e in &mut self.entities {
            if !matches!(e.kind, Kind::Pad(_)) {
                continue;
            }
            let awake = e.lifecycle(map, centre, self.player.body.x, &mut self.rng)?;
            if let Kind::Pad(pad) = &mut e.kind {
                if awake {
                    stats.entity_steps += 1;
                    #[cfg(feature = "benchmark-work-counters")]
                    stats.benchmark_stepped_source_rows.push(e.origin.placed());
                    let crate::PreparedPlacement::Pad { large, .. } = map.placements[e
                        .origin
                        .placed()
                        .expect("pad is a placed verification dependency")]
                    .prepared
                    else {
                        unreachable!("compiler-owned pad flags")
                    };
                    pad.advance(&mut e.body, map, large);
                }
            }
        }
        Ok(())
    }
    pub fn advance(
        &mut self,
        input: u8,
        world: &World,
        stats: &mut crate::Stats,
    ) -> Result<(), Error> {
        if self.goal_reached != 0 {
            return Ok(());
        }
        self.frame = self.frame.checked_add(1).ok_or_else(|| {
            unsupported("saved frame increment exceeds the admitted Stride state range")
        })?;
        let solids = std::cell::RefCell::new(crate::solids::SolidFrame::default());
        solids.borrow_mut().begin(&self.entities);
        let map = crate::body::Probe::with_solids(&world.maps[0], &solids);
        if self.player.life_phase == 0 {
            self.play_ticks = self.play_ticks.saturating_add(1);
            self.total_play_ticks = self.total_play_ticks.saturating_add(1);
            self.attempt_ticks = self.attempt_ticks.saturating_add(1);
            if self
                .player
                .before_play_life(&map, self.camera, &mut self.sound)
            {
                self.deaths = self.deaths.saturating_add(1);
            }
        } else {
            let goal = self.player.life_phase == 7;
            if self.player.life_phase == 6 {
                self.checkpoint.step(&mut self.player);
            } else if self.player.phase_tick(&mut self.sound) {
                self.respawn(world)?;
            }
            if goal {
                self.camera = Position {
                    x: self.player.body.x,
                    y: self.player.body.y - 28 * S,
                };
                if self.player.life_phase == 8 {
                    self.goal_reached = 1;
                }
            }
        }
        self.player
            .dead_body(&map, input, self.frame, &mut self.rng, &mut self.sound);
        // The frozen world still receives callbacks from its moving dead player body.
        self.apply_post_updates(map.post_updates())?;
        if self.player.blocks_step() {
            stats.terrain_queries += map.terrain_queries.get();
            return Ok(());
        }
        let pressed = input & !(self.player.previous_input as u8);
        let released = self.player.previous_input as u8 & !input;
        self.player.previous_input = input as i64;
        self.player.pressed_input = pressed as i64;
        solids.borrow_mut().begin(&self.entities);
        self.entities_step(&map, stats)?;
        let locked = self.player.locks_input();
        let action = if locked {
            self.player.locked_action(input)
        } else {
            input
        };
        let (pressed, released) = if locked { (0, 0) } else { (pressed, released) };
        if self.player.captured_by == 0 {
            self.player.advance(
                &map,
                action,
                pressed,
                released,
                self.frame,
                &mut self.rng,
                &mut self.sound,
            );
            self.apply_post_updates(map.post_updates())?;
            // Contact phase 0 precedes actors (phase 1), regardless of placement order.
            for e in &mut self.entities {
                if let Kind::Pad(pad) = &mut e.kind {
                    if e.status == 1 {
                        stats.contacts += 1;
                        let crate::PreparedPlacement::Pad { large, single_use } = world.maps[0]
                            .placements[e
                            .origin
                            .placed()
                            .expect("pad is a placed verification dependency")]
                        .prepared
                        else {
                            unreachable!("compiler-owned pad flags")
                        };
                        pad.contact(e.body, &mut self.player, action, large, single_use);
                    }
                }
            }
            let mut contact_index = 0;
            while contact_index < self.entities.len() {
                let index = contact_index;
                contact_index += 1;
                let e = &mut self.entities[index];
                if e.status != 1 {
                    continue;
                }
                if let Kind::Post(p) = &e.kind {
                    stats.contacts += 1;
                    if p.spiked != 0 && p.height > 0 {
                        let b = self.player.bounds();
                        if self.player.body.x + b[2] >= e.body.x - 16 * S
                            && self.player.body.x + b[0] <= e.body.x + 16 * S
                            && self.player.body.y + b[3] + S / 10 >= e.body.y - p.height
                            && self.player.body.y + b[1] + S / 10 <= e.body.y
                            && self.player.hurt(e.body.x, &mut self.sound)
                        {
                            stats.damage_events += 1;
                        }
                    }
                    continue;
                }
                if let Kind::Pickup(p) = &mut e.kind {
                    // DispatchLoops.contact skips held entities.
                    if p.held == 1 {
                        continue;
                    }
                    stats.contacts += 1;
                    let b = self.player.bounds();
                    let box_ = [
                        self.player.body.x + b[0],
                        self.player.body.y + b[1],
                        self.player.body.x + b[2],
                        self.player.body.y + b[3],
                    ];
                    if self.player.life_phase == 0 && p.touches(e.body, e.collected, box_) {
                        e.collected = 1;
                        match p.kind {
                            crate::items::PickupKind::Coin => {
                                self.coins = self.coins.saturating_add(1)
                            }
                            crate::items::PickupKind::RedCoin => {
                                self.redcoins = self.redcoins.saturating_add(1)
                            }
                            crate::items::PickupKind::Flower => {
                                self.flowers = self.flowers.saturating_add(1)
                            }
                        }
                        self.sound.emit(2, e.body.x, e.body.y);
                        p.held = 0;
                        if p.kind == crate::items::PickupKind::RedCoin {
                            p.phase = 0;
                            p.collect_y = e.body.y;
                            p.collect_ticks = 60;
                        } else {
                            e.status = 3;
                        }
                        stats.collections += 1;
                    }
                    continue;
                }
                if let Kind::Star(p) = &mut e.kind {
                    stats.contacts += 1;
                    if e.collected == 0
                        && p.pickup_delay == 0
                        && p.held == 0
                        && self.player.life_phase == 0
                        && overlap(e.body, p.bounds(), self.player.body, self.player.bounds())
                    {
                        e.collected = 1;
                        self.player.life.health = (self.player.life.health + 1).min(30);
                        self.sound.emit(2, e.body.x, e.body.y);
                        p.held = 0;
                        e.status = 3;
                        stats.collections += 1;
                    }
                    continue;
                }
                let Kind::Walker(w) = &mut e.kind else {
                    continue;
                };
                // DispatchLoops.contact skips held and hidden entities; actor.gd contact
                // also ignores spat bodies.
                if w.held == 1 || w.hidden == 1 {
                    continue;
                }
                stats.contacts += 1;
                if w.spat != 0 && w.kind != crate::actors::ActorKind::Stilt {
                    continue;
                }
                if w.roll != 0 && w.kind != crate::actors::ActorKind::Stilt {
                    // actor.gd contact: a rolling body breaks on the player after its grace.
                    let b = self.player.bounds();
                    if w.roll_grace == 0
                        && w.roll_up == 0
                        && self.player.captured_by == 0
                        && overlap(e.body, w.bounds(e.body, e.facing), self.player.body, b)
                    {
                        w.remove(&mut e.status, &mut e.can_respawn);
                    }
                    continue;
                }
                if self.player.captured_by != 0 {
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Plant {
                    w.capture(e.body, e.facing, e.family_index, &mut self.player);
                    continue;
                }
                let touching = overlap(
                    self.player.body,
                    self.player.bounds(),
                    e.body,
                    w.body_bounds(e.facing),
                );
                if w.kind == crate::actors::ActorKind::Stilt {
                    let high = self.player.body.y <= e.body.y - w.height + 50 * S;
                    let unseat = touching && w.contact == 0 && high;
                    w.contact = i64::from(touching);
                    if unseat && [2, 3].contains(&self.player.action) {
                        e.status = 3;
                        e.can_respawn = 0;
                        w.held = 0;
                        w.spat = 0;
                        continue;
                    }
                    if unseat {
                        self.player.stomp(e.body.vy, action, &mut self.sound);
                        let position = Position {
                            x: e.body.x,
                            y: e.body.y - w.height + 34 * S,
                        };
                        let variant = w.variant;
                        let facing = e.facing;
                        let layer = e.layer;
                        e.status = 3;
                        e.can_respawn = 0;
                        w.held = 0;
                        w.spat = 0;
                        self.spawn_walker(position, variant, facing, layer)?;
                    } else if touching && !high && self.player.hurt(e.body.x, &mut self.sound) {
                        stats.damage_events += 1;
                    }
                    continue;
                }
                if touching {
                    if e.body.y > self.player.body.y - 8 * S && w.contact == 0 {
                        if ![2, 3].contains(&self.player.action) {
                            self.player.stomp(e.body.vy, action, &mut self.sound);
                        }
                        e.status = 3;
                    } else if e.body.y < self.player.body.y - 8 * S
                        && self.player.hurt(e.body.x, &mut self.sound)
                    {
                        stats.damage_events += 1;
                    }
                    w.contact = 1;
                } else {
                    w.contact = 0;
                }
            }
            for phase2_index in 0..self.entities.len() {
                if matches!(self.entities[phase2_index].kind, Kind::Checkpoint(_))
                    && self.entities[phase2_index].status == 1
                {
                    stats.contacts += 1;
                    self.touch_checkpoint(phase2_index);
                    continue;
                }
                let e = &self.entities[phase2_index];
                if !matches!(e.kind, Kind::Goal) || e.status != 1 {
                    continue;
                }
                stats.contacts += 1;
                if self.player.life_phase == 0
                    && self.player.life.separated == 0
                    && self.player.captured_by == 0
                    && overlap(
                        self.player.body,
                        [-12 * S, -56 * S, 12 * S, 0],
                        e.body,
                        [-8 * S, -8 * S, 8 * S, 8 * S],
                    )
                {
                    let p = &mut self.player;
                    p.life_phase = 7;
                    p.life_ticks = 180;
                    p.goal_from_x = p.body.x;
                    p.goal_from_y = p.body.y;
                    p.goal_x = e.body.x;
                    p.goal_y = e.body.y + 32 * S;
                    p.body.vx = 0;
                    p.body.vy = 0;
                    p.movement = 5;
                    self.sound.player(p.body);
                    break;
                }
            }
            if self.player.life_phase == 7 {
                let centre =
                    screen_centre(self.camera, map.width_pixels * S, map.height_pixels * S);
                for e in &mut self.entities {
                    let b = if let Kind::Walker(w) = &e.kind {
                        w.bounds(e.body, e.facing)
                    } else {
                        continue;
                    };
                    if e.status == 1
                        && e.body.x + b[2] > centre.x - 416 * S
                        && e.body.x + b[0] < centre.x + 416 * S
                        && e.body.y + b[3] > centre.y - 224 * S
                        && e.body.y + b[1] < centre.y + 224 * S
                    {
                        e.status = 3;
                        self.coins = self.coins.saturating_add(1);
                    }
                }
            }
            // registry.gd tongue_contact, in table order (eating.rs).
            if let Some(sensor) = self.player.tongue_box() {
                self.tongue_contact(sensor);
            }
            if let Some(reach) = self.player.tongue_reach() {
                self.player.catch_companion(reach);
            }
        }
        // registry.gd consume_requests: level-wide consumers, then entity consumers.
        self.consumers
            .run(&self.player.food.requests, self.player.food.eggs)?;
        self.consume_item_requests();
        if self.player.after_life(&map, &mut self.sound) {
            self.deaths = self.deaths.saturating_add(1);
        }
        self.compact();
        self.camera = Position {
            x: self.player.body.x,
            y: self.player.body.y - 28 * S,
        };
        if self.player.captured_by == 0 && !self.player.blocks_step() {
            self.player.finish(&map, action);
        }
        #[cfg(test)]
        {
            self.solid_trace = map.solid_trace(self.frame, self.player.body, self.player.bounds());
        }
        stats.terrain_queries += map.terrain_queries.get();
        Ok(())
    }
    pub fn score(&self) -> i64 {
        let remaining = i64::MAX - self.player.life.health;
        if self.redcoins > remaining {
            return i64::MAX;
        }
        let remaining = remaining - self.redcoins;
        if self.flowers > remaining / 10 {
            return i64::MAX;
        }
        self.player.life.health + self.redcoins + 10 * self.flowers
    }
    pub fn wire(&self, world: &World, schema: &Schema) -> WireSnapshot {
        let level = schema
            .level()
            .iter()
            .map(|Field(n, d)| self.level_value(n, world).unwrap_or(*d))
            .collect();
        let player = schema
            .player()
            .iter()
            .map(|Field(n, d)| self.player_value(n).unwrap_or(*d))
            .collect();
        let entities = self
            .entities
            .iter()
            .map(|e| {
                let code = e.code(world);
                let values = schema
                    .entity_fields(code)
                    .iter()
                    .map(|Field(n, d)| self.entity_value(e, n, world).unwrap_or(*d))
                    .collect();
                WireEntity {
                    code: code.to_owned(),
                    id: e.id(world).into_owned(),
                    values,
                }
            })
            .collect();
        WireSnapshot {
            identity: world.identity,
            level,
            player,
            entities,
        }
    }
    fn level_value(&self, n: &str, world: &World) -> Option<i64> {
        if let Some(value) = self.checkpoint.field(n) {
            return Some(value);
        }
        if let Some(value) = self.consumers.field(n) {
            return Some(value);
        }
        Some(match n {
            "frame" => self.frame,
            "camera_x" => self.camera.x,
            "camera_y" => self.camera.y,
            "rng" => self.rng.saved(),
            "goal_reached" => self.goal_reached,
            "deaths" => self.deaths,
            "dynamic_serial" => self.dynamic_serial,
            "life_ready" => 1,
            "run_spawn_x" => world.spawn.x,
            "run_spawn_y" => world.spawn.y,
            "run_spawn_facing" => world.spawn_facing,
            "play_ticks" => self.play_ticks,
            "total_play_ticks" => self.total_play_ticks,
            "coins" => self.coins,
            "redcoins" => self.redcoins,
            "flowers" => self.flowers,
            "flowers_target" => world.flowers_target,
            "redcoins_target" => world.redcoins_target,
            "sound_serial" => self.sound.serial,
            "sound_kind" => self.sound.kind,
            "sound_x" => self.sound.x,
            "sound_y" => self.sound.y,
            _ => return None,
        })
    }
    fn player_value(&self, n: &str) -> Option<i64> {
        if n == "attempt_ticks" {
            Some(self.attempt_ticks)
        } else {
            self.player.field(n)
        }
    }
    fn entity_value(&self, e: &Entity, n: &str, world: &World) -> Option<i64> {
        let specific = match &e.kind {
            Kind::Pickup(p) => p.field(n),
            Kind::Star(p) => p.field(n),
            Kind::Walker(p) => p.field(n),
            Kind::Checkpoint(p) => p.field(n),
            Kind::Post(p) => p.field(n),
            _ => None,
        };
        if specific.is_some() {
            return specific;
        }
        if let Some(value) = e.common_field(n) {
            return Some(value);
        }
        let p = e.source(world);
        let spawn = e.position_at_spawn(world);
        Some(match n {
            "source_index" => e.origin.index(),
            "token" => e.origin.token(),
            "map_index" => 1,
            "family_index" => e.family_index,
            "x" => e.body.x,
            "y" => e.body.y,
            "vx" => e.body.vx,
            "vy" => e.body.vy,
            "facing" => e.facing,
            "status" => e.status,
            "offscreen" => e.offscreen,
            "collected" => e.collected,
            "checkpoint_collected" => e.checkpoint_collected,
            "spawn_mode" | "can_despawn" | "can_respawn" => {
                i64::from(matches!(e.kind, Kind::Walker(_) | Kind::Star(_)))
            }
            "layer" => {
                if matches!(e.kind, Kind::Walker(_)) {
                    8
                } else {
                    7
                }
            }
            "spawn_x" | "home_x" => spawn.x,
            "spawn_y" | "home_y" => spawn.y,
            "phase" => {
                if let Kind::Walker(w) = &e.kind {
                    w.phase
                } else {
                    return None;
                }
            }
            "timer" => {
                if let Kind::Walker(w) = &e.kind {
                    w.timer
                } else {
                    return None;
                }
            }
            "cycles" => {
                if let Kind::Walker(w) = &e.kind {
                    w.cycles
                } else {
                    return None;
                }
            }
            "mode" => {
                if let Kind::Walker(w) = &e.kind {
                    w.mode
                } else {
                    return None;
                }
            }
            "started" => {
                if let Kind::Walker(w) = &e.kind {
                    w.started
                } else {
                    return None;
                }
            }
            "contact" => {
                if let Kind::Walker(w) = &e.kind {
                    w.contact
                } else {
                    return None;
                }
            }
            "squash" => {
                if let Kind::Pad(pad) = &e.kind {
                    pad.squash
                } else {
                    return None;
                }
            }
            "active" => {
                if let Kind::Pad(pad) = &e.kind {
                    i64::from(pad.active)
                } else {
                    return None;
                }
            }
            "large" | "single_use" => {
                if let Some(crate::Placement {
                    prepared: crate::PreparedPlacement::Pad { large, single_use },
                    ..
                }) = p
                {
                    i64::from(if n == "large" { *large } else { *single_use })
                } else {
                    return None;
                }
            }
            _ => return None,
        })
    }
    pub fn validate(&self, world: &World) -> Result<(), Error> {
        let p = &self.player;
        if !self.checkpoint.valid(&self.entities) {
            return Err(unsupported("checkpoint memory"));
        }
        let position_limit = i64::MAX / 16384;
        if self.frame < 0
            || self.play_ticks < 0
            || self.total_play_ticks < self.play_ticks
            || self.attempt_ticks < 0
            || self.coins < 0
            || self.redcoins < 0
            || self.flowers < 0
            || self.deaths < 0
            || !(0..=1).contains(&self.goal_reached)
            || ![-1, 1].contains(&p.facing)
            || !(0..=1).contains(&p.on_floor)
            || p.captured_by < 0
            || p.captured_by
                > self
                    .entities
                    .iter()
                    .filter(|e| matches!(e.kind, Kind::Walker(_)))
                    .count() as i64
            || p.support_bridge < 0
            || p.support_bridge > world.maps[0].bridges.len() as i64
            || !(0..=6).contains(&p.movement)
            || !(0..=255).contains(&p.previous_input)
            || !(0..=255).contains(&p.pressed_input)
            || !(0..=11).contains(&p.action)
            || ![0, 1].contains(&p.duck)
            || ![0, 1].contains(&p.look)
            || !(0..=9).contains(&p.posture_tick)
            || !p.food.valid(p.water.swimming, p.duck)
            || !(0..=position_limit).contains(&p.impact)
            || !p.tongue.valid(p.action)
            || !p.water.valid()
            || ![0, 1].contains(&p.action_wet)
            || p.action_tick < 0
            || p.action_tick
                >= match p.action {
                    1 => 24,
                    4 => p.tongue_end_tick(),
                    5 | 9 => 10,
                    6 => 25,
                    8 => 13,
                    10 => 4,
                    11 => 35,
                    _ => 36,
                }
            || !(0..=6).contains(&p.jump_buffer)
            || !(0..=72).contains(&p.flutter_remaining)
            || !(0..=17).contains(&p.flutter_cooldown)
            || !(0..=1).contains(&p.flutter_ready)
            || !(0..=1).contains(&p.boosted_flutter)
            || !(0..=24).contains(&p.gravity_tick)
            || !(0..=2).contains(&p.bounce)
            || !(0..=1).contains(&p.jump_carry)
            || ![-1, 0, 1].contains(&p.turn)
            || !(0..=30).contains(&p.turn_ticks)
            || !(0..=6).contains(&p.pound_delay)
            || !(0..=1).contains(&p.push)
            || !p.life.valid(p.life_phase, p.life_ticks)
            || (p.life_phase == 0 && p.life_ticks != 0)
            || (p.life_phase == 8) != (self.goal_reached != 0)
            || !(-2000 * 60..=2000 * 60).contains(&p.body.vx)
            || p.body.vy < -2000 * 60
            || p.body.vy > if p.action == 2 { 1408 * 60 } else { 704 * 60 }
            || self.sound.serial < 0
            || !(0..=4).contains(&self.sound.kind)
        {
            return Err(unsupported("state outside implemented Stride semantics"));
        }
        for v in [
            p.body.x,
            p.body.y,
            p.impact_x,
            p.impact_y,
            self.camera.x,
            self.camera.y,
            p.recovery_x,
            p.recovery_y,
            p.goal_x,
            p.goal_y,
            p.goal_from_x,
            p.goal_from_y,
            self.sound.x,
            self.sound.y,
        ] {
            if !(-position_limit..=position_limit).contains(&v) {
                return Err(unsupported("coordinate headroom"));
            }
        }
        if self.dynamic_serial < 1
            || self.dynamic_serial > i64::MAX - crate::entity::TOKEN_BASE + 1
            || self.entities.len() < world.maps[0].placements.len()
        {
            return Err(unsupported("runtime serial/placed prefix validation"));
        }
        // Token uniqueness without a per-step set: placed tokens are slot+1 and the
        // identity check below pins slot == index, so they are distinct. Runtime
        // tokens are TOKEN_BASE+serial; they must be distinct from each other and
        // above every placed token. Checked after the loop.
        let placed_count = world.maps[0].placements.len() as i64;
        let serial = self.player.food.requests.serial();
        if !self.consumers.valid() {
            return Err(unsupported("egg inventory and level request cursors"));
        }
        let mut runtime_serials: Vec<i64> = Vec::new();
        let mut runtime_sorted = true;
        let mut family = 0;
        for (index, e) in self.entities.iter().enumerate() {
            match e.origin {
                Origin::Placed(slot) if slot == index && index < world.maps[0].placements.len() => {
                }
                Origin::Runtime(serial)
                    if index >= world.maps[0].placements.len()
                        && serial >= 1
                        && serial < self.dynamic_serial
                        && e.spawn_mode == 0
                        && e.can_respawn == 0 => {}
                _ => return Err(unsupported("ordered placed/runtime identity")),
            }
            if let Origin::Runtime(serial) = e.origin {
                if runtime_serials.last().is_some_and(|last| *last >= serial) {
                    runtime_sorted = false;
                }
                if e.origin.token() <= placed_count {
                    return Err(unsupported("duplicate entity token"));
                }
                runtime_serials.push(serial);
            }
            if matches!(e.kind, Kind::Walker(_)) {
                if e.family_index != family {
                    return Err(unsupported("enemy family order"));
                }
                family += 1;
            }
            if ![0, 1].contains(&e.spawn_mode)
                || ![0, 1].contains(&e.can_despawn)
                || ![0, 1].contains(&e.can_respawn)
                || ![
                    e.activation_x,
                    e.activation_y,
                    e.despawn_radius,
                    e.respawn_radius,
                ]
                .iter()
                .all(|v| (0..=position_limit).contains(v))
            {
                return Err(unsupported("entity common field headroom"));
            }
            if !(0..=3).contains(&e.status)
                || ![-1, 1].contains(&e.facing)
                || !(0..=1).contains(&e.offscreen)
                || ![0, 1].contains(&e.collected)
                || ![0, 1].contains(&e.checkpoint_collected)
                || !(-position_limit..=position_limit).contains(&e.body.x)
                || !(-position_limit..=position_limit).contains(&e.body.y)
            {
                return Err(unsupported("entity lifecycle validation"));
            }
            if let Kind::Post(p) = &e.kind {
                if !p.valid() {
                    return Err(unsupported("post fields"));
                }
            }
            if let Kind::Checkpoint(p) = &e.kind {
                if !p.valid() {
                    return Err(unsupported("checkpoint marker fields"));
                }
            }
            if let Kind::Pickup(p) = &e.kind {
                if !p.valid()
                    || !(-position_limit..=position_limit).contains(&p.collect_y)
                    || p.collect_ticks != 0
                        && (p.kind != crate::items::PickupKind::RedCoin || e.collected != 1)
                    || ![0, 1].contains(&p.held)
                    || !(0..=serial).contains(&p.request_cursor)
                    || p.origin_token != 0
                    || !(-1024 * 60..=1024 * 60).contains(&e.body.vx)
                    || !(-1024 * 60..=1024 * 60).contains(&e.body.vy)
                {
                    return Err(unsupported("pickup state/request path"));
                }
            }
            if let Kind::Star(p) = &e.kind {
                if !p.valid()
                    || ![0, 1].contains(&p.held)
                    || !(0..=serial).contains(&p.request_cursor)
                    || p.origin_token != 0
                    || !(-1024 * 60..=1024 * 60).contains(&e.body.vx)
                    || !(-1024 * 60..=1024 * 60).contains(&e.body.vy)
                {
                    return Err(unsupported("health-drop state/request path"));
                }
            }
            if let Kind::Pad(pad) = &e.kind {
                if !(0..=12).contains(&pad.squash)
                    || e.body.vx != 0
                    || !(0..=704 * 60).contains(&e.body.vy)
                {
                    return Err(unsupported("pad validation"));
                }
            }
            if let Kind::Walker(w) = &e.kind {
                if !w.valid()
                    || !(0..=360).contains(&w.phase)
                    || !(0..=210).contains(&w.timer)
                    || !(-1..=180).contains(&w.cycles)
                    || !(0..=5).contains(&w.mode)
                    || (w.held != 0 && w.spat != 0)
                    || w.hidden != 0
                    || w.frozen != 0
                    || !(0..=serial).contains(&w.request_cursor)
                    || w.impact_cursor > p.impact
                    || !(0..=1).contains(&w.started)
                    || !(0..=1).contains(&w.contact)
                    || !(-512 * 60..=512 * 60).contains(&e.body.vx)
                    || e.body.vy < -944 * 60
                    || e.body.vy > 704 * 60
                {
                    return Err(unsupported("walker validation"));
                }
            }
        }
        if !runtime_sorted {
            runtime_serials.sort_unstable();
            if runtime_serials.windows(2).any(|w| w[0] == w[1]) {
                return Err(unsupported("duplicate entity token"));
            }
        }
        Ok(())
    }
}
macro_rules! fields {($($name:literal=>$($path:ident).+),*$(,)?)=>{
impl Player{
    pub fn field(&self,n:&str)->Option<i64>{Some(match n{$($name=>self.$($path).+,)*_=>return self.food.field(n).or_else(||self.life.field(n))})}
    pub fn set_field(&mut self,n:&str,v:i64)->bool{match n{$($name=>{self.$($path).+ = v;true},)*_=>self.food.set_field(n,v)||self.life.set_field(n,v)}}
}};}
fields! {
"captured_by"=>captured_by,
"x"=>body.x,"y"=>body.y,"vx"=>body.vx,"vy"=>body.vy,"facing"=>facing,"movement"=>movement,"on_floor"=>on_floor,"support_bridge"=>support_bridge,"previous_input"=>previous_input,"pressed_input"=>pressed_input,
"jump_buffer"=>jump_buffer,"flutter_remaining"=>flutter_remaining,"flutter_cooldown"=>flutter_cooldown,"flutter_ready"=>flutter_ready,"boosted_flutter"=>boosted_flutter,
"move_tongue_axis"=>tongue.axis,"move_tongue_length"=>tongue.length,"move_tongue_phase"=>tongue.phase,"move_tongue_block_tick"=>tongue.block_tick,"move_tongue_hold"=>tongue.hold,
"swimming"=>water.swimming,"water_wait"=>water.wait,"water_phase"=>water.phase,"water_deep"=>water.deep,"move_dive"=>water.dive,"move_water_jump"=>water.jump,"move_water_transition"=>water.transition,"move_action_wet"=>action_wet,
"move_duck"=>duck,"move_look"=>look,"move_posture_tick"=>posture_tick,"move_impact"=>impact,"move_impact_x"=>impact_x,"move_impact_y"=>impact_y,
"move_action"=>action,"move_action_tick"=>action_tick,"move_turn"=>turn,"move_turn_ticks"=>turn_ticks,"move_push"=>push,"move_pound_delay"=>pound_delay,"move_gravity_tick"=>gravity_tick,"move_bounce"=>bounce,"move_brake_vx"=>brake_vx,"move_jump_carry"=>jump_carry,
"life_phase"=>life_phase,"life_ticks"=>life_ticks,"recovery_x"=>recovery_x,"recovery_y"=>recovery_y,"goal_from_x"=>goal_from_x,"goal_from_y"=>goal_from_y,"goal_x"=>goal_x,"goal_y"=>goal_y
}
