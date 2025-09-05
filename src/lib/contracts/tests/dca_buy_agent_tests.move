#[test_only]
module recadence::dca_buy_agent_tests {
    use std::signer;
    use std::vector;
    use std::option;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::object::{Self, Object};

    use recadence::base_agent;
    use recadence::dca_buy_agent;

    // Test addresses
    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_KEEPER_ADDR: address = @0x4444;

    // Token addresses (matching contract constants)
    const APT_TOKEN_ADDR: address = @0x1;
    const USDC_TOKEN_ADDR: address = @0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832;
    const USDT_TOKEN_ADDR: address = @0x357b0b74bc833e95a115ad22604854d6b0fca151cecd94111770e5d6ffc9dc2b;

    // Test constants
    const INITIAL_APT_BALANCE: u64 = 100000000; // 1 APT
    const INITIAL_USDT_BALANCE: u64 = 1000000000; // 1000 USDT
    const BUY_AMOUNT_USDT: u64 = 10000000; // 10 USDT
    const INITIAL_DEPOSIT: u64 = 100000000; // 100 USDT

    // Timing constants
    const TIMING_UNIT_HOURS: u8 = 1;
    const TIMING_VALUE: u64 = 1; // 1 hour

    #[test_only]
    struct MockUSDT {}

    #[test_only]
    fun setup_test_env() {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
    }

    #[test_only]
    fun init_aptos_coin() {
        let aptos_framework = account::create_signer_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test_only]
    fun init_mock_usdt() {
        let mock_account = account::create_signer_for_test(USDT_TOKEN_ADDR);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MockUSDT>(
            &mock_account,
            string::utf8(b"Mock USDT"),
            string::utf8(b"mUSDT"),
            6,
            false,
        );
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_freeze_cap(freeze_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test_only]
    fun setup_accounts_with_balances(admin: &signer, user: &signer, keeper: &signer) {
        let admin_addr = signer::address_of(admin);
        let user_addr = signer::address_of(user);
        let keeper_addr = signer::address_of(keeper);

        // Create accounts
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);
        account::create_account_for_test(keeper_addr);

        // Register for tokens
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user);
        coin::register<AptosCoin>(keeper);

        coin::register<MockUSDT>(admin);
        coin::register<MockUSDT>(user);
        coin::register<MockUSDT>(keeper);

        // Mint initial balances
        let apt_coins = coin::mint<AptosCoin>(INITIAL_APT_BALANCE, &account::create_signer_for_test(@0x1));
        let usdt_coins = coin::mint<MockUSDT>(INITIAL_USDT_BALANCE, &account::create_signer_for_test(USDT_TOKEN_ADDR));

        coin::deposit(user_addr, apt_coins);
        coin::deposit(user_addr, usdt_coins);
    }

    #[test_only]
    fun create_mock_token_metadata(): Object<Metadata> {
        // For testing, we'll create a mock metadata object
        let constructor_ref = &object::create_object(@recadence);
        object::object_from_constructor_ref<Metadata>(constructor_ref)
    }

    #[test(admin = @0x1111)]
    fun test_get_supported_tokens(admin: signer) {
        setup_test_env();
        init_aptos_coin();

        base_agent::initialize_platform(&admin);

        // Test supported tokens function
        let supported_tokens = dca_buy_agent::get_supported_tokens();
        assert!(vector::length(&supported_tokens) == 3, 1);
        assert!(vector::contains(&supported_tokens, &APT_TOKEN_ADDR), 2);
        assert!(vector::contains(&supported_tokens, &USDC_TOKEN_ADDR), 3);
        assert!(vector::contains(&supported_tokens, &USDT_TOKEN_ADDR), 4);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_timing_info_display(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();

        base_agent::initialize_platform(&admin);

        // Test timing info helper function
        let (unit_name, _) = dca_buy_agent::get_timing_info(TIMING_UNIT_HOURS, 1);

        // Verify unit name is returned (exact content may vary)
        assert!(vector::length(&unit_name) > 0, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_create_dca_buy_agent_success(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdt();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        // Create mock metadata object for APT
        let target_token = create_mock_token_metadata();

        let agent_name = b"Test DCA Buy Agent";
        let buy_amount = BUY_AMOUNT_USDT;
        let timing_unit = TIMING_UNIT_HOURS;
        let timing_value = TIMING_VALUE;
        let initial_deposit = INITIAL_DEPOSIT;
        let stop_date = option::none<u64>();

        // Create DCA Buy agent - should succeed without error
        dca_buy_agent::create_dca_buy_agent(
            &user,
            target_token,
            buy_amount,
            timing_unit,
            timing_value,
            initial_deposit,
            stop_date,
            agent_name
        );

        // Verify user has agent created
        let agent_ids = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&agent_ids) >= 1, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_dca_buy_agent_lifecycle(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdt();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();
        let agent_name = b"Lifecycle Test Agent";
        let buy_amount = BUY_AMOUNT_USDT;
        let timing_unit = TIMING_UNIT_HOURS;
        let timing_value = TIMING_VALUE;
        let initial_deposit = INITIAL_DEPOSIT;
        let stop_date = option::none<u64>();

        // Create DCA Buy agent
        dca_buy_agent::create_dca_buy_agent(
            &user,
            target_token,
            buy_amount,
            timing_unit,
            timing_value,
            initial_deposit,
            stop_date,
            agent_name
        );

        // Get user's agent information
        let agent_ids = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&agent_ids) == 1, 1);

        // Verify user stats updated
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 1, 2);
        assert!(sponsored_count == 1, 3);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_multiple_dca_buy_agents(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdt();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();

        // Create multiple DCA Buy agents with different parameters
        let i = 0;
        while (i < 3) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"DCA Agent ");
            vector::push_back(&mut name, (48 + i) as u8); // ASCII '0' + i

            dca_buy_agent::create_dca_buy_agent(
                &user,
                target_token,
                BUY_AMOUNT_USDT + (i * 1000000), // Different amounts
                TIMING_UNIT_HOURS,
                TIMING_VALUE + i, // Different intervals
                INITIAL_DEPOSIT,
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Verify user has multiple agents
        let (active_count, _, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 3, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_dca_buy_agent_with_stop_date(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdt();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();
        let agent_name = b"Stop Date Test Agent";
        let buy_amount = BUY_AMOUNT_USDT;
        let timing_unit = TIMING_UNIT_HOURS;
        let timing_value = TIMING_VALUE;
        let initial_deposit = INITIAL_DEPOSIT;

        // Set stop date to 30 days from now
        let current_time = timestamp::now_seconds();
        let stop_date = option::some(current_time + (30 * 24 * 3600));

        // Create DCA Buy agent with stop date
        dca_buy_agent::create_dca_buy_agent(
            &user,
            target_token,
            buy_amount,
            timing_unit,
            timing_value,
            initial_deposit,
            stop_date,
            agent_name
        );

        // Agent should be created successfully with stop date
        let (active_count, _, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 1, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_agent_limit_enforcement(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdt();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();

        // Create up to the limit (should be 10 agents max per user)
        let i = 0;
        while (i < 10) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_buy_agent::create_dca_buy_agent(
                &user,
                target_token,
                BUY_AMOUNT_USDT,
                TIMING_UNIT_HOURS,
                TIMING_VALUE,
                INITIAL_DEPOSIT,
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Verify user has reached the limit
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 10, 1);
        assert!(sponsored_count == 10, 2);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    #[expected_failure(abort_code = 1, location = recadence::base_agent)]
    fun test_agent_limit_exceeded_fails(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdt();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();

        // Create 10 agents (the maximum)
        let i = 0;
        while (i < 10) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_buy_agent::create_dca_buy_agent(
                &user,
                target_token,
                BUY_AMOUNT_USDT,
                TIMING_UNIT_HOURS,
                TIMING_VALUE,
                INITIAL_DEPOSIT,
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Try to create the 11th agent (should fail)
        dca_buy_agent::create_dca_buy_agent(
            &user,
            target_token,
            BUY_AMOUNT_USDT,
            TIMING_UNIT_HOURS,
            TIMING_VALUE,
            INITIAL_DEPOSIT,
            option::none<u64>(),
            b"Agent 11"
        );
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_user_agent_statistics(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdt();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();

        // Initially no agents
        let (active_count_before, sponsored_count_before, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count_before == 0, 1);
        assert!(sponsored_count_before == 0, 2);

        // Create some agents
        let num_agents = 3;
        let i = 0;
        while (i < num_agents) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Stats Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_buy_agent::create_dca_buy_agent(
                &user,
                target_token,
                BUY_AMOUNT_USDT,
                TIMING_UNIT_HOURS,
                TIMING_VALUE,
                INITIAL_DEPOSIT,
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Verify stats updated
        let (active_count_after, sponsored_count_after, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count_after == num_agents, 3);
        assert!(sponsored_count_after == num_agents, 4);

        // Verify agent IDs are tracked
        let agent_ids = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&agent_ids) == num_agents, 5);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_platform_statistics(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdt();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        // Check initial platform stats
        let (total_created_before, total_active_before) = base_agent::get_platform_stats();
        assert!(total_created_before == 0, 1);
        assert!(total_active_before == 0, 2);

        let target_token = create_mock_token_metadata();

        // Create some agents
        let num_agents = 2;
        let i = 0;
        while (i < num_agents) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Platform Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_buy_agent::create_dca_buy_agent(
                &user,
                target_token,
                BUY_AMOUNT_USDT,
                TIMING_UNIT_HOURS,
                TIMING_VALUE,
                INITIAL_DEPOSIT,
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Check updated platform stats
        let (total_created_after, total_active_after) = base_agent::get_platform_stats();
        assert!(total_created_after == num_agents, 3);
        assert!(total_active_after == num_agents, 4);
    }
}
