//! Disjoint main-thread CPU/wall phases. Fixed-memory quantile histograms.
//! Quantiles are upper bounds: <= 1/512 relative bucket width above 512ns.
//! Maxima are exact. GPU async time is never inferred from these CPU samples.
use serde::Serialize;
use std::time::Instant;
fn cpu_ns() -> u128 {
    let mut t = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    let result = unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut t) };
    assert_eq!(result, 0, "thread CPU clock unavailable");
    t.tv_sec as u128 * 1_000_000_000 + t.tv_nsec as u128
}
pub struct Timer {
    wall: Instant,
    cpu: u128,
}
impl Default for Timer {
    fn default() -> Self {
        Self::new()
    }
}
impl Timer {
    pub fn new() -> Self {
        Self {
            wall: Instant::now(),
            cpu: cpu_ns(),
        }
    }
    pub fn finish(self) -> Sample {
        Sample {
            wall_ns: self.wall.elapsed().as_nanos() as u64,
            cpu_ns: (cpu_ns() - self.cpu) as u64,
        }
    }
}
#[derive(Clone, Copy, Debug, Default, Serialize)]
pub struct Sample {
    pub wall_ns: u64,
    pub cpu_ns: u64,
}
#[derive(Clone, Debug)]
pub struct Histogram {
    bins: Vec<u64>,
    pub count: u64,
    maximum: u64,
}
impl Default for Histogram {
    fn default() -> Self {
        Self {
            bins: vec![0; 512 + 55 * 512],
            count: 0,
            maximum: 0,
        }
    }
}
impl Histogram {
    pub fn add(&mut self, value: u64) {
        let index = if value < 512 {
            value as usize
        } else {
            let exponent = 63 - value.leading_zeros() as usize;
            512 + (exponent - 9) * 512 + ((value >> (exponent - 9)) as usize - 512)
        };
        self.bins[index] += 1;
        self.count += 1;
        self.maximum = self.maximum.max(value);
    }
    fn upper(index: usize) -> u64 {
        if index < 512 {
            return index as u64;
        }
        let exponent = (index - 512) / 512 + 9;
        let mantissa = (index - 512) % 512 + 512;
        ((((mantissa + 1) as u128) << (exponent - 9)) - 1).min(u64::MAX as u128) as u64
    }
    fn quantile(&self, percent: u64) -> u64 {
        let rank = (self.count * percent).div_ceil(100).max(1);
        let mut n = 0;
        for (i, count) in self.bins.iter().enumerate() {
            n += count;
            if n >= rank {
                return Self::upper(i);
            }
        }
        0
    }
    pub fn summary(&self) -> Distribution {
        Distribution {
            p50: self.quantile(50),
            p95: self.quantile(95),
            p99: self.quantile(99),
            max: self.maximum,
        }
    }
}
#[derive(Default)]
pub struct Samples {
    pub wall: Histogram,
    pub cpu: Histogram,
}
impl Samples {
    pub fn add(&mut self, s: Sample) {
        self.wall.add(s.wall_ns);
        self.cpu.add(s.cpu_ns);
    }
    pub fn summary(&self) -> serde_json::Value {
        serde_json::json!({"count":self.wall.count,"wall_ns":self.wall.summary(),"thread_cpu_ns":self.cpu.summary(),"quantiles":"fixed log-histogram upper bounds; relative bucket width <=1/512 above512ns; maxima exact"})
    }
}
#[derive(Clone, Copy, Debug, Default, Serialize)]
pub struct Distribution {
    pub p50: u64,
    pub p95: u64,
    pub p99: u64,
    pub max: u64,
}
pub fn distribution(input: &[u64]) -> Distribution {
    let mut h = Histogram::default();
    for value in input {
        h.add(*value);
    }
    h.summary()
}
pub fn memory_kib() -> serde_json::Value {
    let status = std::fs::read_to_string("/proc/self/status").unwrap_or_default();
    let read = |name: &str| {
        status.lines().find_map(|l| {
            l.strip_prefix(name)
                .and_then(|v| v.split_whitespace().next())
                .and_then(|v| v.parse::<u64>().ok())
        })
    };
    serde_json::json!({"rss_kib":read("VmRSS:"),"peak_rss_kib":read("VmHWM:")})
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tails_are_nearest_rank() {
        let v: Vec<u64> = (1..=100).collect();
        let p = distribution(&v);
        assert_eq!((p.p50, p.p95, p.p99, p.max), (50, 95, 99, 100));
    }
    #[test]
    fn empty_tails_are_explicit_count_zero() {
        assert_eq!(distribution(&[]).max, 0);
        assert_eq!(Samples::default().summary()["count"], 0);
    }
    #[test]
    fn memory_is_constant_and_all_u64_values_fit() {
        let mut h = Histogram::default();
        let n = h.bins.len();
        for value in [0, 1, 511, 512, 1023, 1024, 16_666_667, u64::MAX] {
            h.add(value);
        }
        assert_eq!(h.bins.len(), n);
        assert_eq!(h.summary().max, u64::MAX);
    }
}
