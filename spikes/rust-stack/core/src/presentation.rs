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
    let name = if p.action == 9 {
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
        visual: VisualState::default(),
        lifetime: if p.life_phase == 0 {
            Lifetime::Active
        } else {
            Lifetime::Goal
        },
        life_phase: p.life_phase,
        on_floor: p.on_floor != 0,
        swimming: false,
        visible: true,
        companion,
        companion_phase: 0,
        health: 10,
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
        mode: 0,
        companion: aux(true, 13, p.facing, "idle", companion),
        bubble: aux(false, 12, 1, "", companion),
        rescuers: std::array::from_fn(|_| aux(false, 13, 1, "", Motion::default())),
    };
    let status = if p.life_phase == 7 {
        if p.life_ticks > 60 {
            "Goal"
        } else {
            "Score 10"
        }
    } else if p.life_phase == 8 {
        "Complete  Score 10"
    } else {
        ""
    };
    let hud = HudPicture {
        health: 10,
        coins: run.coins,
        redcoins: 0,
        redcoins_target: 0,
        flowers: 0,
        flowers_target: 0,
        hits: 0,
        deaths: 0,
        total_play_ticks: run.total_play_ticks,
        life_phase: p.life_phase,
        life_ticks: p.life_ticks,
        separated: false,
        score: 10,
        status: status.into(),
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
