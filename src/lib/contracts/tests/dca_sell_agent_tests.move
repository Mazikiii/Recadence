#[test_only]
module recadence::dca_sell_agent_tests {
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
    use recadence::dca_sell_agent;

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
        let supported_tokens = dca_sell_agent::get_supported_tokens();
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
        let (unit_name, _) = dca_sell_agent::get_timing_info(1, 1); // TIMING_UNIT_HOURS, 1 hour

        // Verify unit name is returned
        assert!(vector::length(&unit_name) > 0, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_create_dca_sell_agent_success(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        // Create mock metadata object for APT (source token to sell)
        let source_token = create_mock_token_metadata();

        let sell_amount_tokens = 100000000; // 1 APT (8 decimals)
        let timing_unit = 1; // TIMING_UNIT_HOURS
        let timing_value = 1; // 1 hour
        let initial_token_deposit = 1000000000; // 10 APT
        let stop_date = option::none<u64>();
        let agent_name = b"Test DCA Sell Agent";

        // Create DCA Sell agent - should succeed without error
        dca_sell_agent::create_dca_sell_agent_for_testing(
            &user,
            source_token,
            sell_amount_tokens,
            timing_unit,
            timing_value,
            initial_token_deposit,
            stop_date,
            agent_name
        );

        // Verify user has agent created
        let user_agents = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&user_agents) == 1, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_dca_sell_agent_lifecycle(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        base_agent::initialize_platform(&admin);

        let source_token = create_mock_token_metadata();
        let sell_amount_tokens = 100000000; // 1 APT
        let timing_unit = 1; // TIMING_UNIT_HOURS
        let timing_value = 1; // 1 hour
        let initial_token_deposit = 1000000000; // 10 APT
        let stop_date = option::none<u64>();
        let agent_name = b"Lifecycle Test Agent";

        // Create DCA Sell agent
        dca_sell_agent::create_dca_sell_agent_for_testing(
            &user,
            source_token,
            sell_amount_tokens,
            timing_unit,
            timing_value,
            initial_token_deposit,
            stop_date,
            agent_name
        );

        // Get user's agent information
        let agent_ids = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&agent_ids) == 1, 1);

        // Verify user stats updated
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 1, 1);
        assert!(sponsored_count == 1, 1); // First 10 agents are sponsored
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_multiple_dca_sell_agents(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        base_agent::initialize_platform(&admin);

        let source_token = create_mock_token_metadata();

        // Create multiple agents with different configurations
        let i = 0;
        while (i < 3) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"DCA Sell Agent ");
            vector::push_back(&mut name, (48 + i) as u8); // ASCII '0' + i

            dca_sell_agent::create_dca_sell_agent_for_testing(
                &user,
                source_token,
                100000000 + (i * 50000000), // Different amounts: 1, 1.5, 2 APT
                1, // TIMING_UNIT_HOURS
                1 + i, // Different intervals
                1000000000 + (i * 500000000), // Different deposits: 10, 15, 20 APT
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Verify all agents created
        let user_agents = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&user_agents) == 3, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_dca_sell_agent_with_stop_date(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        base_agent::initialize_platform(&admin);

        let source_token = create_mock_token_metadata();
        let sell_amount_tokens = 100000000; // 1 APT
        let timing_unit = 2; // TIMING_UNIT_DAYS
        let timing_value = 1; // 1 day
        let initial_token_deposit = 3000000000; // 30 APT

        let current_time = timestamp::now_seconds();
        let stop_date = option::some(current_time + (30 * 24 * 3600)); // 30 days from now

        // Create DCA Sell agent with stop date
        dca_sell_agent::create_dca_sell_agent_for_testing(
            &user,
            source_token,
            sell_amount_tokens,
            timing_unit,
            timing_value,
            initial_token_deposit,
            stop_date,
            b"Stop Date Test Agent"
        );

        // Verify agent was created successfully
        let user_agents = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&user_agents) == 1, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_agent_limit_enforcement(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        base_agent::initialize_platform(&admin);

        let source_token = create_mock_token_metadata();

        // Create 10 agents (the maximum allowed)
        let i = 0;
        while (i < 10) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_sell_agent::create_dca_sell_agent_for_testing(
                &user,
                source_token,
                100000000, // 1 APT
                1, // TIMING_UNIT_HOURS
                1, // 1 hour
                1000000000, // 10 APT
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Verify all 10 agents were created
        let user_agents = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&user_agents) == 10, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    #[expected_failure(abort_code = 1, location = recadence::base_agent)]
    fun test_agent_limit_exceeded_fails(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        base_agent::initialize_platform(&admin);

        let source_token = create_mock_token_metadata();

        // Create 10 agents first
        let i = 0;
        while (i < 10) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_sell_agent::create_dca_sell_agent_for_testing(
                &user,
                source_token,
                100000000, // 1 APT
                1, // TIMING_UNIT_HOURS
                1, // 1 hour
                1000000000, // 10 APT
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Try to create 11th agent - should fail (using test-only function)
        dca_sell_agent::create_dca_sell_agent_for_testing(
            &user,
            source_token,
            100000000, // 1 APT
            1, // TIMING_UNIT_HOURS
            1, // 1 hour
            1000000000, // 10 APT
            option::none<u64>(),
            b"Agent That Should Fail"
        );
    }

    #[test(admin = @0x1111, user1 = @0x2222, user2 = @0x3333)]
    fun test_platform_statistics(admin: signer, user1: signer, user2: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x4444);
        account::create_account_for_test(@0x4444);
        coin::register<AptosCoin>(&dummy_user);

        setup_accounts(&admin, &user1, &user2);
        base_agent::initialize_platform(&admin);

        let source_token = create_mock_token_metadata();
        let num_agents = 5;

        // Create agents across multiple users
        let i = 0;
        while (i < num_agents) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Platform Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_sell_agent::create_dca_sell_agent_for_testing(
                &user1,
                source_token,
                100000000, // 1 APT
                1, // TIMING_UNIT_HOURS
                1, // 1 hour
                1000000000, // 10 APT
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Verify platform statistics are updated
        let user1_agents = base_agent::get_user_agent_ids(signer::address_of(&user1));
        assert!(vector::length(&user1_agents) == num_agents, 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_token_balance_validation(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user, &dummy_user);

        base_agent::initialize_platform(&admin);

        let source_token = create_mock_token_metadata();

        // Test agent creation with various token amounts
        let test_amounts = vector[
            100000000,  // 1 APT
            500000000,  // 5 APT
            1000000000, // 10 APT
            5000000000  // 50 APT
        ];

        let i = 0;
        while (i < vector::length(&test_amounts)) {
            let sell_amount = *vector::borrow(&test_amounts, i);
            let deposit_amount = sell_amount * 10; // Ensure sufficient deposit

            let name = vector::empty<u8>();
            vector::append(&mut name, b"Balance Test Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            dca_sell_agent::create_dca_sell_agent_for_testing(
                &user,
                source_token,
                sell_amount,
                1, // TIMING_UNIT_HOURS
                1, // 1 hour
                deposit_amount,
                option::none<u64>(),
                name
            );
            i = i + 1;
        };

        // Verify all agents were created successfully
        let user_agents = base_agent::get_user_agent_ids(signer::address_of(&user));
        assert!(vector::length(&user_agents) == 4, 1);
    }
}
