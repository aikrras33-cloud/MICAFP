// ─────────────────────────────────────────────────────────────────────────────
// CountdownTimer — §8.5 expiry countdown.
//
// One-second-tick countdown timer for the Enterprise License Panel countdown
// cells. Computes remaining days/hours/minutes/seconds and an RGB border
// animation speed multiplier that intensifies as expiry approaches:
//   • 1×  when > 24 h remaining   (idle pulsing)
//   • 4×  at T−24 h               (slow warning pulse)
//   • 8×  at T−1 h                (urgent pulse)
//   • 16× at T−5 min (and at T−0) (maximum urgency pulse)
//
// Persian numeral support: `to_persian_digits(n)` converts the Latin digits
// `0123456789` in `n`'s decimal representation to Persian digits
// `۰۱۲۳۴۵۶۷۸۹` for the RTL countdown UI (§6.7 / §8.5).
// ─────────────────────────────────────────────────────────────────────────────

/// Border animation speed multipliers per §6.4.4 + §8.5.
pub const BORDER_ANIM_1X: i64 = 1;
pub const BORDER_ANIM_4X: i64 = 4;
pub const BORDER_ANIM_8X: i64 = 8;
pub const BORDER_ANIM_16X: i64 = 16;

/// 1 second in milliseconds.
pub const MS_PER_SEC: i64 = 1_000;
/// 1 minute in milliseconds.
pub const MS_PER_MIN: i64 = 60 * MS_PER_SEC;
/// 1 hour in milliseconds.
pub const MS_PER_HOUR: i64 = 60 * MS_PER_MIN;
/// 1 day in milliseconds.
pub const MS_PER_DAY: i64 = 24 * MS_PER_HOUR;

/// Snapshot of the countdown at a single tick.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CountdownSnapshot {
    /// Days remaining (floor).
    pub days: i64,
    /// Hours remaining (floor, 0-23).
    pub hours: i64,
    /// Minutes remaining (floor, 0-59).
    pub minutes: i64,
    /// Seconds remaining (floor, 0-59).
    pub seconds: i64,
    /// Whether the license has expired (remaining_ms == 0).
    pub is_expired: bool,
    /// RGB border animation speed multiplier (1, 4, 8, or 16×).
    pub border_animation_speed_multiplier: i64,
}

impl CountdownSnapshot {
    /// Format the snapshot as a `DD:HH:MM:SS` countdown string with Latin
    /// digits.
    pub fn to_latin_string(&self) -> String {
        format!(
            "{:02}:{:02}:{:02}:{:02}",
            self.days, self.hours, self.minutes, self.seconds
        )
    }

    /// Format the snapshot as a `DD:HH:MM:SS` countdown string with Persian
    /// digits (`۰۱۲۳۴۵۶۷۸۹`).
    pub fn to_persian_string(&self) -> String {
        format!(
            "{}:{}:{}:{}",
            to_persian_digits(self.days),
            to_persian_digits(self.hours),
            to_persian_digits(self.minutes),
            to_persian_digits(self.seconds),
        )
    }
}

/// One-second-tick countdown timer. Does NOT own a thread — the caller
/// drives ticks via [`CountdownTimer::tick`].
#[derive(Debug, Clone)]
pub struct CountdownTimer {
    /// Expiry timestamp (Unix-epoch ms).
    pub expiry_ms: i64,
    /// Last observed tick timestamp (Unix-epoch ms).
    pub last_tick_ms: i64,
}

impl CountdownTimer {
    /// Construct a timer for the given expiry timestamp (ms since Unix epoch).
    pub fn new(expiry_ms: i64) -> Self {
        Self {
            expiry_ms,
            last_tick_ms: 0,
        }
    }

    /// Record a tick at `now_ms` and return the current countdown snapshot.
    pub fn tick(&mut self, now_ms: i64) -> CountdownSnapshot {
        self.last_tick_ms = now_ms;
        let remaining_ms = (self.expiry_ms - now_ms).max(0);
        let total_secs = remaining_ms / MS_PER_SEC;
        let days = total_secs / 86_400;
        let hours = (total_secs % 86_400) / 3_600;
        let minutes = (total_secs % 3_600) / 60;
        let seconds = total_secs % 60;
        let is_expired = remaining_ms == 0;
        let border_speed = if remaining_ms == 0 {
            BORDER_ANIM_16X
        } else if remaining_ms <= 5 * MS_PER_MIN {
            BORDER_ANIM_16X
        } else if remaining_ms <= MS_PER_HOUR {
            BORDER_ANIM_8X
        } else if remaining_ms <= 24 * MS_PER_HOUR {
            BORDER_ANIM_4X
        } else {
            BORDER_ANIM_1X
        };
        CountdownSnapshot {
            days,
            hours,
            minutes,
            seconds,
            is_expired,
            border_animation_speed_multiplier: border_speed,
        }
    }
}

/// Convert the Latin digits `0123456789` in `n`'s decimal string
/// representation to Persian digits `۰۱۲۳۴۵۶۷۸۹`. Non-digit characters
/// (e.g. leading `-` for negative numbers) are left unchanged.
pub fn to_persian_digits(n: i64) -> String {
    let latin: [char; 10] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    let persian: [char; 10] = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    n.to_string()
        .chars()
        .map(|c| {
            if let Some(i) = latin.iter().position(|&l| l == c) {
                persian[i]
            } else {
                c
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persian_digits_basic() {
        assert_eq!(to_persian_digits(0), "۰");
        assert_eq!(to_persian_digits(9), "۹");
        assert_eq!(to_persian_digits(1234567890), "۱۲۳۴۵۶۷۸۹۰");
        assert_eq!(to_persian_digits(-1), "-۱");
    }

    #[test]
    fn countdown_at_t_minus_24h() {
        let expiry = 1_000_000_000;
        let mut t = CountdownTimer::new(expiry);
        let snap = t.tick(expiry - 24 * MS_PER_HOUR);
        assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (1, 0, 0, 0));
        assert!(!snap.is_expired);
        assert_eq!(snap.border_animation_speed_multiplier, 4);
    }

    #[test]
    fn countdown_at_t_minus_1h() {
        let expiry = 1_000_000_000;
        let mut t = CountdownTimer::new(expiry);
        let snap = t.tick(expiry - MS_PER_HOUR);
        assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (0, 1, 0, 0));
        assert_eq!(snap.border_animation_speed_multiplier, 8);
    }

    #[test]
    fn countdown_at_t_minus_5min() {
        let expiry = 1_000_000_000;
        let mut t = CountdownTimer::new(expiry);
        let snap = t.tick(expiry - 5 * MS_PER_MIN);
        assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (0, 0, 5, 0));
        assert_eq!(snap.border_animation_speed_multiplier, 16);
    }

    #[test]
    fn countdown_at_t_zero_expired() {
        let expiry = 1_000_000_000;
        let mut t = CountdownTimer::new(expiry);
        let snap = t.tick(expiry);
        assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (0, 0, 0, 0));
        assert!(snap.is_expired);
        assert_eq!(snap.border_animation_speed_multiplier, 16);

        // Just past expiry: still expired, still 16×.
        let snap = t.tick(expiry + 60 * MS_PER_SEC);
        assert!(snap.is_expired);
        assert_eq!(snap.border_animation_speed_multiplier, 16);
    }

    #[test]
    fn countdown_far_future_valid() {
        let expiry = 1_000_000_000;
        let mut t = CountdownTimer::new(expiry);
        let snap = t.tick(expiry - 7 * 24 * MS_PER_HOUR); // 7 days out
        assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (7, 0, 0, 0));
        assert!(!snap.is_expired);
        assert_eq!(snap.border_animation_speed_multiplier, 1);
    }

    #[test]
    fn persian_string_format() {
        let snap = CountdownSnapshot {
            days: 7,
            hours: 5,
            minutes: 3,
            seconds: 1,
            is_expired: false,
            border_animation_speed_multiplier: 1,
        };
        assert_eq!(snap.to_latin_string(), "07:05:03:01");
        assert_eq!(snap.to_persian_string(), "۷:۵:۳:۱");
    }
}
