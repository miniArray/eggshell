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
    pub message: crate::blocks::Message,
    /// timed_switch.gd LEVEL_FIELDS.
    pub clock: crate::switch::Clock,
    /// Reused buffers of the step's solid rows (no game state; never saved).
    pub solid_scratch: crate::solids::Scratch,
    /// Table length and row indices of the e27 mace walkers, for mace_on_remove
    /// (derived from the table; never saved).
    pub mace_rows: (usize, Vec<usize>),
    /// Table length and the rows whose kind can press a count ledge (walkers, stars,
    /// eggs, stems, hounds), for ledge_contact (derived; never saved).
    pub presser_rows: (usize, Vec<usize>),
    /// Eggs pushed out of a full six-egg queue so far (made or picked up at six). Drawing
    /// only: the original drops the front egg of the trail off screen (YFS Yoshi 487-490,
    /// Objects 185-188). No game state; never saved, and a restore starts it again at 0.
    pub egg_pops: u64,
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
    /// Any level whose every placement and map feature the core implements loads; any
    /// other code, form or feature is refused with its reason (spawn_rows, World).
    pub fn create(world: &World, stats: &mut crate::Stats) -> Result<Self, Error> {
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
        // play_state.gd: the camera is set before spawn_map runs the birth hooks.
        let entities = Self::spawn_map(
            world,
            Position {
                x: world.spawn.x,
                y: world.spawn.y - 28 * S,
            },
        )?;
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
            message: crate::blocks::Message::default(),
            clock: crate::switch::Clock::default(),
            solid_scratch: crate::solids::Scratch::default(),
            mace_rows: (usize::MAX, Vec::new()),
            presser_rows: (usize::MAX, Vec::new()),
            egg_pops: 0,
            #[cfg(test)]
            solid_trace: crate::solids::SolidTrace::default(),
        };
        let solids = std::cell::RefCell::new(crate::solids::SolidFrame::default());
        let map = crate::body::Probe::with_solids(&world.maps[0], &solids);
        for _ in 0..2 {
            solids.borrow_mut().begin(&run.entities);
            run.entities_step(&map, stats)?;
            run.player
                .advance(&map, 0, 0, 0, 0, &mut run.rng, false, &mut run.sound);
            run.apply_post_updates(map.post_updates())?;
            // step.gd begin_level: the registry's request consumers, Life.after_step and
            // the compaction run in both level-start steps too.
            run.block_level_requests();
            for action in run
                .consumers
                .run(&run.player.food.requests, run.player.food.eggs)?
            {
                run.apply_consumer(action)?;
            }
            run.consume_item_requests();
            if run.player.after_life(&map, &mut run.sound) {
                run.deaths = run.deaths.saturating_add(1);
            }
            run.compact();
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
    /// registry.gd spawn_map: every placed row is created, then entity_lifecycle.gd
    /// created applies the opt-in birth cull around the given camera.
    fn spawn_map(world: &World, camera: Position) -> Result<Vec<Entity>, Error> {
        let map = &world.maps[0];
        let centre = screen_centre(camera, map.width_pixels * S, map.height_pixels * S);
        let mut rows = Self::spawn_rows(world)?;
        for row in &mut rows {
            row.creation_cull(centre);
        }
        Ok(rows)
    }
    fn spawn_rows(world: &World) -> Result<Vec<Entity>, Error> {
        let mut next_family = 0;
        let mut next_pad = 0;
        world.maps[0]
            .placements
            .iter()
            .enumerate()
            .map(|(source, p)| {
                let kind = match p.code.as_str() {
                    "o5" => Kind::Goal,
                    "empty" | "" => Kind::Blank,
                    "o23" => Kind::Post(crate::post::Post::new(p)?),
                    "o6" => Kind::Checkpoint(crate::checkpoint::Marker::new(p)?),
                    // decor.gd: static scenery; out-of-range forms and transformed
                    // extendable scenery degrade there (refused here). Extendable scenery
                    // is drawn from its E1 height; an invalid height does not load.
                    code if crate::decor::is_decor(code)
                        && (0..crate::decor::frame_count(code)).contains(&p.variant)
                        && (0..=1).contains(&p.mirror)
                        && (!crate::decor::resized(code) || crate::decor::untransformed(p)) =>
                    {
                        if crate::decor::resized(code) {
                            crate::decor::height(p)?;
                        }
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
                    // item_egg.gd prepare: forms 0..3 (others degrade).
                    "o7" if (0..=3).contains(&p.variant) => {
                        Kind::Egg(crate::egg::Egg::new(p.variant))
                    }
                    "o8" => Kind::Cache(crate::clouds::Cache::new(p)?),
                    "o19" => Kind::Redirect(crate::clouds::Redirect::new(p)?),
                    "o9" | "o15" | "o18" | "o24" => Kind::Block(crate::blocks::Block::new(p)?),
                    "o28" | "o29" | "o12" => Kind::Hard(crate::blocks::Hard::new(p)?),
                    "o20" => Kind::Fall(crate::blocks::Fall::new(p)?),
                    "o10" => Kind::Grow(crate::blocks::Grow::default()),
                    "o31" => Kind::Gate(crate::gate::Gate::new(p)?),
                    "o32" => Kind::Ledge(crate::ledge::Ledge::new(p)?),
                    "o17" => Kind::Stem(crate::stem::Stem::new(p)?),
                    "o22" => Kind::StarFlower(crate::flower::Flower::new(p)?),
                    "o14" => Kind::Switch(crate::switch::Switch::new(p)?),
                    "o21" => Kind::Lift(crate::lift::Lift::new(p)?),
                    "o25" => Kind::Melon(crate::melon::Melon::new(p)?),
                    "o16" => {
                        let ordinal = world.maps[0].placements[..=source]
                            .iter()
                            .filter(|p| p.code == "o16")
                            .count() as i64;
                        Kind::Hound(crate::hound::Hound::new(p, ordinal)?)
                    }
                    "e37" => Kind::Launcher(crate::launcher::Launcher::new(p)?),
                    "e34" => Kind::Sack(crate::sack::Sack::new(p)?),
                    "o27" => Kind::EggBlock(crate::egg_block::EggBlock::new(p)?),
                    "o13" => Kind::Pillar(crate::pillar::Pillar::new(p)?),
                    "o26" => Kind::Balloon(crate::balloon::Balloon::new(p)?),
                    "o33" | "o34" => Kind::Dice(crate::dice::Dice::new(p)?),
                    "p11" | "p12" => Kind::SpinSpan(crate::spin::SpinSpan::new(p)?),
                    "o30" => Kind::SpinBlock(crate::spin::SpinBlock::new(p)?),
                    "d5" | "d6" | "d7" | "d8" | "d23" => {
                        Kind::Platform(crate::platform::Platform::new(p)?)
                    }
                    "d25" | "d26" => Kind::Lamp(crate::platform::Lamp::new(p)?),
                    "p2" | "p3" | "p4" | "p5" | "p6" | "p7" | "p8" | "p9" | "p10" | "p13"
                    | "p14" | "p15" | "p16" | "p17" | "p18" | "p19" | "p20" | "p21" => {
                        Kind::Span(crate::spans::Span::new(p)?)
                    }
                    "p1" if matches!(p.prepared, crate::PreparedPlacement::Bridge { .. }) => {
                        Kind::Bridge
                    }
                    "o11" if matches!(p.prepared, crate::PreparedPlacement::Pad { .. }) => {
                        Kind::Pad(crate::pad::Pad::default())
                    }
                    "e1" | "e2" | "e3" | "e4" | "e5" | "e35" | "e20" | "e21" | "e32"
                        if p.variant >= 0
                            && p.variant
                                <= match p.code.as_str() {
                                    "e1" | "e2" | "e35" => 4,
                                    "e32" => 3,
                                    "e20" | "e21" => 3,
                                    "e4" => 0,
                                    _ => 1,
                                }
                            && (0..=2).contains(&p.mirror)
                            && p.rotation == 0 =>
                    {
                        let kind = match p.code.as_str() {
                            // lantern_walker.gd runs the plain walker's rules as e1.
                            "e1" | "e32" => crate::actors::ActorKind::Walker,
                            "e20" => crate::actors::ActorKind::Fish,
                            "e21" => crate::actors::ActorKind::LandFish,
                            "e2" => crate::actors::ActorKind::Flyer,
                            "e3" => crate::actors::ActorKind::Flower,
                            "e35" => crate::actors::ActorKind::Stilt,
                            "e4" => crate::actors::ActorKind::Flat,
                            _ => crate::actors::ActorKind::Plant,
                        };
                        let mut actor =
                            crate::actors::Actor::new(kind, p.variant, p.mirror, p.position);
                        if kind == crate::actors::ActorKind::Stilt {
                            actor.height = crate::stilt::height(p)?;
                        }
                        if p.code == "e32" {
                            actor.look = 5;
                        }
                        Kind::Walker(Box::new(actor))
                    }
                    "e6" | "e8" if p.rotation == 0 => {
                        Kind::Walker(Box::new(crate::actors::Actor::shell(p)?))
                    }
                    "e7" | "e9" => Kind::Walker(Box::new(crate::actors::Actor::bare_runner(p)?)),
                    "e11" if p.rotation == 0 => {
                        Kind::Walker(Box::new(crate::actors::Actor::armored(p)?))
                    }
                    "e22" if p.rotation == 0 => {
                        Kind::Walker(Box::new(crate::actors::Actor::spear_guard(p)?))
                    }
                    "e10" => Kind::Walker(Box::new(crate::actors::Actor::thief(p)?)),
                    "e28" => Kind::Walker(Box::new(crate::actors::Actor::roller(p)?)),
                    "e31" => Kind::Walker(Box::new(crate::actors::Actor::shooter(p)?)),
                    "e18" => Kind::Walker(Box::new(crate::actors::Actor::petal_stem(p)?)),
                    "e41" => Kind::Walker(Box::new(crate::actors::Actor::spitter(p)?)),
                    "e23" => Kind::Walker(Box::new(crate::actors::Actor::soft_walker(p)?)),
                    "e24" => Kind::Walker(Box::new(crate::actors::Actor::soft_giant(p)?)),
                    "e29" => Kind::Walker(Box::new(crate::actors::Actor::helmet(p)?)),
                    "e19" => Kind::Walker(Box::new(crate::actors::Actor::bumper(p)?)),
                    "e27" => Kind::Walker(Box::new(crate::actors::Actor::mace(p)?)),
                    "e30" => Kind::Walker(Box::new(crate::actors::Actor::wing(p)?)),
                    "e12" => Kind::Walker(Box::new(crate::actors::Actor::sprout(p)?)),
                    "e40" => Kind::Walker(Box::new(crate::actors::Actor::hopper(p)?)),
                    "e42" => Kind::Walker(Box::new(crate::actors::Actor::juggler(p)?)),
                    "e17" => Kind::Walker(Box::new(crate::actors::Actor::bulk(p)?)),
                    "e33" => Kind::Walker(Box::new(crate::actors::Actor::gust(p)?)),
                    "e13" => Kind::Walker(Box::new(crate::actors::Actor::spore(p)?)),
                    "e14" => Kind::Walker(Box::new(crate::actors::Actor::hang(p)?)),
                    "e25" => Kind::Walker(Box::new(crate::actors::Actor::spine(p)?)),
                    "e15" => Kind::Walker(Box::new(crate::actors::Actor::slime(p)?)),
                    "e16" => Kind::Walker(Box::new(crate::actors::Actor::bubble(p)?)),
                    "e36" => Kind::Walker(Box::new(crate::actors::Actor::thorn(p)?)),
                    "e43" => Kind::Walker(Box::new(crate::actors::Actor::bee(p)?)),
                    "e26" => Kind::Walker(Box::new(crate::actors::Actor::shy(p)?)),
                    "e39" => Kind::Walker(Box::new(crate::actors::Actor::blind(p)?)),
                    "e38" => Kind::DiscBlock(crate::disc::DiscBlock::new(p)?),
                    "d22" => Kind::SnowTree(crate::snow_tree::SnowTree::new(p)?),
                    // Name the code and form so sweeps can rank what is still missing.
                    _ => {
                        return Err(unsupported(&format!(
                            "entity {} F={} R={}",
                            p.code, p.variant, p.rotation
                        )))
                    }
                };
                // registry.gd compile: enemies and o11 springs each count their own family.
                let family_index = match kind {
                    Kind::Walker(ref a) if a.kind != crate::actors::ActorKind::Gust => {
                        next_family += 1;
                        next_family - 1
                    }
                    Kind::Pad(_) => {
                        next_pad += 1;
                        next_pad - 1
                    }
                    _ => 0,
                };
                let mut row = Entity::placed(source, p, kind, family_index);
                // item_block.gd prepare: an o24 sits 32 px above its placement.
                if let Kind::Block(b) = &row.kind {
                    row.body.y = b.home_y;
                }
                Ok(row)
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
        let spawn = if self.checkpoint.id != 0 {
            self.checkpoint.position
        } else {
            world.spawn
        };
        // life.gd _respawn: creation culling uses the respawn destination, not the old
        // death camera.
        self.entities = Self::spawn_map(
            world,
            Position {
                x: spawn.x,
                y: spawn.y - 28 * S,
            },
        )?;
        for (entity, flag) in self.entities.iter_mut().zip(flags) {
            entity.collected = flag;
            entity.checkpoint_collected = flag;
        }
        // item_egg/seed/element reset_map run in spawn_map, before Moves.reset clears
        // the request history, so they keep the serial from before the reset.
        self.consumers.reset_map(self.player.food.requests.serial());
        // item_block.gd reset_map and registry.gd modal_token.
        self.message = crate::blocks::Message::default();
        // timed_switch.gd reset_map.
        self.clock = crate::switch::Clock::default();
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
    /// step.gd _catch_events (Godot d9513bf): a companion catch (REJOIN) blocks world and
    /// body motion, not the player's input events. They run frozen, and any requests they
    /// emit are consumed at once so the saved request history cannot overflow.
    fn catch_events(&mut self, input: u8, map: &crate::body::Probe) -> Result<(), Error> {
        let pressed = input & !(self.player.previous_input as u8);
        let released = self.player.previous_input as u8 & !input;
        self.player.previous_input = input as i64;
        if self.player.captured_by != 0 {
            return Ok(());
        }
        let locked = self.player.locks_input();
        let action = if locked { 0 } else { input };
        let (pressed, released) = if locked { (0, 0) } else { (pressed, released) };
        let serial = self.player.food.requests.serial();
        self.player.advance(
            map,
            action,
            pressed,
            released,
            self.frame,
            &mut self.rng,
            true,
            &mut self.sound,
        );
        if self.player.food.requests.serial() != serial {
            // registry.gd consume_requests(frozen): held bodies, level consumers, then
            // entity consumers.
            self.consume_frozen_requests(map);
            self.block_level_requests();
            for action in self
                .consumers
                .run(&self.player.food.requests, self.player.food.eggs)?
            {
                self.apply_consumer(action)?;
            }
            self.consume_item_requests();
        }
        self.player.finish(map, action);
        Ok(())
    }
    fn entities_step(
        &mut self,
        map: &crate::body::Probe,
        stats: &mut crate::Stats,
    ) -> Result<(), Error> {
        let centre = screen_centre(self.camera, map.width_pixels * S, map.height_pixels * S);
        // mace_walker.gd on_remove runs inside every removal; with an e27 placed, each
        // step ends by dropping the balls of walkers it removed.
        let has_mace = map.placements.iter().any(|p| p.code == "e27");
        let mut next = 0;
        while next < self.entities.len() {
            let e = &mut self.entities[next];
            next += 1;
            if !matches!(
                e.kind,
                Kind::Pickup(_)
                    | Kind::Star(_)
                    | Kind::Walker(_)
                    | Kind::Post(_)
                    | Kind::Egg(_)
                    | Kind::Cache(_)
                    | Kind::Redirect(_)
                    | Kind::Block(_)
                    | Kind::Fall(_)
                    | Kind::Grow(_)
                    | Kind::Gate(_)
                    | Kind::Stem(_)
                    | Kind::StarFlower(_)
                    | Kind::Switch(_)
                    | Kind::Lift(_)
                    | Kind::Hound(_)
                    | Kind::Melon(_)
                    | Kind::Seed(_)
                    | Kind::Overlap(_)
                    | Kind::Launcher(_)
                    | Kind::Sack(_)
                    | Kind::EggBlock(_)
                    | Kind::Balloon(_)
                    | Kind::Dice(_)
                    | Kind::SpinSpan(_)
                    | Kind::SpinBlock(_)
                    | Kind::ElementShot(_)
                    | Kind::DiscBlock(_)
            ) {
                continue;
            }
            let waiting = e.status == 0;
            let awake = e.lifecycle(
                map,
                centre,
                crate::Position {
                    x: self.player.body.x,
                    y: self.player.body.y,
                },
                self.player.impact,
                &mut self.rng,
            )?;
            // blind_ghost.gd activate: sounds made before it woke up are not news to it.
            if waiting && e.status == 1 {
                if let Kind::Walker(w) = &mut e.kind {
                    if w.kind == crate::actors::ActorKind::Blind {
                        w.heard = self.sound.serial;
                    }
                }
            }
            if !awake {
                // dispatch_loops.gd: every member with a solid row refiles it after its
                // dispatch, so a solid that just woke (or left) changes the rows now.
                self.refresh_block_solid(next - 1, map);
                continue;
            }
            stats.entity_steps += 1;
            #[cfg(feature = "benchmark-work-counters")]
            stats.benchmark_stepped_source_rows.push(e.origin.placed());
            let token = e.origin.token();
            let after = match &mut e.kind {
                Kind::Post(_) => crate::eating::After::Nothing,
                Kind::Block(_) => crate::eating::After::BlockStep,
                Kind::Fall(_) => crate::eating::After::FallStep,
                Kind::Gate(_) => crate::eating::After::GateStep,
                Kind::Stem(_) => crate::eating::After::StemStep,
                Kind::StarFlower(_) => crate::eating::After::FlowerStep,
                Kind::Switch(_) => crate::eating::After::SwitchStep,
                Kind::Lift(_) => crate::eating::After::LiftStep,
                Kind::Melon(_) => crate::eating::After::MelonStep,
                Kind::Seed(_) => crate::eating::After::SeedStep,
                Kind::Hound(_) => crate::eating::After::HoundStep,
                Kind::Launcher(_) => crate::eating::After::LauncherStep,
                Kind::Sack(s) => {
                    s.step(&mut e.body, map);
                    crate::eating::After::Nothing
                }
                Kind::EggBlock(_) => crate::eating::After::EggBlockStep,
                Kind::Balloon(_) => crate::eating::After::BalloonStep,
                Kind::Dice(_) => crate::eating::After::DiceStep,
                Kind::SpinSpan(s) => {
                    s.step();
                    crate::eating::After::RefreshSolid
                }
                Kind::SpinBlock(_) => crate::eating::After::SpinBlockStep,
                Kind::Grow(g) => {
                    g.step();
                    crate::eating::After::RefreshSolid
                }
                Kind::Egg(_) => crate::eating::After::EggStep,
                Kind::Overlap(_) => crate::eating::After::OverlapStep,
                Kind::ElementShot(_) => crate::eating::After::ElementShotStep,
                Kind::DiscBlock(_) => crate::eating::After::DiscBlockStep,
                Kind::Cache(_) => crate::eating::After::CacheStep,
                Kind::Redirect(r) => {
                    r.step(&mut self.rng);
                    crate::eating::After::Nothing
                }
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
                Kind::Walker(w)
                    if [
                        crate::actors::ActorKind::Shell,
                        crate::actors::ActorKind::Runner,
                    ]
                    .contains(&w.kind) =>
                {
                    crate::eating::After::ShellStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Armored => {
                    crate::eating::After::ArmoredStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Spear => {
                    crate::eating::After::SpearStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Thief => {
                    crate::eating::After::ThiefStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Roller => {
                    crate::eating::After::RollerStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Shooter => {
                    crate::eating::After::ShooterStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Pellet => {
                    crate::eating::After::PelletStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::PetalStem => {
                    crate::eating::After::PetalStemStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Petal => {
                    crate::eating::After::PetalStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Spitter => {
                    crate::eating::After::SpitterStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Spike => {
                    crate::eating::After::SpikeStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::SoftWalker => {
                    crate::eating::After::SoftWalkerStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::SoftGiant => {
                    crate::eating::After::SoftGiantStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Helmet => {
                    crate::eating::After::HelmetStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Bumper => {
                    crate::eating::After::BumperStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Mace => {
                    crate::eating::After::MaceStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::MaceBall => {
                    crate::eating::After::MaceBallStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Wing => {
                    crate::eating::After::WingStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Shot => {
                    crate::eating::After::ShotStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Sprout => {
                    crate::eating::After::SproutStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Hopper => {
                    crate::eating::After::HopperStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Juggler => {
                    crate::eating::After::JugglerStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Bulk => {
                    crate::eating::After::BulkStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Gust => {
                    crate::eating::After::GustStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Spore => {
                    crate::eating::After::SporeStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Hang => {
                    crate::eating::After::HangStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Spine => {
                    crate::eating::After::SpineStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Slime => {
                    crate::eating::After::SlimeStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Bubble => {
                    crate::eating::After::BubbleStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Thorn => {
                    crate::eating::After::ThornStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Bee => {
                    crate::eating::After::BeeStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Shy => {
                    crate::eating::After::ShyStep
                }
                Kind::Walker(w) if w.kind == crate::actors::ActorKind::Blind => {
                    crate::eating::After::BlindStep
                }
                Kind::Walker(w) => {
                    #[cfg(debug_assertions)]
                    {
                        use crate::actors::ActorKind;
                        // The benchmark counters keep their e1,e2,e3,e5,e35 order.
                        let index = match w.kind {
                            ActorKind::Walker => Some(0),
                            ActorKind::Flyer => Some(1),
                            ActorKind::Flower => Some(2),
                            ActorKind::Plant => Some(3),
                            ActorKind::Stilt => Some(4),
                            ActorKind::Flat
                            | ActorKind::Shell
                            | ActorKind::Runner
                            | ActorKind::Armored
                            | ActorKind::Spear
                            | ActorKind::Thief
                            | ActorKind::Roller
                            | ActorKind::Shooter
                            | ActorKind::Pellet
                            | ActorKind::PetalStem
                            | ActorKind::Petal
                            | ActorKind::Spitter
                            | ActorKind::Spike
                            | ActorKind::SoftWalker
                            | ActorKind::SoftGiant
                            | ActorKind::Helmet
                            | ActorKind::Bumper
                            | ActorKind::Mace
                            | ActorKind::MaceBall
                            | ActorKind::Wing
                            | ActorKind::Shot
                            | ActorKind::Sprout
                            | ActorKind::Hopper
                            | ActorKind::Juggler
                            | ActorKind::Bulk
                            | ActorKind::Gust
                            | ActorKind::Spore
                            | ActorKind::Hang
                            | ActorKind::Spine
                            | ActorKind::Slime
                            | ActorKind::Fish
                            | ActorKind::LandFish
                            | ActorKind::Bubble
                            | ActorKind::Thorn
                            | ActorKind::Bee
                            | ActorKind::Shy
                            | ActorKind::Blind => None,
                        };
                        if let Some(index) = index {
                            stats.benchmark_actor_steps[index] += 1;
                        }
                    }
                    let mut context = crate::actors::ActorStep {
                        map,
                        frame: self.frame,
                        camera: self.camera,
                        player: &mut self.player,
                        rng: &mut self.rng,
                    };
                    let before = e.status;
                    let after = w.advance(
                        token,
                        &mut e.body,
                        &mut e.facing,
                        &mut e.status,
                        &mut e.can_respawn,
                        &mut context,
                    )?;
                    // enemy_body.gd remove runs actor.gd on_remove: an e5 removed in its own
                    // step (lava, a roll, a spit) lets go of the player it holds.
                    if before != 3 && e.status == 3 && w.kind == crate::actors::ActorKind::Plant {
                        let (facing, family) = (e.facing, e.family_index);
                        if self.player.captured_by == family + 1 {
                            if self.player.life.separated == 0 {
                                self.player.separate(-facing * 400 * 60, true);
                            }
                            w.mode = 5;
                            w.timer = 30;
                            let p = &mut self.player;
                            p.captured_by = 0;
                            p.life.invulnerable = 121;
                            p.life.hurt = 38;
                            p.life.hurt_phase = 1;
                            p.life.hurt_deceleration = 648;
                            p.body.vx = facing * 400 * 60;
                            p.body.vy = -384 * 60;
                            p.on_floor = 0;
                        }
                    }
                    after
                }
                _ => unreachable!("phase 0 members"),
            };
            match after {
                crate::eating::After::HitOthers(b) => {
                    self.hit_others(next - 1, b, crate::eating::HitKind::Spit, true)?
                }
                crate::eating::After::ConsumeItem => self.consume_item(next - 1),
                crate::eating::After::EggStep => self.egg_step(next - 1, map)?,
                crate::eating::After::CacheStep => self.cache_step(next - 1, centre)?,
                crate::eating::After::BlockStep => {
                    self.block_step(next - 1, centre)?;
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::RefreshSolid => self.refresh_block_solid(next - 1, map),
                crate::eating::After::StemStep => self.stem_step(next - 1, map, centre)?,
                crate::eating::After::FlowerStep => self.flower_step(next - 1)?,
                crate::eating::After::ShellStep => self.shell_step(next - 1, map)?,
                crate::eating::After::ArmoredStep => self.armored_step(next - 1, map)?,
                crate::eating::After::SpearStep => self.spear_step(next - 1, map)?,
                crate::eating::After::ThiefStep => self.thief_step(next - 1, map)?,
                crate::eating::After::RollerStep => self.roller_step(next - 1, map)?,
                crate::eating::After::ShooterStep => self.shooter_step(next - 1, map)?,
                crate::eating::After::PelletStep => self.pellet_step(next - 1, map),
                crate::eating::After::PetalStemStep => self.petal_stem_step(next - 1, map)?,
                crate::eating::After::PetalStep => self.petal_step(next - 1, map)?,
                crate::eating::After::SpitterStep => self.spitter_step(next - 1, map)?,
                crate::eating::After::SpikeStep => self.spike_step(next - 1, map)?,
                crate::eating::After::SoftWalkerStep => self.soft_walker_step(next - 1, map)?,
                crate::eating::After::SoftGiantStep => self.soft_giant_step(next - 1, map)?,
                crate::eating::After::HelmetStep => self.helmet_step(next - 1, map)?,
                crate::eating::After::BumperStep => self.bumper_step(next - 1, map)?,
                crate::eating::After::MaceStep => self.mace_step(next - 1, map)?,
                crate::eating::After::MaceBallStep => self.mace_ball_step(next - 1, map)?,
                crate::eating::After::OverlapStep => self.overlap_step(next - 1),
                crate::eating::After::WingStep => self.wing_step(next - 1, map)?,
                crate::eating::After::ShotStep => self.shot_step(next - 1, map)?,
                crate::eating::After::SproutStep => self.sprout_step(next - 1, map)?,
                crate::eating::After::HopperStep => self.hopper_step(next - 1, map)?,
                crate::eating::After::JugglerStep => self.juggler_step(next - 1, map)?,
                crate::eating::After::BulkStep => self.bulk_step(next - 1, map)?,
                crate::eating::After::GustStep => self.gust_step(next - 1, map)?,
                crate::eating::After::SporeStep => self.spore_step(next - 1, map)?,
                crate::eating::After::HangStep => self.hang_step(next - 1, map)?,
                crate::eating::After::SpineStep => self.spine_step(next - 1, map)?,
                crate::eating::After::SlimeStep => self.slime_step(next - 1, map)?,
                crate::eating::After::LauncherStep => {
                    self.launcher_step(next - 1)?;
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::BubbleStep => self.bubble_step(next - 1, map)?,
                crate::eating::After::ThornStep => self.thorn_step(next - 1, map)?,
                crate::eating::After::DiscBlockStep => {
                    self.disc_block_step(next - 1)?;
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::BeeStep => self.bee_step(next - 1, map)?,
                crate::eating::After::ShyStep => {
                    self.shy_step(next - 1, map)?;
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::BlindStep => self.blind_step(next - 1, map)?,
                crate::eating::After::ElementShotStep => self.element_shot_step(next - 1, map)?,
                crate::eating::After::SwitchStep => self.switch_step(next - 1, map),
                crate::eating::After::HoundStep => {
                    self.hound_step(next - 1, map)?;
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::LiftStep => {
                    self.lift_step(next - 1, map);
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::GateStep => {
                    self.gate_step(next - 1);
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::FallStep => {
                    self.fall_step(next - 1, map, centre);
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::MelonStep => self.melon_step(next - 1, map),
                crate::eating::After::SeedStep => self.seed_step(next - 1, map)?,
                crate::eating::After::SpinBlockStep => {
                    let e = &mut self.entities[next - 1];
                    if let Kind::SpinBlock(b) = &mut e.kind {
                        b.step(&mut e.body);
                    }
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::DiceStep => {
                    self.dice_step(next - 1);
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::BalloonStep => {
                    self.balloon_step(next - 1, map);
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::EggBlockStep => {
                    self.egg_block_step(next - 1)?;
                    self.refresh_block_solid(next - 1, map);
                }
                crate::eating::After::Nothing => {}
            }
            if has_mace {
                self.mace_on_remove();
            }
            if matches!(&self.entities[next - 1].kind, Kind::Walker(w) if [crate::actors::ActorKind::Flat, crate::actors::ActorKind::Bulk].contains(&w.kind))
            {
                self.refresh_block_solid(next - 1, map);
            }
        }
        // Captures skip phase 1 exactly as DispatchLoops.advance does.
        if self.player.captured_by != 0 {
            return Ok(());
        }
        // Step phase 1, still in saved table order: pads and orbit_disc.gd discs.
        for index in 0..self.entities.len() {
            let e = &mut self.entities[index];
            if matches!(e.kind, Kind::Disc(_)) {
                let awake = e.lifecycle(
                    map,
                    centre,
                    crate::Position {
                        x: self.player.body.x,
                        y: self.player.body.y,
                    },
                    self.player.impact,
                    &mut self.rng,
                )?;
                if awake {
                    stats.entity_steps += 1;
                    self.disc_step(index);
                }
                continue;
            }
            if !matches!(e.kind, Kind::Pad(_)) {
                continue;
            }
            let awake = e.lifecycle(
                map,
                centre,
                crate::Position {
                    x: self.player.body.x,
                    y: self.player.body.y,
                },
                self.player.impact,
                &mut self.rng,
            )?;
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
        // The step's solid rows start empty every step; only their buffers are reused.
        let solids = std::cell::RefCell::new(std::mem::take(&mut self.solid_scratch.0));
        let result = self.advance_with(input, world, stats, &solids);
        self.solid_scratch.0 = solids.into_inner();
        result
    }
    fn advance_with(
        &mut self,
        input: u8,
        world: &World,
        stats: &mut crate::Stats,
        solids: &std::cell::RefCell<crate::solids::SolidFrame>,
    ) -> Result<(), Error> {
        if self.goal_reached != 0 {
            return Ok(());
        }
        self.frame = self.frame.checked_add(1).ok_or_else(|| {
            unsupported("saved frame increment exceeds the admitted Stride state range")
        })?;
        // step.gd: an open message consumes the whole step.
        if self.modal_step(input, world)? {
            return Ok(());
        }
        solids.borrow_mut().begin(&self.entities);
        let map = crate::body::Probe::with_solids(&world.maps[0], solids);
        if self.player.life_phase == 0 {
            self.play_ticks = self.play_ticks.saturating_add(1);
            self.total_play_ticks = self.total_play_ticks.saturating_add(1);
            self.attempt_ticks = self.attempt_ticks.saturating_add(1);
            // step.gd (Godot 629ef5d): Collision.begin_step runs before Life.before_step, so
            // companion physics sees this frame's registered solids.
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
            if self.player.life_phase == 1 {
                self.catch_events(input, &map)?;
            }
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
                false,
                &mut self.sound,
            );
            self.apply_post_updates(map.post_updates())?;
            // collision.gd _bump side 0, deferred to the end of the player's move: the
            // head bumps reach item_block.gd bump in contact order.
            for (token, player) in map.head_bumps() {
                if let Some(i) = self.find_token(token) {
                    if matches!(self.entities[i].kind, Kind::EggBlock(_)) {
                        self.egg_block_bump(i)?;
                    } else if matches!(self.entities[i].kind, Kind::SpinBlock(_)) {
                        self.spin_block_trigger(i)?;
                    } else if matches!(self.entities[i].kind, Kind::Dice(_)) {
                        self.dice_bump(i, player, &map)?;
                    } else {
                        let centre =
                            screen_centre(self.camera, map.width_pixels * S, map.height_pixels * S);
                        self.block_bump(i, centre)?;
                    }
                    self.refresh_block_solid(i, &map);
                }
            }
            // Contact phase 0 precedes actors (phase 1), regardless of placement order:
            // pads and snow_tree.gd trees, in table order.
            for index in 0..self.entities.len() {
                if matches!(self.entities[index].kind, Kind::SnowTree(_)) {
                    if self.entities[index].status == 1 {
                        stats.contacts += 1;
                        self.snow_tree_contact(index, &map);
                    }
                    continue;
                }
                let e = &mut self.entities[index];
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
                if matches!(e.kind, Kind::Egg(_)) {
                    stats.contacts += 1;
                    self.egg_contact_player(index)?;
                    continue;
                }
                if let Kind::Cache(c) = &mut e.kind {
                    stats.contacts += 1;
                    let b = self.player.bounds();
                    let p = self.player.body;
                    c.contact(
                        e.body.x,
                        e.body.y,
                        e.collected,
                        [p.x + b[0], p.y + b[1], p.x + b[2], p.y + b[3]],
                    );
                    continue;
                }
                if matches!(e.kind, Kind::Fall(_)) {
                    stats.contacts += 1;
                    self.fall_contact(index);
                    continue;
                }
                if matches!(e.kind, Kind::Grow(_)) {
                    stats.contacts += 1;
                    self.grow_contact(index)?;
                    continue;
                }
                if matches!(e.kind, Kind::Lift(_)) {
                    stats.contacts += 1;
                    self.lift_contact(index);
                    continue;
                }
                if matches!(e.kind, Kind::Sack(_)) {
                    stats.contacts += 1;
                    if self.sack_contact(index) {
                        stats.damage_events += 1;
                    }
                    continue;
                }
                if matches!(e.kind, Kind::Balloon(_)) {
                    stats.contacts += 1;
                    self.balloon_contact(index);
                    continue;
                }
                if matches!(e.kind, Kind::Switch(_)) {
                    stats.contacts += 1;
                    self.switch_contact(index);
                    continue;
                }
                if matches!(e.kind, Kind::Ledge(_)) {
                    stats.contacts += 1;
                    self.ledge_contact(index);
                    self.refresh_block_solid(index, &map);
                    continue;
                }
                // orbit_disc.gd contact: touching a disc hurts.
                if matches!(e.kind, Kind::Disc(_)) {
                    stats.contacts += 1;
                    self.disc_contact(index);
                    continue;
                }
                // spike_pillar.gd contact: touching the spike edge is fatal.
                if let Kind::Pillar(pillar) = &e.kind {
                    stats.contacts += 1;
                    let b = self.player.bounds();
                    let p = self.player.body;
                    let spike = pillar.spike_box(e.body);
                    if self.player.captured_by == 0
                        && p.x + b[2] > spike[0]
                        && p.x + b[0] < spike[2]
                        && p.y + b[3] > spike[1]
                        && p.y + b[1] < spike[3]
                        && self.player.kill(3, false, &mut self.sound)
                    {
                        self.deaths = self.deaths.saturating_add(1);
                    }
                    continue;
                }
                // thorn_block.gd contact: any touch (2 px above the head) is fatal.
                if let Kind::Hard(h) = &e.kind {
                    if h.kind == crate::blocks::HardKind::Thorn {
                        stats.contacts += 1;
                        let b = self.player.bounds();
                        let p = self.player.body;
                        if self.player.captured_by == 0
                            && p.x + b[2] + S > e.body.x - 16 * S
                            && p.x + b[0] - S < e.body.x + 16 * S
                            && p.y + b[3] + S > e.body.y - 16 * S
                            && p.y + b[1] - 2 * S < e.body.y + 16 * S
                            && self.player.kill(3, false, &mut self.sound)
                        {
                            self.deaths = self.deaths.saturating_add(1);
                        }
                    }
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
                // element_reactions.gd frozen_contact runs first in every enemy contact;
                // lava_bubble.gd contact (frozen contact, then a hurting touch).
                if let Kind::Walker(w) = &e.kind {
                    if w.held != 1
                        && w.hidden != 1
                        && (w.frozen != 0 || w.kind == crate::actors::ActorKind::Bubble)
                    {
                        stats.contacts += 1;
                        if w.kind == crate::actors::ActorKind::Bubble {
                            self.bubble_contact(index, action)?;
                        } else {
                            self.frozen_contact(index, action)?;
                        }
                        continue;
                    }
                }
                let e = &mut self.entities[index];
                let Kind::Walker(w) = &mut e.kind else {
                    continue;
                };
                // DispatchLoops.contact skips held and hidden entities; actor.gd contact
                // also ignores spat bodies.
                if w.held == 1 || w.hidden == 1 {
                    continue;
                }
                stats.contacts += 1;
                if [
                    crate::actors::ActorKind::Shell,
                    crate::actors::ActorKind::Runner,
                ]
                .contains(&w.kind)
                {
                    self.shell_contact(index, action)?;
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Armored {
                    self.armored_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Spear {
                    self.spear_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Thief {
                    self.thief_contact(index, action, &map)?;
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Roller {
                    self.roller_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Shooter {
                    self.shooter_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Pellet {
                    self.pellet_contact(index);
                    continue;
                }
                // petal_stem.gd CONTACT_PHASE -1: no contact rule.
                if w.kind == crate::actors::ActorKind::PetalStem {
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Petal {
                    self.petal_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Spitter {
                    self.spitter_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Spike {
                    self.spike_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::SoftWalker {
                    self.soft_walker_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::SoftGiant {
                    self.soft_giant_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Helmet {
                    self.helmet_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Bumper {
                    self.bumper_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Mace {
                    self.mace_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::MaceBall {
                    self.mace_ball_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Wing {
                    self.wing_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Shot {
                    self.shot_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Sprout {
                    self.sprout_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Thorn {
                    self.thorn_contact(index, action)?;
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Bee {
                    self.bee_contact(index, action)?;
                    continue;
                }
                if [
                    crate::actors::ActorKind::Shy,
                    crate::actors::ActorKind::Blind,
                ]
                .contains(&w.kind)
                {
                    self.ghost_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Hopper {
                    self.hopper_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Juggler {
                    self.juggler_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Bulk {
                    self.bulk_contact(index)?;
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Gust {
                    self.gust_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Spore {
                    self.spore_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Hang {
                    self.hang_contact(index, action);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Spine {
                    self.spine_contact(index);
                    continue;
                }
                if w.kind == crate::actors::ActorKind::Slime {
                    self.slime_contact(index);
                    continue;
                }
                // flat_walker.gd contact: a spat body or a capture still runs it (and clears
                // its contact memory).
                if w.kind == crate::actors::ActorKind::Flat {
                    use crate::actors::{FLAT_FLAT, FLAT_FLATTEN};
                    let b = w.body_bounds(e.facing);
                    let pb = self.player.bounds();
                    // enemy_body.gd impact_on_top: a ground-pound landing on its top edge.
                    let pounding = [2, 3].contains(&self.player.action);
                    if self.player.impact != 0 && self.player.impact > w.impact_cursor {
                        w.impact_cursor = self.player.impact;
                        if pounding
                            && w.held == 0
                            && w.spat == 0
                            && self.player.impact_x + pb[2] > e.body.x + b[0]
                            && self.player.impact_x + pb[0] < e.body.x + b[2]
                            && (self.player.impact_y - (e.body.y + b[1])).abs() <= 1
                        {
                            w.remove(&mut e.status, &mut e.can_respawn);
                            continue;
                        }
                    }
                    // enemy_body.gd player_overlap: open edges; nothing hidden, held, spat
                    // or captured touches.
                    let p = self.player.body;
                    let touching = e.status == 1
                        && w.hidden == 0
                        && w.held == 0
                        && w.spat == 0
                        && self.player.captured_by == 0
                        && e.body.x + b[0] < p.x + pb[2]
                        && e.body.x + b[2] > p.x + pb[0]
                        && e.body.y + b[1] < p.y + pb[3]
                        && e.body.y + b[3] > p.y + pb[1];
                    if touching {
                        if e.body.y > p.y - 8 * S && w.contact == 0 {
                            if pounding {
                                w.remove(&mut e.status, &mut e.can_respawn);
                                w.contact = 1;
                                continue;
                            }
                            if w.mode < FLAT_FLATTEN {
                                self.player.enemy_bounce(
                                    e.body.vy,
                                    action,
                                    self.message.modal_token != 0,
                                    &mut self.sound,
                                );
                            }
                            w.timer = if w.mode == FLAT_FLAT { 63 } else { 65 };
                            w.mode = FLAT_FLATTEN;
                            e.body.vx = 0;
                        } else if w.mode < FLAT_FLATTEN
                            && e.body.y < p.y - 8 * S
                            && self.player.hurt(e.body.x, &mut self.sound)
                        {
                            stats.damage_events += 1;
                        }
                    }
                    w.contact = i64::from(touching);
                    continue;
                }
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
                            self.player.enemy_bounce(
                                e.body.vy,
                                action,
                                self.message.modal_token != 0,
                                &mut self.sound,
                            );
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
                    let b = match &e.kind {
                        // enemy_pellet.gd, petal_stem.gd and mace_ball.gd GOAL_COIN is false.
                        Kind::Walker(w)
                            if [
                                crate::actors::ActorKind::Pellet,
                                crate::actors::ActorKind::PetalStem,
                                crate::actors::ActorKind::MaceBall,
                            ]
                            .contains(&w.kind) =>
                        {
                            continue
                        }
                        Kind::Walker(w) => w.bounds(e.body, e.facing),
                        _ => continue,
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
            if world.maps[0].placements.iter().any(|p| p.code == "e27") {
                self.mace_on_remove();
            }
            // registry.gd tongue_contact, in table order (eating.rs).
            if let Some(sensor) = self.player.tongue_box() {
                self.tongue_contact(sensor);
            }
            if let Some(reach) = self.player.tongue_reach() {
                self.player.catch_companion(reach);
            }
        }
        // registry.gd consume_requests: level-wide consumers (item_block.gd first, in
        // registry order), then entity consumers.
        self.block_level_requests();
        for action in self
            .consumers
            .run(&self.player.food.requests, self.player.food.eggs)?
        {
            self.apply_consumer(action)?;
        }
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
    /// A level or player field of the saved state by its saved name, as play_state.gd
    /// keeps them in one flat dictionary. None when the state has no such field.
    pub fn saved_field(&self, n: &str, world: &World) -> Option<i64> {
        self.player_value(n).or_else(|| self.level_value(n, world))
    }
    /// A saved field of one entity row by its saved name.
    pub fn saved_entity_field(&self, e: &Entity, n: &str, world: &World) -> Option<i64> {
        self.entity_value(e, n, world)
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
        if let Some(value) = self.message.field(n) {
            return Some(value);
        }
        if let Some(value) = self.clock.field(n) {
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
            Kind::Hound(p) => p.field(n),
            Kind::Post(p) => p.field(n),
            Kind::Block(p) => p.field(n),
            Kind::Span(p) => p.field(n),
            Kind::Hard(p) => (n == "form").then_some(p.form),
            Kind::Fall(p) => p.field(n),
            Kind::Grow(p) => p.field(n),
            Kind::Gate(p) => p.field(n),
            Kind::Ledge(p) => p.field(n),
            Kind::Stem(p) => p.field(n),
            Kind::StarFlower(p) => p.field(n),
            Kind::Switch(p) => p.field(n),
            Kind::Lift(p) => p.field(n),
            Kind::Launcher(p) => p.field(n),
            Kind::Sack(p) => p.field(n),
            Kind::Egg(p) => p.field(n),
            Kind::Cache(p) => p.field(n),
            Kind::Redirect(p) => p.field(n),
            Kind::Melon(p) => p.field(n),
            Kind::Seed(p) => p.field(n),
            Kind::Overlap(p) => p.field(n),
            Kind::EggBlock(p) => p.field(n),
            Kind::Pillar(p) => p.field(n),
            Kind::Balloon(p) => p.field(n),
            Kind::Dice(p) => p.field(n),
            Kind::SpinSpan(p) => p.field(n),
            Kind::SpinBlock(p) => p.field(n),
            Kind::Platform(p) => p.field(n),
            Kind::Lamp(p) => p.field(n),
            Kind::ElementShot(p) => p.field(n),
            Kind::DiscBlock(p) => p.field(n),
            Kind::SnowTree(p) => p.field(n),
            Kind::Disc(p) => p.field(n),
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
        // Each condition is named, so a refusal says which part of the state left the
        // implemented range.
        let outside: Vec<&str> = [
            ("self.frame < 0", self.frame < 0),
            ("self.play_ticks < 0", self.play_ticks < 0),
            ("self.total_play_ticks < self.play_ticks", self.total_play_ticks < self.play_ticks),
            ("self.attempt_ticks < 0", self.attempt_ticks < 0),
            ("self.coins < 0", self.coins < 0),
            ("self.redcoins < 0", self.redcoins < 0),
            ("self.flowers < 0", self.flowers < 0),
            ("self.deaths < 0", self.deaths < 0),
            ("!(0..=1).contains(&self.goal_reached)", !(0..=1).contains(&self.goal_reached)),
            ("![-1, 1].contains(&p.facing)", ![-1, 1].contains(&p.facing)),
            ("!(0..=1).contains(&p.on_floor)", !(0..=1).contains(&p.on_floor)),
            ("p.captured_by < 0", p.captured_by < 0),
            ("p.captured_by > self.entities.iter().filter(|e| e.is_enemy()).count() as i64", p.captured_by > self.entities.iter().filter(|e| e.is_enemy()).count() as i64),
            ("p.support_bridge < 0", p.support_bridge < 0),
            ("p.support_bridge > world.maps[0].bridges.len() as i64", p.support_bridge > world.maps[0].bridges.len() as i64),
            ("!(0..=6).contains(&p.movement)", !(0..=6).contains(&p.movement)),
            ("!(0..=255).contains(&p.previous_input)", !(0..=255).contains(&p.previous_input)),
            ("!(0..=255).contains(&p.pressed_input)", !(0..=255).contains(&p.pressed_input)),
            ("!(0..=11).contains(&p.action)", !(0..=11).contains(&p.action)),
            ("![0, 1].contains(&p.duck)", ![0, 1].contains(&p.duck)),
            ("![0, 1].contains(&p.look)", ![0, 1].contains(&p.look)),
            ("!(0..=9).contains(&p.posture_tick)", !(0..=9).contains(&p.posture_tick)),
            ("!p.food.valid(p.water.swimming, p.duck)", !p.food.valid(p.water.swimming, p.duck)),
            ("!(0..=position_limit).contains(&p.impact)", !(0..=position_limit).contains(&p.impact)),
            ("!p.tongue.valid(p.action)", !p.tongue.valid(p.action)),
            ("!p.water.valid()", !p.water.valid()),
            ("![0, 1].contains(&p.action_wet)", ![0, 1].contains(&p.action_wet)),
            ("p.action_tick < 0", p.action_tick < 0),
            ("p.action_tick >= match p.action { 1 => 24, 4 => p.tongue_end_tick(), 5 | 9 => 10, 6 => 25, 8 => 13, 10 => 4, 11 => 35, _", p.action_tick >= match p.action { 1 => 24, 4 => p.tongue_end_tick(), 5 | 9 => 10, 6 => 25, 8 => 13, 10 => 4, 11 => 35, _ => 36, }),
            ("!(0..=6).contains(&p.jump_buffer)", !(0..=6).contains(&p.jump_buffer)),
            ("!(0..=72).contains(&p.flutter_remaining)", !(0..=72).contains(&p.flutter_remaining)),
            ("!(0..=17).contains(&p.flutter_cooldown)", !(0..=17).contains(&p.flutter_cooldown)),
            ("!(0..=1).contains(&p.flutter_ready)", !(0..=1).contains(&p.flutter_ready)),
            ("!(0..=1).contains(&p.boosted_flutter)", !(0..=1).contains(&p.boosted_flutter)),
            ("!(0..=24).contains(&p.gravity_tick)", !(0..=24).contains(&p.gravity_tick)),
            ("!(0..=2).contains(&p.bounce)", !(0..=2).contains(&p.bounce)),
            ("!(0..=1).contains(&p.jump_carry)", !(0..=1).contains(&p.jump_carry)),
            ("![-1, 0, 1].contains(&p.turn)", ![-1, 0, 1].contains(&p.turn)),
            ("!(0..=30).contains(&p.turn_ticks)", !(0..=30).contains(&p.turn_ticks)),
            ("!(0..=6).contains(&p.pound_delay)", !(0..=6).contains(&p.pound_delay)),
            ("!(0..=1).contains(&p.push)", !(0..=1).contains(&p.push)),
            ("!p.life.valid(p.life_phase, p.life_ticks)", !p.life.valid(p.life_phase, p.life_ticks)),
            ("(p.life_phase == 0 && p.life_ticks != 0)", (p.life_phase == 0 && p.life_ticks != 0)),
            ("(p.life_phase == 8) != (self.goal_reached != 0)", (p.life_phase == 8) != (self.goal_reached != 0)),
            ("!(-2000 * 60..=2000 * 60).contains(&p.body.vx)", !(-2000 * 60..=2000 * 60).contains(&p.body.vx)),
            ("p.body.vy < -2000 * 60", p.body.vy < -2000 * 60),
            // Bodies like bump_walker.gd push the player past the fall caps (Godot reaches
            // 44512 on 64eb684c), so only the speed range bounds the fall.
            ("p.body.vy > 2000 * 60", p.body.vy > 2000 * 60),
            ("self.sound.serial < 0", self.sound.serial < 0),
            ("!(0..=4).contains(&self.sound.kind)", !(0..=4).contains(&self.sound.kind)),
        ]
        .into_iter()
        .filter_map(|(name, bad)| bad.then_some(name))
        .collect();
        if !outside.is_empty() {
            return Err(Error::Unsupported {
                requirements: outside
                    .iter()
                    .map(|n| format!("state outside implemented Stride semantics: {n}"))
                    .collect(),
            });
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
        if !self.clock.valid() {
            return Err(unsupported("switch clock"));
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
            if e.is_enemy() {
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
            if let Kind::Grow(g) = &e.kind {
                if !g.valid() {
                    return Err(unsupported("grow block fields"));
                }
            }
            if let Kind::Gate(g) = &e.kind {
                if !g.valid() {
                    return Err(unsupported("gate fields"));
                }
            }
            if let Kind::Hound(h) = &e.kind {
                if !h.valid(e.body) {
                    return Err(unsupported("runner fields"));
                }
            }
            if let Kind::Lift(l) = &e.kind {
                if !l.valid() {
                    return Err(unsupported("wheel fields"));
                }
            }
            if let Kind::Melon(m) = &e.kind {
                if !m.valid(serial) {
                    return Err(unsupported("melon fields"));
                }
            }
            if matches!(&e.kind, Kind::Lamp(l) if !l.valid()) {
                return Err(unsupported("lamp fields"));
            }
            if matches!(&e.kind, Kind::Platform(p) if !p.valid()) {
                return Err(unsupported("scenery ledge fields"));
            }
            if matches!(&e.kind, Kind::SpinSpan(s) if !s.valid())
                || matches!(&e.kind, Kind::SpinBlock(b) if !b.valid(e.body.y))
            {
                return Err(unsupported("turning span fields"));
            }
            if matches!(&e.kind, Kind::Dice(d) if !d.valid(e.body.y)) {
                return Err(unsupported("dice block fields"));
            }
            if matches!(&e.kind, Kind::Balloon(b) if !b.valid()) {
                return Err(unsupported("balloon fields"));
            }
            if matches!(&e.kind, Kind::Pillar(p) if !p.valid()) {
                return Err(unsupported("spike pillar fields"));
            }
            if let Kind::EggBlock(b) = &e.kind {
                if !b.valid(e.body.y) {
                    return Err(unsupported("egg block fields"));
                }
            }
            if let Kind::Seed(s) = &e.kind {
                if !s.valid() || e.origin.placed().is_some() {
                    return Err(unsupported("seed fields"));
                }
            }
            if let Kind::Sack(s) = &e.kind {
                if !s.valid() {
                    return Err(unsupported("sack fields"));
                }
            }
            if let Kind::Launcher(l) = &e.kind {
                if !l.valid() {
                    return Err(unsupported("launcher fields"));
                }
            }
            if let Kind::Switch(s) = &e.kind {
                if !s.valid() {
                    return Err(unsupported("switch fields"));
                }
            }
            if let Kind::StarFlower(f) = &e.kind {
                if !f.valid() {
                    return Err(unsupported("star flower fields"));
                }
            }
            if let Kind::Stem(s) = &e.kind {
                if !s.valid(e.body) {
                    return Err(unsupported("producer fields"));
                }
            }
            if let Kind::Ledge(l) = &e.kind {
                if !l.valid() {
                    return Err(unsupported("countdown ledge fields"));
                }
            }
            if let Kind::Fall(f) = &e.kind {
                if !f.valid(e.body.vy) {
                    return Err(unsupported("falling span fields"));
                }
            }
            if let Kind::Hard(h) = &e.kind {
                if !(0..=h.last_form()).contains(&h.form) {
                    return Err(unsupported("hard block form"));
                }
            }
            if let Kind::Span(s) = &e.kind {
                if !s.valid() {
                    return Err(unsupported("span fields"));
                }
            }
            if let Kind::Block(b) = &e.kind {
                if !b.valid() {
                    return Err(unsupported("item block fields"));
                }
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
                    || p.origin_token < 0
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
                    || p.origin_token < 0
                    || !(-1024 * 60..=1024 * 60).contains(&e.body.vx)
                    || !(-1024 * 60..=1024 * 60).contains(&e.body.vy)
                {
                    return Err(unsupported("health-drop state/request path"));
                }
            }
            if let Kind::Egg(egg) = &e.kind {
                if !egg.valid(e.body) {
                    return Err(unsupported("egg validation"));
                }
            }
            if matches!(&e.kind, Kind::SnowTree(t) if !t.valid()) {
                return Err(unsupported("snow tree fields"));
            }
            if matches!(&e.kind, Kind::DiscBlock(b) if !b.valid())
                || matches!(&e.kind, Kind::Disc(d) if !d.valid() || e.origin.placed().is_some())
            {
                return Err(unsupported("disc block fields"));
            }
            if matches!(&e.kind, Kind::ElementShot(shot) if !shot.valid() || e.origin.placed().is_some())
            {
                return Err(unsupported("element shot validation"));
            }
            if matches!(&e.kind, Kind::Cache(c) if !c.valid())
                || matches!(&e.kind, Kind::Redirect(r) if !r.valid())
            {
                return Err(unsupported("cloud validation"));
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
                    || (w.kind == crate::actors::ActorKind::Blind && !w.blind_valid(e.body))
                    || (w.kind == crate::actors::ActorKind::Hopper && !w.hopper_valid(e.body.vx))
                    || !(0..=360).contains(&w.phase)
                    || (!(0..=if w.kind == crate::actors::ActorKind::PetalStem {
                        318
                    } else {
                        210
                    })
                        .contains(&w.timer)
                        && w.kind != crate::actors::ActorKind::Bubble)
                    || !(-1..=180).contains(&w.cycles)
                    || !(0..=match w.kind {
                        crate::actors::ActorKind::Flat => 6,
                        crate::actors::ActorKind::Shell | crate::actors::ActorKind::Runner => {
                            crate::shell::UP_SPIT
                        }
                        crate::actors::ActorKind::Armored => crate::armored::RECOVER,
                        _ => 5,
                    })
                        .contains(&w.mode)
                    || (w.held != 0 && w.spat != 0)
                    // An exhausted fish (enemy_fish.gd fish_finish) is hidden for good.
                    || (w.hidden != 0
                        && w.fish_exhausted == 0
                        && w.kind != crate::actors::ActorKind::Bubble
                        && !(w.kind == crate::actors::ActorKind::Slime
                            && w.phase == crate::slime::HANG))
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
"move_action"=>action,"move_action_tick"=>action_tick,"move_turn"=>turn,"move_turn_ticks"=>turn_ticks,"move_push"=>push,"move_pound_delay"=>pound_delay,"move_gravity_tick"=>gravity_tick,"move_bounce"=>bounce,"move_brake_vx"=>brake_vx,"move_snow"=>snow,"move_jump_carry"=>jump_carry,
"life_phase"=>life_phase,"life_ticks"=>life_ticks,"recovery_x"=>recovery_x,"recovery_y"=>recovery_y,"goal_from_x"=>goal_from_x,"goal_from_y"=>goal_from_y,"goal_x"=>goal_x,"goal_y"=>goal_y
}

#[cfg(test)]
mod catch_event_tests {
    use super::*;

    #[test]
    fn step_catch_events_read_input_during_the_rejoin_freeze() {
        let level = serde_json::json!({
            "version":"s3.8", "name":"rejoin", "desc":"", "author":"test",
            "startpoint":{"map":1, "X":128, "Y":128},
            "maps":{"map1":{"width":4096, "height":2048, "objects":{}}}
        })
        .to_string();
        let world = World::compile(
            &level,
            include_str!("../../../../data/collision_table.json"),
        )
        .unwrap();
        let mut stats = crate::Stats::default();
        let mut run = Run::create(&world, &mut stats).unwrap();
        run.player.life_phase = 1;
        run.player.life_ticks = 51;
        run.player.body.vy = -400 * 60;
        run.player.on_floor = 0;
        let (x, y) = (run.player.body.x, run.player.body.y);
        // A jump press is buffered without elapsed time; the body does not move.
        run.advance(4, &world, &mut stats).unwrap();
        assert_eq!(run.player.previous_input, 4);
        assert_eq!(run.player.jump_buffer, 6);
        assert_eq!((run.player.body.x, run.player.body.y), (x, y));
        // Releasing jump while rising still cuts the rise, and the buffer does not count down.
        run.advance(0, &world, &mut stats).unwrap();
        assert_eq!(run.player.previous_input, 0);
        assert_eq!(run.player.body.vy, -100 * 60);
        assert_eq!(run.player.jump_buffer, 6);
        assert_eq!(run.player.life_phase, 1);
    }

    #[test]
    fn flat_walker_contact_clears_its_memory_while_spat_over_the_player() {
        let level = serde_json::json!({
            "version":"s3.8", "name":"flat", "desc":"", "author":"test",
            "startpoint":{"map":1, "X":128, "Y":128},
            "maps":{"map1":{"width":4096, "height":2048, "objects":{
                "f":{"A":"e4", "X":140, "Y":128}
            }}}
        })
        .to_string();
        let world = World::compile(
            &level,
            include_str!("../../../../data/collision_table.json"),
        )
        .unwrap();
        let mut stats = crate::Stats::default();
        let mut run = Run::create(&world, &mut stats).unwrap();
        let e = &mut run.entities[0];
        e.status = 1;
        e.body = run.player.body;
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        w.spat = 1;
        w.contact = 1;
        run.advance(0, &world, &mut stats).unwrap();
        let Kind::Walker(w) = &run.entities[0].kind else {
            unreachable!()
        };
        assert_eq!(w.contact, 0);
    }
}
