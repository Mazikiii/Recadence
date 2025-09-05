#[test_only]
module recadence::dca_buy_agent_tests {
    use std::signer;
    use std::vector;
    use std::option;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object;

    use recadence::base_agent;
    use recadence::dca_buy_agent;
    use recadence::agent_registry;

    // Test addresses
    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_KEEPER_ADDR: address = @0x4444;

    // Mock token addresses for testing
    const MOCK_USDC_ADDR: address = @0x8888;

    // Test constants
    const INITIAL_APT_BALANCE: u64 = 100000000; // 1 APT
    const INITIAL_USDC_BALANCE: u64 = 1000000000; // 1000 USDC (assuming 6 decimals)
    const DCA_AMOUNT: u64 = 10000000; // 10 USDC
    const INTERVAL_SECONDS: u64 = 3600; // 1 hour

    #[test_only]
    struct MockUSDC {}

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
    fun init_mock_usdc() {
        let mock_account = account::create_signer_for_test(MOCK_USDC_ADDR);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MockUSDC>(
            &mock_account,
            b"Mock USDC",
            b"mUSDC",
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

        // Register for APT
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user);
        coin::register<AptosCoin>(keeper);

        // Register for Mock USDC
        coin::register<MockUSDC>(admin);
        coin::register<MockUSDC>(user);
        coin::register<MockUSDC>(keeper);

        // Mint initial balances
        let apt_coins = coin::mint<AptosCoin>(INITIAL_APT_BALANCE, &account::create_signer_for_test(@0x1));
        let usdc_coins = coin::mint<MockUSDC>(INITIAL_USDC_BALANCE, &account::create_signer_for_test(MOCK_USDC_ADDR));

        coin::deposit(user_addr, apt_coins);
        coin::deposit(user_addr, usdc_coins);
    }

    #[test_only]
    fun create_agent_with_unique_seed(creator: &signer, agent_id: u64): (signer, address) {
        let seed = vector::empty<u8>();
        vector::append(&mut seed, b"dca_buy_");
        let id_bytes = std::bcs::to_bytes(&agent_id);
        vector::append(&mut seed, id_bytes);

        let (resource_signer, _) = account::create_resource_account(creator, seed);
        let resource_addr = signer::address_of(&resource_signer);
        (resource_signer, resource_addr)
    }

    #[test_only]
    fun mock_successful_swap(
        _from_token: address,
        _to_token: address,
        _amount_in: u64,
        _expected_amount_out: u64
    ): u64 {
        // Mock successful swap - in real implementation this would call DEX
        // For testing, we assume successful swap and return expected amount
        _expected_amount_out
    }

    #[test(admin = @0x1111)]
    fun test_initialize_dca_buy_agent_registry(admin: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();

        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Verify registry is initialized
        assert!(dca_buy_agent::is_initialized(), 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_create_dca_buy_agent_success(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform and registry
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Create DCA Buy agent
        let agent_name = b"Test DCA Buy Agent";
        let target_token = @0x1; // APT
        let source_amount = DCA_AMOUNT;
        let interval = INTERVAL_SECONDS;

        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_buy_agent::create_dca_buy_agent(
            &user,
            agent_name,
            target_token,
            source_amount,
            interval
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_buy_agent::store_dca_buy_agent(&resource_signer, dca_agent_struct);

        // Verify agent properties
        assert!(base_agent::is_agent_active(resource_addr), 1);
        assert!(base_agent::get_agent_creator(resource_addr) == signer::address_of(&user), 2);
        assert!(dca_buy_agent::get_target_token(resource_addr) == target_token, 3);
        assert!(dca_buy_agent::get_source_amount(resource_addr) == source_amount, 4);
        assert!(dca_buy_agent::get_interval_seconds(resource_addr) == interval, 5);

        // Verify user stats updated
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 1, 6);
        assert!(sponsored_count == 1, 7);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    #[expected_failure(abort_code = 1, location = recadence::dca_buy_agent)]
    fun test_create_dca_buy_agent_insufficient_balance(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);

        // Create accounts without sufficient balance
        account::create_account_for_test(signer::address_of(&user));
        coin::register<MockUSDC>(&user);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Try to create agent with more than available balance
        let agent_name = b"Test DCA Buy Agent";
        let target_token = @0x1;
        let source_amount = INITIAL_USDC_BALANCE + 1; // More than available
        let interval = INTERVAL_SECONDS;

        let (_, _, _) = dca_buy_agent::create_dca_buy_agent(
            &user,
            agent_name,
            target_token,
            source_amount,
            interval
        );
    }

    #[test(admin = @0x1111, user = @0x2222)]
    #[expected_failure(abort_code = 4, location = recadence::dca_buy_agent)]
    fun test_create_dca_buy_agent_invalid_token(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Try to create agent with invalid target token
        let agent_name = b"Invalid Token Agent";
        let invalid_token = @0x9999; // Invalid token address
        let source_amount = DCA_AMOUNT;
        let interval = INTERVAL_SECONDS;

        let (_, _, _) = dca_buy_agent::create_dca_buy_agent(
            &user,
            agent_name,
            invalid_token,
            source_amount,
            interval
        );
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    fun test_execute_dca_buy_success(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Create DCA Buy agent
        let agent_name = b"Test DCA Buy Agent";
        let target_token = @0x1; // APT
        let source_amount = DCA_AMOUNT;
        let interval = INTERVAL_SECONDS;

        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_buy_agent::create_dca_buy_agent(
            &user,
            agent_name,
            target_token,
            source_amount,
            interval
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_buy_agent::store_dca_buy_agent(&resource_signer, dca_agent_struct);

        // Fast forward time to allow execution
        timestamp::fast_forward_seconds(interval + 1);

        // Get initial balances
        let initial_usdc_balance = coin::balance<MockUSDC>(signer::address_of(&user));
        let initial_apt_balance = coin::balance<AptosCoin>(signer::address_of(&user));

        // Execute DCA buy (would normally be called by keeper)
        dca_buy_agent::execute_dca_buy(resource_addr, &keeper);

        // Verify balances changed (in real implementation)
        // Note: This would require actual DEX integration for full verification

        // Verify execution timestamp updated
        let last_execution = dca_buy_agent::get_last_execution_time(resource_addr);
        assert!(last_execution > 0, 1);

        // Verify transaction count increased
        let tx_count = dca_buy_agent::get_total_purchases(resource_addr);
        assert!(tx_count == 1, 2);
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    #[expected_failure(abort_code = 3, location = recadence::dca_buy_agent)]
    fun test_execute_dca_buy_too_early(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Create DCA Buy agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_buy_agent::create_dca_buy_agent(
            &user,
            b"Test DCA Buy Agent",
            @0x1, // APT
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_buy_agent::store_dca_buy_agent(&resource_signer, dca_agent_struct);

        // Try to execute immediately (should fail)
        dca_buy_agent::execute_dca_buy(resource_addr, &keeper);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_pause_resume_dca_buy_agent(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Create DCA Buy agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_buy_agent::create_dca_buy_agent(
            &user,
            b"Test DCA Buy Agent",
            @0x1, // APT
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_buy_agent::store_dca_buy_agent(&resource_signer, dca_agent_struct);

        // Verify initially active
        assert!(base_agent::is_agent_active(resource_addr), 1);

        // Pause agent
        base_agent::pause_agent_by_addr(resource_addr, &user);
        assert!(!base_agent::is_agent_active(resource_addr), 2);

        // Resume agent
        base_agent::resume_agent_by_addr(resource_addr, &user);
        assert!(base_agent::is_agent_active(resource_addr), 3);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_update_dca_buy_parameters(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Create DCA Buy agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_buy_agent::create_dca_buy_agent(
            &user,
            b"Test DCA Buy Agent",
            @0x1, // APT
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_buy_agent::store_dca_buy_agent(&resource_signer, dca_agent_struct);

        // Update parameters
        let new_amount = DCA_AMOUNT * 2;
        let new_interval = INTERVAL_SECONDS * 2;

        dca_buy_agent::update_dca_parameters(
            resource_addr,
            &user,
            new_amount,
            new_interval
        );

        // Verify updates
        assert!(dca_buy_agent::get_source_amount(resource_addr) == new_amount, 1);
        assert!(dca_buy_agent::get_interval_seconds(resource_addr) == new_interval, 2);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_delete_dca_buy_agent(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Create DCA Buy agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_buy_agent::create_dca_buy_agent(
            &user,
            b"Test DCA Buy Agent",
            @0x1, // APT
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_buy_agent::store_dca_buy_agent(&resource_signer, dca_agent_struct);

        // Verify initially active
        assert!(base_agent::is_agent_active(resource_addr), 1);

        // Delete agent
        base_agent::delete_agent_by_addr(resource_addr, &user);

        // Verify agent state is deleted
        assert!(base_agent::get_agent_state(resource_addr) == 3, 2); // DELETED state

        // Verify user stats updated
        let (active_count, _, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 0, 3);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_multiple_dca_buy_agents(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Create multiple DCA Buy agents with different targets
        let apt_agent = dca_buy_agent::create_dca_buy_agent(
            &user,
            b"APT DCA Agent",
            @0x1, // APT
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let (base1, resource1, dca1) = apt_agent;
        let resource_addr1 = signer::address_of(&resource1);
        base_agent::store_base_agent(&resource1, base1);
        dca_buy_agent::store_dca_buy_agent(&resource1, dca1);

        // Create second agent with different parameters
        let usdc_agent = dca_buy_agent::create_dca_buy_agent(
            &user,
            b"USDC DCA Agent",
            MOCK_USDC_ADDR,
            DCA_AMOUNT / 2,
            INTERVAL_SECONDS * 2
        );

        let (base2, resource2, dca2) = usdc_agent;
        let resource_addr2 = signer::address_of(&resource2);
        base_agent::store_base_agent(&resource2, base2);
        dca_buy_agent::store_dca_buy_agent(&resource2, dca2);

        // Verify both agents are active
        assert!(base_agent::is_agent_active(resource_addr1), 1);
        assert!(base_agent::is_agent_active(resource_addr2), 2);

        // Verify different configurations
        assert!(dca_buy_agent::get_target_token(resource_addr1) == @0x1, 3);
        assert!(dca_buy_agent::get_target_token(resource_addr2) == MOCK_USDC_ADDR, 4);
        assert!(dca_buy_agent::get_source_amount(resource_addr1) == DCA_AMOUNT, 5);
        assert!(dca_buy_agent::get_source_amount(resource_addr2) == DCA_AMOUNT / 2, 6);

        // Verify user has 2 active agents
        let (active_count, _, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 2, 7);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_dca_buy_agent_statistics(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_usdc();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_buy_agent::initialize(&admin);

        // Create DCA Buy agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_buy_agent::create_dca_buy_agent(
            &user,
            b"Stats Test Agent",
            @0x1, // APT
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_buy_agent::store_dca_buy_agent(&resource_signer, dca_agent_struct);

        // Verify initial statistics
        assert!(dca_buy_agent::get_total_purchases(resource_addr) == 0, 1);
        assert!(dca_buy_agent::get_total_amount_purchased(resource_addr) == 0, 2);
        assert!(dca_buy_agent::get_last_execution_time(resource_addr) == 0, 3);

        // Simulate multiple executions
        let execution_count = 3;
        let i = 0;
        while (i < execution_count) {
            timestamp::fast_forward_seconds(interval + 1);
            dca_buy_agent::execute_dca_buy(resource_addr, &keeper);
            i = i + 1;
        };

        // Verify statistics updated
        assert!(dca_buy_agent::get_total_purchases(resource_addr) == execution_count, 4);
        assert!(dca_buy_agent::get_last_execution_time(resource_addr) > 0, 5);
    }
}
