//! Real pack Vorbis -> decoder thread -> SDL callback, driven by real saved steps.
//! Use SDL_AUDIODRIVER=dummy for a host check without physical audio output.
use eggshell_spike_core::Session;
use eggshell_spike_player::{
    audio::{AudioMap, Command, Device, Mixer, MixerStats, MusicStream, Observer},
    feel::FeelSettings,
    pack::Pack,
};
use std::{path::Path, sync::Arc, sync::atomic::Ordering, sync::mpsc, time::Duration};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.len() != 3 {
        return Err("usage: audio_probe SCHEMA.json PACK_ROOT PACK_INVENTORY.json".into());
    }
    let schema = std::fs::read_to_string(&args[0]).map_err(|e| e.to_string())?;
    let pack = Pack::open(Path::new(&args[1]), Path::new(&args[2]))?;
    let map = AudioMap::parse(&pack.manifest);
    let file = map.music.get("1").ok_or("pack lacks music 1")?;
    let bytes: Arc<[u8]> = Arc::from(pack.verified_bytes(file)?);
    let (sender, receiver) = mpsc::channel();
    let stats = Arc::new(MixerStats::default());
    let mut mixer = Mixer::new(receiver, stats.clone());
    sender
        .send(Command::Music {
            stream: MusicStream::start(bytes, true, 0)?,
            gain: 0.8,
        })
        .map_err(|_| "mixer closed")?;
    let mut peak = 0.0_f32;
    for _ in 0..100 {
        let mut out = [0.0; 2048];
        mixer.mix(&mut out);
        peak = out.iter().fold(peak, |peak, x| peak.max(x.abs()));
        if peak > 0.0 {
            break;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(peak > 0.0, "stream produced no music samples");
    assert_eq!(stats.decode_errors.load(Ordering::Relaxed), 0);
    println!("AUDIO_PROBE_STREAM file={file} nonzero_peak={peak:.6} decoder_errors=0");
    drop(mixer);

    let sdl = sdl2::init()?;
    for (name, level) in [
        (
            "collections",
            include_str!("../../core/tests/fixtures/collections.level.json"),
        ),
        (
            "lagoon",
            include_str!("../../../../tests/fixtures/lagoon.level.json"),
        ),
    ] {
        // These public courses omit music. Select the real pack track in memory only.
        let mut level: serde_json::Value =
            serde_json::from_str(level).map_err(|e| e.to_string())?;
        level["maps"]["map1"]["music"] = serde_json::json!(1);
        let level = level.to_string();
        let collision = include_str!("../../../../data/collision_table.json");
        let mut on = Session::load_benchmark_unverified(&level, collision, &schema)?;
        let mut off = Session::load_benchmark_unverified(&level, collision, &schema)?;
        let (device, out) = Device::open(&sdl)?;
        let mut audio = Observer::new(map.clone(), on.world(), Some(&pack), Some(out))?;
        let mut disabled_audio = Observer::new(map.clone(), off.world(), None, None)?;
        let settings = FeelSettings::default();
        let disabled = FeelSettings {
            muffle_enabled: false,
            goal_music_enabled: false,
            ..settings
        };
        let mut wet_steps = 0;
        for _ in 0..400 {
            on.advance(2)?;
            off.advance(2)?;
            let snapshot = on.snapshot()?;
            let p = on.presentation();
            wet_steps += usize::from(p.player.swimming);
            audio.observe(&on);
            audio.observe_feel(&p, settings);
            disabled_audio.observe(&off);
            disabled_audio.observe_feel(&off.presentation(), disabled);
            assert_eq!(on.snapshot()?, snapshot, "audio wrote saved state");
            assert_eq!(
                snapshot,
                off.snapshot()?,
                "audio settings changed save bytes"
            );
            // Allow the real SDL callback and decoder to run while advancing the course.
            std::thread::sleep(Duration::from_millis(2));
        }
        if name == "lagoon" {
            assert!(wet_steps > 0, "course never entered water");
        }
        assert!(device.stats.music_started.load(Ordering::Relaxed) > 0);
        assert!(device.stats.callbacks.load(Ordering::Relaxed) > 0);
        assert_eq!(device.stats.decode_errors.load(Ordering::Relaxed), 0);
        println!(
            "AUDIO_PROBE level={name} steps=400 wet_steps={wet_steps} save_bytes_identical=true playback={}",
            device.summary()
        );
    }
    Ok(())
}
