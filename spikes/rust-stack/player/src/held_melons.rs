//! Spike stopgap for the missing o25 held flag in EntityPicture.
//! Reads saved rows only; remove this bridge when the DTO exposes item holds.
use eggshell_spike_core::{EntityPicture, Motion, Position, Session};

#[derive(Default)]
pub struct HeldMelons {
    current: Option<(i64, usize, Vec<i64>)>,
    frames: std::collections::VecDeque<(i64, usize, Vec<i64>)>,
}
impl HeldMelons {
    pub fn observe(&mut self, session: &Session) {
        let mut tokens = Vec::new();
        if session.saved_field("move_action") == Some(4) {
            session.visit_saved_rows(|code, field| {
                if code == "o25"
                    && field("held") == Some(1)
                    && field("status") == Some(1)
                    && let Some(token) = field("token")
                {
                    tokens.push(token);
                }
            });
        }
        self.record(session.stats().tick, session.presentation_view().0, tokens);
    }
    fn record(&mut self, tick: i64, map: usize, tokens: Vec<i64>) {
        if self
            .current
            .as_ref()
            .is_some_and(|s| s.0 == tick && s.1 == map)
        {
            return;
        }
        if self
            .current
            .as_ref()
            .is_some_and(|s| tick < s.0 || map != s.1)
        {
            self.frames.clear();
        }
        self.frames.push_back((tick, map, tokens.clone()));
        self.current = Some((tick, map, tokens));
    }
    pub fn tokens(&mut self, tick: i64, map: usize) -> &[i64] {
        if let Some(index) = self.frames.iter().position(|s| s.0 == tick && s.1 == map) {
            self.frames.drain(..index);
            &self.frames[0].2
        } else {
            &[]
        }
    }
}

/// The body origin is not necessarily its centre. Keep the captured picture's
/// centre on the tip, without changing either tongue endpoint or simulation.
pub fn pulled(
    entity: &EntityPicture,
    tip: Option<Position>,
    melon_tokens: &[i64],
) -> Option<EntityPicture> {
    let held = entity.held || entity.code == "o25" && melon_tokens.contains(&entity.token);
    if !held || entity.hidden {
        return None;
    }
    let tip = tip?;
    let b = entity.body_bounds;
    let at = Position {
        x: tip.x - (b[0] + b[2]) / 2,
        y: tip.y - (b[1] + b[3]) / 2,
    };
    Some(EntityPicture {
        motion: Motion {
            previous: at,
            current: at,
        },
        visible: true,
        held: false,
        ..entity.clone()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn captured_melon_rides_the_tip_and_disappears_when_swallowed() {
        let entity = EntityPicture {
            token: 7,
            code: "o25".into(),
            placement_id: None,
            source_index: Some(6),
            body_bounds: [-16, -16, 16, 16],
            motion: Motion::default(),
            facing: 1,
            layer: 7,
            variant: 4,
            status: eggshell_spike_core::EntityStatus::Active,
            visible: false,
            held: false,
            hidden: false,
            visual: eggshell_spike_core::VisualState::default(),
            auxiliary: vec![],
        };
        for tip in [
            Position { x: 100, y: 200 },
            Position { x: -100, y: 200 },
            Position { x: 0, y: -200 },
        ] {
            let picture = pulled(&entity, Some(tip), &[7]).unwrap();
            assert_eq!(picture.motion.current, tip);
            assert!(picture.visible && !picture.held);
            assert_eq!(entity.motion, Motion::default());
        }
        assert!(pulled(&entity, Some(Position::default()), &[]).is_none());
        assert!(pulled(&entity, None, &[7]).is_none());
    }
    #[test]
    fn catch_up_batch_keeps_the_prepared_frame_until_it_draws() {
        let mut holds = HeldMelons::default();
        holds.record(1, 1, vec![7]);
        for tick in 2..100 {
            holds.record(tick, 1, vec![]);
        }
        assert_eq!(holds.tokens(1, 1), &[7]);
        assert!(holds.tokens(99, 1).is_empty());
        assert_eq!(holds.frames.len(), 1);
    }
    #[test]
    fn hold_samples_are_tick_exact_and_keep_one_pipelined_frame() {
        let mut holds = HeldMelons::default();
        holds.record(10, 1, vec![7]);
        holds.record(11, 1, vec![]);
        assert_eq!(holds.tokens(10, 1), &[7]);
        assert!(holds.tokens(11, 1).is_empty());
        holds.record(2, 1, vec![]);
        assert!(holds.tokens(10, 1).is_empty());
        holds.record(3, 2, vec![8]);
        assert!(holds.tokens(3, 1).is_empty());
        assert_eq!(holds.tokens(3, 2), &[8]);
    }
}
