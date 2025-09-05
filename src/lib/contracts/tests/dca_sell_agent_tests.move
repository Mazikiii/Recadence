#[test_only]
module recadence::dca_sell_agent_tests {
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
    use recadence::dca_sell_agent;
    use recadence::agent_registry;

    // Test addresses
    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_KEEPER_ADDR: address = @0x4444;

    // Mock token addresses for testing
    const MOCK_USDC_ADDR: address = @0x8888;
    const MOCK_WETH_ADDR: address = @0x9999;

    // Test constants
    const INITIAL_APT_BALANCE: u64 = 1000000000; // 10 APT
    const INITIAL_USDC_BALANCE: u64 = 1000000000; // 1000 USDC
    const INITIAL_WETH_BALANCE: u64 = 100000000; // 1 WETH (assuming 8 decimals)
    const DCA_AMOUNT: u64 = 100000000; // 1 APT or equivalent
    const INTERVAL_SECONDS: u64 = 3600; // 1 hour

    #[test_only]
    struct MockUSDC {}

    #[test_only]
    struct MockWETH {}

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
    fun init_mock_tokens() {
        // Initialize Mock USDC
        let mock_usdc_account = account::create_signer_for_test(MOCK_USDC_ADDR);
        let (burn_cap_usdc, freeze_cap_usdc, mint_cap_usdc) = coin::initialize<MockUSDC>(
            &mock_usdc_account,
            b"Mock USDC",
            b"mUSDC",
            6,
            false,
        );
        coin::destroy_burn_cap(burn_cap_usdc);
        coin::destroy_freeze_cap(freeze_cap_usdc);
        coin::destroy_mint_cap(mint_cap_usdc);

        // Initialize Mock WETH
        let mock_weth_account = account::create_signer_for_test(MOCK_WETH_ADDR);
        let (burn_cap_weth, freeze_cap_weth, mint_cap_weth) = coin::initialize<MockWETH>(
            &mock_weth_account,
            b"Mock WETH",
            b"mWETH",
            8,
            false,
        );
        coin::destroy_burn_cap(burn_cap_weth);
        coin::destroy_freeze_cap(freeze_cap_weth);
        coin::destroy_mint_cap(mint_cap_weth);
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

        // Register for all tokens
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user);
        coin::register<AptosCoin>(keeper);

        coin::register<MockUSDC>(admin);
        coin::register<MockUSDC>(user);
        coin::register<MockUSDC>(keeper);

        coin::register<MockWETH>(admin);
        coin::register<MockWETH>(user);
        coin::register<MockWETH>(keeper);

        // Mint initial balances for user
        let apt_coins = coin::mint<AptosCoin>(INITIAL_APT_BALANCE, &account::create_signer_for_test(@0x1));
        let usdc_coins = coin::mint<MockUSDC>(INITIAL_USDC_BALANCE, &account::create_signer_for_test(MOCK_USDC_ADDR));
        let weth_coins = coin::mint<MockWETH>(INITIAL_WETH_BALANCE, &account::create_signer_for_test(MOCK_WETH_ADDR));

        coin::deposit(user_addr, apt_coins);
        coin::deposit(user_addr, usdc_coins);
        coin::deposit(user_addr, weth_coins);
    }

    #[test_only]
    fun create_agent_with_unique_seed(creator: &signer, agent_id: u64): (signer, address) {
        let seed = vector::empty<u8>();
        vector::append(&mut seed, b"dca_sell_");
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
        // Mock successful swap - returns expected amount for testing
        _expected_amount_out
    }

    #[test(admin = @0x1111)]
    fun test_initialize_dca_sell_agent_registry(admin: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();

        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Verify registry is initialized
        assert!(dca_sell_agent::is_initialized(), 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_create_dca_sell_agent_apt_success(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform and registry
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create DCA Sell agent for APT -> USDC
        let agent_name = b"APT Sell Agent";
        let source_token = @0x1; // APT
        let target_token = MOCK_USDC_ADDR; // USDC
        let source_amount = DCA_AMOUNT;
        let interval = INTERVAL_SECONDS;

        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_sell_agent::create_dca_sell_agent(
            &user,
            agent_name,
            source_token,
            target_token,
            source_amount,
            interval
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_sell_agent::store_dca_sell_agent(&resource_signer, dca_agent_struct);

        // Verify agent properties
        assert!(base_agent::is_agent_active(resource_addr), 1);
        assert!(base_agent::get_agent_creator(resource_addr) == signer::address_of(&user), 2);
        assert!(dca_sell_agent::get_source_token(resource_addr) == source_token, 3);
        assert!(dca_sell_agent::get_target_token(resource_addr) == target_token, 4);
        assert!(dca_sell_agent::get_source_amount(resource_addr) == source_amount, 5);
        assert!(dca_sell_agent::get_interval_seconds(resource_addr) == interval, 6);

        // Verify user stats updated
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 1, 7);
        assert!(sponsored_count == 1, 8);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    #[expected_failure(abort_code = 1, location = recadence::dca_sell_agent)]
    fun test_create_dca_sell_agent_insufficient_token_balance(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();

        // Create user account with minimal balance
        account::create_account_for_test(signer::address_of(&user));
        coin::register<AptosCoin>(&user);
        coin::register<MockUSDC>(&user);

        // Give user small APT balance (less than required for DCA)
        let small_apt = coin::mint<AptosCoin>(DCA_AMOUNT / 2, &account::create_signer_for_test(@0x1));
        coin::deposit(signer::address_of(&user), small_apt);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Try to create agent with more than available balance
        let agent_name = b"Insufficient Balance Agent";
        let source_token = @0x1; // APT
        let target_token = MOCK_USDC_ADDR;
        let source_amount = DCA_AMOUNT; // More than available
        let interval = INTERVAL_SECONDS;

        let (_, _, _) = dca_sell_agent::create_dca_sell_agent(
            &user,
            agent_name,
            source_token,
            target_token,
            source_amount,
            interval
        );
    }

    #[test(admin = @0x1111, user = @0x2222)]
    #[expected_failure(abort_code = 4, location = recadence::dca_sell_agent)]
    fun test_create_dca_sell_agent_invalid_source_token(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Try to create agent with invalid source token
        let agent_name = b"Invalid Token Agent";
        let invalid_token = @0x7777; // Invalid token address
        let target_token = MOCK_USDC_ADDR;
        let source_amount = DCA_AMOUNT;
        let interval = INTERVAL_SECONDS;

        let (_, _, _) = dca_sell_agent::create_dca_sell_agent(
            &user,
            agent_name,
            invalid_token,
            target_token,
            source_amount,
            interval
        );
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    fun test_execute_dca_sell_apt_success(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create DCA Sell agent for APT -> USDC
        let agent_name = b"APT Sell Agent";
        let source_token = @0x1; // APT
        let target_token = MOCK_USDC_ADDR;
        let source_amount = DCA_AMOUNT;
        let interval = INTERVAL_SECONDS;

        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_sell_agent::create_dca_sell_agent(
            &user,
            agent_name,
            source_token,
            target_token,
            source_amount,
            interval
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_sell_agent::store_dca_sell_agent(&resource_signer, dca_agent_struct);

        // Fast forward time to allow execution
        timestamp::fast_forward_seconds(interval + 1);

        // Get initial balances
        let initial_apt_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        let initial_usdc_balance = coin::balance<MockUSDC>(signer::address_of(&user));

        // Execute DCA sell (would normally be called by keeper)
        dca_sell_agent::execute_dca_sell(resource_addr, &keeper);

        // Verify execution timestamp updated
        let last_execution = dca_sell_agent::get_last_execution_time(resource_addr);
        assert!(last_execution > 0, 1);

        // Verify transaction count increased
        let tx_count = dca_sell_agent::get_total_sales(resource_addr);
        assert!(tx_count == 1, 2);

        // Verify token balance validation was performed
        assert!(dca_sell_agent::has_sufficient_balance(resource_addr, signer::address_of(&user)), 3);
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    #[expected_failure(abort_code = 1, location = recadence::dca_sell_agent)]
    fun test_execute_dca_sell_insufficient_balance_at_runtime(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();

        // Create user with minimal balance
        account::create_account_for_test(signer::address_of(&user));
        coin::register<AptosCoin>(&user);
        coin::register<MockUSDC>(&user);

        // Give user just enough to create agent initially
        let minimal_apt = coin::mint<AptosCoin>(DCA_AMOUNT, &account::create_signer_for_test(@0x1));
        coin::deposit(signer::address_of(&user), minimal_apt);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create DCA Sell agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"Balance Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_sell_agent::store_dca_sell_agent(&resource_signer, dca_agent_struct);

        // Artificially reduce user's balance below required amount
        let user_apt_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        let excess_withdrawal = coin::withdraw<AptosCoin>(&user, user_apt_balance - (DCA_AMOUNT / 2));
        coin::destroy_for_testing(excess_withdrawal);

        // Fast forward time and try to execute (should fail due to insufficient balance)
        timestamp::fast_forward_seconds(INTERVAL_SECONDS + 1);
        dca_sell_agent::execute_dca_sell(resource_addr, &keeper);
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    #[expected_failure(abort_code = 3, location = recadence::dca_sell_agent)]
    fun test_execute_dca_sell_too_early(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create DCA Sell agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"Early Execution Test",
            @0x1, // APT
            MOCK_USDC_ADDR,
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_sell_agent::store_dca_sell_agent(&resource_signer, dca_agent_struct);

        // Try to execute immediately (should fail)
        dca_sell_agent::execute_dca_sell(resource_addr, &keeper);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_dca_sell_agent_balance_validation_multiple_tokens(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create APT sell agent
        let (base1, resource1, dca1) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"APT Sell Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr1 = signer::address_of(&resource1);
        base_agent::store_base_agent(&resource1, base1);
        dca_sell_agent::store_dca_sell_agent(&resource1, dca1);

        // Create WETH sell agent
        let (base2, resource2, dca2) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"WETH Sell Agent",
            MOCK_WETH_ADDR,
            MOCK_USDC_ADDR,
            DCA_AMOUNT / 10, // Smaller amount for WETH
            INTERVAL_SECONDS * 2
        );

        let resource_addr2 = signer::address_of(&resource2);
        base_agent::store_base_agent(&resource2, base2);
        dca_sell_agent::store_dca_sell_agent(&resource2, dca2);

        // Verify balance validation works for both tokens
        assert!(dca_sell_agent::has_sufficient_balance(resource_addr1, signer::address_of(&user)), 1);
        assert!(dca_sell_agent::has_sufficient_balance(resource_addr2, signer::address_of(&user)), 2);

        // Verify token-specific balance checks
        let user_apt_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        let user_weth_balance = coin::balance<MockWETH>(signer::address_of(&user));

        assert!(user_apt_balance >= DCA_AMOUNT, 3);
        assert!(user_weth_balance >= DCA_AMOUNT / 10, 4);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_pause_resume_dca_sell_agent(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create DCA Sell agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"Pause Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_sell_agent::store_dca_sell_agent(&resource_signer, dca_agent_struct);

        // Verify initially active
        assert!(base_agent::is_agent_active(resource_addr), 1);

        // Pause agent
        base_agent::pause_agent_by_addr(resource_addr, &user);
        assert!(!base_agent::is_agent_active(resource_addr), 2);
        assert!(base_agent::get_agent_state(resource_addr) == 2, 3); // PAUSED state

        // Resume agent
        base_agent::resume_agent_by_addr(resource_addr, &user);
        assert!(base_agent::is_agent_active(resource_addr), 4);
        assert!(base_agent::get_agent_state(resource_addr) == 1, 5); // ACTIVE state
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_update_dca_sell_parameters(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create DCA Sell agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"Update Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_sell_agent::store_dca_sell_agent(&resource_signer, dca_agent_struct);

        // Update parameters
        let new_amount = DCA_AMOUNT / 2; // Reduce amount
        let new_interval = INTERVAL_SECONDS * 3; // Increase interval

        dca_sell_agent::update_dca_parameters(
            resource_addr,
            &user,
            new_amount,
            new_interval
        );

        // Verify updates
        assert!(dca_sell_agent::get_source_amount(resource_addr) == new_amount, 1);
        assert!(dca_sell_agent::get_interval_seconds(resource_addr) == new_interval, 2);

        // Verify balance validation still works with new amount
        assert!(dca_sell_agent::has_sufficient_balance(resource_addr, signer::address_of(&user)), 3);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_dca_sell_agent_statistics_and_tracking(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create DCA Sell agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"Stats Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_sell_agent::store_dca_sell_agent(&resource_signer, dca_agent_struct);

        // Verify initial statistics
        assert!(dca_sell_agent::get_total_sales(resource_addr) == 0, 1);
        assert!(dca_sell_agent::get_total_amount_sold(resource_addr) == 0, 2);
        assert!(dca_sell_agent::get_last_execution_time(resource_addr) == 0, 3);

        // Execute multiple times and track statistics
        let execution_count = 5;
        let i = 0;
        while (i < execution_count) {
            timestamp::fast_forward_seconds(INTERVAL_SECONDS + 1);

            // Verify balance before execution
            assert!(dca_sell_agent::has_sufficient_balance(resource_addr, signer::address_of(&user)), 100 + i);

            dca_sell_agent::execute_dca_sell(resource_addr, &keeper);
            i = i + 1;
        };

        // Verify final statistics
        assert!(dca_sell_agent::get_total_sales(resource_addr) == execution_count, 4);
        assert!(dca_sell_agent::get_last_execution_time(resource_addr) > 0, 5);

        // Verify total amount tracking
        let expected_total_sold = DCA_AMOUNT * execution_count;
        assert!(dca_sell_agent::get_total_amount_sold(resource_addr) == expected_total_sold, 6);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_delete_dca_sell_agent_with_balance_cleanup(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create DCA Sell agent
        let (base_agent_struct, resource_signer, dca_agent_struct) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"Delete Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        dca_sell_agent::store_dca_sell_agent(&resource_signer, dca_agent_struct);

        // Verify initially active
        assert!(base_agent::is_agent_active(resource_addr), 1);

        // Get user balance before deletion
        let balance_before = coin::balance<AptosCoin>(signer::address_of(&user));

        // Delete agent (should return any reserved funds)
        base_agent::delete_agent_by_addr(resource_addr, &user);

        // Verify agent state is deleted
        assert!(base_agent::get_agent_state(resource_addr) == 3, 2); // DELETED state

        // Verify user stats updated
        let (active_count, _, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 0, 3);

        // In a real implementation, verify any reserved funds are returned
        let balance_after = coin::balance<AptosCoin>(signer::address_of(&user));
        // Balance should be same or higher (if reserved funds returned)
        assert!(balance_after >= balance_before, 4);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_multiple_token_dca_sell_agents(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        dca_sell_agent::initialize(&admin);

        // Create APT -> USDC agent
        let (base1, resource1, dca1) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"APT to USDC",
            @0x1, // APT
            MOCK_USDC_ADDR,
            DCA_AMOUNT,
            INTERVAL_SECONDS
        );
        let addr1 = signer::address_of(&resource1);
        base_agent::store_base_agent(&resource1, base1);
        dca_sell_agent::store_dca_sell_agent(&resource1, dca1);

        // Create WETH -> USDC agent
        let (base2, resource2, dca2) = dca_sell_agent::create_dca_sell_agent(
            &user,
            b"WETH to USDC",
            MOCK_WETH_ADDR,
            MOCK_USDC_ADDR,
            DCA_AMOUNT / 10, // Smaller amount for WETH
            INTERVAL_SECONDS * 2
        );
        let addr2 = signer::address_of(&resource2);
        base_agent::store_base_agent(&resource2, base2);
        dca_sell_agent::store_dca_sell_agent(&resource2, dca2);

        // Verify both agents are active and have correct configurations
        assert!(base_agent::is_agent_active(addr1), 1);
        assert!(base_agent::is_agent_active(addr2), 2);

        // Verify different source tokens
        assert!(dca_sell_agent::get_source_token(addr1) == @0x1, 3);
        assert!(dca_sell_agent::get_source_token(addr2) == MOCK_WETH_ADDR, 4);

        // Verify different amounts and intervals
        assert!(dca_sell_agent::get_source_amount(addr1) == DCA_AMOUNT, 5);
        assert!(dca_sell_agent::get_source_amount(addr2) == DCA_AMOUNT / 10, 6);
        assert!(dca_sell_agent::get_interval_seconds(addr1) == INTERVAL_SECONDS, 7);
        assert!(dca_sell_agent::get_interval_seconds(addr2) == INTERVAL_SECONDS * 2, 8);

        // Verify both have sufficient balances for their respective tokens
        assert!(dca_sell_agent::has_sufficient_balance(addr1, signer::address_of(&user)), 9);
        assert!(dca_sell_agent::has_sufficient_balance(addr2, signer::address_of(&user)), 10);

        // Verify user has 2 active agents
        let (active_count, _, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 2, 11);
    }
}
