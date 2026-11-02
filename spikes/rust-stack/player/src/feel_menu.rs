//! Paused, presentation-only controls. Settings live in Scene, not in the menu.
use crate::{
    feel::FeelSettings,
    input,
    menu::{self, MenuPage},
};
use std::time::{Duration, Instant};

const WATER_ROW: usize = 13;
const WATER_STRENGTH_ROW: usize = 14;
const LIGHTS_ROW: usize = 15;
const LIGHT_STRENGTH_ROW: usize = 16;
const GLOW_ROW: usize = 17;
const GLOW_STRENGTH_ROW: usize = 18;
const AUTO_NORMALS_ROW: usize = 19;
const GLOW_STYLE_ROW: usize = 20;
const ZOOM_STEPS_ROW: usize = 21;
const PREVIEW_ROW: usize = 22;
const RESTART_ROW: usize = 23;
const RESET_ROW: usize = 24;
const RESUME_ROW: usize = 25;
pub const ROWS: usize = RESUME_ROW + 1;
#[derive(Default)]
pub struct Model {
    pub focus: usize,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    None,
    Preview { hit: bool },
    Resume,
    Restart,
}
impl Model {
    pub fn step(&mut self, delta: i64) {
        self.focus = (self.focus as i64 + delta).rem_euclid(ROWS as i64) as usize;
    }
    pub fn input(&mut self, edges: u8, s: &mut FeelSettings) -> Action {
        if edges & input::USE != 0 {
            return Action::Resume;
        }
        if edges & input::UP != 0 {
            self.step(-1);
        }
        if edges & input::DOWN != 0 {
            self.step(1);
        }
        let delta = i64::from(edges & input::RIGHT != 0) - i64::from(edges & input::LEFT != 0);
        let confirm = edges & input::JUMP != 0;
        let old = *s;
        if delta != 0 {
            match self.focus {
                0 => s.shake_enabled = !s.shake_enabled,
                1 => s.pound_strength_px += delta,
                2 => s.pound_steps += delta,
                3 => s.hit_strength_px += delta,
                4 => s.hit_steps += delta,
                5 => s.dust_enabled = !s.dust_enabled,
                6 => s.dust_amount += delta,
                7 => s.muffle_enabled = !s.muffle_enabled,
                8 => s.muffle_strength += delta,
                9 => s.sparkle_enabled = !s.sparkle_enabled,
                10 => s.splash_enabled = !s.splash_enabled,
                11 => s.goal_music_enabled = !s.goal_music_enabled,
                12 => s.goal_music_strength += delta,
                WATER_ROW => s.water_fx_enabled = !s.water_fx_enabled,
                WATER_STRENGTH_ROW => s.water_fx_strength += delta,
                LIGHTS_ROW => s.lights_enabled = !s.lights_enabled,
                LIGHT_STRENGTH_ROW => s.light_strength += delta,
                GLOW_ROW => s.glow_enabled = !s.glow_enabled,
                GLOW_STRENGTH_ROW => s.glow_strength += delta,
                AUTO_NORMALS_ROW => s.auto_normals = !s.auto_normals,
                GLOW_STYLE_ROW => s.glow_style.toggle(),
                ZOOM_STEPS_ROW => s.zoom_steps.toggle(),
                _ => {}
            }
        }
        if confirm {
            match self.focus {
                0 => s.shake_enabled = !s.shake_enabled,
                5 => s.dust_enabled = !s.dust_enabled,
                7 => s.muffle_enabled = !s.muffle_enabled,
                9 => s.sparkle_enabled = !s.sparkle_enabled,
                10 => s.splash_enabled = !s.splash_enabled,
                11 => s.goal_music_enabled = !s.goal_music_enabled,
                WATER_ROW => s.water_fx_enabled = !s.water_fx_enabled,
                LIGHTS_ROW => s.lights_enabled = !s.lights_enabled,
                GLOW_ROW => s.glow_enabled = !s.glow_enabled,
                AUTO_NORMALS_ROW => s.auto_normals = !s.auto_normals,
                GLOW_STYLE_ROW => s.glow_style.toggle(),
                ZOOM_STEPS_ROW => s.zoom_steps.toggle(),
                PREVIEW_ROW => return Action::Preview { hit: false },
                RESTART_ROW => return Action::Restart,
                RESET_ROW => *s = FeelSettings::default(),
                RESUME_ROW => return Action::Resume,
                _ => {}
            }
        }
        s.clamp();
        if old != *s && (self.focus <= 4 || self.focus == RESET_ROW) {
            Action::Preview {
                hit: self.focus == 3 || self.focus == 4,
            }
        } else {
            Action::None
        }
    }
}

pub struct Page<'a> {
    pub model: &'a Model,
    pub settings: &'a FeelSettings,
}
impl MenuPage for Page<'_> {
    fn title(&self) -> &str {
        "Feel"
    }
    fn info(&self) -> String {
        "Paused. Drawing and audio only.".into()
    }
    fn status(&self) -> &str {
        ""
    }
    fn hint(&self) -> &str {
        "Up/down: select. Left/right: change. A: confirm. B/Start: resume."
    }
    fn focused(&self) -> usize {
        self.model.focus
    }
    fn items(&self) -> Vec<menu::Item> {
        let s = self.settings;
        let on = |v| if v { "on" } else { "off" };
        vec![
            format!("Shake: {}", on(s.shake_enabled)),
            format!("Pound strength: {} px", s.pound_strength_px),
            format!("Pound length: {} steps", s.pound_steps),
            format!("Hit strength: {} px", s.hit_strength_px),
            format!("Hit length: {} steps", s.hit_steps),
            format!("Dust: {}", on(s.dust_enabled)),
            format!("Dust amount: {}", s.dust_amount),
            format!("Underwater muffle: {}", on(s.muffle_enabled)),
            format!("Muffle strength: {}", s.muffle_strength),
            format!("Coin sparkle: {}", on(s.sparkle_enabled)),
            format!("Water splashes: {}", on(s.splash_enabled)),
            format!("Goal music: {}", on(s.goal_music_enabled)),
            format!("Goal music strength: {}", s.goal_music_strength),
            format!("Water FX: {}", on(s.water_fx_enabled)),
            format!("Water FX strength: {}", s.water_fx_strength),
            format!("Lights: {}", on(s.lights_enabled)),
            format!("Light strength: {}", s.light_strength),
            format!("Glow: {}", on(s.glow_enabled)),
            format!("Glow strength: {}", s.glow_strength),
            format!("Auto normals: {}", on(s.auto_normals)),
            format!("Glow style: {}", s.glow_style.label()),
            format!("Zoom steps: {}", s.zoom_steps.label()),
            "Preview shake".into(),
            "Restart level".into(),
            "Reset to defaults".into(),
            "Resume".into(),
        ]
        .into_iter()
        .map(menu::feel_item)
        .collect()
    }
}

/// Hidden screenshot hook: `--feel-demo N` pauses after N successful steps.
/// Visits every row at 400 ms intervals, changes pound strength and back, previews,
/// then resumes. Restart and reset are never activated by an unattended demo.
pub struct Demo {
    pub after: u64,
    row: Option<usize>,
    next: Instant,
    undo: Option<(Instant, i64)>,
}
impl Demo {
    pub fn new(after: u64) -> Self {
        Self {
            after,
            row: None,
            next: Instant::now(),
            undo: None,
        }
    }
    pub fn running(&self) -> bool {
        self.row.is_some()
    }
    pub fn update(
        &mut self,
        now: Instant,
        completed: u64,
        model: &mut Model,
        s: &mut FeelSettings,
    ) -> Action {
        if self.row.is_none() {
            if completed < self.after {
                return Action::None;
            }
            self.row = Some(0);
            model.focus = 0;
            self.next = now + Duration::from_millis(400);
            return Action::None;
        }
        if let Some((_, original)) = self.undo.filter(|(at, _)| now >= *at) {
            s.pound_strength_px = original;
            self.undo = None;
            return Action::Preview { hit: false };
        }
        if now < self.next {
            return Action::None;
        }
        let row = self.row.unwrap() + 1;
        self.next = now + Duration::from_millis(400);
        self.row = Some(row);
        if row >= ROWS {
            return Action::Resume;
        }
        model.focus = row;
        if row == 1 {
            let original = s.pound_strength_px;
            self.undo = Some((now + Duration::from_millis(150), original));
            s.pound_strength_px += if original == 8 { -1 } else { 1 };
            Action::Preview { hit: false }
        } else if row == PREVIEW_ROW {
            Action::Preview { hit: false }
        } else {
            Action::None
        }
    }
}

/// Release barrier on resume. Simulation receives neither a held menu press nor
/// an artificial zero-mask step while the press is still held.
#[derive(Default)]
pub struct ReleaseGate {
    waiting: bool,
}
impl ReleaseGate {
    pub fn wait(&mut self) {
        self.waiting = true;
    }
    pub fn is_waiting(&self) -> bool {
        self.waiting
    }
    pub fn blocked(&mut self, held: u8) -> bool {
        self.waiting &= held != 0;
        self.waiting
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn new_rows_toggle_on_confirm_and_arrows_in_the_existing_menu() {
        let mut m = Model::default();
        let mut s = FeelSettings::default();
        for row in 9..=11 {
            m.focus = row;
            m.input(input::JUMP, &mut s);
            let enabled = |s: &FeelSettings| match row {
                9 => s.sparkle_enabled,
                10 => s.splash_enabled,
                _ => s.goal_music_enabled,
            };
            assert!(!enabled(&s));
            m.input(input::RIGHT, &mut s);
            assert!(enabled(&s));
        }
        let items = Page {
            model: &m,
            settings: &s,
        }
        .items();
        assert_eq!(items.len(), ROWS);
    }
    #[test]
    fn restart_is_confirm_only_before_reset_and_does_not_change_settings() {
        let mut m = Model { focus: RESTART_ROW };
        let mut s = FeelSettings::default();
        let original = s;
        for edges in [0, input::LEFT, input::RIGHT] {
            assert_eq!(m.input(edges, &mut s), Action::None);
        }
        assert_eq!(m.input(input::JUMP, &mut s), Action::Restart);
        assert_eq!(s, original);
        assert_eq!(m.input(input::USE, &mut s), Action::Resume);
        let labels: Vec<_> = Page {
            model: &m,
            settings: &s,
        }
        .items()
        .into_iter()
        .map(|item| item.label)
        .collect();
        assert_eq!(labels[PREVIEW_ROW], "Preview shake");
        assert_eq!(labels[RESTART_ROW], "Restart level");
        assert_eq!(labels[RESET_ROW], "Reset to defaults");
        assert_eq!(labels[RESUME_ROW], "Resume");
        assert_eq!(RESTART_ROW + 1, RESET_ROW);
        let mut gate = ReleaseGate::default();
        gate.wait();
        assert!(gate.blocked(input::JUMP));
        assert!(!gate.blocked(0));
    }
    #[test]
    fn resume_waits_for_release() {
        let mut gate = ReleaseGate::default();
        assert!(!gate.blocked(input::JUMP));
        gate.wait();
        assert!(gate.blocked(input::JUMP));
        assert!(gate.blocked(input::USE));
        assert!(!gate.blocked(0));
        assert!(!gate.blocked(input::JUMP));
    }
    #[test]
    fn focus_values_clamping_reset_and_resume() {
        let mut m = Model::default();
        let mut s = FeelSettings::default();
        m.step(-1);
        assert_eq!(m.focus, RESUME_ROW);
        m.step(1);
        assert_eq!(m.focus, 0);
        m.input(input::RIGHT, &mut s);
        assert!(!s.shake_enabled);
        m.focus = 1;
        for _ in 0..20 {
            m.input(input::RIGHT, &mut s);
        }
        assert_eq!(s.pound_strength_px, 8);
        for _ in 0..20 {
            m.input(input::LEFT, &mut s);
        }
        assert_eq!(s.pound_strength_px, 0);
        for (row, lower, upper) in [
            (2, 6, 30),
            (3, 0, 8),
            (4, 6, 30),
            (6, 0, 3),
            (8, 0, 3),
            (12, 0, 3),
            (WATER_STRENGTH_ROW, 0, 3),
        ] {
            m.focus = row;
            for _ in 0..40 {
                m.input(input::RIGHT, &mut s);
            }
            let value = |s: &FeelSettings| match row {
                2 => s.pound_steps,
                3 => s.hit_strength_px,
                4 => s.hit_steps,
                6 => s.dust_amount,
                8 => s.muffle_strength,
                12 => s.goal_music_strength,
                _ => s.water_fx_strength,
            };
            assert_eq!(value(&s), upper);
            for _ in 0..40 {
                m.input(input::LEFT, &mut s);
            }
            assert_eq!(value(&s), lower);
        }
        for (row, read) in [
            (
                LIGHT_STRENGTH_ROW,
                (|s: &FeelSettings| s.light_strength) as fn(&FeelSettings) -> i64,
            ),
            (
                GLOW_STRENGTH_ROW,
                (|s: &FeelSettings| s.glow_strength) as fn(&FeelSettings) -> i64,
            ),
        ] {
            m.focus = row;
            for _ in 0..10 {
                m.input(input::RIGHT, &mut s);
            }
            assert_eq!(read(&s), 3);
            for _ in 0..10 {
                m.input(input::LEFT, &mut s);
            }
            assert_eq!(read(&s), 0);
        }
        for row in [
            LIGHTS_ROW,
            GLOW_ROW,
            AUTO_NORMALS_ROW,
            GLOW_STYLE_ROW,
            ZOOM_STEPS_ROW,
        ] {
            m.focus = row;
            let old = s;
            m.input(input::JUMP, &mut s);
            assert_ne!(s, old);
            m.input(input::LEFT, &mut s);
            assert_eq!(s, old);
        }
        m.focus = RESET_ROW;
        m.input(input::JUMP, &mut s);
        assert_eq!(s, FeelSettings::default());
        m.focus = PREVIEW_ROW;
        assert_eq!(m.input(input::JUMP, &mut s), Action::Preview { hit: false });
        m.focus = RESUME_ROW;
        assert_eq!(m.input(input::JUMP, &mut s), Action::Resume);
        assert_eq!(m.input(input::USE, &mut s), Action::Resume);
    }
    #[test]
    fn water_rows_follow_muffle_and_do_not_preview_shake() {
        let mut m = Model { focus: WATER_ROW };
        let mut s = FeelSettings::default();
        assert_eq!(m.input(input::JUMP, &mut s), Action::None);
        assert!(!s.water_fx_enabled);
        assert_eq!(m.input(input::RIGHT, &mut s), Action::None);
        assert!(s.water_fx_enabled);
        m.focus = WATER_STRENGTH_ROW;
        assert_eq!(m.input(input::RIGHT, &mut s), Action::None);
        assert_eq!(s.water_fx_strength, 3);
        let labels: Vec<_> = Page {
            model: &m,
            settings: &s,
        }
        .items()
        .into_iter()
        .map(|item| item.label)
        .collect();
        assert_eq!(
            &labels[12..16],
            &[
                "Goal music strength: 2",
                "Water FX: on",
                "Water FX strength: 3",
                "Lights: on"
            ]
        );
    }
    #[test]
    fn real_menu_renderer_keeps_each_focus_visible_at_player_scale() {
        use crate::{binding::Catalog, hud::Font, menu::View};
        let path =
            std::env::temp_dir().join(format!("feel-font-metrics-{}.json", std::process::id()));
        std::fs::write(&path, br#"{"space_advance":4,"font_size":16}"#).unwrap();
        let chars: String = ('!'..='~').collect();
        let manifest = serde_json::json!({"fonts":{"hud":{"file":"font.png","cell_width":8,"cell_height":16,"characters":chars}}});
        let font = Font::prepare(&manifest, &mut Catalog::default(), &path).unwrap();
        std::fs::remove_file(path).unwrap();
        let mut view = View::new(font, [752.0, 16.0], true);
        let mut model = Model::default();
        let mut settings = FeelSettings::default();
        for max in [false, true] {
            if max {
                settings.pound_strength_px = 8;
                settings.pound_steps = 30;
                settings.hit_strength_px = 8;
                settings.hit_steps = 30;
                settings.dust_amount = 3;
                settings.muffle_strength = 3;
                settings.goal_music_strength = 3;
                settings.water_fx_strength = 3;
                settings.light_strength = 3;
                settings.glow_strength = 3;
            }
            for size in [
                [640.0, 480.0],
                [320.0, 480.0],
                [640.0, 170.0],
                [1280.0, 720.0],
            ] {
                for focus in 0..ROWS {
                    model.focus = focus;
                    let mut quads = Vec::new();
                    view.emit(
                        &Page {
                            model: &model,
                            settings: &settings,
                        },
                        size,
                        1,
                        &mut quads,
                    )
                    .unwrap();
                    assert!(view.visible_rows >= 1);
                    assert!(quads.iter().any(|q| q.image == 1
                        && q.color == menu::WHITE
                        && q.corners[2][1] - q.corners[0][1] > 1.0
                        && q.corners[2][0] - q.corners[0][0] > 1.0));
                    assert!(quads.iter().flat_map(|q| q.corners).all(|[x, y]| x >= 0.0
                        && y >= 0.0
                        && x <= size[0] as f32
                        && y <= size[1] as f32));
                }
            }
        }
    }
    #[test]
    fn demo_visits_all_rows_restores_value_and_resumes() {
        let mut d = Demo::new(5);
        let mut m = Model::default();
        let mut s = FeelSettings {
            pound_strength_px: 8,
            ..FeelSettings::default()
        };
        let original = s;
        let start = Instant::now();
        d.update(start, 4, &mut m, &mut s);
        assert!(!d.running());
        d.update(start, 5, &mut m, &mut s);
        assert!(d.running());
        for row in 1..ROWS {
            let now = start + Duration::from_millis(row as u64 * 400);
            d.update(now, 5, &mut m, &mut s);
            assert_eq!(m.focus, row);
            d.update(now + Duration::from_millis(150), 5, &mut m, &mut s);
        }
        assert_eq!(s, original);
        assert_eq!(
            d.update(
                start + Duration::from_millis(ROWS as u64 * 400),
                5,
                &mut m,
                &mut s
            ),
            Action::Resume
        );
    }
}
