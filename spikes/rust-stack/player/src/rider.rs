//! The mounted rider is separate art, attached to the current body's saddle point.
use crate::binding::{Frame, Visual};
use eggshell_spike_core::Presentation;

pub fn frame<'a>(p: &Presentation, art: &'a Visual) -> Result<&'a Frame, String> {
    let pose = &p.player.selected_pose;
    let (name, literal) = selection(
        &pose.name,
        pose.tick,
        p.player.velocity.x,
        p.player.on_floor,
    );
    art.sample_required(pose.tick, name, 0, literal)
}
fn selection(pose: &str, _tick: i64, vx: i64, grounded: bool) -> (&'static str, Option<i64>) {
    if pose.starts_with("Duck") {
        ("LookDown", None)
    } else if pose.starts_with("LookUp") {
        ("LookUp", None)
    } else if grounded && vx.abs() * 60 > 320 * eggshell_spike_core::SCALE {
        ("Move", Some(0))
    } else {
        ("Idle", None)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn aim_and_toss_keep_separate_rider_art_not_a_frozen_body_offset() {
        for pose in ["GrabEgg0", "WalkAimR0", "WalkAimL0", "EggToss0"] {
            assert_eq!(selection(pose, 0, 0, true), ("Idle", None));
            assert_eq!(
                selection(pose, 0, 6 * eggshell_spike_core::SCALE, true),
                ("Move", Some(0))
            );
        }
        assert_eq!(selection("Duck0", 5, 0, true), ("LookDown", None));
        assert_eq!(selection("LookUp0", 5, 0, true), ("LookUp", None));
    }
    #[test]
    fn saddle_point_tracks_each_frame_and_mirrors_at_pack_density() {
        use crate::egg_trail::frame_with_point;
        let frames = [
            frame_with_point(
                "a.png",
                [46, 62],
                [16, 62],
                ("Saddle", 18.0 / 46.0, 24.0 / 62.0),
            ),
            frame_with_point(
                "b.png",
                [56, 62],
                [24, 62],
                ("Saddle", 18.0 / 56.0, 24.0 / 62.0),
            ),
        ];
        let manifest = serde_json::json!({"player":{"EggToss0":{"frames":frames}}});
        let mut catalog = crate::binding::Catalog::default();
        catalog.image("a.png").unwrap();
        catalog.image("b.png").unwrap();
        let points = crate::egg_trail::HandPoints::prepare_named(&manifest, &catalog, "Saddle");
        assert_eq!(points.at(0, [100.0, 200.0], 1, 1), Some([102.0, 162.0]));
        assert_eq!(points.at(1, [100.0, 200.0], 1, 1), Some([94.0, 162.0]));
        assert_eq!(points.at(1, [100.0, 200.0], -1, 2), Some([103.0, 181.0]));
    }
}
