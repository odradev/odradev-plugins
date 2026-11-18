// Scenario for bin/cli.rs: opens (or tops up) the token/CSPR pool on CSPR.trade.
//
// To use it in a project:
//   1. copy cspr_trade.rs to src/ and add `pub mod cspr_trade;` to src/lib.rs;
//   2. paste this into bin/cli.rs, replace `my_project` with the crate name and `MyToken` with
//      the token contract, and add `.scenario(ListOnCsprTrade)` to the `OdraCli` builder;
//   3. bin/cli.rs needs these imports (the cep18 template already has them):
//        use odra::host::HostEnv;
//        use odra::prelude::Address;
//        use odra::schema::casper_contract_schema::NamedCLType;
//        use odra_cli::{scenario::{Args, Error, Scenario, ScenarioMetadata},
//                       CommandArg, ContractProvider, DeployedContractsContainer};
//
// Verified on casper-test with Odra 2.10.1 (router package hashes as of 2026-11).

/// Opens (or tops up) the token/CSPR pool on CSPR.trade, which makes the token tradable.
pub struct ListOnCsprTrade;

impl ListOnCsprTrade {
    /// The CSPR.trade router of the network the CLI is connected to.
    fn router() -> Result<Address, Error> {
        let chain = std::env::var("ODRA_CASPER_LIVENET_CHAIN_NAME").unwrap_or_default();
        let hash = match chain.as_str() {
            "casper-test" => "hash-04a11a367e708c52557930c4e9c1301f4465100d1b1b6d0a62b48d3e32402867",
            "casper" => "hash-1dbac65585475fec53e5b1f9110923c8d232921702097e83105b36751d682186",
            _ => return Err(Error::OdraError { message: format!("CSPR.trade is not deployed on '{chain}'") }),
        };
        Ok(hash.parse::<Address>().expect("a valid package hash"))
    }
}

impl Scenario for ListOnCsprTrade {
    fn args(&self) -> Vec<CommandArg> {
        vec![
            CommandArg::new("token_amount", "Tokens to put in the pool, in the smallest unit", NamedCLType::U256).required(),
            CommandArg::new("cspr_amount", "CSPR to put in the pool, in motes", NamedCLType::U512).required(),
            CommandArg::new("gas", "Payment limit of the add-liquidity transaction, in motes", NamedCLType::U64),
        ]
    }

    fn run(
        &self,
        env: &HostEnv,
        container: &DeployedContractsContainer,
        args: Args,
    ) -> Result<(), Error> {
        use odra::casper_types::{U256, U512};
        use odra::host::HostRef;
        use odra::prelude::Addressable;
        use my_project::cspr_trade::CsprTradeRouterHostRef;

        let token_amount = args.get_single::<U256>("token_amount")?;
        let cspr_amount = args.get_single::<U512>("cspr_amount")?;
        let gas = args.get_single::<u64>("gas").unwrap_or(odra_cli::cspr!(500));

        let mut token = container.contract_ref::<MyToken>(env)?;
        let token_address = token.address();
        let router = CsprTradeRouterHostRef::new(Self::router()?, env.clone());
        let me = env.caller();

        // 1. Let the router take the tokens.
        env.set_gas(odra_cli::cspr!(5));
        token.approve(&router.address(), &token_amount);

        // 2. Deposit tokens and CSPR. The first deposit creates the pool and sets the price.
        let deadline = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_millis() as u64
            + 20 * 60 * 1000;
        let cspr_as_u256 = U256::from(cspr_amount.as_u128());
        env.set_gas(gas);
        let (tokens_in, cspr_in, lp_tokens) = router.with_tokens(cspr_amount).add_liquidity_cspr(
            token_address,
            token_amount,
            token_amount * 99 / 100,
            cspr_as_u256 * 99 / 100,
            me,
            deadline,
        );
        odra_cli::log(format!("Deposited {tokens_in} token units and {cspr_in} motes; received {lp_tokens} LP tokens."));

        let on_testnet = std::env::var("ODRA_CASPER_LIVENET_CHAIN_NAME").as_deref() == Ok("casper-test");
        let trade = if on_testnet { "https://testnet.cspr.trade" } else { "https://cspr.trade" };
        odra_cli::log(format!("The pool is listed on {trade} (Pool page) a minute or two after the transaction."));
        Ok(())
    }
}

impl ScenarioMetadata for ListOnCsprTrade {
    const NAME: &'static str = "list_on_cspr_trade";
    const DESCRIPTION: &'static str =
        "Adds token/CSPR liquidity on CSPR.trade, creating the pool on the first run.";
}
