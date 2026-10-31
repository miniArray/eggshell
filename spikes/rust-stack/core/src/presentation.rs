//! Pure semantic sampling. Pack frame binding and screen planning stay in the player.
#[cfg(test)]
#[path = "presentation_policy_tests.rs"]
mod policy_tests;
use crate::{entity::Kind, state::Run, *};
#[derive(Clone, Debug)]
pub(crate) struct Previous {
    pub player: Position,
    pub companion: Position,
    pub follow: Position,
    /// The previous state's entity rows, moved (not copied) from that state.
    /// Looked up by token only for the rows a picture samples.
    entities: Vec<crate::entity::Entity>,
    placed: usize,
    pub rescuers: [Position; 4],
}
impl Previous {
    pub fn of(run: &Run, placed: usize) -> Self {
        Self::from_entities(run, run.entities.clone(), placed)
    }
    /// Takes the finished state's rows without copying them.
    pub fn from_run(mut run: Run, placed: usize) -> Self {
        let entities = std::mem::take(&mut run.entities);
        Self::from_entities(&run, entities, placed)
    }
    fn from_entities(run: &Run, entities: Vec<crate::entity::Entity>, placed: usize) -> Self {
        Self {
            player: pos(run.player.body),
            companion: Position {
                x: run.player.recovery_x,
                y: run.player.recovery_y,
            },
            follow: run.camera,
            entities,
            placed,
            rescuers: run.player.life.rescuers,
        }
    }
    pub fn into_entities(self) -> Vec<crate::entity::Entity> {
        self.entities
    }
    /// Same result as the former token map: position and plant head box of the
    /// previous row with this token, or None when the token did not exist.
    pub fn entity(&self, token: i64) -> Option<(Position, Option<[i64; 4]>)> {
        let row = |e: &crate::entity::Entity| {
            let head = match &e.kind {
                Kind::Walker(w)
                    if w.kind == crate::actors::ActorKind::Plant && w.head_size != 0 =>
                {
                    Some(w.head_box(e.body, e.facing))
                }
                _ => None,
            };
            (pos(e.body), head)
        };
        // Placed token t lives at index t-1 in a validated state.
        if token >= 1 && token <= self.placed as i64 {
            if let Some(e) = self.entities.get(token as usize - 1) {
                if e.origin.token() == token {
                    return Some(row(e));
                }
            }
        } else if let Some(runtime) = self.entities.get(self.placed..) {
            if let Ok(i) = runtime.binary_search_by_key(&token, |e| e.origin.token()) {
                if runtime[i].origin.token() == token {
                    return Some(row(&runtime[i]));
                }
            }
        }
        // Fallback for any layout the fast paths do not cover.
        self.entities
            .iter()
            .rev()
            .find(|e| e.origin.token() == token)
            .map(row)
    }
}
fn pos(b: crate::body::Body) -> Position {
    Position { x: b.x, y: b.y }
}
fn item_alpha(remaining: i64) -> f64 {
    let period = if remaining < 120 { 6 } else { 12 };
    if remaining > 0 && remaining < 240 && remaining % period >= period / 2 {
        0.0
    } else {
        1.0
    }
}
fn pickup_visual(p: &crate::items::Pickup, collected: i64) -> VisualState {
    let flower = p.kind == crate::items::PickupKind::Flower;
    let red = p.kind == crate::items::PickupKind::RedCoin;
    let animation = if flower {
        "Animation 1"
    } else if collected != 0 {
        "RedCollected"
    } else if p.enabled == 0 {
        if red {
            "RedDotted"
        } else {
            "Dotted"
        }
    } else if red {
        "Red"
    } else {
        "Yellow"
    };
    VisualState {
        animation: Some(animation.into()),
        frame: Some(if flower { 0 } else { p.phase * 8 / 60 % 4 }),
        rotation_degrees: Some(if flower {
            crate::math::sine(p.phase, 60, 10000).expect("bounded flower sway") as f64 / 1000.0
        } else {
            0.0
        }),
        alpha: item_alpha(p.despawn_ticks),
        ..VisualState::default()
    }
}
fn actor_visual(w: &crate::actors::Actor, body: crate::body::Body, facing: i64) -> VisualState {
    use crate::actors::ActorKind;
    // hanging_roller.gd and enemy_pellet.gd have no view_state.
    if [ActorKind::Roller, ActorKind::Pellet].contains(&w.kind) {
        return VisualState::default();
    }
    if w.kind == ActorKind::Shot {
        // launcher_shot.gd view_state
        let (animation, rotation) = w.shot_view();
        return VisualState {
            animation: Some(animation),
            rotation_degrees: Some(rotation),
            ..VisualState::default()
        };
    }
    if [ActorKind::Hopper, ActorKind::Juggler].contains(&w.kind) {
        // spike_hopper.gd / needle_juggler.gd view_state
        return VisualState {
            animation: Some(
                match (w.kind, w.colour) {
                    (ActorKind::Juggler, _) => "Default",
                    (_, 0) => "Green",
                    _ => "Yellow",
                }
                .into(),
            ),
            frame: (w.kind == ActorKind::Juggler).then_some(w.frame),
            ..VisualState::default()
        };
    }
    if w.kind == ActorKind::Gust {
        // gust_flyer.gd view_state
        let (rotation, flip) = w.gust_view();
        return VisualState {
            rotation_degrees: Some(rotation),
            flip_h: Some(flip),
            ..VisualState::default()
        };
    }
    if w.kind == ActorKind::Bulk {
        // leap_bulk.gd view_state
        return VisualState {
            size_pixels: [None, w.bulk_height()],
            ..VisualState::default()
        };
    }
    if w.kind == ActorKind::Sprout {
        // hop_sprout.gd view_state
        let (animation, frame) = w.sprout_view(body);
        return VisualState {
            animation: Some(animation.into()),
            frame,
            ..VisualState::default()
        };
    }
    if w.kind == ActorKind::Stilt {
        return VisualState {
            size_pixels: [None, Some(w.height as f64 / SCALE as f64)],
            ..VisualState::default()
        };
    }
    let animation = match w.kind {
        ActorKind::Walker | ActorKind::Flyer => {
            if w.roll != 0 {
                "Roll".into()
            } else {
                format!(
                    "{}{}",
                    w.variant,
                    if w.kind == ActorKind::Flyer && w.ground_form == 0 {
                        "Fly"
                    } else if w.mode == 0 {
                        "Idle"
                    } else {
                        "Walk"
                    }
                )
            }
        }
        ActorKind::Stilt => unreachable!("stilt samples a size, not actor animation"),
        // flat_walker.gd view_state
        ActorKind::Flat => {
            if w.mode == crate::actors::FLAT_AIR && body.vy >= 0 {
                "Fall".into()
            } else {
                [
                    "Walk",
                    "PrepareJump",
                    "Jump",
                    "Idle",
                    "Squash",
                    "SquashWalk",
                    "Unsquash",
                ][w.mode.clamp(0, 6) as usize]
                    .into()
            }
        }
        // shell_walker.gd view_state
        ActorKind::Shell | ActorKind::Runner => w.shell_animation(),
        // armored_walker.gd view_state
        ActorKind::Armored => w.armored_animation(),
        // spear_guard.gd view_state
        ActorKind::Spear => w.spear_animation(),
        // sneak_thief.gd view_state
        ActorKind::Thief => w.thief_animation().into(),
        ActorKind::Roller | ActorKind::Pellet => unreachable!("no view_state"),
        // masked_shooter.gd view_state
        ActorKind::Shooter => w.shooter_animation().into(),
        // wing_drifter.gd view_state
        ActorKind::Wing => w.wing_animation().into(),
        ActorKind::Shot
        | ActorKind::Sprout
        | ActorKind::Hopper
        | ActorKind::Juggler
        | ActorKind::Bulk
        | ActorKind::Gust => {
            unreachable!("returns its own view above")
        }
        // actor.gd view_state
        ActorKind::Fish | ActorKind::LandFish => w.fish_animation(body, facing).into(),
        ActorKind::Flower => {
            if w.mode != 0 {
                "turn".into()
            } else {
                "walk".into()
            }
        }
        ActorKind::Plant => {
            if w.mode != 0 {
                "active".into()
            } else {
                "idle".into()
            }
        }
    };
    VisualState {
        animation: Some(animation),
        flip_v: if w.kind == ActorKind::Plant && w.variant == 1 {
            Some(true)
        } else {
            None
        },
        head_box: if w.kind == ActorKind::Plant && w.head_size != 0 {
            Some(w.head_box(body, facing))
        } else {
            None
        },
        ..VisualState::default()
    }
}
fn actor_visible(e: &crate::entity::Entity) -> bool {
    let Kind::Walker(w) = &e.kind else {
        return false;
    };
    let eligible = w.held == 0 && w.hidden == 0;
    let inactive =
        e.origin.placed().is_some() && (e.status == 0 || (e.status == 2 && e.can_respawn != 0));
    eligible && (e.status == 1 || inactive)
}
/// The original stilt walker (YFS Enemies sheet, StiltGuyCollision events): StiltGuy_Feet at
/// the body, a StiltGuy_PolesMiddle strip on the feet's top grown to height-68 px, and
/// StiltGuy_Top on the poles. Feet play "Walk" (12 frames, 20 fps) once per stride and the
/// poles copy the feet frame; the top advances one of its 24 frames per feet frame. Knocked:
/// feet and poles frame 9, top frame 21. The Godot port drew the still editor image instead.
/// Colours: the player recolours the parts per variant from the pack's e1 colour frames.
fn stilt_parts(e: &crate::entity::Entity, visible: bool) -> Vec<EntityAuxiliaryPicture> {
    let Kind::Walker(w) = &e.kind else {
        return Vec::new();
    };
    if w.kind != crate::actors::ActorKind::Stilt {
        return Vec::new();
    }
    let knocked = w.phase == 1;
    // stride counts 36 ticks per step (72 in water); three ticks per feet frame.
    let feet = if knocked { 9 } else { (w.stride / 3).min(11) };
    let parity = (e.body.x.div_euclid(24 * SCALE)) & 1;
    let top = if knocked {
        21
    } else {
        (feet + 12 * parity) % 24
    };
    let poles = (w.height / SCALE - 68).max(0);
    let flip = if e.facing > 0 { -1.0 } else { 1.0 };
    let part = |kind, key: &str, y: i64, frame: i64, height: Option<f64>, shown: bool| {
        let at = Position { x: e.body.x, y };
        EntityAuxiliaryPicture {
            kind,
            scale: [flip, 1.0],
            picture: AuxiliaryPicture {
                motion: motion(at, at),
                visible: shown,
                layer: 10,
                facing: e.facing,
                animation: String::new(),
                tick: 0,
                visual: VisualState {
                    asset_key: Some(key.into()),
                    frame: Some(frame),
                    size_pixels: [None, height],
                    ..VisualState::default()
                },
            },
        }
    };
    let feet_top = e.body.y - 30 * SCALE;
    vec![
        part(
            EntityAuxiliaryKind::StiltFeet,
            "StiltGuy_Feet",
            e.body.y,
            feet,
            None,
            visible,
        ),
        part(
            EntityAuxiliaryKind::StiltPoles,
            "StiltGuy_PolesMiddle",
            feet_top,
            feet,
            Some(poles as f64),
            visible && poles > 0,
        ),
        part(
            EntityAuxiliaryKind::StiltTop,
            "StiltGuy_Top",
            feet_top - poles * SCALE,
            top,
            None,
            visible,
        ),
    ]
}
/// The plant head as the original draws it (Enemies sheet, PiranhaPlantHead): the 64x54 head
/// art pivots at its origin (2,20) on the stem top, turned toward its aim (head_dx/dy), scaled
/// by head_size, and flipped vertically when facing right so it never turns upside down.
/// The saved head_box hull (Godot's view, used by the oracle) stays in visual.head_box.
/// The Godot port stretched the unrotated art over that hull instead.
fn plant_head(
    e: &crate::entity::Entity,
    _previous: Option<[i64; 4]>,
    frame: i64,
) -> Vec<EntityAuxiliaryPicture> {
    let Kind::Walker(w) = &e.kind else {
        return Vec::new();
    };
    if w.kind != crate::actors::ActorKind::Plant || w.head_size == 0 {
        return Vec::new();
    }
    let at = Position {
        x: e.body.x + e.facing * 2 * SCALE,
        y: w.pivot(e.body),
    };
    let width = (16 * SCALE + 48 * SCALE * w.head_size / 15) as f64 / SCALE as f64;
    let height = (16 * SCALE + 38 * SCALE * w.head_size / 15) as f64 / SCALE as f64;
    let angle = if w.head_dx == 0 && w.head_dy == 0 {
        if e.facing > 0 {
            0.0
        } else {
            180.0
        }
    } else {
        (w.head_dy as f64).atan2(w.head_dx as f64).to_degrees()
    };
    vec![EntityAuxiliaryPicture {
        kind: EntityAuxiliaryKind::PlantHead,
        scale: [
            width / 64.0,
            height / 54.0 * if e.facing > 0 { -1.0 } else { 1.0 },
        ],
        picture: AuxiliaryPicture {
            motion: motion(at, at),
            visible: e.status == 1 && e.collected == 0 && w.held == 0 && w.hidden == 0,
            layer: 10,
            facing: e.facing,
            animation: String::new(),
            tick: frame,
            visual: VisualState {
                asset_key: Some("e5_head".into()),
                rotation_degrees: Some(angle),
                ..VisualState::default()
            },
        },
    }]
}
fn pad_visual(large: bool, remaining: i64) -> VisualState {
    let size = if large { 48.0 } else { 32.0 };
    let squash = remaining.min(12 - remaining) as f64;
    VisualState {
        scale: Some([
            (size + 16.0 * squash / 6.0) / size,
            (size - 16.0 * squash / 6.0) / size,
        ]),
        ..VisualState::default()
    }
}
fn motion(previous: Position, current: Position) -> Motion {
    Motion { previous, current }
}
pub(crate) fn sample(
    run: &Run,
    world: &World,
    previous: &Previous,
    interpolate: bool,
) -> Presentation {
    sample_rows(run, world, previous, interpolate, None)
}
pub(crate) fn sample_rows(
    run: &Run,
    world: &World,
    previous: &Previous,
    interpolate: bool,
    indices: Option<&[usize]>,
) -> Presentation {
    let p = &run.player;
    let frame = run.frame;
    let mut tick = p.action_tick;
    let mut literal_frame = 0;
    // player_pose.gd select: the trailing digit is 1 while the mouth is full.
    let full = i64::from(p.food.full());
    let wet = p.action_wet;
    let name: String = if p.life.hurt != 0 {
        format!("Hurt{full}")
    } else if [1, 2].contains(&p.action) {
        if p.action == 2 {
            tick += 24;
        }
        format!("GroundPound{full}")
    } else if p.action == 3 {
        format!("GPLand{full}")
    } else if p.action == 4 {
        if p.tongue.phase == 3 {
            literal_frame = 1 + (tick * 24 / 60).min(1);
        }
        format!(
            "{}{wet}",
            if p.tongue.axis != 0 {
                "TongueUp"
            } else {
                "Tongue"
            }
        )
    } else if p.action == 5 {
        format!(
            "{}{wet}",
            if p.tongue.axis != 0 { "SpitUp" } else { "Spit" }
        )
    } else if p.action == 6 {
        "LayEgg".into()
    } else if p.action == 7 {
        let seed = p.food.ammo == 1;
        let mut name = String::from(if seed { "SpewSeed" } else { "Spew" });
        if p.tongue.axis != 0 {
            name.push_str("Up");
        }
        if seed && p.on_floor == 0 && p.water.swimming == 0 {
            name.push_str("Jump");
        } else {
            name.push_str(&p.water.swimming.to_string());
        }
        name
    } else if p.action == 8 {
        format!("EggToss{full}")
    } else if p.action == 11 {
        "InstantSwallow".into()
    } else if p.action == 9 {
        format!("HeadBump{full}")
    } else if p.food.aim != 0 {
        if p.flutter_remaining != 0 {
            format!("FlutterAim{full}")
        } else if p.on_floor != 0 && p.body.vx != 0 {
            format!("WalkAim{}{full}", if p.body.vx > 0 { "R" } else { "L" })
        } else {
            format!("GrabEgg{full}")
        }
    } else if p.duck != 0 {
        tick = p.posture_tick;
        format!("Duck{full}")
    } else if p.look != 0 {
        literal_frame = i64::from(p.posture_tick != 0);
        format!("LookUp{full}")
    } else if p.water.swimming != 0 {
        if p.water.jump != 0 {
            format!("Jump{full}")
        } else if p.water.transition != 0 {
            tick = 9 - p.water.transition;
            format!(
                "{}{full}",
                if p.water.dive != 0 {
                    "Submerge"
                } else {
                    "Unsubmerge"
                }
            )
        } else if p.water.dive != 0 {
            tick = if p.body.vx != 0 { frame } else { 9 };
            if p.body.vx != 0 {
                "SwimSubmerged".into()
            } else {
                format!("Submerge{full}")
            }
        } else {
            tick = frame;
            format!("{}{full}", if p.body.vx != 0 { "Swim" } else { "Float" })
        }
    } else if p.push != 0 {
        tick = frame;
        format!("Push{full}")
    } else if p.turn != 0 {
        tick = 30 - p.turn_ticks;
        format!("Turn{full}")
    } else if p.action == 10 {
        format!("Land{full}")
    } else if p.gravity_tick != 0 {
        format!("Fall{full}")
    } else {
        tick = frame;
        format!(
            "{}{full}",
            ["Idle", "Walk", "Sprint", "Jump", "Fall", "Idle", "Flutter"][p.movement as usize]
        )
    };
    let selected_pose = PoseSelection {
        name,
        tick,
        frame: literal_frame,
    };
    let companion = motion(
        previous.companion,
        Position {
            x: p.recovery_x,
            y: p.recovery_y,
        },
    );
    let player = PlayerPicture {
        motion: motion(previous.player, pos(p.body)),
        velocity: Position {
            x: p.body.vx,
            y: p.body.vy,
        },
        facing: p.facing,
        movement: p.movement,
        action: p.action,
        posture: p.duck,
        pose: p.action,
        pose_ticks: p.action_tick,
        selected_pose,
        body_bounds: p.bounds(),
        visual: VisualState {
            alpha: if p.life.invulnerable != 0 { 0.5 } else { 1.0 },
            ..VisualState::default()
        },
        lifetime: match p.life_phase {
            1 => Lifetime::Rescuing,
            2 | 3 => Lifetime::Dying,
            4 | 5 => Lifetime::Respawning,
            7 | 8 => Lifetime::Goal,
            _ if p.life.hurt != 0 => Lifetime::Hurt,
            _ if p.life.separated != 0 => Lifetime::Separated,
            _ => Lifetime::Active,
        },
        life_phase: p.life_phase,
        on_floor: p.on_floor != 0,
        swimming: p.water.swimming != 0,
        visible: p.captured_by == 0
            && (p.life.invulnerable == 0 || (120 - p.life.invulnerable) % 6 < 3),
        companion,
        companion_phase: p.life.companion_mode,
        tongue: p.tongue_picture(),
        eggs: (0..p.food.eggs.clamp(0, 6) as usize)
            .map(|slot| run.consumers.colour[slot])
            .collect(),
        aim_degrees: (p.food.aim != 0).then(|| {
            let mut angle = if p.facing > 0 {
                p.food.aim_angle
            } else {
                180_000 - p.food.aim_angle
            };
            if angle > 180_000 {
                angle -= 360_000;
            }
            angle as f64 / 1000.0
        }),
        health: p.life.health,
        coins: run.coins,
        red_coins: run.redcoins,
        flowers: run.flowers,
    };
    let aux = |visible, layer, facing, animation: &str, motion| AuxiliaryPicture {
        motion,
        visible,
        layer,
        facing,
        animation: animation.into(),
        tick: frame,
        visual: VisualState::default(),
    };
    let companions = CompanionPictures {
        mode: p.life.companion_mode,
        companion: aux(
            true,
            13,
            if p.life.companion_mode == 0 {
                p.facing
            } else {
                1
            },
            if p.life.companion_mode == 2 {
                "cry"
            } else {
                "idle"
            },
            companion,
        ),
        bubble: aux(p.life.companion_mode == 2, 12, 1, "", companion),
        rescuers: std::array::from_fn(|index| {
            aux(
                p.life.rescue_active != 0 && [2, 4].contains(&p.life.companion_mode),
                13,
                1,
                "",
                motion(previous.rescuers[index], p.life.rescuers[index]),
            )
        }),
    };
    let status = match p.life_phase {
        1 => "Rescued".to_string(),
        2..=5 => "Respawn".to_string(),
        6 => "Checkpoint".to_string(),
        7 if p.life_ticks > 60 => "Goal".to_string(),
        7 => format!("Score {}", run.score()),
        8 => format!("Complete  Score {}", run.score()),
        _ if p.life.separated != 0 => "Rescue".to_string(),
        _ => String::new(),
    };
    let hud = HudPicture {
        health: p.life.health,
        coins: run.coins,
        redcoins: run.redcoins,
        redcoins_target: world.redcoins_target,
        flowers: run.flowers,
        flowers_target: world.flowers_target,
        hits: p.life.hits,
        deaths: run.deaths,
        total_play_ticks: run.total_play_ticks,
        life_phase: p.life_phase,
        life_ticks: p.life_ticks,
        separated: p.life.separated != 0,
        score: run.score(),
        status,
    };
    let rows: Box<dyn Iterator<Item = &crate::entity::Entity> + '_> = if let Some(indices) = indices
    {
        Box::new(indices.iter().map(|i| &run.entities[*i]))
    } else {
        Box::new(run.entities.iter())
    };
    let entities = rows
        .map(|e| {
            let source = e.source(world);
            let previous_entity = previous
                .entity(e.origin.token())
                .unwrap_or((pos(e.body), None));
            let (bounds, visual) = match &e.kind {
                Kind::Goal | Kind::Decor | Kind::Checkpoint(_) | Kind::Overlap(_) => {
                    ([0; 4], VisualState::default())
                }
                // grow_block.gd view_state
                Kind::Grow(g) => (
                    g.bounds(),
                    VisualState {
                        animation: Some("Default".into()),
                        offset_pixels: [0.0, g.lift as f64 / SCALE as f64],
                        size_pixels: [
                            Some(g.size as f64 / SCALE as f64),
                            Some(g.size as f64 / SCALE as f64),
                        ],
                        ..VisualState::default()
                    },
                ),
                // falling_span.gd view_state
                Kind::Fall(f) => (
                    f.bounds(),
                    VisualState {
                        animation: Some(f.view().0.into()),
                        frame: Some(f.view().1),
                        ..VisualState::default()
                    },
                ),
                // hard_block.gd view_state
                Kind::Hard(h) => (
                    h.bounds(),
                    VisualState {
                        animation: Some(h.animation().into()),
                        frame: Some(h.form),
                        ..VisualState::default()
                    },
                ),
                // plank_bridge.gd / ledge_span.gd / wide_span.gd view_state
                Kind::Span(s) => (
                    s.bounds(),
                    VisualState {
                        size_pixels: [
                            Some(s.width as f64 / SCALE as f64),
                            Some((s.height() / SCALE) as f64),
                        ],
                        ..VisualState::default()
                    },
                ),
                // item_block.gd view_state
                Kind::Block(b) => (
                    b.bounds(),
                    match b.kind {
                        crate::blocks::BlockKind::Linked => VisualState {
                            animation: Some(if b.enabled != 0 { "On" } else { "Off" }.into()),
                            ..VisualState::default()
                        },
                        crate::blocks::BlockKind::Message
                            if run.message.modal_token == e.origin.token() =>
                        {
                            let lift = (78 - run.message.ticks).min(run.message.ticks - 42).max(0);
                            VisualState {
                                frame: Some(0),
                                offset_pixels: [
                                    0.0,
                                    if run.message.stage == crate::blocks::OPENING {
                                        -80.0 * lift as f64 / 18.0
                                    } else {
                                        0.0
                                    },
                                ],
                                ..VisualState::default()
                            }
                        }
                        _ => VisualState::default(),
                    },
                ),
                Kind::Post(post) => (
                    post.bounds(),
                    // The pack's visible post is the Post<colour> / SpikedPost<colour>
                    // nine-patch; the o23 object art is a transparent collision box.
                    VisualState {
                        size_pixels: [Some(32.0), Some((post.height / SCALE) as f64)],
                        frame: Some(post.colour),
                        asset_key: Some(format!(
                            "{}Post{}",
                            if post.spiked != 0 { "Spiked" } else { "" },
                            post.colour
                        )),
                        ..VisualState::default()
                    },
                ),
                Kind::Pickup(pickup) => (pickup.bounds(), pickup_visual(pickup, e.collected)),
                Kind::Star(star) => (
                    star.bounds(),
                    VisualState {
                        animation: Some("Jump".into()),
                        frame: Some((star.phase / 5).min(2)),
                        flip_h: Some(e.facing > 0),
                        alpha: item_alpha(star.despawn_ticks),
                        ..VisualState::default()
                    },
                ),
                Kind::Bridge => {
                    let crate::PreparedPlacement::Bridge { geometry_index } =
                        source.expect("placed bridge").prepared
                    else {
                        unreachable!("compiler-owned bridge geometry")
                    };
                    let b = world.maps[0].bridges[geometry_index];
                    (
                        [
                            b.left - e.body.x,
                            b.top - e.body.y,
                            b.right - e.body.x,
                            b.top + 2 * SCALE - e.body.y,
                        ],
                        VisualState::default(),
                    )
                }
                Kind::Pad(pad) => {
                    let crate::PreparedPlacement::Pad { large, .. } =
                        source.expect("placed pad").prepared
                    else {
                        unreachable!("compiler-owned pad facts")
                    };
                    (crate::pad::bounds(large), pad_visual(large, pad.squash))
                }
                Kind::Walker(w) => (w.body_bounds(e.facing), actor_visual(w, e.body, e.facing)),
                // release_cloud.gd view_state
                Kind::Cache(c) => (
                    c.bounds(),
                    if c.phase == crate::clouds::OPENING {
                        let size = 32.0 + 16.0 * (c.age.min(18) as f64) / 18.0;
                        VisualState {
                            animation: Some("Wingless".into()),
                            frame: Some(0),
                            size_pixels: [Some(size), Some(size)],
                            ..VisualState::default()
                        }
                    } else {
                        VisualState {
                            animation: Some("Default".into()),
                            frame: Some([0, 1, 2, 3, 2, 1][(c.age * 16 / 60 % 6) as usize]),
                            alpha: if c.phase == crate::clouds::REVEALED {
                                0.5
                            } else {
                                1.0
                            },
                            ..VisualState::default()
                        }
                    },
                ),
                // shot_launcher.gd view_state
                Kind::Launcher(l) => (
                    l.bounds(),
                    VisualState {
                        animation: Some(l.form.to_string()),
                        alpha: if l.frozen != 0 { 0.6 } else { 1.0 },
                        rotation_degrees: (l.aim != 0).then(|| l.heading as f64 / 1000.0),
                        ..VisualState::default()
                    },
                ),
                // arrow_lift.gd view_state
                Kind::Lift(l) => (
                    l.bounds(),
                    VisualState {
                        frame: Some(l.form),
                        rotation_degrees: Some(l.view().0),
                        size_pixels: [Some(l.view().1), Some(l.view().1)],
                        ..VisualState::default()
                    },
                ),
                // timed_switch.gd view_state
                Kind::Switch(s) => {
                    let (_, frame, size) = s.view().unwrap_or((false, 0, [40.0, 42.0]));
                    (
                        s.bounds(),
                        VisualState {
                            animation: Some("Default".into()),
                            frame: Some(frame),
                            size_pixels: [Some(size[0]), Some(size[1])],
                            ..VisualState::default()
                        },
                    )
                }
                // star_flower.gd view_state
                Kind::StarFlower(f) => (
                    f.bounds(),
                    VisualState {
                        animation: Some("Default".into()),
                        ..VisualState::default()
                    },
                ),
                // item_stem.gd view_state
                Kind::Stem(s) => (
                    s.bounds(),
                    VisualState {
                        animation: Some(s.view().0.into()),
                        frame: Some(s.view().1),
                        ..VisualState::default()
                    },
                ),
                // count_ledge.gd view_state
                Kind::Ledge(l) => (
                    l.bounds(),
                    VisualState {
                        animation: Some(
                            if l.pressed != 0 {
                                "Pressed"
                            } else {
                                "Unpressed"
                            }
                            .into(),
                        ),
                        ..VisualState::default()
                    },
                ),
                // one_way_gate.gd view_state
                Kind::Gate(g) => (
                    g.bounds(),
                    VisualState {
                        frame: Some(g.opened),
                        rotation_degrees: Some(g.angle as f64 / 1000.0),
                        ..VisualState::default()
                    },
                ),
                // redirect_cloud.gd view_state
                Kind::Redirect(r) => (
                    r.bounds(),
                    VisualState {
                        animation: Some(format!("Color{}", r.colour.max(0))),
                        frame: Some(r.age / 10 % 3),
                        rotation_degrees: Some(r.angle as f64 / 1000.0),
                        ..VisualState::default()
                    },
                ),
                // seed_melon.gd view_state
                Kind::Melon(m) => (
                    m.bounds(),
                    VisualState {
                        frame: Some(m.form),
                        ..VisualState::default()
                    },
                ),
                // seed_shot.gd view_state
                Kind::Seed(s) => (
                    s.bounds(),
                    VisualState {
                        rotation_degrees: Some(s.heading as f64 / 1000.0),
                        ..VisualState::default()
                    },
                ),
                // item_egg.gd view_state: the colour picks the animation; despawn flickers.
                Kind::Egg(egg) => (
                    egg.bounds(),
                    VisualState {
                        animation: Some(
                            ["Green", "Yellow", "Red", "Purple"][egg.colour.clamp(0, 3) as usize]
                                .into(),
                        ),
                        alpha: if egg.despawn_ticks > 0
                            && egg.despawn_ticks < 180
                            && run.frame % 12 < 6
                        {
                            0.0
                        } else {
                            1.0
                        },
                        ..VisualState::default()
                    },
                ),
            };
            EntityPicture {
                token: e.origin.token(),
                code: e.code(world).to_owned(),
                placement_id: source.map(|p| p.id.clone()),
                source_index: e.origin.placed(),
                body_bounds: bounds,
                motion: motion(previous_entity.0, pos(e.body)),
                facing: e.facing,
                layer: e.layer,
                variant: if let Kind::Walker(w) = &e.kind {
                    w.variant
                } else {
                    source.map(|p| p.variant).unwrap_or(0)
                },
                status: match e.status {
                    0 => EntityStatus::Waiting,
                    1 => EntityStatus::Active,
                    2 => EntityStatus::Queued,
                    _ => EntityStatus::Defeated,
                },
                visible: matches!(e.kind, Kind::Post(_))
                    || e.status != 3
                        && match &e.kind {
                            Kind::Checkpoint(_) => e.collected == 0,
                            Kind::Pad(pad) => pad.active,
                            Kind::Pickup(p) => {
                                e.status == 1
                                    && p.held == 0
                                    && (e.collected == 0 || p.collect_ticks > 0)
                            }
                            Kind::Star(p) => e.status == 1 && p.held == 0 && e.collected == 0,
                            Kind::Walker(_) => actor_visible(e),
                            Kind::Egg(_) => e.status == 1 && e.collected == 0,
                            Kind::Cache(c) => {
                                e.status == 1
                                    && c.phase != crate::clouds::HIDDEN
                                    && e.collected == 0
                            }
                            Kind::Redirect(_) | Kind::Gate(_) | Kind::Ledge(_) | Kind::Stem(_) => {
                                e.status == 1
                            }
                            Kind::StarFlower(_) => e.status == 1 && e.collected == 0,
                            Kind::Lift(_) | Kind::Seed(_) => e.status == 1,
                            Kind::Melon(m) => e.status == 1 && m.held == 0,
                            Kind::Launcher(_) => e.status == 1,
                            Kind::Switch(s) => e.status == 1 && s.view().is_ok_and(|v| v.0),
                            Kind::Block(_) => e.status == 1 && e.collected == 0,
                            Kind::Span(_) | Kind::Hard(_) | Kind::Fall(_) | Kind::Grow(_) => {
                                e.status == 1
                            }
                            // enemy_overlap.gd view_state
                            Kind::Overlap(_) => false,
                            _ => true,
                        },
                held: matches!(&e.kind,Kind::Walker(w)if w.held!=0),
                hidden: matches!(&e.kind,Kind::Walker(w)if w.hidden!=0),
                visual,
                auxiliary: {
                    let mut parts = plant_head(e, previous_entity.1, frame);
                    parts.extend(stilt_parts(e, e.status == 1 && actor_visible(e)));
                    parts
                },
            }
        })
        .collect();
    Presentation {
        tick: frame,
        map_index: 1,
        interpolate,
        follow: motion(previous.follow, run.camera),
        player,
        companions,
        hud,
        // item_block.gd message_state while a message is open.
        message: run
            .find_token(run.message.modal_token)
            .filter(|_| run.message.stage != crate::blocks::CLOSED)
            .map(|i| crate::MessagePicture {
                holder_token: run.message.modal_token,
                text: run.message_text(i, world),
                section: run.message.section,
                sections: run.message_sections(i, world),
            }),
        entities,
        sound: SoundEvent {
            serial: run.sound.serial,
            kind: run.sound.kind,
            position: Position {
                x: run.sound.x,
                y: run.sound.y,
            },
        },
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pad_squash_matches_original_ratios_and_reversal() {
        for large in [false, true] {
            assert_eq!(pad_visual(large, 0).scale, Some([1.0, 1.0]));
            assert_eq!(pad_visual(large, 12).scale, Some([1.0, 1.0]));
            for tick in 0..=12 {
                assert_eq!(
                    pad_visual(large, tick).scale,
                    pad_visual(large, 12 - tick).scale
                );
            }
        }
        assert_eq!(pad_visual(false, 6).scale, Some([1.5, 0.5]));
        assert_eq!(pad_visual(true, 6).scale, Some([64.0 / 48.0, 32.0 / 48.0]));
    }
}
