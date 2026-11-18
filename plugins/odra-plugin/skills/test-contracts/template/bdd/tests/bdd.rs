//! Runs the scenarios of `tests/features/`.
//!
//! `cargo odra test` runs them after the unit tests, on the backend it selects (`-b casper`).
//! `cargo test --test bdd -- "highest bidder"` runs only the scenarios whose name, or whose
//! feature's name, contains that text.
mod common;
mod steps;

fn main() {
    // Fails the run when a step fails or has no definition.
    odra_bdd::run::<common::world::TestWorld>("tests/features");
}
