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
    // Every physical face and shoulder, through actual SDL sampling and events.
    for (layout, expected) in [
        (ButtonLayout::Snes, [JUMP, 64, 8, 64, 128, 128]),
        (ButtonLayout::Xbox, [JUMP, JUMP, 8, 8, 64, 128]),
    ] {
        controls.mask(layout);
        for (button, expected) in [0, 1, 2, 3, 9, 10].into_iter().zip(expected) {
            controls.clear_steps();
            unsafe {
                assert_eq!(sys::SDL_JoystickSetVirtualButton(raw, button, 1), 0);
                sys::SDL_JoystickUpdate();
            }
            for event in events.poll_iter() {
                controls.event(event);
            }
            let live = controls.mask(layout);
            assert_eq!(
                controls.step_mask(live),
                expected,
                "{layout:?} physical button {button}"
            );
            if button < 2 {
                let confirm = match layout {
                    ButtonLayout::Snes => button == 0,
                    ButtonLayout::Xbox => button == 1,
                };
                assert_eq!(controls.menu_mask, if confirm { JUMP } else { 8 });
            }
            unsafe {
                assert_eq!(sys::SDL_JoystickSetVirtualButton(raw, button, 0), 0);
                sys::SDL_JoystickUpdate();
            }
            for event in events.poll_iter() {
                controls.event(event);
            }
            let live = controls.mask(layout);
            assert_eq!(controls.step_mask(live), 0);
        }
    }
    controls.mask(ButtonLayout::Snes);
    println!(
        "INPUT_LAYOUT_PROBE snes_positions=true xbox_unchanged=true both_shoulders=true menu_confirm_back=true"
    );
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
        // Down uses the live axis while jump edges are queued separately.
        set(false);
        unsafe {
            assert_eq!(sys::SDL_JoystickSetVirtualAxis(raw, 1, 32767), 0);
            sys::SDL_JoystickUpdate();
        }
        let mut down_poses = 0;
        let mut max_down_y = f64::NEG_INFINITY;
        for _ in 0..180 {
            let live = batch(&mut controls, &mut events);
            let mask = controls.step_mask(live);
            assert_ne!(mask & eggshell_spike_player::input::DOWN, 0);
            session.advance(mask).unwrap();
            let p = session.presentation();
            down_poses += usize::from(p.player.selected_pose.name.starts_with("Submerge"));
            max_down_y = max_down_y.max(p.player.motion.current.y as f64 / SCALE as f64);
            assert!(p.player.swimming);
        }
        assert!(down_poses > 150);
        assert!(
            max_down_y < 340.0,
            "Down is a posture, not downward swimming"
        );
        unsafe {
            assert_eq!(sys::SDL_JoystickSetVirtualAxis(raw, 1, 0), 0);
            sys::SDL_JoystickUpdate();
        }
        set(true);
        let mut exits = 0;
        let mut jumps = 0;
        for _ in 0..120 {
            let live = batch(&mut controls, &mut events);
            session.advance(controls.step_mask(live)).unwrap();
            let p = session.presentation();
            exits += usize::from(!p.player.swimming);
            jumps += usize::from(p.player.selected_pose.name == "Jump0");
        }
        assert!(jumps > 0 && exits > 0);
        println!(
            "INPUT_WATER_PROBE actual_showcase=true down_steps=180 submerge_pose_steps={down_poses} deepest_down_feet={max_down_y:.3} jump_pose_steps={jumps} dry_steps={exits}"
        );
    }
    unsafe {
        sys::SDL_JoystickClose(raw);
        sys::SDL_JoystickDetachVirtual(index);
    }
    println!("INPUT_PROBE virtual_sdl_gamepad=true edges_preserved=true");
}
