//! Normal fixture controls. Oracle bytes compare, but never supply uninterrupted stepping state.
use eggshell_spike_core::{
    schema::Schema,
    wire::{required, WireSnapshot},
    Session,
};
use std::{collections::BTreeSet, fs, path::PathBuf};
fn run(restores: bool) {
    let name = std::env::var("CORE_FIXTURE").unwrap();
    assert!([
        "bounce",
        "bounce.pad",
        "bounce.moves",
        "stride.eat",
        "lagoon",
        "collections",
        "actors_target",
        "stilts_target",
        "stilts_target.knock",
        "checkpoint_target",
        "posts_target",
        "posts_target.pound",
        "posts_target.duck",
        "blocks_target",
        "spans_target",
        "flats_target",
        "hards_target",
        "falls_target",
        "grows_target",
        "gates_target",
        "ledges_target",
        "stems_target",
        "flowers_target",
        "switches_target",
        "shells_target",
        "armored_target",
        "spears_target",
        "lifts_target",
        "snowflow_target",
        "fish_target",
        "melons_target",
        "thieves_target",
        "rollers_target",
        "shooters_target",
        "hounds_target",
        "wings_target",
        "launchers_target",
        "sprouts_target",
        "jugglers_target",
        "bulks_target",
        "gusts_target",
        "spores_target",
        "hangs_target",
        "eggblocks_target",
        "pillars_target",
        "balloons_target",
        "clears_target",
        "dice_target",
        "decor_target",
        "rejoin_target",
        // Pack parity sweep: a private corpus level on a generic route, no coverage goal.
        "corpus"
    ]
    .contains(&name.as_str()));
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_FIXTURE_DIR").unwrap());
    let level = fs::read_to_string(std::env::var("CORE_FIXTURE_LEVEL").unwrap()).unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let inputs: Vec<u8> =
        serde_json::from_slice(&fs::read(std::env::var("CORE_FIXTURE_INPUT").unwrap()).unwrap())
            .unwrap();
    let stream = fs::read(root.join("snapshots.v10.stream")).unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap_or_else(|error| {
        panic!("{name} next support/action gate at initialization: {error}")
    });
    let pictures: Option<Vec<serde_json::Value>> = if name == "actors_target"
        || name.starts_with("stilts_target")
        || name == "checkpoint_target"
        || name.starts_with("posts_target")
    {
        Some(serde_json::from_slice(&fs::read(root.join("pictures.json")).unwrap()).unwrap())
    } else {
        None
    };
    let mut cursor = 0;
    let mut bridge_ticks = 0;
    let mut squash_ticks = 0;
    let mut tongue_ticks = 0;
    let mut message_ticks = 0;
    let mut message_sections = 0;
    let mut raised_floor_ticks = 0;
    let mut flat_ticks = 0;
    let mut cracked_ticks = 0;
    let mut falling_ticks = 0;
    let mut grown_ticks = 0;
    let mut gate_open_ticks = 0;
    let mut gate_closings = 0;
    let mut gates_open = 0;
    let mut ledge_pressed_ticks = 0;
    let mut ledges_left = usize::MAX;
    let mut ledge_breaks = 0;
    let mut stem_fast_ticks = 0;
    let mut stem_frames = 0;
    let mut flowers_seen = 0;
    let mut flowers_gone = 0;
    let mut switch_ticks = 0;
    let mut switch_restarts = 0;
    let mut switch_clock = 0;
    let mut shell_spin_ticks = 0;
    let mut shell_runner_ticks = 0;
    let mut shell_hop_lands = 0;
    let mut armored_modes = [0usize; 6];
    let mut spear_knocks = 0;
    let mut spear_dropped = 0;
    let mut spear_held = 0;
    let mut thief_plans = [0usize; 5];
    let mut thief_carry = 0;
    let mut thief_stomped = 0;
    let mut thief_struck = 0;
    let mut thief_shoved = 0;
    let mut thief_defeated = 0;
    let mut roller_modes = [0usize; 3];
    let mut roller_walled = 0;
    let mut overlap_ticks = 0;
    let mut shooter_modes = [0usize; 4];
    let mut shooter_held = 0;
    let mut shooter_removed = 0;
    let mut pellet_ticks = 0;
    let mut lift_riding = 0;
    let mut lift_shrinks = 0;
    let mut lift_angles: std::collections::BTreeMap<String, i64> = Default::default();
    let mut lift_turns = 0;
    let mut snow_ticks = 0;
    let mut fish_modes = [0usize; 5];
    let mut fish_exhausted = 0;
    let mut fish_dry = 0;
    let mut melon_held_ticks = 0;
    let mut hound_ridden = 0;
    let mut hound_playing = 0;
    let mut hound_swimming = 0;
    let mut hound_jumps = 0;
    let mut melons_eaten = 0;
    let mut seed_ticks = 0;
    let mut seed_struck = BTreeSet::new();
    let mut wing_modes = [0usize; 4];
    let mut wing_stomps = 0;
    let mut wing_strikes = 0;
    let mut wing_held = 0;
    let mut shot_forms = [0usize; 3];
    let mut shot_pauses = 0;
    let mut shot_falling = 0;
    let mut shot_held = 0;
    let mut launcher_charges = 0;
    let mut bounce_fires = 0;
    let mut hang_modes = [0usize; 5];
    let mut hang_held = 0;
    let mut hang_removals = 0;
    let mut hang_status: std::collections::BTreeMap<String, i64> = Default::default();
    let mut spore_turns = 0;
    let mut spore_facings: std::collections::BTreeMap<String, i64> = Default::default();
    let mut spore_removals = 0;
    let mut spore_status: std::collections::BTreeMap<String, i64> = Default::default();
    let mut grown_sprouts = BTreeSet::new();
    let mut waking_ticks = 0;
    let mut gust_full_speed = 0;
    let mut gust_headings = BTreeSet::new();
    let mut gust_held = 0;
    let mut gust_removals = 0;
    let mut gust_status: std::collections::BTreeMap<String, i64> = Default::default();
    let mut bulk_phases = [0usize; 4];
    let mut bulk_squashed = 0;
    let mut bulk_defeats = 0;
    let mut bulk_status: std::collections::BTreeMap<String, i64> = Default::default();
    let mut juggler_tosses = 0;
    let mut juggler_frowns = 0;
    let mut juggler_rises = 0;
    let mut hopper_thrown = 0;
    let mut hopper_sinking = 0;
    let mut hopper_held = 0;
    let mut sprout_hops = 0;
    let mut sprout_held = 0;
    let mut sprout_removals = 0;
    let mut sprout_status: std::collections::BTreeMap<String, i64> = Default::default();
    let mut sprout_facings: std::collections::BTreeMap<String, i64> = Default::default();
    let mut sprout_turns = 0;
    let mut egg_block_rising = 0;
    let mut egg_blocks_spent = 0;
    let mut egg_block_bumped = BTreeSet::new();
    let mut pillar_side_ticks = 0;
    let mut balloon_ride_ticks = 0;
    let mut clear_charges = BTreeSet::new();
    let mut dice_states = BTreeSet::new();
    let mut ledge_heights = BTreeSet::new();
    let mut rejoin_ticks = 0;
    let mut lamp_views = BTreeSet::new();
    let mut dice_lifted = 0;
    let mut dice_tints = BTreeSet::new();
    let mut cleared = BTreeSet::new();
    let mut balloon_landings = 0;
    let mut balloon_bob_ticks = 0;
    let mut swimming_ticks = 0;
    let mut held_ticks = 0;
    let mut most_eggs = 0;
    let mut requests = 0;
    let mut captured_ticks = 0;
    let mut head_ticks = 0;
    let mut rescuer_ticks = 0;
    let mut post_floor_ticks = 0;
    let mut maximum_x = 0;
    let mut post_height = 96 * 3600;
    let mut post_updates = Vec::new();
    let mut pound_ticks = [0usize; 3];
    let mut impact = 0;
    let mut duck_ticks = 0;
    let mut shortest_duck = 56 * 3600;
    let mut old_action = 0;
    let mut action_changes = Vec::new();
    let mut old_post_floor = false;
    let mut post_floor_changes = Vec::new();
    let mut inactive_waiting_samples = 0;
    let mut inactive_queued_samples = 0;
    let mut phases = BTreeSet::new();
    let mut modes = BTreeSet::new();
    let mut max_runtime = 0;
    let mut runtime_ticks = 0;
    let mut first_spawn = None;
    let mut first_compaction = None;
    let mut previous_runtime = 0;
    let mut last_serial = 1;
    let mut knock_ticks = 0;
    let mut checkpoint_ticks = 0;
    let mut checkpoint_respawn_ticks = 0;
    let mut previous_phase = 0;
    let mut previous_health = 10;
    let mut checkpoint_transitions = Vec::new();
    let mut checkpoint_award_ticks = Vec::new();
    let mut checkpoint_coin_changes = Vec::new();
    let mut previous_coins = 0;
    let mut checkpoint_flags_seen = false;
    let mut first_knock = None;
    let mut last_knock = None;
    let mut restore_ticks = vec![0, 1, 6, 11, 66, 70, 75, 90, 160, 220, 350, 500];
    let mut branch_ticks = vec![1, 6, 11, 70, 75, 90, 160, 220, 350];
    if name == "actors_target" {
        restore_ticks.extend([
            600, 700, 780, 790, 791, 800, 900, 1000, 1040, 1080, 1100, 1200, 1500,
        ]);
        branch_ticks.extend([780, 790, 791, 1000, 1080, 1100, 1200]);
    }
    if name == "stilts_target" {
        restore_ticks.extend([106, 107, 108, 244, 245, 246]);
        branch_ticks.extend([106, 107, 108, 244, 245, 246]);
    }
    if name == "stilts_target.knock" {
        restore_ticks.extend([25, 26, 27, 77, 78, 79]);
        branch_ticks.extend([25, 26, 27, 77, 78, 79]);
    }
    if name == "checkpoint_target" {
        let cuts = [
            52, 53, 54, 58, 59, 60, 112, 113, 114, 157, 158, 159, 1333, 1334, 1335, 1573, 1574,
            1575, 1634, 1635, 1636, 1637, 1638, 1639, 174, 175, 176, 1672, 1673, 1674,
        ];
        restore_ticks.extend(cuts);
        branch_ticks.extend(cuts);
    }
    if name == "posts_target.duck" {
        let cuts = [80, 81, 82, 89, 90, 91, 100, 101, 102];
        restore_ticks.extend(cuts);
        branch_ticks.extend(cuts);
    }
    if name == "posts_target" {
        let cuts = [53, 54, 55, 198, 199, 200];
        restore_ticks.extend(cuts);
        branch_ticks.extend(cuts);
    }
    if name == "posts_target.pound" {
        let cuts = [
            53, 54, 55, 80, 81, 82, 142, 143, 144, 152, 153, 154, 214, 215, 216, 224, 225, 226, 92,
            93, 94, 116, 117, 118, 120, 121, 122, 164, 165, 166, 188, 189, 190, 192, 193, 194, 236,
            237, 238, 260, 261, 262, 264, 265, 266, 286, 287, 288,
        ];
        restore_ticks.extend(cuts);
        branch_ticks.extend(cuts);
    }
    restore_ticks.sort_unstable();
    restore_ticks.dedup();
    branch_ticks.sort_unstable();
    branch_ticks.dedup();
    for tick in 0..=inputs.len() {
        let size = u32::from_le_bytes(stream[cursor..cursor + 4].try_into().unwrap()) as usize;
        cursor += 4;
        let expected = &stream[cursor..cursor + size];
        cursor += size;
        let actual = session.snapshot().unwrap();
        let wire = WireSnapshot::decode(&actual, session.world().identity, &schema).unwrap();
        if actual != expected {
            let a = WireSnapshot::decode(expected, session.world().identity, &schema).unwrap();
            // Every differing player field, for diagnosis (the panic names the first).
            for (index, field) in schema.player().iter().enumerate() {
                if a.player.get(index) != wire.player.get(index) {
                    println!(
                        "MISMATCH_PLAYER field={} expected={:?} actual={:?}",
                        field.0,
                        a.player.get(index),
                        wire.player.get(index)
                    );
                }
            }
            // Every differing entity field, for diagnosis.
            for (x, y) in a.entities.iter().zip(&wire.entities) {
                for ((f, ev), av) in schema
                    .entity_fields(&x.code)
                    .iter()
                    .zip(&x.values)
                    .zip(&y.values)
                {
                    if ev != av {
                        println!(
                            "MISMATCH_ENTITY id={} code={} field={} expected={ev} actual={av}",
                            x.id, x.code, f.0
                        );
                    }
                }
            }
            panic!(
                "{name} mismatch tick={tick}: {:?}",
                a.first_difference(&wire, &schema)
            );
        }
        let packet = session.presentation();
        if let Some(pictures) = &pictures {
            let expected = &pictures[tick];
            let pose = &expected["player"];
            assert_eq!(
                packet.player.selected_pose.name,
                pose["name"].as_str().unwrap()
            );
            assert_eq!(
                packet.player.selected_pose.tick,
                pose["tick"].as_i64().unwrap()
            );
            assert_eq!(
                packet.player.selected_pose.frame,
                pose["frame"].as_i64().unwrap()
            );
            for e in expected["entities"].as_array().unwrap() {
                let token = e["token"].as_i64().unwrap();
                let picture = packet.entities.iter().find(|p| p.token == token).unwrap();
                let b = e["body"].as_array().unwrap();
                assert_eq!(
                    picture.body_bounds,
                    [
                        b[0].as_i64().unwrap(),
                        b[1].as_i64().unwrap(),
                        b[2].as_i64().unwrap(),
                        b[3].as_i64().unwrap()
                    ]
                );
                assert_eq!(
                    picture.visual.animation.as_deref(),
                    e["view"]["animation"].as_str()
                );
                if let Some(size) = e["view"]["size_x"].as_f64() {
                    assert_eq!(picture.visual.size_pixels[0], Some(size));
                }
                if let Some(frame) = e["view"]["frame"].as_i64() {
                    assert_eq!(picture.visual.frame, Some(frame));
                }
                if let Some(size) = e["view"]["size_y"].as_f64() {
                    assert_eq!(picture.visual.size_pixels[1], Some(size));
                }
                if let Some(visible) = e["visible"].as_bool() {
                    assert_eq!(picture.visible, visible);
                }
                if e["inactive"].as_bool() == Some(true) {
                    assert!(picture.visible);
                    assert!(picture.auxiliary.iter().all(|head| !head.picture.visible));
                    match picture.status {
                        eggshell_spike_core::EntityStatus::Waiting => inactive_waiting_samples += 1,
                        eggshell_spike_core::EntityStatus::Queued => inactive_queued_samples += 1,
                        _ => panic!("original inactive policy marked active/defeated row"),
                    }
                }
                let h = e["head"].as_array().unwrap();
                // Godot reports only the plant head; stilt parts are a Rust-only drawing
                // detail (the original's animated walker), not part of the oracle view.
                let heads: Vec<_> = picture
                    .auxiliary
                    .iter()
                    .filter(|a| a.kind == eggshell_spike_core::EntityAuxiliaryKind::PlantHead)
                    .collect();
                if h.is_empty() {
                    assert!(heads.is_empty());
                    assert_eq!(picture.visual.head_box, None);
                } else {
                    let b = [
                        h[0].as_i64().unwrap(),
                        h[1].as_i64().unwrap(),
                        h[2].as_i64().unwrap(),
                        h[3].as_i64().unwrap(),
                    ];
                    assert_eq!(picture.visual.head_box, Some(b));
                    // The drawn head is the original's rotated head art (pivot, angle,
                    // flip), not Godot's stretched hull; only its presence is compared.
                    assert_eq!(heads.len(), 1);
                    let aux = heads[0];
                    let at = aux.picture.motion.current;
                    assert!(at.x >= b[0] - 64 * 3600 && at.x <= b[2] + 64 * 3600);
                    assert!(at.y >= b[1] - 64 * 3600 && at.y <= b[3] + 64 * 3600);
                    assert!(aux.picture.visual.rotation_degrees.is_some());
                }
            }
        }
        let runtime_count = wire
            .entities
            .iter()
            .filter(|e| {
                required(&e.values, schema.entity_fields(&e.code), "source_index").unwrap() == -1
            })
            .count();
        max_runtime = max_runtime.max(runtime_count);
        runtime_ticks += usize::from(runtime_count > 0);
        if runtime_count > previous_runtime && first_spawn.is_none() {
            first_spawn = Some(tick);
        }
        if runtime_count < previous_runtime && first_compaction.is_none() {
            first_compaction = Some(tick);
        }
        previous_runtime = runtime_count;
        let serial = required(&wire.level, schema.level(), "dynamic_serial").unwrap();
        if serial != last_serial {
            println!("RUNTIME_SERIAL_CHANGE tick={tick} before={last_serial} after={serial} player_x={} player_y={} retained={runtime_count}",packet.player.motion.current.x,packet.player.motion.current.y);
        }
        last_serial = serial;
        let knocked = wire.entities.iter().any(|e| {
            e.code == "e35"
                && required(&e.values, schema.entity_fields("e35"), "phase").unwrap() == 1
        });
        knock_ticks += usize::from(knocked);
        if knocked {
            if first_knock.is_none() {
                first_knock = Some(tick);
            }
            last_knock = Some(tick);
        }
        checkpoint_ticks += usize::from(packet.player.life_phase == 6);
        checkpoint_respawn_ticks +=
            usize::from(packet.hud.deaths > 0 && packet.player.life_phase == 5);
        if packet.player.life_phase != previous_phase {
            checkpoint_transitions.push((tick, packet.player.life_phase));
            previous_phase = packet.player.life_phase;
        }
        if packet.player.life_phase == 6 && packet.hud.health != previous_health {
            checkpoint_award_ticks.push(tick);
        }
        previous_health = packet.hud.health;
        if packet.hud.coins != previous_coins {
            checkpoint_coin_changes.push((tick, packet.hud.coins));
            previous_coins = packet.hud.coins;
        }
        if name == "checkpoint_target" && packet.hud.deaths > 0 && packet.player.life_phase == 5 {
            for (id, collected) in [
                ("coin_before", 1),
                ("redcoin_before", 1),
                ("flower_before", 1),
                ("checkpoint", 1),
                ("coin_after", 0),
            ] {
                let row = wire.entities.iter().find(|e| e.id == id).unwrap();
                let fields = schema.entity_fields(&row.code);
                assert_eq!(
                    required(&row.values, fields, "collected").unwrap(),
                    collected
                );
                assert_eq!(
                    required(&row.values, fields, "checkpoint_collected").unwrap(),
                    collected
                );
            }
            assert_eq!(packet.player.motion.current.x, 288 * 3600);
            if required(&wire.player, schema.player(), "life_ticks").unwrap() == 3 {
                assert_eq!(packet.player.motion.current.y, 384 * 3600);
            }
            assert_eq!(packet.hud.health, 20);
            assert_eq!((packet.hud.redcoins, packet.hud.flowers), (1, 1));
            checkpoint_flags_seen = true;
        }
        maximum_x = maximum_x.max(packet.player.motion.current.x);
        if packet.player.posture != 0 {
            duck_ticks += 1;
            shortest_duck = shortest_duck.min(-packet.player.body_bounds[1]);
        }
        if (1..=3).contains(&packet.player.action) {
            pound_ticks[(packet.player.action - 1) as usize] += 1;
        }
        impact = required(&wire.player, schema.player(), "move_impact").unwrap();
        if let Some(post) = wire.entities.iter().find(|e| e.id == "post96") {
            let fields = schema.entity_fields("o23");
            let height = required(&post.values, fields, "height").unwrap();
            if height != post_height {
                post_updates.push((
                    tick,
                    height,
                    required(&post.values, fields, "status").unwrap(),
                ));
                post_height = height;
            }
        }
        let post_supported = packet.player.on_floor
            && packet.entities.iter().any(|e| {
                e.code == "o23"
                    && e.status == eggshell_spike_core::EntityStatus::Active
                    && packet.player.motion.current.x + 12 * 3600 >= e.motion.current.x - 16 * 3600
                    && packet.player.motion.current.x - 12 * 3600 <= e.motion.current.x + 16 * 3600
                    && packet.player.motion.current.y <= e.motion.current.y + e.body_bounds[1]
                    && packet.player.motion.current.y
                        >= e.motion.current.y + e.body_bounds[1] - 3600
            });
        post_floor_ticks += usize::from(post_supported);
        if post_supported != old_post_floor {
            post_floor_changes.push((tick, post_supported));
            old_post_floor = post_supported;
        }
        if packet.player.action != old_action {
            action_changes.push((tick, packet.player.action));
            old_action = packet.player.action;
        }
        phases.insert(packet.player.life_phase);
        modes.insert(packet.companions.mode);
        captured_ticks +=
            usize::from(required(&wire.player, schema.player(), "captured_by").unwrap() != 0);
        head_ticks += usize::from(packet.entities.iter().any(|e| !e.auxiliary.is_empty()));
        rescuer_ticks += usize::from(packet.companions.rescuers.iter().any(|r| r.visible));
        bridge_ticks +=
            usize::from(required(&wire.player, schema.player(), "support_bridge").unwrap() != 0);
        tongue_ticks += usize::from(packet.player.action == 4);
        raised_floor_ticks += usize::from(
            required(&wire.player, schema.player(), "on_floor").unwrap() != 0
                && required(&wire.player, schema.player(), "y").unwrap() < 380 * 3600,
        );
        // An egg changed a hard block: hard4 cracked (frame 5), or one of the three broke.
        cracked_ticks += usize::from(
            packet
                .entities
                .iter()
                .filter(|e| e.visible && e.visual.animation.as_deref() == Some("Rock"))
                .count()
                < 3
                || packet.entities.iter().any(|e| {
                    e.visual.animation.as_deref() == Some("Rock") && e.visual.frame == Some(5)
                }),
        );
        grown_ticks += usize::from(packet.entities.iter().any(|e| {
            e.visual.animation.as_deref() == Some("Default")
                && e.visual.size_pixels[0].unwrap_or(0.0) > 40.0
        }));
        // one_way_gate.gd: frame 1 while opened; a drop in the open count is a closing.
        let open = packet
            .entities
            .iter()
            .filter(|e| {
                e.visual.rotation_degrees.is_some()
                    && e.visual.animation.is_none()
                    && e.visual.frame == Some(1)
            })
            .count();
        gate_open_ticks += usize::from(open > 0);
        gate_closings += usize::from(open < gates_open);
        gates_open = open;
        // count_ledge.gd: Pressed while pressed; a ledge that breaks leaves the view.
        let ledges = packet
            .entities
            .iter()
            .filter(|e| {
                e.visible && matches!(e.visual.animation.as_deref(), Some("Pressed" | "Unpressed"))
            })
            .count();
        ledge_pressed_ticks += usize::from(
            packet
                .entities
                .iter()
                .any(|e| e.visual.animation.as_deref() == Some("Pressed")),
        );
        ledge_breaks += usize::from(ledges < ledges_left && ledges_left != usize::MAX);
        ledges_left = ledges;
        // item_stem.gd: FastLoop while bursting; late Loop frames mean a release cycle ran.
        stem_fast_ticks += usize::from(
            packet
                .entities
                .iter()
                .any(|e| e.visible && e.visual.animation.as_deref() == Some("FastLoop")),
        );
        // star_flower.gd: ticks with a fed flower (phase 1 to 5), and wilted flowers.
        let flower = |phase: i64| {
            wire.entities
                .iter()
                .filter(|e| {
                    e.code == "o22"
                        && required(&e.values, schema.entity_fields("o22"), "phase").unwrap()
                            == phase
                })
                .count()
        };
        flowers_seen += usize::from((1..=5).any(|p| flower(p) > 0));
        flowers_gone = flowers_gone.max(
            wire.entities
                .iter()
                .filter(|e| {
                    e.code == "o22"
                        && required(&e.values, schema.entity_fields("o22"), "collected").unwrap()
                            == 1
                })
                .count(),
        );
        // timed_switch.gd: ticks with the interval running, and interval (re)starts.
        let clock = required(&wire.level, schema.level(), "switch_ticks").unwrap();
        switch_ticks += usize::from(clock > 0);
        switch_restarts += usize::from(clock == 630 && switch_clock != 630);
        switch_clock = clock;
        // shell_walker.gd: spinning shells (mode 6), live runners, hop landings (mode 3).
        let shell_mode = |mode: i64| {
            wire.entities.iter().any(|e| {
                matches!(e.code.as_str(), "e6" | "e8")
                    && required(&e.values, schema.entity_fields(&e.code), "status").unwrap() == 1
                    && required(&e.values, schema.entity_fields(&e.code), "mode").unwrap() == mode
            })
        };
        shell_spin_ticks += usize::from(shell_mode(6));
        shell_hop_lands += usize::from(shell_mode(3));
        // armored_walker.gd: ticks per mode (walk, prepare, air, push, roll, recover).
        for e in wire.entities.iter().filter(|e| e.code == "e11") {
            let mode = required(&e.values, schema.entity_fields("e11"), "mode").unwrap();
            if required(&e.values, schema.entity_fields("e11"), "status").unwrap() == 1
                && (0..6).contains(&mode)
            {
                armored_modes[mode as usize] += 1;
            }
        }
        // spear_guard.gd: knocked (block), spear dropped, held by the tongue.
        for e in wire.entities.iter().filter(|e| e.code == "e22") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e22"), n).unwrap();
            spear_knocks += usize::from(f("block") > 0);
            spear_dropped += usize::from(f("has_spear") == 0);
            spear_held += usize::from(f("held") == 1);
        }
        // sneak_thief.gd: ticks per plan, carrying the bubble, worn down by stomps and
        // strikes, shoved by the tongue (sitting at the shove speed or less), defeated.
        for e in wire.entities.iter().filter(|e| e.code == "e10") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e10"), n).unwrap();
            if f("status") == 1 && (0..5).contains(&f("plan")) {
                thief_plans[f("plan") as usize] += 1;
            }
            thief_carry += usize::from(f("status") == 1 && f("carrying") == 1);
            thief_stomped += usize::from(f("jump_health") < 3);
            thief_struck += usize::from(f("hit_health") < 6);
            thief_shoved += usize::from(
                f("status") == 1 && f("pose") == 8 && (1..=128 * 60).contains(&f("vx").abs()),
            );
            thief_defeated += usize::from(f("status") == 3);
        }
        // hanging_roller.gd: ticks per mode (hang, laugh, roll), stopped by a wall (queued
        // after it started), and enemy_overlap.gd entry-contact rows.
        for e in wire.entities.iter().filter(|e| e.code == "e28") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e28"), n).unwrap();
            if f("status") == 1 && (0..3).contains(&f("mode")) {
                roller_modes[f("mode") as usize] += 1;
            }
            roller_walled += usize::from(f("status") == 2 && f("started") == 1);
        }
        overlap_ticks += usize::from(wire.entities.iter().any(|e| e.code == "enemy_overlap"));
        // masked_shooter.gd: ticks per mode (walk, prepare, inhale, shoot), held by the
        // tongue, removed; enemy_pellet.gd shots in flight.
        for e in wire.entities.iter().filter(|e| e.code == "e31") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e31"), n).unwrap();
            if f("status") == 1 && (0..4).contains(&f("mode")) {
                shooter_modes[f("mode") as usize] += 1;
            }
            shooter_held += usize::from(f("held") == 1);
            shooter_removed += usize::from(f("status") == 3);
        }
        pellet_ticks += usize::from(wire.entities.iter().any(|e| e.code == "enemy_pellet"));
        // arrow_lift.gd: riding ticks, shrink ticks, and arrow changes while riding.
        for e in wire.entities.iter().filter(|e| e.code == "o21") {
            let f = |n: &str| required(&e.values, schema.entity_fields("o21"), n).unwrap();
            lift_riding += usize::from(f("riding") == 1);
            lift_shrinks += usize::from(f("shrink") > 0);
            let angle = f("angle");
            if f("riding") == 1 && lift_angles.get(&e.id).is_some_and(|a| *a != angle) {
                lift_turns += 1;
            }
            lift_angles.insert(e.id.clone(), angle);
        }
        snow_ticks +=
            usize::from(required(&wire.player, schema.player(), "move_snow").unwrap() != 0);
        // enemy_fish.gd: ticks per mode, exhausted and dry fish.
        for e in wire
            .entities
            .iter()
            .filter(|e| matches!(e.code.as_str(), "e20" | "e21"))
        {
            let f = |n: &str| required(&e.values, schema.entity_fields(&e.code), n).unwrap();
            if f("status") == 1 && (0..5).contains(&f("mode")) {
                fish_modes[f("mode") as usize] += 1;
            }
            fish_exhausted += usize::from(f("fish_exhausted") == 1);
            fish_dry += usize::from(f("fish_dry") == 1);
        }
        // seed_melon.gd / seed_shot.gd: held and eaten melons, flying seeds, and placed
        // targets defeated or collected well ahead of the player (only a seed reaches them).
        let mut eaten = 0;
        for e in &wire.entities {
            let f = |n: &str| required(&e.values, schema.entity_fields(&e.code), n).unwrap();
            if e.code == "o25" {
                melon_held_ticks += usize::from(f("held") == 1);
                eaten += usize::from(f("status") == 3 && f("can_respawn") == 0);
            }
            if ["e1", "e6", "e35", "o1"].contains(&e.code.as_str())
                && f("source_index") >= 0
                && (f("status") == 3 || f("collected") == 1)
                && f("x") > packet.player.motion.current.x + 96 * 3600
            {
                seed_struck.insert(e.id.clone());
            }
        }
        melons_eaten = melons_eaten.max(eaten);
        // life.gd REJOIN: the world frozen while a caught companion returns.
        rejoin_ticks += usize::from(packet.player.life_phase == 1);
        // decor_platform.gd / lamp.gd: heights stood on above the floor, lamp views.
        if packet.player.on_floor && packet.player.motion.current.y < 380 * 3600 {
            ledge_heights.insert(packet.player.motion.current.y / 3600);
        }
        for e in packet.entities.iter().filter(|e| e.code == "d25") {
            lamp_views.insert(e.visual.animation.clone());
        }
        // dice_block.gd: each block's on/solid_ready states, lifted switches and tints.
        for e in wire.entities.iter().filter(|e| e.code == "o33" || e.code == "o34") {
            let f = |n: &str| required(&e.values, schema.entity_fields(&e.code), n).unwrap();
            dice_states.insert((e.id.clone(), f("on"), f("solid_ready")));
            dice_lifted += usize::from(f("busy") > 0);
        }
        for e in packet.entities.iter().filter(|e| e.code == "o33" || e.code == "o34") {
            dice_tints.insert(e.visual.tint);
        }
        // item_block.gd o24: charges used, and enemies removed while the player stands
        // far away (only a clear reaches them).
        for e in &wire.entities {
            let f = |n: &str| required(&e.values, schema.entity_fields(&e.code), n).unwrap();
            if e.code == "o24" {
                clear_charges.insert((f("charges"), f("status")));
            }
            if e.code.starts_with('e')
                && f("status") == 3
                && (f("x") - packet.player.motion.current.x).abs() > 160 * 3600
            {
                cleared.insert(e.id.clone());
            }
        }
        // rise_balloon.gd: rides (stepped), landing pauses and bobbing balloons.
        for e in wire.entities.iter().filter(|e| e.code == "o26") {
            let f = |n: &str| required(&e.values, schema.entity_fields(&e.code), n).unwrap();
            balloon_ride_ticks += usize::from(f("stepped") == 1);
            balloon_landings += usize::from(f("land_delay") == 6);
            balloon_bob_ticks += usize::from(f("status") == 1 && f("age") > 0);
        }
        // spike_pillar.gd: alive on the floor against a pillar's safe left face.
        for e in packet.entities.iter().filter(|e| e.code == "o13") {
            let right = packet.player.motion.current.x + 12 * 3600;
            pillar_side_ticks += usize::from(
                packet.player.life_phase == 0
                    && packet.player.on_floor
                    && (right - (e.motion.current.x - 16 * 3600)).abs() <= 3600
                    && (packet.player.motion.current.y - e.motion.current.y).abs() <= 32 * 3600,
            );
        }
        // egg_block.gd: rising blocks, spent blocks and what their bumps struck.
        let mut spent = 0;
        for e in wire.entities.iter().filter(|e| e.code == "o27") {
            let f = |n: &str| required(&e.values, schema.entity_fields(&e.code), n).unwrap();
            egg_block_rising += usize::from(f("busy") > 0);
            spent += usize::from(f("status") == 3);
        }
        egg_blocks_spent = egg_blocks_spent.max(spent);
        for id in ["rider", "coin"] {
            if let Some(e) = wire.entities.iter().find(|e| e.id == id) {
                let f = |n: &str| required(&e.values, schema.entity_fields(&e.code), n).unwrap();
                if f("status") == 3 || f("vy") != 0 {
                    egg_block_bumped.insert(id);
                }
            }
        }
        seed_ticks += usize::from(wire.entities.iter().any(|e| e.code == "seed_shot"));
        // ride_hound.gd: ridden, playing, swimming and jumping ticks.
        for e in wire.entities.iter().filter(|e| e.code == "o16") {
            let f = |n: &str| required(&e.values, schema.entity_fields("o16"), n).unwrap();
            hound_ridden += usize::from(f("ridden") == 1);
            hound_playing += usize::from(f("playing") == 1);
            hound_swimming += usize::from(f("swimming") == 1);
            hound_jumps += usize::from(f("mode") == 5);
        }
        // wing_drifter.gd: ticks per mode (fly, stomped, angry, charge), stomp knocks
        // (straight down) and strike knocks (along an egg or spat body), held ticks.
        for e in wire.entities.iter().filter(|e| e.code == "e30") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e30"), n).unwrap();
            if f("status") == 1 && (0..4).contains(&f("mode")) {
                wing_modes[f("mode") as usize] += 1;
            }
            if f("mode") == 1 {
                wing_stomps += usize::from(f("knock_dx") == 0 && f("knock_dy") > 0);
                wing_strikes += usize::from(f("knock_dx") != 0);
            }
            wing_held += usize::from(f("held") == 1);
        }
        // shot_launcher.gd / launcher_shot.gd: charging launchers, live shots per form,
        // bounce pauses, stomped (falling) and held shots.
        for e in wire.entities.iter().filter(|e| e.code == "e37") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e37"), n).unwrap();
            launcher_charges += usize::from(f("charge") > 0);
            bounce_fires += usize::from(f("form") == 1 && f("shot_token") != 0);
        }
        // hang_flyer.gd: ticks per mode (hang, dive, swoop, forward, flee), held ticks
        // and removals.
        for e in wire.entities.iter().filter(|e| e.code == "e14") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e14"), n).unwrap();
            if f("status") == 1 && (0..5).contains(&f("mode")) {
                hang_modes[f("mode") as usize] += 1;
            }
            hang_held += usize::from(f("held") == 1);
            if f("status") == 3 && hang_status.get(&e.id) == Some(&1) {
                hang_removals += 1;
            }
            hang_status.insert(e.id.clone(), f("status"));
        }
        // drift_spore.gd: sway turns, removals (grown or swallowed), grown sprouts and
        // their waking ticks.
        for e in wire.entities.iter().filter(|e| e.code == "e13") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e13"), n).unwrap();
            if f("status") == 1 && spore_facings.get(&e.id).is_some_and(|v| *v != f("facing")) {
                spore_turns += 1;
            }
            spore_facings.insert(e.id.clone(), f("facing"));
            if f("status") == 3 && spore_status.get(&e.id) == Some(&1) {
                spore_removals += 1;
            }
            spore_status.insert(e.id.clone(), f("status"));
        }
        for e in wire.entities.iter().filter(|e| e.code == "e12") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e12"), n).unwrap();
            if f("source_index") == -1 {
                grown_sprouts.insert(e.id.clone());
                waking_ticks += usize::from(f("mode") == 1);
            }
        }
        // gust_flyer.gd: full-speed ticks, headings flown, held ticks, removals.
        for e in wire.entities.iter().filter(|e| e.code == "e33") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e33"), n).unwrap();
            if f("status") == 1 {
                gust_full_speed += usize::from(f("ramp") == 60);
                gust_headings.insert(f("heading"));
            }
            gust_held += usize::from(f("held") == 1);
            if f("status") == 3 && gust_status.get(&e.id) == Some(&1) {
                gust_removals += 1;
            }
            gust_status.insert(e.id.clone(), f("status"));
        }
        // leap_bulk.gd: ticks per phase (wait, flatten, rise, air), squashed ticks under
        // a standing player, and defeats.
        for e in wire.entities.iter().filter(|e| e.code == "e17") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e17"), n).unwrap();
            if f("status") == 1 && (0..4).contains(&f("phase")) {
                bulk_phases[f("phase") as usize] += 1;
            }
            bulk_squashed += usize::from(f("squashed") == 1);
            if f("status") == 3 && bulk_status.get(&e.id) == Some(&1) {
                bulk_defeats += 1;
            }
            bulk_status.insert(e.id.clone(), f("status"));
        }
        // needle_juggler.gd / spike_hopper.gd: tosses, frowns, regrowth; thrown, sinking
        // and held hoppers.
        for e in wire.entities.iter().filter(|e| e.code == "e42") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e42"), n).unwrap();
            juggler_tosses += usize::from(f("thrown_now") == 1);
            juggler_frowns += usize::from(f("frowning") == 1);
            juggler_rises += usize::from(f("rise") > 0);
        }
        for e in wire.entities.iter().filter(|e| e.code == "e40") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e40"), n).unwrap();
            hopper_thrown += usize::from(f("thrown") == 1 && f("status") == 1);
            hopper_sinking += usize::from(f("sinking") == 1 && f("status") == 1);
            hopper_held += usize::from(f("held") == 1);
        }
        // hop_sprout.gd: rising hops, held ticks, removed sprouts and turns while free.
        for e in wire.entities.iter().filter(|e| e.code == "e12") {
            let f = |n: &str| required(&e.values, schema.entity_fields("e12"), n).unwrap();
            sprout_hops += usize::from(f("status") == 1 && f("vy") < 0 && f("spat") == 0);
            sprout_held += usize::from(f("held") == 1);
            if f("status") == 3 && sprout_status.get(&e.id) == Some(&1) {
                sprout_removals += 1;
            }
            sprout_status.insert(e.id.clone(), f("status"));
            if f("status") == 1
                && f("spat") == 0
                && f("held") == 0
                && sprout_facings.get(&e.id).is_some_and(|v| *v != f("facing"))
            {
                sprout_turns += 1;
            }
            sprout_facings.insert(e.id.clone(), f("facing"));
        }
        for e in wire.entities.iter().filter(|e| e.code == "enemy_shot") {
            let f = |n: &str| required(&e.values, schema.entity_fields("enemy_shot"), n).unwrap();
            if f("status") == 1 && (0..3).contains(&f("form")) {
                shot_forms[f("form") as usize] += 1;
            }
            shot_pauses += usize::from(f("pause") > 0);
            shot_falling += usize::from(f("falling") == 1);
            shot_held += usize::from(f("held") == 1);
        }
        shell_runner_ticks += usize::from(wire.entities.iter().any(|e| e.code == "enemy_runner"));
        stem_frames += usize::from(packet.entities.iter().any(|e| {
            e.visual.animation.as_deref() == Some("Loop") && e.visual.frame.unwrap_or(0) >= 10
        }));
        falling_ticks += usize::from(packet.entities.iter().any(|e| {
            e.visual.animation.as_deref() == Some("Falling") && e.visual.frame == Some(4)
        }));
        flat_ticks += usize::from(
            packet
                .entities
                .iter()
                .any(|e| e.visual.animation.as_deref() == Some("SquashWalk")),
        );
        if let Some(m) = &packet.message {
            message_ticks += 1;
            message_sections = message_sections.max(m.section + 1);
        }
        held_ticks +=
            usize::from(required(&wire.player, schema.player(), "move_held_id").unwrap() != 0);
        most_eggs = most_eggs.max(required(&wire.player, schema.player(), "move_eggs").unwrap());
        if std::env::var_os("FIXTURE_DUMP").is_some() && !restores {
            let f = |n: &str| required(&wire.player, schema.player(), n).unwrap();
            println!(
                "DUMP tick={tick} input={} action={} hurt={} held={} digest={} eggs={} serial={} x={} y={} on_floor={} cmode={} cvx={} rx={} ry={}",
                inputs.get(tick.saturating_sub(1)).copied().unwrap_or(0),
                f("move_action"), f("hurt"), f("move_held_id"), f("move_digest"), f("move_eggs"),
                f("move_emit_serial"), f("x"), f("y"), f("on_floor"), f("companion_mode"), f("companion_vx"), f("recovery_x"), f("recovery_y")
            );
            let loose: Vec<String> = packet
                .entities
                .iter()
                .filter(|e| e.code == "o7" && e.visible)
                .map(|e| {
                    format!(
                        "{},{}",
                        e.motion.current.x / 3600,
                        e.motion.current.y / 3600
                    )
                })
                .collect();
            if !loose.is_empty() {
                println!("DUMP_EGGS tick={tick} at={}", loose.join(" "));
            }
            // FIXTURE_DUMP_IDS=77,78: every Rust field of those wire entities.
            if let Ok(ids) = std::env::var("FIXTURE_DUMP_IDS") {
                for e in wire
                    .entities
                    .iter()
                    .filter(|e| ids.split(',').any(|id| id == e.id))
                {
                    let fields = schema.entity_fields(&e.code);
                    let row: Vec<String> = fields
                        .iter()
                        .zip(&e.values)
                        .map(|(f, v)| format!("{}={v}", f.0))
                        .collect();
                    println!(
                        "DUMP_ENTITY tick={tick} id={} code={} {}",
                        e.id,
                        e.code,
                        row.join(" ")
                    );
                }
            }
        }
        requests =
            requests.max(required(&wire.player, schema.player(), "move_emit_serial").unwrap());
        assert_eq!(
            packet.player.swimming,
            required(&wire.player, schema.player(), "swimming").unwrap() != 0
        );
        swimming_ticks += usize::from(packet.player.swimming);
        for (entity, picture) in wire.entities.iter().zip(&packet.entities) {
            if entity.code == "o11" {
                let fields = schema.entity_fields("o11");
                let remaining = required(&entity.values, fields, "squash").unwrap();
                let size = if required(&entity.values, fields, "large").unwrap() != 0 {
                    48.0
                } else {
                    32.0
                };
                let squash = remaining.min(12 - remaining) as f64;
                assert_eq!(
                    picture.visual.scale,
                    Some([
                        (size + 16.0 * squash / 6.0) / size,
                        (size - 16.0 * squash / 6.0) / size
                    ])
                );
                squash_ticks += usize::from(remaining != 0);
            }
        }
        assert_eq!(
            session.snapshot().unwrap(),
            actual,
            "presentation mutates saved state"
        );
        if restores && restore_ticks.contains(&tick) {
            session.restore(expected).unwrap();
            assert_eq!(session.snapshot().unwrap(), expected);
        }
        if !restores && branch_ticks.contains(&tick) {
            fs::write(root.join(format!("rust-uninterrupted-{tick}.v10")), &actual).unwrap();
        }
        if tick < inputs.len() {
            session
                .advance(inputs[tick])
                .unwrap_or_else(|error| panic!("{name} next gate at tick={}: {error}", tick + 1));
        }
    }
    assert_eq!(cursor, stream.len());
    assert_eq!(session.stats().completed_ticks, inputs.len() as u64);
    assert_eq!(
        session.stats().restore_count,
        if restores {
            restore_ticks.len() as u64
        } else {
            0
        }
    );
    if name == "bounce.pad" {
        assert!(
            squash_ticks > 0,
            "named normal route must actually activate the pad"
        );
    } else if name == "collections" {
        let hud = session.presentation().hud;
        println!(
            "COLLECTION_READOUT coins={} redcoins={} flowers={} health={} score={} collections={}",
            hud.coins,
            hud.redcoins,
            hud.flowers,
            hud.health,
            hud.score,
            session.stats().collections
        );
        assert_eq!(
            (
                hud.coins,
                hud.redcoins,
                hud.flowers,
                hud.health,
                hud.score,
                session.stats().collections
            ),
            (1, 1, 1, 11, 22, 4)
        );
    } else if name == "checkpoint_target" {
        println!("CHECKPOINT_COVERAGE checkpoint_ticks={checkpoint_ticks} respawn_ticks={checkpoint_respawn_ticks} transitions={checkpoint_transitions:?} award_ticks={checkpoint_award_ticks:?} coin_changes={checkpoint_coin_changes:?} persistence_seen={checkpoint_flags_seen} deaths={} coins={} redcoins={} flowers={}",session.presentation().hud.deaths,session.presentation().hud.coins,session.presentation().hud.redcoins,session.presentation().hud.flowers);
        assert!(checkpoint_ticks > 0 && checkpoint_respawn_ticks > 0 && checkpoint_flags_seen);
        let hud = session.presentation().hud;
        assert!(hud.coins >= 3 && hud.redcoins == 1 && hud.flowers == 1);
    } else if name.starts_with("posts_target") {
        println!("POST_COLLISION_COVERAGE floor_ticks={post_floor_ticks} maximum_x={maximum_x} changes={post_updates:?} pound_phase_ticks={pound_ticks:?} impact={impact} duck_ticks={duck_ticks} shortest_duck={shortest_duck} action_changes={action_changes:?} floor_changes={post_floor_changes:?}");
        if name == "posts_target.duck" {
            assert_eq!(duck_ticks, 20);
            assert_eq!(shortest_duck, 32 * 3600);
            assert!(post_updates.is_empty());
        }
        if name == "posts_target.pound" {
            assert_eq!(post_updates.len(), 3);
            assert_eq!(post_height, 16 * 3600);
            assert_eq!(impact, 3);
            assert!(pound_ticks.iter().all(|v| *v > 0));
            let stump = session
                .presentation()
                .entities
                .into_iter()
                .find(|e| e.placement_id.as_deref() == Some("post96"))
                .unwrap();
            assert!(stump.visible && stump.status == eggshell_spike_core::EntityStatus::Defeated);
            assert!(maximum_x > 384 * 3600);
        }
        assert!(
            post_floor_ticks > 0,
            "normal route must stand on an actual post"
        );
    } else if name == "stilts_target.knock" {
        println!("STILT_KNOCK_COVERAGE knocked_ticks={knock_ticks} tongue_ticks={tongue_ticks} first={first_knock:?} last={last_knock:?}");
        assert!(knock_ticks > 0 && tongue_ticks > 0);
    } else if name == "stilts_target" {
        println!("STILT_RUNTIME_COVERAGE max_runtime={max_runtime} runtime_ticks={runtime_ticks} first_spawn={first_spawn:?} first_compaction={first_compaction:?} serial={last_serial} knocked_ticks={knock_ticks}");
        assert!(
            max_runtime > 0
                && last_serial > 1
                && runtime_ticks > 0
                && first_compaction > first_spawn,
            "normal stilt route must unseat a rider"
        );
    } else if name == "actors_target" {
        assert!(captured_ticks > 0 && head_ticks > 0 && rescuer_ticks > 0);
        assert!(phases.contains(&2) && phases.contains(&3) && phases.contains(&5));
        println!("ACTOR_LIFE_COVERAGE captured_ticks={captured_ticks} head_ticks={head_ticks} rescuers_visible_ticks={rescuer_ticks} phases={phases:?} companion_modes={modes:?}");
        println!(
            "ACTOR_COURSE_DONE hits={} deaths={} life_phase={}",
            session.presentation().hud.hits,
            session.presentation().hud.deaths,
            session.presentation().hud.life_phase
        );
    } else if name == "hounds_target" {
        println!("HOUND_COVERAGE ridden={hound_ridden} playing={hound_playing} swimming={hound_swimming} jumping={hound_jumps}");
        assert!(hound_ridden > 0 && hound_playing > 0 && hound_swimming > 0 && hound_jumps > 0);
    } else if name == "melons_target" {
        println!("MELON_COVERAGE held_ticks={melon_held_ticks} eaten={melons_eaten} seed_ticks={seed_ticks} struck={seed_struck:?}");
        assert!(melon_held_ticks > 0 && melons_eaten >= 3 && seed_ticks > 0);
        assert!(seed_struck.len() >= 3, "seeds must strike placed targets");
    } else if name == "hangs_target" {
        println!("HANG_COVERAGE mode_ticks={hang_modes:?} held_ticks={hang_held} removals={hang_removals}");
        assert!(hang_modes.iter().all(|n| *n > 0) && hang_held > 0 && hang_removals > 0);
    } else if name == "spores_target" {
        println!("SPORE_COVERAGE turns={spore_turns} removals={spore_removals} grown={} waking_ticks={waking_ticks}", grown_sprouts.len());
        // At least one spore is swallowed rather than grown.
        assert!(
            spore_turns > 0
                && !grown_sprouts.is_empty()
                && waking_ticks > 0
                && spore_removals > grown_sprouts.len()
        );
    } else if name == "gusts_target" {
        println!("GUST_COVERAGE full_speed_ticks={gust_full_speed} headings={gust_headings:?} held_ticks={gust_held} removals={gust_removals}");
        assert!(
            gust_full_speed > 0 && gust_headings.len() >= 4 && gust_held > 0 && gust_removals > 0
        );
    } else if name == "bulks_target" {
        println!("BULK_COVERAGE phase_ticks={bulk_phases:?} squashed_ticks={bulk_squashed} defeats={bulk_defeats} max_runtime={max_runtime}");
        assert!(
            bulk_phases.iter().all(|n| *n > 0)
                && bulk_squashed > 0
                && bulk_defeats > 0
                && max_runtime > 0
        );
    } else if name == "jugglers_target" {
        println!("JUGGLER_COVERAGE toss_ticks={juggler_tosses} frown_ticks={juggler_frowns} rise_ticks={juggler_rises} thrown_ticks={hopper_thrown} sinking_ticks={hopper_sinking} held_ticks={hopper_held}");
        assert!(
            juggler_tosses > 0
                && juggler_frowns > 0
                && juggler_rises > 0
                && hopper_thrown > 0
                && hopper_sinking > 0
                && hopper_held > 0
        );
    } else if name == "sprouts_target" {
        println!("SPROUT_COVERAGE hop_ticks={sprout_hops} held_ticks={sprout_held} removals={sprout_removals} turns={sprout_turns}");
        assert!(sprout_hops > 0 && sprout_held > 0 && sprout_removals >= 2 && sprout_turns > 0);
    } else if name == "launchers_target" {
        println!("LAUNCHER_COVERAGE charge_ticks={launcher_charges} shot_form_ticks={shot_forms:?} bounce_fires={bounce_fires} pause_ticks={shot_pauses} falling_ticks={shot_falling} held_ticks={shot_held}");
        // A bouncing shot overlaps its launcher's solid when fresh and is removed at once.
        assert!(
            launcher_charges > 0
                && shot_forms[0] > 0
                && shot_forms[2] > 0
                && bounce_fires > 0
                && shot_falling > 0
                && shot_held > 0
        );
    } else if name == "wings_target" {
        println!("WING_COVERAGE mode_ticks={wing_modes:?} stomp_ticks={wing_stomps} strike_ticks={wing_strikes} held_ticks={wing_held}");
        assert!(
            wing_modes.iter().all(|n| *n > 0)
                && wing_stomps > 0
                && wing_strikes > 0
                && wing_held > 0
        );
    } else if name == "rejoin_target" {
        println!("REJOIN_COVERAGE rejoin_ticks={rejoin_ticks}");
        assert!(rejoin_ticks >= 51);
    } else if name == "decor_target" {
        println!("DECOR_COVERAGE ledge_heights={ledge_heights:?} lamp_views={lamp_views:?}");
        // Feet just above the strips' tops (y 322 and 282 px).
        assert!(ledge_heights.contains(&321) && ledge_heights.contains(&281));
        assert!(lamp_views.len() == 2);
    } else if name == "dice_target" {
        println!("DICE_COVERAGE states={dice_states:?} lifted_ticks={dice_lifted} tints={dice_tints:?}");
        for id in ["blockA", "blockB", "blockC", "switch1", "switch2"] {
            assert!(
                dice_states.iter().any(|s| s.0 == id && s.1 == 0)
                    && dice_states.iter().any(|s| s.0 == id && s.1 == 1),
                "{id} must flip"
            );
        }
        assert!(dice_lifted > 0 && dice_tints.contains(&Some([0, 128, 255])));
    } else if name == "clears_target" {
        println!("CLEAR_COVERAGE charges={clear_charges:?} cleared={cleared:?} serial={last_serial} max_runtime={max_runtime}");
        assert!(clear_charges.contains(&(0, 3)) && cleared.len() >= 4);
        // The unseated rider is created during the clear and cleared in the same step, so
        // the serial moved but no runtime row ever reaches a snapshot.
        assert!(last_serial >= 2 && max_runtime == 0, "the unseated rider is cleared too");
    } else if name == "balloons_target" {
        println!("BALLOON_COVERAGE ride_ticks={balloon_ride_ticks} landings={balloon_landings} bob_ticks={balloon_bob_ticks}");
        assert!(balloon_ride_ticks > 0 && balloon_landings >= 2 && balloon_bob_ticks > 0);
    } else if name == "pillars_target" {
        let deaths = session.presentation().hud.deaths;
        println!("PILLAR_COVERAGE side_ticks={pillar_side_ticks} deaths={deaths}");
        assert!(pillar_side_ticks > 0 && deaths >= 2);
    } else if name == "eggblocks_target" {
        // Each spent block spawned its egg (the serial counts them; the player takes each
        // egg in the tick it appears, so none is left in a snapshot).
        println!("EGG_BLOCK_COVERAGE rising_ticks={egg_block_rising} spent={egg_blocks_spent} bumped={egg_block_bumped:?} most_eggs={most_eggs} serial={last_serial}");
        assert!(egg_block_rising > 0 && egg_blocks_spent >= 4 && most_eggs >= 4 && last_serial >= 5);
        assert!(!egg_block_bumped.is_empty(), "a bump must strike what stands on a block");
    } else if name == "fish_target" {
        println!("FISH_COVERAGE mode_ticks={fish_modes:?} exhausted_ticks={fish_exhausted} dry_ticks={fish_dry}");
        assert!(fish_modes.iter().all(|n| *n > 0) && fish_exhausted > 0 && fish_dry > 0);
    } else if name == "snowflow_target" {
        println!("SNOW_COVERAGE snow_ticks={snow_ticks}");
        assert!(snow_ticks > 0);
    } else if name == "lifts_target" {
        println!("LIFT_COVERAGE riding_ticks={lift_riding} shrink_ticks={lift_shrinks} reflections={lift_turns}");
        assert!(lift_riding > 0 && lift_shrinks > 0 && lift_turns > 0);
    } else if name == "shooters_target" {
        println!("SHOOTER_COVERAGE mode_ticks={shooter_modes:?} held_ticks={shooter_held} removed_ticks={shooter_removed} pellet_ticks={pellet_ticks}");
        assert!(
            shooter_modes.iter().all(|n| *n > 0)
                && shooter_held > 0
                && shooter_removed > 0
                && pellet_ticks > 0
        );
    } else if name == "rollers_target" {
        println!("ROLLER_COVERAGE mode_ticks={roller_modes:?} walled_ticks={roller_walled} overlap_ticks={overlap_ticks}");
        assert!(roller_modes.iter().all(|n| *n > 0) && roller_walled > 0 && overlap_ticks > 0);
    } else if name == "thieves_target" {
        println!("THIEF_COVERAGE plan_ticks={thief_plans:?} carry_ticks={thief_carry} stomped_ticks={thief_stomped} struck_ticks={thief_struck} shoved_ticks={thief_shoved} defeated_ticks={thief_defeated}");
        assert!(
            thief_plans.iter().all(|n| *n > 0)
                && thief_carry > 0
                && thief_stomped > 0
                && thief_struck > 0
                && thief_shoved > 0
                && thief_defeated > 0
        );
    } else if name == "spears_target" {
        println!("SPEAR_COVERAGE knock_ticks={spear_knocks} dropped_ticks={spear_dropped} held_ticks={spear_held}");
        assert!(spear_knocks > 0 && spear_dropped > 0 && spear_held > 0);
    } else if name == "armored_target" {
        println!("ARMORED_COVERAGE mode_ticks={armored_modes:?}");
        assert!(armored_modes.iter().all(|n| *n > 0));
    } else if name == "shells_target" {
        println!("SHELL_COVERAGE spin_ticks={shell_spin_ticks} runner_ticks={shell_runner_ticks} hop_land_ticks={shell_hop_lands}");
        assert!(shell_spin_ticks > 0 && shell_runner_ticks > 0 && shell_hop_lands > 0);
    } else if name == "switches_target" {
        println!("SWITCH_COVERAGE clock_ticks={switch_ticks} starts={switch_restarts}");
        assert!(switch_ticks > 630 && switch_restarts > 1);
    } else if name == "flowers_target" {
        println!("FLOWER_COVERAGE fed_ticks={flowers_seen} wilted={flowers_gone} max_runtime={max_runtime}");
        assert!(flowers_seen > 0 && flowers_gone > 0 && max_runtime > 0);
    } else if name == "stems_target" {
        println!("STEM_COVERAGE fast_ticks={stem_fast_ticks} release_frames={stem_frames} max_runtime={max_runtime}");
        assert!(stem_fast_ticks > 0 && stem_frames > 0 && max_runtime > 0);
    } else if name == "ledges_target" {
        println!("LEDGE_COVERAGE pressed_ticks={ledge_pressed_ticks} breaks={ledge_breaks}");
        assert!(ledge_pressed_ticks > 0 && ledge_breaks > 0);
    } else if name == "gates_target" {
        println!("GATE_COVERAGE open_ticks={gate_open_ticks} closings={gate_closings}");
        assert!(gate_open_ticks > 0 && gate_closings > 0);
    } else if name == "grows_target" {
        println!("GROW_COVERAGE grown_ticks={grown_ticks} raised_floor_ticks={raised_floor_ticks}");
        assert!(grown_ticks > 0 && raised_floor_ticks > 0);
    } else if name == "falls_target" {
        println!(
            "FALL_COVERAGE falling_ticks={falling_ticks} raised_floor_ticks={raised_floor_ticks}"
        );
        assert!(falling_ticks > 0 && raised_floor_ticks > 0);
    } else if name == "hards_target" {
        println!("HARD_COVERAGE cracked_or_broken_ticks={cracked_ticks} most_eggs={most_eggs}");
        assert!(cracked_ticks > 0 && most_eggs > 0);
    } else if name == "flats_target" {
        // The flat route must flatten a walker and stand on a raised (flat) floor.
        println!("FLAT_COVERAGE flat_ticks={flat_ticks} raised_floor_ticks={raised_floor_ticks}");
        assert!(flat_ticks > 0 && raised_floor_ticks > 0);
    } else if name == "spans_target" {
        // The span route must stand on top-only spans above the ground.
        println!("SPAN_COVERAGE raised_floor_ticks={raised_floor_ticks}");
        assert!(raised_floor_ticks > 0);
    } else if name == "blocks_target" {
        // The block route must open the message, page it and get eggs from a block.
        println!("BLOCK_COVERAGE message_ticks={message_ticks} sections_read={message_sections} first_spawn={first_spawn:?} max_runtime={max_runtime} most_eggs={most_eggs}");
        assert!(message_ticks > 0 && message_sections > 1 && first_spawn.is_some());
    } else if name == "corpus" {
        println!("CORPUS_PARITY ticks={}", inputs.len());
    } else {
        assert!(tongue_ticks > 0);
        if name == "lagoon" {
            assert!(swimming_ticks > 0);
        }
    }
    if pictures.is_some() {
        println!("LEGAL_INACTIVE_VISIBILITY_COVERAGE fixture={name} waiting_samples={inactive_waiting_samples} queued_samples={inactive_queued_samples} original_policy=true");
    }
    if name == "stride.eat" {
        // The eating route must really eat, spit and lay, or it proves nothing.
        assert!(
            held_ticks > 0 && most_eggs > 0 && requests >= 3,
            "held={held_ticks} eggs={most_eggs} requests={requests}"
        );
    }
    println!("FIXTURE_VERTICAL_DONE fixture={name} snapshots={} accepted_ticks={} saved_frame={} uninterrupted={} A_to_B_restores={} bridge_support_ticks={bridge_ticks} pad_squash_ticks={squash_ticks} tongue_ticks={tongue_ticks} swimming_ticks={swimming_ticks} held_ticks={held_ticks} most_eggs={most_eggs} requests={requests} target_admission=refused",inputs.len()+1,session.stats().completed_ticks,session.stats().tick,!restores,session.stats().restore_count);
}
#[test]
#[ignore = "requires original Godot fixture stream"]
fn admitted_fixture_has_uninterrupted_every_tick_parity() {
    run(false);
}
#[test]
#[ignore = "requires original Godot fixture stream"]
fn admitted_fixture_has_original_restore_continuation() {
    run(true);
}
#[test]
#[ignore = "requires original schema and collection verification course"]
fn popup_coordinate_headroom_refuses_atomically() {
    if std::env::var("CORE_FIXTURE").unwrap() != "collections" {
        return;
    }
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_FIXTURE_DIR").unwrap());
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let mut session = Session::load(
        &fs::read_to_string(std::env::var("CORE_FIXTURE_LEVEL").unwrap()).unwrap(),
        &fs::read_to_string(project.join("src/level/collision_table.json")).unwrap(),
        &metadata,
    )
    .unwrap();
    let before = session.snapshot().unwrap();
    let mut wire = WireSnapshot::decode(&before, session.world().identity, &schema).unwrap();
    let red = wire.entities.iter_mut().find(|e| e.code == "o2").unwrap();
    let fields = schema.entity_fields("o2");
    for (name, value) in [
        ("collect_y", i64::MIN),
        ("collect_ticks", 1),
        ("collected", 1),
    ] {
        let index = fields.iter().position(|f| f.0 == name).unwrap();
        red.values[index] = value;
    }
    let malformed = wire.encode(&schema).unwrap();
    assert!(session.restore(&malformed).is_err());
    assert_eq!(session.snapshot().unwrap(), before);
    assert_eq!(session.stats().restore_count, 0);
}
// The former refusal of tongue food is gone: eating is ported (P1) and checked
// against Godot by the stride.eat fixture route.
