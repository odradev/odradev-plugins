//! The part of CSPR.trade (the Casper DEX, a Uniswap V2 style AMM) needed to open a pool.
//!
//! Only transactions can be sent to a contract known by its interface: on a live network a
//! getter of an external contract (`factory_address`, `get_pair`) cannot be called from the CLI.
use odra::casper_types::U256;
use odra::prelude::*;

/// The CSPR.trade router.
#[odra::external_contract]
pub trait CsprTradeRouter {
    /// Adds liquidity to the token/CSPR pool, creating the pool if it does not exist. The attached
    /// CSPR is the CSPR side; what is not used is sent back. Returns (tokens, CSPR, LP tokens).
    fn add_liquidity_cspr(
        &mut self,
        token: Address,
        amount_token_desired: U256,
        amount_token_min: U256,
        amount_cspr_min: U256,
        to: Address,
        deadline: u64,
    ) -> (U256, U256, U256);
}
