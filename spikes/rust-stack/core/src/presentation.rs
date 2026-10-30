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
    pub entities: std::collections::BTreeMap<i64, (Position, Option<[i64; 4]>)>,
    pub rescuers: [Position; 4],
}
impl Previous {
    pub fn of(run: &Run) -> Self {
        Self {
            player: pos(run.player.body),
            companion: Position {
                x: run.player.recovery_x,
                y: run.player.recovery_y,
            },
            follow: run.camera,
            entities: run
                .entities
                .iter()
                .map(|e| {
                    let head = match &e.kind {
                        Kind::Walker(w)
                            if w.kind == crate::actors::ActorKind::Plant && w.head_size != 0 =>
                        {
                            Some(w.head_box(e.body, e.facing))
                        }
                        _ => None,
                    };
                    (e.origin.token(), (pos(e.body), head))
                })
                .collect(),
            rescuers: run.player.life.rescuers,
        }
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
fn plant_head(
    e: &crate::entity::Entity,
    previous: Option<[i64; 4]>,
    frame: i64,
) -> Vec<EntityAuxiliaryPicture> {
    let Kind::Walker(w) = &e.kind else {
        return Vec::new();
    };
    if w.kind != crate::actors::ActorKind::Plant || w.head_size == 0 {
        return Vec::new();
    }
    let b = w.head_box(e.body, e.facing);
    let old = previous.unwrap_or(b);
    vec![EntityAuxiliaryPicture {
        kind: EntityAuxiliaryKind::PlantHead,
        scale: [1.0, 1.0],
        picture: AuxiliaryPicture {
            motion: motion(
                Position {
                    x: old[0],
                    y: old[1],
                },
                Position { x: b[0], y: b[1] },
            ),
            visible: e.status == 1 && e.collected == 0 && w.held == 0 && w.hidden == 0,
            layer: 10,
            facing: e.facing,
            animation: String::new(),
            tick: frame,
            visual: VisualState {
                asset_key: Some("e5_head".into()),
                origin_pixels: Some([0.0, 0.0]),
                size_pixels: [
                    Some((b[2] - b[0]) as f64 / SCALE as f64),
                    Some((b[3] - b[1]) as f64 / SCALE as f64),
                ],
                rotation_degrees: Some(0.0),
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
    let p = &run.player;
    let frame = run.frame;
    let mut tick = p.action_tick;
    let mut literal_frame = 0;
    let name = if p.life.hurt != 0 {
        "Hurt0"
    } else if p.action == 4 {
        if p.tongue.phase == 3 {
            literal_frame = 1 + (tick * 24 / 60).min(1);
        }
        match (p.tongue.axis != 0, p.action_wet != 0) {
            (true, true) => "TongueUp1",
            (true, false) => "TongueUp0",
            (false, true) => "Tongue1",
            (false, false) => "Tongue0",
        }
    } else if p.action == 9 {
        "HeadBump0"
    } else if p.water.swimming != 0 {
        if p.water.jump != 0 {
            "Jump0"
        } else if p.water.transition != 0 {
            tick = 9 - p.water.transition;
            if p.water.dive != 0 {
                "Submerge0"
            } else {
                "Unsubmerge0"
            }
        } else if p.water.dive != 0 {
            tick = if p.body.vx != 0 { frame } else { 9 };
            if p.body.vx != 0 {
                "SwimSubmerged"
            } else {
                "Submerge0"
            }
        } else {
            tick = frame;
            if p.body.vx != 0 {
                "Swim0"
            } else {
                "Float0"
            }
        }
    } else if p.push != 0 {
        tick = frame;
        "Push0"
    } else if p.turn != 0 {
        tick = 30 - p.turn_ticks;
        "Turn0"
    } else if p.action == 10 {
        "Land0"
    } else if p.gravity_tick != 0 {
        "Fall0"
    } else {
        tick = frame;
        [
            "Idle0", "Walk0", "Sprint0", "Jump0", "Fall0", "Idle0", "Flutter0",
        ][p.movement as usize]
    };
    let selected_pose = PoseSelection {
        name: name.into(),
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
        posture: 0,
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
    let entities = run
        .entities
        .iter()
        .map(|e| {
            let source = e.source(world);
            let previous_entity = previous
                .entities
                .get(&e.origin.token())
                .copied()
                .unwrap_or((pos(e.body), None));
            let (bounds, visual) = match &e.kind {
                Kind::Goal | Kind::Decor | Kind::Checkpoint(_) => ([0; 4], VisualState::default()),
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
                visible: e.status != 3
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
                        _ => true,
                    },
                held: matches!(&e.kind,Kind::Walker(w)if w.held!=0),
                hidden: matches!(&e.kind,Kind::Walker(w)if w.hidden!=0),
                visual,
                auxiliary: plant_head(e, previous_entity.1, frame),
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
        message: None,
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
