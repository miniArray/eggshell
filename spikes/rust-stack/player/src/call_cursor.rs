//! Application input-call cursor, deliberately independent of saved simulation frame.
//! Restored snapshots do not encode this adapter cursor; replay continuation supplies it.
pub fn index(offset: u64, successful_calls: u64) -> Result<usize, String> {
    let position = offset
        .checked_add(successful_calls)
        .ok_or("input call cursor overflow")?;
    usize::try_from(position).map_err(|_| "input call cursor outside address space".into())
}
pub fn autosave_due(successful_calls: u64, cadence: u64) -> bool {
    cadence != 0 && successful_calls != 0 && successful_calls.is_multiple_of(cadence)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn frozen_saved_frame_cannot_repeat_masks_or_autosaves() {
        let saved_frame = 420;
        let mut saves = 0;
        for calls in 1..=800 {
            assert_eq!(index(0, calls - 1).unwrap(), calls as usize - 1);
            if autosave_due(calls, 60) {
                saves += 1;
            }
            assert_eq!(saved_frame, 420);
        }
        assert_eq!(saves, 13);
    }
    #[test]
    fn restore_cursor_is_explicit_not_inferred_from_frame() {
        assert_eq!(index(680, 10).unwrap(), 690);
        assert!(!autosave_due(419, 60));
        assert!(autosave_due(420, 60));
    }
}
