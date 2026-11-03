//! Actual Wayland compositor delivery feedback on SDL2's existing connection.
//! C shim owns protocol proxy listeners; Rust owns fixed-memory statistics.
use crate::timing::Histogram;
use serde::Serialize;
use std::{ffi::c_void, ptr::NonNull};
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
struct Sample {
    frame: u64,
    tick: u64,
    timestamp_ns: u64,
    submitted_ns: u64,
    sequence: u64,
    refresh_ns: u32,
    flags: u32,
    presented: u32,
    reserved: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Default, Debug, Serialize)]
pub struct Stats {
    pub requested: u64,
    pub presented: u64,
    pub discarded: u64,
    pub pending: u64,
    pub maximum_pending: u64,
    pub lost_samples: u64,
    pub clock_id: u32,
    pub available: u32,
}
unsafe extern "C" {
    fn egg_present_create(window: *mut sdl2::sys::SDL_Window) -> *mut c_void;
    fn egg_present_request(p: *mut c_void, frame: u64, tick: u64) -> i32;
    fn egg_present_dispatch(p: *mut c_void) -> i32;
    fn egg_present_pop(p: *mut c_void, sample: *mut Sample) -> i32;
    fn egg_present_stats(p: *mut c_void, stats: *mut Stats);
    fn egg_present_destroy(p: *mut c_void);
}
pub struct Feedback {
    pointer: NonNull<c_void>,
    intervals: Histogram,
    latency: Histogram,
    previous_time: Option<u64>,
    previous_sequence: Option<u64>,
    pub delivered_unique: u64,
    pub duplicate_presented_callbacks: u64,
    pub sequence_gaps: u64,
    pub intervals_over_budget: u64,
    pub refresh_ns: u32,
    pub flags: u32,
    pub last_frame: u64,
    pub last_tick: u64,
}
impl Feedback {
    /// Must be dropped before the SDL Window. Call on the SDL/main thread only.
    pub fn new(window: &sdl2::video::Window) -> Result<Self, String> {
        let pointer = NonNull::new(unsafe { egg_present_create(window.raw()) })
            .ok_or_else(sdl2::get_error)?;
        let result = Self {
            pointer,
            intervals: Histogram::default(),
            latency: Histogram::default(),
            previous_time: None,
            previous_sequence: None,
            delivered_unique: 0,
            duplicate_presented_callbacks: 0,
            sequence_gaps: 0,
            intervals_over_budget: 0,
            refresh_ns: 0,
            flags: 0,
            last_frame: 0,
            last_tick: 0,
        };
        println!(
            "RUST_PRESENTATION_BACKEND protocol=wp_presentation-v1 actual={:?} swap_calls_are_not_delivered_frames=true",
            result.stats()
        );
        Ok(result)
    }
    pub fn request(&mut self, frame: u64, tick: u64) -> Result<(), String> {
        if unsafe { egg_present_request(self.pointer.as_ptr(), frame, tick) } != 0 {
            return Err(sdl2::get_error());
        }
        Ok(())
    }
    pub fn stats(&self) -> Stats {
        let mut s = Stats::default();
        unsafe { egg_present_stats(self.pointer.as_ptr(), &mut s) };
        s
    }
    /// SDL event pumping and EGL's Wayland driver dispatch listeners; this drains
    /// their fixed-capacity result queue without an extra round trip per frame.
    pub fn collect(&mut self) -> Result<(), String> {
        if unsafe { egg_present_dispatch(self.pointer.as_ptr()) } != 0 {
            return Err(sdl2::get_error());
        }
        let stats = self.stats();
        if stats.available == 0 || stats.lost_samples != 0 {
            return Err("Wayland presentation feedback lost/unavailable".into());
        }
        loop {
            let mut sample = Sample::default();
            if unsafe { egg_present_pop(self.pointer.as_ptr(), &mut sample) } == 0 {
                break;
            }
            if sample.presented == 0 {
                continue;
            }
            self.last_frame = sample.frame;
            self.last_tick = sample.tick;
            self.flags = sample.flags;
            self.refresh_ns = sample.refresh_ns;
            if self.previous_time == Some(sample.timestamp_ns)
                && self.previous_sequence == Some(sample.sequence)
            {
                self.duplicate_presented_callbacks += 1;
                continue;
            }
            self.delivered_unique += 1;
            if let Some(previous) = self.previous_time {
                if sample.timestamp_ns < previous {
                    return Err("presentation clock moved backwards".into());
                }
                let interval = sample.timestamp_ns - previous;
                self.intervals.add(interval);
                if interval > 16_666_667 {
                    self.intervals_over_budget += 1;
                }
            }
            if sample.flags & 1 != 0 {
                if let Some(previous) = self.previous_sequence {
                    self.sequence_gaps +=
                        sample.sequence.saturating_sub(previous).saturating_sub(1);
                }
                self.previous_sequence = Some(sample.sequence);
            }
            if stats.clock_id == libc::CLOCK_MONOTONIC as u32
                && sample.timestamp_ns >= sample.submitted_ns
            {
                self.latency.add(sample.timestamp_ns - sample.submitted_ns);
            }
            self.previous_time = Some(sample.timestamp_ns);
        }
        Ok(())
    }
    pub fn summary(&self) -> serde_json::Value {
        serde_json::json!({"protocol":"wp_presentation-v1","stats":self.stats(),"actual_unique_deliveries":self.delivered_unique,"duplicate_presented_feedbacks":self.duplicate_presented_callbacks,"last_frame":self.last_frame,"last_saved_tick":self.last_tick,"reported_refresh_ns":self.refresh_ns,"last_flags":self.flags,"vblank_sequence_gaps":self.sequence_gaps,"delivered_intervals_over_16_667ms":self.intervals_over_budget,"delivered_interval_ns":self.intervals.summary(),"submit_to_present_ns":self.latency.summary(),"latency_clock":"computed only when compositor clock_id equals CLOCK_MONOTONIC","quantiles":"fixed log histogram upper bounds, relative bucket width <=1/512 above512ns; exact maxima"})
    }
}
impl Drop for Feedback {
    fn drop(&mut self) {
        unsafe { egg_present_destroy(self.pointer.as_ptr()) };
    }
}
