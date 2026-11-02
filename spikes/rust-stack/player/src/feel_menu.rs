//! Paused, presentation-only controls. Settings live in Scene, not in the menu.
use crate::{
    feel::FeelSettings,
    input,
    menu::{self, MenuPage},
};
use std::time::{Duration, Instant};

pub const ROWS: usize = 17;
#[derive(Default)]
pub struct Model {
    pub focus: usize,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    None,
    Preview { hit: bool },
    Resume,
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
                9 => s.lights_enabled = !s.lights_enabled,
                10 => s.light_strength += delta,
                11 => s.glow_enabled = !s.glow_enabled,
                12 => s.glow_strength += delta,
                13 => s.auto_normals = !s.auto_normals,
                _ => {}
            }
        }
        if confirm {
            match self.focus {
                0 => s.shake_enabled = !s.shake_enabled,
                5 => s.dust_enabled = !s.dust_enabled,
                7 => s.muffle_enabled = !s.muffle_enabled,
                9 => s.lights_enabled = !s.lights_enabled,
                11 => s.glow_enabled = !s.glow_enabled,
                13 => s.auto_normals = !s.auto_normals,
                14 => return Action::Preview { hit: false },
                15 => *s = FeelSettings::default(),
                16 => return Action::Resume,
                _ => {}
            }
        }
        s.clamp();
        if old != *s && (self.focus <= 4 || self.focus == 15) {
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
            format!("Lights: {}", on(s.lights_enabled)),
            format!("Light strength: {}", s.light_strength),
            format!("Glow: {}", on(s.glow_enabled)),
            format!("Glow strength: {}", s.glow_strength),
            format!("Auto normals: {}", on(s.auto_normals)),
            "Preview shake".into(),
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
/// then resumes. No reset activation: an unattended demo preserves preferences.
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
        } else if row == 14 {
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
        assert_eq!(m.focus, 16);
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
        for (row, lower, upper) in [(2, 6, 30), (3, 0, 8), (4, 6, 30), (6, 0, 3), (8, 0, 3)] {
            m.focus = row;
            for _ in 0..40 {
                m.input(input::RIGHT, &mut s);
            }
            let value = |s: &FeelSettings| match row {
                2 => s.pound_steps,
                3 => s.hit_strength_px,
                4 => s.hit_steps,
                6 => s.dust_amount,
                _ => s.muffle_strength,
            };
            assert_eq!(value(&s), upper);
            for _ in 0..40 {
                m.input(input::LEFT, &mut s);
            }
            assert_eq!(value(&s), lower);
        }
        for (row, read) in [
            (
                10,
                (|s: &FeelSettings| s.light_strength) as fn(&FeelSettings) -> i64,
            ),
            (
                12,
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
        for row in [9, 11, 13] {
            m.focus = row;
            let old = s;
            m.input(input::JUMP, &mut s);
            assert_ne!(s, old);
            m.input(input::LEFT, &mut s);
            assert_eq!(s, old);
        }
        m.focus = 15;
        m.input(input::JUMP, &mut s);
        assert_eq!(s, FeelSettings::default());
        m.focus = 14;
        assert_eq!(m.input(input::JUMP, &mut s), Action::Preview { hit: false });
        m.focus = 16;
        assert_eq!(m.input(input::JUMP, &mut s), Action::Resume);
        assert_eq!(m.input(input::USE, &mut s), Action::Resume);
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
