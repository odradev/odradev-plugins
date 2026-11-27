//! Steps that do not depend on the contracts: CSPR balances, time, expected failures.
use crate::common::{params::Span, world::TestWorld};
use cucumber::{given, then, when};
use odra_bdd::types::{account::Account, cspr::CSPRAmount};

/// Balances are counted from here: the account's real balance in the test environment is large
/// and arbitrary, so a scenario states the one it wants to reason about.
#[given(expr = "{account} has {cspr_amount} CSPR")]
fn set_balance(world: &mut TestWorld, account: Account, amount: CSPRAmount) {
    world.bdd.set_balance(&account, amount);
}

#[then(expr = "{account} has {cspr_amount} CSPR")]
fn check_balance(world: &mut TestWorld, account: Account, amount: CSPRAmount) {
    let balance = world.bdd.get_balance(&account);
    assert!(
        balance == amount,
        "{account} has {balance} motes, expected {amount} motes"
    );
}

#[when(expr = "{account} sends {cspr_amount} CSPR to {account}")]
fn send_cspr(world: &mut TestWorld, from: Account, amount: CSPRAmount, to: Account) {
    world.bdd.set_caller(&from);
    let to = world.bdd.get_address(&to);
    world.env().transfer(to, amount.amount()).unwrap();
}

#[when(expr = "{account} tries to send {cspr_amount} CSPR to {account}")]
fn try_send_cspr(world: &mut TestWorld, from: Account, amount: CSPRAmount, to: Account) {
    world.bdd.set_caller(&from);
    let to = world.bdd.get_address(&to);
    let result = world.env().transfer(to, amount.amount());
    world.record(result);
}

#[when(expr = "{span} pass(es)")]
fn time_passes(world: &mut TestWorld, span: Span) {
    world.env().advance_block_time(span.millis());
}

#[then("it fails")]
fn fails(world: &mut TestWorld) {
    let result = last_result(world);
    assert!(result.is_err(), "the action was expected to fail and succeeded");
}

#[then(expr = "it fails with {word}")]
fn fails_with(world: &mut TestWorld, error: String) {
    assert_eq!(last_result(world), Err(TestWorld::error(&error)));
}

#[then("it succeeds")]
fn succeeds(world: &mut TestWorld) {
    assert_eq!(last_result(world), Ok(()));
}

fn last_result(world: &mut TestWorld) -> odra::prelude::OdraResult<()> {
    world
        .last_result
        .take()
        .expect("no outcome to check: the step before must be a `tries to ...` step that calls `world.record(..)`")
}
