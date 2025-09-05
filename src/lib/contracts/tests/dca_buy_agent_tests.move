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
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::{Self, Object};

    use recadence::base_agent;
    use recadence::dca_buy_agent;

    // Test addresses
    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;

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
    fun setup_accounts(admin: &signer, user1: &signer, user2: &signer) {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user1_addr);
        account::create_account_for_test(user2_addr);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
    }

    #[test_only]
    fun create_mock_token_metadata(): Object<Metadata> {
        // Create mock object at APT_TOKEN address (@0x1) so it passes is_supported_token check
        let creator = account::create_signer_for_test(@0x1);
        let constructor_ref = object::create_named_object(&creator, b"apt_token");

        // Create the actual Metadata resource using add_fungibility
        fungible_asset::add_fungibility(
            &constructor_ref,
            option::none(), // unlimited supply for testing
            string::utf8(b"Mock APT Token"),
            string::utf8(b"APT"),
            8, // decimals
            string::utf8(b""),
            string::utf8(b""),
        );

        object::object_from_constructor_ref<Metadata>(&constructor_ref)
    }

    #[test(admin = @0x1111)]
    fun test_get_supported_tokens(admin: signer) {
        setup_test_env();
        init_aptos_coin();

        base_agent::initialize_platform(&admin);

        // Test supported tokens function
        let supported_tokens = dca_buy_agent::get_supported_tokens();
        assert!(vector::length(&supported_tokens) >= 3, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_timing_info_display(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        base_agent::initialize_platform(&admin);

        // Test timing info helper function
        let (unit_name, _) = dca_buy_agent::get_timing_info(1, 1); // TIMING_UNIT_HOURS, 1 hour

        // Verify unit name is returned
        assert!(vector::length(&unit_name) > 0, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_create_dca_buy_agent_success(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        // Create mock metadata object for APT
        let target_token = create_mock_token_metadata();

        let buy_amount_usdt = 10000000; // 10 USDT (6 decimals)
        let timing_unit = 1; // TIMING_UNIT_HOURS
        let timing_value = 1; // 1 hour
        let initial_usdt_deposit = 100000000; // 100 USDT
        let stop_date = option::none<u64>();
        let agent_name = b"Test DCA Buy Agent";

        // Create DCA Buy agent - should succeed without error
        dca_buy_agent::create_dca_buy_agent_for_testing(
            &user,
            target_token,
            buy_amount_usdt,
            timing_unit,
            timing_value,
            initial_usdt_deposit,
            stop_date,
            agent_name
        );

        // Verify user has agent created
        let agent_ids = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&agent_ids) >= 1, 1);

        // Verify user stats updated
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count >= 1, 2);
        assert!(sponsored_count >= 1, 3);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_dca_buy_agent_lifecycle(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();
        let buy_amount_usdt = 10000000; // 10 USDT
        let timing_unit = 1; // TIMING_UNIT_HOURS
        let timing_value = 1; // 1 hour
        let initial_usdt_deposit = 100000000; // 100 USDT
        let stop_date = option::none<u64>();
        let agent_name = b"Lifecycle Test Agent";

        // Create DCA Buy agent
        dca_buy_agent::create_dca_buy_agent_for_testing(
            &user,
            target_token,
            buy_amount_usdt,
            timing_unit,
            timing_value,
            initial_usdt_deposit,
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
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();

        // Create multiple DCA Buy agents with different parameters
        let i = 0;
        while (i < 3) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"DCA Agent ");
            vector::push_back(&mut name, (48 + i) as u8); // ASCII '0' + i

            dca_buy_agent::create_dca_buy_agent_for_testing(
                &user,
                target_token,
                10000000 + (i * 1000000), // Different amounts
                1, // TIMING_UNIT_HOURS
                1 + i, // Different intervals
                100000000, // Same deposit
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
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();
        let buy_amount_usdt = 10000000; // 10 USDT
        let timing_unit = 1; // TIMING_UNIT_HOURS
        let timing_value = 1; // 1 hour
        let initial_usdt_deposit = 100000000; // 100 USDT
        let agent_name = b"Stop Date Test Agent";

        // Set stop date to 30 days from now
        let current_time = timestamp::now_seconds();
        let stop_date = option::some(current_time + (30 * 24 * 3600));

        // Create DCA Buy agent with stop date
        dca_buy_agent::create_dca_buy_agent_for_testing(
            &user,
            target_token,
            buy_amount_usdt,
            timing_unit,
            timing_value,
            initial_usdt_deposit,
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
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();

        // Create up to the limit (should be 10 agents max per user)
        let i = 0;
        while (i < 10) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_buy_agent::create_dca_buy_agent_for_testing(
                &user,
                target_token,
                10000000, // 10 USDT
                1, // TIMING_UNIT_HOURS
                1, // 1 hour
                100000000, // 100 USDT deposit
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
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        let target_token = create_mock_token_metadata();

        // Create 10 agents (the maximum)
        let i = 0;
        while (i < 10) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_buy_agent::create_dca_buy_agent_for_testing(
                &user,
                target_token,
                10000000, // 10 USDT
                1, // TIMING_UNIT_HOURS
                1, // 1 hour
                100000000, // 100 USDT deposit
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Try to create 11th agent - should fail (using test-only function)
        dca_buy_agent::create_dca_buy_agent_for_testing(
            &user,
            target_token,
            10000000, // 10 USDT
            1, // TIMING_UNIT_HOURS
            1, // 1 hour
            100000000, // 100 USDT deposit
            option::none<u64>(),
            b"Agent 11"
        );
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_platform_statistics(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        // Check initial platform stats
        let (total_created_before, total_active_before) = base_agent::get_platform_stats();

        let target_token = create_mock_token_metadata();

        // Create some agents
        let num_agents = 2;
        let i = 0;
        while (i < num_agents) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Platform Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_buy_agent::create_dca_buy_agent_for_testing(
                &user,
                target_token,
                10000000, // 10 USDT
                1, // TIMING_UNIT_HOURS
                1, // 1 hour
                100000000, // 100 USDT deposit
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Check updated platform stats
        let (total_created_after, total_active_after) = base_agent::get_platform_stats();
        assert!(total_created_after >= total_created_before + num_agents, 1);
        assert!(total_active_after >= total_active_before + num_agents, 2);
    }
}
