//! Pure semantic sampling. Pack frame binding and screen planning stay in the player.
use crate::{
    state::{Kind, Run},
    *,
};
#[derive(Clone, Debug)]
pub(crate) struct Previous {
    pub player: Position,
    pub companion: Position,
    pub follow: Position,
    pub entities: Vec<Position>,
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
            entities: run.entities.iter().map(|e| pos(e.body)).collect(),
            rescuers: run.player.life.rescuers,
        }
    }
}
fn pos(b: crate::body::Body) -> Position {
    Position { x: b.x, y: b.y }
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
    let name = if p.life.hurt != 0 {
        "Hurt0"
    } else if p.action == 9 {
        "HeadBump0"
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
        frame: 0,
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
        swimming: false,
        visible: p.life.invulnerable == 0 || (120 - p.life.invulnerable) % 6 < 3,
        companion,
        companion_phase: p.life.companion_mode,
        health: p.life.health,
        coins: run.coins,
        red_coins: 0,
        flowers: 0,
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
        7 => format!("Score {}", p.life.health),
        8 => format!("Complete  Score {}", p.life.health),
        _ if p.life.separated != 0 => "Rescue".to_string(),
        _ => String::new(),
    };
    let hud = HudPicture {
        health: p.life.health,
        coins: run.coins,
        redcoins: 0,
        redcoins_target: 0,
        flowers: 0,
        flowers_target: 0,
        hits: p.life.hits,
        deaths: run.deaths,
        total_play_ticks: run.total_play_ticks,
        life_phase: p.life_phase,
        life_ticks: p.life_ticks,
        separated: p.life.separated != 0,
        score: p.life.health,
        status,
    };
    let entities = run
        .entities
        .iter()
        .enumerate()
        .map(|(index, e)| {
            let source = &world.maps[0].placements[e.source];
            let (bounds, visual) = match &e.kind {
                Kind::Goal => ([0; 4], VisualState::default()),
                Kind::Walker(w) => (
                    [-10 * SCALE, -18 * SCALE, 10 * SCALE, 16 * SCALE],
                    VisualState {
                        animation: Some(if w.mode == 0 { "0Idle" } else { "0Walk" }.into()),
                        ..VisualState::default()
                    },
                ),
            };
            EntityPicture {
                token: e.source as i64 + 1,
                code: source.code.clone(),
                placement_id: Some(source.id.clone()),
                source_index: Some(e.source),
                body_bounds: bounds,
                motion: motion(previous.entities[index], pos(e.body)),
                facing: e.facing,
                layer: if matches!(e.kind, Kind::Goal) { 7 } else { 8 },
                variant: 0,
                status: match e.status {
                    0 => EntityStatus::Waiting,
                    1 => EntityStatus::Active,
                    2 => EntityStatus::Queued,
                    _ => EntityStatus::Defeated,
                },
                visible: e.status != 3,
                held: false,
                hidden: false,
                visual,
                auxiliary: Vec::new(),
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
