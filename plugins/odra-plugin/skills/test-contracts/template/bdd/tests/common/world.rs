//! The world of a scenario: a fresh blockchain and the contracts under test. Every scenario
//! starts with a new one, so scenarios never see each other's state.
use odra::host::HostEnv;
use odra::prelude::*;
use odra_bdd::bdd_env::BDDEnv;
use std::fmt::{Debug, Formatter};

#[derive(cucumber::World)]
#[world(init = Self::new)]
pub struct TestWorld {
    /// The test environment: accounts by name, the caller, CSPR balances.
    pub bdd: BDDEnv,
    /// How the last `tries to ...` step ended, for `Then it fails with ...`.
    pub last_result: Option<OdraResult<()>>,
    // The contracts go here, each as an `Option<...HostRef>` that a `Given` step deploys:
    //     pub auction: Option<AuctionHostRef>,
}

impl TestWorld {
    fn new() -> Self {
        Self {
            // `odra_test::env()` is OdraVM, or CasperVM under `cargo odra test -b casper`.
            bdd: BDDEnv::new(odra_test::env()),
            last_result: None,
        }
    }

    pub fn env(&self) -> &HostEnv {
        self.bdd.env()
    }

    /// Keeps the outcome of a call that is allowed to fail (`contract.try_bid()`).
    pub fn record<T>(&mut self, result: OdraResult<T>) {
        self.last_result = Some(result.map(|_| ()));
    }

    /// The error a feature file names in `Then it fails with <Name>`.
    pub fn error(name: &str) -> OdraError {
        match name {
            // "BidTooLow" => Error::BidTooLow.into(),
            other => panic!("unknown error name in a feature file: {other}"),
        }
    }
}

impl Debug for TestWorld {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "TestWorld")
    }
}
