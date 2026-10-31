//! Literal ScreenPlan policy. This is drawing-only and never feeds activation.
#[derive(Clone, Copy, Debug)]
pub struct Plan {
    pub scale: f64,
    pub center: [f64; 2],
    pub visible: [f64; 2],
    pub offset: [f64; 2],
    pub base_scale: f64,
    pub zoom: i32,
    pub zoom_min: i32,
    pub zoom_max: i32,
}
pub fn plan(
    container: [f64; 2],
    level: [f64; 2],
    focus: [f64; 2],
    density: u32,
    zoom: i32,
) -> Result<Plan, String> {
    if container
        .into_iter()
        .chain(level)
        .any(|v| !v.is_finite() || v <= 0.0)
        || focus.into_iter().any(|v| !v.is_finite())
        || density == 0
    {
        return Err("invalid screen plan input".into());
    }
    let d = density as f64;
    let reference = (container[0] * container[1] / (832.0 * 448.0)).sqrt() / d;
    let mut k = (reference.floor() as i32).max(1);
    if reference > (k as f64 * (k + 1) as f64).sqrt() {
        k += 1;
    }
    let fit = ((container[0] / (level[0] * d))
        .max(container[1] / (level[1] * d))
        .ceil() as i32)
        .max(1);
    k = k.max(fit);
    let closest = (container[0] / (208.0 * d))
        .min(container[1] / (112.0 * d))
        .floor() as i32;
    let largest = k.max(closest);
    // Deviation from the Godot camera (user request on the Pro): zooming out may go below
    // `fit` down to 1x. The default (zoom 0) is unchanged. A view larger than the level
    // centres the level on that axis; the bands outside it show the clear colour.
    let smallest = 1;
    let multiple = k.saturating_add(zoom).clamp(smallest, largest);
    let scale = multiple as f64 * d;
    let visible = [container[0] / scale, container[1] / scale];
    let center = std::array::from_fn(|i| {
        if visible[i] >= level[i] {
            level[i] / 2.0
        } else {
            focus[i].clamp(visible[i] / 2.0, level[i] - visible[i] / 2.0)
        }
    });
    // Root Node2D uses rounded offset, unlike the unrounded plan value.
    let offset = std::array::from_fn(|i| container[i] / 2.0 - center[i] * scale);
    Ok(Plan {
        scale,
        center,
        visible,
        offset,
        base_scale: k as f64 * d,
        zoom: multiple - k,
        zoom_min: smallest - k,
        zoom_max: largest - k,
    })
}
pub fn godot_round(x: f64) -> f64 {
    if x < 0.0 {
        -(-x + 0.5).floor()
    } else {
        (x + 0.5).floor()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pro_reference_camera() {
        let p = plan([640.0, 480.0], [15040.0, 448.0], [416.0, 224.0], 1, 0).unwrap();
        assert_eq!(p.scale, 2.0);
        assert_eq!(p.visible, [320.0, 240.0]);
        assert_eq!(p.offset, [-512.0, -208.0]);
    }
    #[test]
    fn container_ladder_remains_bounded() {
        for s in [
            [832.0, 448.0],
            [640.0, 480.0],
            [416.0, 448.0],
            [170.0, 720.0],
            [1280.0, 170.0],
            [32.0, 24.0],
        ] {
            let p = plan(s, [15040.0, 448.0], [0.0, 0.0], 1, 0).unwrap();
            for i in 0..2 {
                assert!(p.visible[i] <= [15040.0, 448.0][i]);
                assert!(p.center[i] >= p.visible[i] / 2.0);
            }
        }
    }
    #[test]
    fn stress_zoom_clamps_extreme_initial_values() {
        let low = plan([640.0, 480.0], [1536.0, 448.0], [416.0, 224.0], 1, i32::MIN).unwrap();
        let high = plan([640.0, 480.0], [1536.0, 448.0], [416.0, 224.0], 1, i32::MAX).unwrap();
        assert_eq!((low.zoom, low.zoom_min, low.zoom_max), (-1, -1, 1));
        assert_eq!((high.zoom, high.zoom_min, high.zoom_max), (1, -1, 1));
    }
    #[test]
    fn zoom_out_reaches_one_to_one_and_centres_a_short_level() {
        let p = plan([640.0, 480.0], [15040.0, 448.0], [416.0, 224.0], 1, -1).unwrap();
        assert_eq!(p.scale, 1.0);
        assert_eq!(p.visible, [640.0, 480.0]);
        assert_eq!(p.center, [416.0, 224.0]);
        assert_eq!(p.offset, [-96.0, 16.0]);
    }
    #[test]
    fn godot_half_away_from_zero() {
        assert_eq!(godot_round(-0.5), -1.0);
        assert_eq!(godot_round(0.5), 1.0);
    }
}
