//! Host-only SDL virtual gamepad: real controller events, sampling and step delivery.
use eggshell_spike_player::{
    feel::ButtonLayout,
    input::{Controls, JUMP},
};
use sdl2::sys;
fn main() {
    let sdl = sdl2::init().unwrap();
    let js = sdl.joystick().unwrap();
    let gc = sdl.game_controller().unwrap();
    // SDL virtual joystick is a real SDL input implementation, with no device I/O.
    let index = unsafe {
        sys::SDL_JoystickAttachVirtual(
            sys::SDL_JoystickType::SDL_JOYSTICK_TYPE_GAMECONTROLLER,
            6,
            21,
            0,
        )
    };
    assert!(index >= 0, "{}", sdl2::get_error());
    let joy = js.open(index as u32).unwrap();
    gc.add_mapping(&format!("{},Step probe,a:b0,b:b1,x:b2,y:b3,back:b4,start:b6,leftshoulder:b9,rightshoulder:b10,leftx:a0,lefty:a1,",joy.guid())).unwrap();
    let mut controls = Controls::open(&sdl).unwrap();
    let mut events = sdl.event_pump().unwrap();
    let raw = unsafe { sys::SDL_JoystickOpen(index) };
    let set = |down| unsafe {
        assert_eq!(sys::SDL_JoystickSetVirtualButton(raw, 0, u8::from(down)), 0);
        sys::SDL_JoystickUpdate();
    };
    let batch = |controls: &mut Controls, events: &mut sdl2::EventPump| {
        for event in events.poll_iter() {
            controls.event(event);
        }
        controls.mask(ButtonLayout::Snes)
    };
    set(true);
    let live = batch(&mut controls, &mut events);
    assert_ne!(live & JUMP, 0);
    // Establish held JUMP at a simulation step.
    let delivered = controls.step_mask(live);
    assert_ne!(delivered & JUMP, 0);
    // Device can release/repress inside one event batch, or while no step is owed.
    set(false);
    set(true);
    let live = batch(&mut controls, &mut events);
    assert_ne!(live & JUMP, 0); // instantaneous state alone loses the release
    assert_eq!(
        controls.step_mask(live) & JUMP,
        0,
        "release lost in the real SDL path"
    );
    assert_ne!(controls.step_mask(live) & JUMP, 0, "fresh press lost");
    assert_ne!(controls.step_mask(live) & JUMP, 0, "held state lost");
    set(false);
    let live = batch(&mut controls, &mut events);
    assert_eq!(controls.step_mask(live) & JUMP, 0);
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.len() == 2 {
        use eggshell_spike_core::{SCALE, Session};
        let schema = std::fs::read_to_string(&args[0]).unwrap();
        let mut level: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&args[1]).unwrap()).unwrap();
        // Exact showcase terrain/objects, moved spawn to the pool floor only.
        level["startpoint"]["X"] = 800.into();
        level["startpoint"]["Y"] = 384.into();
        let mut session = Session::load_benchmark_unverified(
            &level.to_string(),
            include_str!("../../../../src/level/collision_table.json"),
            &schema,
        )
        .unwrap();
        controls.clear_steps();
        set(true);
        let mut min_feet = f64::INFINITY;
        let mut max_feet = f64::NEG_INFINITY;
        for _ in 0..180 {
            let live = batch(&mut controls, &mut events);
            session.advance(controls.step_mask(live)).unwrap();
            let feet = session.presentation().player.motion.current.y as f64 / SCALE as f64;
            min_feet = min_feet.min(feet);
            max_feet = max_feet.max(feet);
        }
        let p = session.presentation();
        println!(
            "INPUT_WATER_PROBE actual_showcase=true held_steps=180 feet_y={:.3} range=[{min_feet:.3},{max_feet:.3}] swimming={} velocity_y={}",
            p.player.motion.current.y as f64 / SCALE as f64,
            p.player.swimming,
            p.player.velocity.y
        );
        assert!(p.player.swimming);
        // Release/repress in the very same SDL batch, then consume actual step masks.
        set(false);
        set(true);
        let live = batch(&mut controls, &mut events);
        assert_eq!(controls.step_mask(live) & JUMP, 0);
        session.advance(0).unwrap();
        let mut exits = 0;
        let mut jumps = 0;
        for _ in 0..120 {
            let live = batch(&mut controls, &mut events);
            session.advance(controls.step_mask(live)).unwrap();
            let p = session.presentation();
            exits += usize::from(!p.player.swimming);
            jumps += usize::from(p.player.selected_pose.name == "Jump0");
        }
        let p = session.presentation();
        assert_eq!((jumps, exits), (0, 0));
        println!(
            "INPUT_WATER_PROBE actual_showcase=true fresh_edge_delivered=true after_steps=120 jump_pose_steps={jumps} dry_steps={exits} feet_y={:.3} probe50_y={:.3}",
            p.player.motion.current.y as f64 / SCALE as f64,
            p.player.motion.current.y as f64 / SCALE as f64 - 50.0
        );
        // Probe a separately authored in-memory comparison: same water3 surface,
        // full-contact interior cells (cell 1) instead of submerged dry caps.
        let mut water: serde_json::Value =
            serde_json::from_str(level["maps"]["map1"]["layer1"]["water3"].as_str().unwrap())
                .unwrap();
        let mut cells = vec![-1; 50 * 14];
        for y in 9..12 {
            for x in 22..31 {
                cells[y * 50 + x] = i32::from(y > 9);
            }
        }
        water["data"] = cells
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(",")
            .into();
        level["maps"]["map1"]["layer1"]["water3"] = water.to_string().into();
        let mut session = Session::load_benchmark_unverified(
            &level.to_string(),
            include_str!("../../../../src/level/collision_table.json"),
            &schema,
        )
        .unwrap();
        for _ in 0..180 {
            let live = batch(&mut controls, &mut events);
            session.advance(controls.step_mask(live)).unwrap();
        }
        let p = session.presentation();
        println!(
            "INPUT_WATER_PROBE full_interior_comparison=true settled_feet_y={:.3} probe50_y={:.3}",
            p.player.motion.current.y as f64 / SCALE as f64,
            p.player.motion.current.y as f64 / SCALE as f64 - 50.0
        );
        set(false);
        set(true);
        let live = batch(&mut controls, &mut events);
        session.advance(controls.step_mask(live)).unwrap();
        let mut exit = None;
        for age in 1..=30 {
            let live = batch(&mut controls, &mut events);
            session.advance(controls.step_mask(live)).unwrap();
            if !session.presentation().player.swimming {
                exit = Some(age);
                break;
            }
        }
        assert!(exit.is_some());
        println!(
            "INPUT_WATER_PROBE full_interior_comparison=true real_sdl_fresh_press_exit_steps={exit:?}"
        );
    }
    set(false);
    batch(&mut controls, &mut events);
    controls.clear_steps();
    let key = |keycode, down| {
        use sdl2::{event::Event, keyboard::Mod};
        if down {
            Event::KeyDown {
                timestamp: 0,
                window_id: 0,
                keycode: Some(keycode),
                scancode: None,
                keymod: Mod::NOMOD,
                repeat: false,
            }
        } else {
            Event::KeyUp {
                timestamp: 0,
                window_id: 0,
                keycode: Some(keycode),
                scancode: None,
                keymod: Mod::NOMOD,
                repeat: false,
            }
        }
    };
    use sdl2::keyboard::Keycode;
    controls.event(key(Keycode::Space, true));
    let live = controls.mask(ButtonLayout::Snes);
    assert_ne!(controls.step_mask(live) & JUMP, 0);
    controls.event(key(Keycode::Z, true));
    controls.event(key(Keycode::Space, false));
    let live = controls.mask(ButtonLayout::Snes);
    assert_ne!(live & JUMP, 0);
    assert_ne!(controls.step_mask(live) & JUMP, 0);
    controls.event(key(Keycode::Z, false));
    let live = controls.mask(ButtonLayout::Snes);
    assert_eq!(controls.step_mask(live) & JUMP, 0);
    println!("INPUT_PROBE keyboard_jump_alias_release=true");
    unsafe {
        sys::SDL_JoystickClose(raw);
    }
    println!(
        "INPUT_PROBE real_sdl_virtual_pad=true same_batch_release_press=preserved per_step_masks=[4,0,4,4,0]"
    );
}
