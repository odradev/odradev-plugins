//! Values a step reads out of a sentence, next to the ones `odra-bdd` brings:
//! `{account}` (Owner, Alice, Bob, Charlie, Dave, Eve) and `{cspr_amount}` (`10`, `0.5`).
use cucumber::Parameter;
use std::str::FromStr;

/// A length of time: `10 seconds`, `30 minutes`, `2 hours`, `1 day`.
#[derive(Debug, Clone, Copy, Parameter)]
#[param(name = "span", regex = r"\d+ (?:second|minute|hour|day)s?")]
pub struct Span(u64);

impl Span {
    /// In milliseconds, the unit of block time.
    pub fn millis(&self) -> u64 {
        self.0
    }
}

impl FromStr for Span {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let (number, unit) = s.split_once(' ').ok_or("expected '<number> <unit>'")?;
        let number: u64 = number.parse().map_err(|_| format!("not a number: {number}"))?;
        let unit = match unit.trim_end_matches('s') {
            "second" => 1_000,
            "minute" => 60_000,
            "hour" => 3_600_000,
            "day" => 86_400_000,
            other => return Err(format!("unknown unit of time: {other}")),
        };
        Ok(Span(number * unit))
    }
}
