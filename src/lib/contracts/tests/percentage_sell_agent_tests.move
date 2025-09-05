#[test_only]
module recadence::percentage_sell_agent_tests {
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
    use recadence::percentage_sell_agent;
    use recadence::agent_registry;

    // Test addresses
    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_KEEPER_ADDR: address = @0x4444;
    const TEST_ORACLE_ADDR: address = @0x5555;

    // Mock token addresses for testing
    const MOCK_USDC_ADDR: address = @0x8888;
    const MOCK_WETH_ADDR: address = @0x9999;

    // Test constants
    const INITIAL_APT_BALANCE: u64 = 1000000000; // 10 APT
    const INITIAL_USDC_BALANCE: u64 = 1000000000; // 1000 USDC
    const INITIAL_WETH_BALANCE: u64 = 100000000; // 1 WETH
    const SELL_AMOUNT: u64 = 100000000; // 1 APT or equivalent
    const PERCENTAGE_THRESHOLD: u64 = 500; // 5% (500 basis points)
    const HIGHER_PERCENTAGE_THRESHOLD: u64 = 1000; // 10%

    // Trend constants
    const TREND_DOWN: u8 = 0;
    const TREND_UP: u8 = 1;

    // Mock price constants (scaled by 1e8 for precision)
    const INITIAL_PRICE: u64 = 1000000000; // $10.00
    const DOWN_TRIGGER_PRICE: u64 = 950000000; // $9.50 (5% down)
    const UP_TRIGGER_PRICE: u64 = 1050000000; // $10.50 (5% up)
    const LARGE_DOWN_PRICE: u64 = 900000000; // $9.00 (10% down)
    const LARGE_UP_PRICE: u64 = 1100000000; // $11.00 (10% up)

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
    fun setup_accounts_with_balances(admin: &signer, user: &signer, keeper: &signer, oracle: &signer) {
        let admin_addr = signer::address_of(admin);
        let user_addr = signer::address_of(user);
        let keeper_addr = signer::address_of(keeper);
        let oracle_addr = signer::address_of(oracle);

        // Create accounts
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);
        account::create_account_for_test(keeper_addr);
        account::create_account_for_test(oracle_addr);

        // Register for all tokens
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user);
        coin::register<AptosCoin>(keeper);
        coin::register<AptosCoin>(oracle);

        coin::register<MockUSDC>(admin);
        coin::register<MockUSDC>(user);
        coin::register<MockUSDC>(keeper);
        coin::register<MockUSDC>(oracle);

        coin::register<MockWETH>(admin);
        coin::register<MockWETH>(user);
        coin::register<MockWETH>(keeper);
        coin::register<MockWETH>(oracle);

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
        vector::append(&mut seed, b"percentage_sell_");
        let id_bytes = std::bcs::to_bytes(&agent_id);
        vector::append(&mut seed, id_bytes);

        let (resource_signer, _) = account::create_resource_account(creator, seed);
        let resource_addr = signer::address_of(&resource_signer);
        (resource_signer, resource_addr)
    }

    #[test_only]
    fun mock_price_update(token: address, new_price: u64) {
        // Mock function to simulate oracle price updates
        percentage_sell_agent::update_mock_price_for_testing(token, new_price);
    }

    #[test_only]
    fun mock_get_current_price(token: address): u64 {
        // Mock function to get current price
        percentage_sell_agent::get_mock_price_for_testing(token)
    }

    #[test(admin = @0x1111)]
    fun test_initialize_percentage_sell_agent_registry(admin: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();

        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Verify registry is initialized
        assert!(percentage_sell_agent::is_initialized(), 1);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_create_percentage_sell_agent_up_trend(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform and registry
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create Percentage Sell agent for UP trend (sell when price goes up)
        let agent_name = b"APT Up Trend Sell";
        let source_token = @0x1; // APT
        let target_token = MOCK_USDC_ADDR; // USDC
        let sell_amount = SELL_AMOUNT;
        let percentage_threshold = PERCENTAGE_THRESHOLD;
        let trend_direction = TREND_UP; // Sell when price goes UP

        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            agent_name,
            source_token,
            target_token,
            sell_amount,
            percentage_threshold,
            trend_direction
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Verify agent properties
        assert!(base_agent::is_agent_active(resource_addr), 1);
        assert!(base_agent::get_agent_creator(resource_addr) == signer::address_of(&user), 2);
        assert!(percentage_sell_agent::get_source_token(resource_addr) == source_token, 3);
        assert!(percentage_sell_agent::get_target_token(resource_addr) == target_token, 4);
        assert!(percentage_sell_agent::get_sell_amount(resource_addr) == sell_amount, 5);
        assert!(percentage_sell_agent::get_percentage_threshold(resource_addr) == percentage_threshold, 6);
        assert!(percentage_sell_agent::get_trend_direction(resource_addr) == trend_direction, 7);

        // Verify initial reference price is set
        assert!(percentage_sell_agent::get_reference_price(resource_addr) == INITIAL_PRICE, 8);

        // Verify user stats updated
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 1, 9);
        assert!(sponsored_count == 1, 10);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_create_percentage_sell_agent_down_trend(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform and registry
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create Percentage Sell agent for DOWN trend (stop-loss selling)
        let agent_name = b"APT Stop Loss";
        let source_token = @0x1; // APT
        let target_token = MOCK_USDC_ADDR; // USDC
        let sell_amount = SELL_AMOUNT;
        let percentage_threshold = PERCENTAGE_THRESHOLD;
        let trend_direction = TREND_DOWN; // Sell when price goes DOWN (stop-loss)

        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            agent_name,
            source_token,
            target_token,
            sell_amount,
            percentage_threshold,
            trend_direction
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Verify trend direction is DOWN (stop-loss)
        assert!(percentage_sell_agent::get_trend_direction(resource_addr) == TREND_DOWN, 1);

        // Verify initial reference price is set
        assert!(percentage_sell_agent::get_reference_price(resource_addr) == INITIAL_PRICE, 2);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    #[expected_failure(abort_code = 1, location = recadence::percentage_sell_agent)]
    fun test_create_percentage_sell_agent_insufficient_token_balance(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();

        // Create user account with minimal balance
        account::create_account_for_test(signer::address_of(&user));
        coin::register<AptosCoin>(&user);
        coin::register<MockUSDC>(&user);

        // Give user small APT balance (less than required for sell amount)
        let small_apt = coin::mint<AptosCoin>(SELL_AMOUNT / 2, &account::create_signer_for_test(@0x1));
        coin::deposit(signer::address_of(&user), small_apt);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Try to create agent with more than available balance
        let (_, _, _) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Insufficient Balance Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT, // More than available
            PERCENTAGE_THRESHOLD,
            TREND_UP
        );
    }

    #[test(admin = @0x1111, user = @0x2222)]
    #[expected_failure(abort_code = 7, location = recadence::percentage_sell_agent)]
    fun test_create_percentage_sell_agent_invalid_percentage(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        mock_price_update(@0x1, INITIAL_PRICE);

        // Try to create agent with invalid percentage (over 100%)
        let (_, _, _) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Invalid Percentage Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            15000, // 150% - invalid
            TREND_UP
        );
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    fun test_execute_percentage_sell_up_trend_success(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create UP trend sell agent (take profit)
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"APT Take Profit",
            @0x1, // APT
            MOCK_USDC_ADDR, // USDC
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD,
            TREND_UP
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Simulate price increase to trigger execution
        mock_price_update(@0x1, UP_TRIGGER_PRICE);

        // Get initial balances
        let initial_apt_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        let initial_usdc_balance = coin::balance<MockUSDC>(signer::address_of(&user));

        // Execute percentage sell
        percentage_sell_agent::execute_percentage_sell(resource_addr, &keeper);

        // Verify execution occurred
        assert!(percentage_sell_agent::get_total_sales(resource_addr) == 1, 1);
        assert!(percentage_sell_agent::get_last_execution_time(resource_addr) > 0, 2);

        // Verify reference price updated to trigger price
        assert!(percentage_sell_agent::get_reference_price(resource_addr) == UP_TRIGGER_PRICE, 3);

        // Verify execution price recorded
        assert!(percentage_sell_agent::get_last_execution_price(resource_addr) == UP_TRIGGER_PRICE, 4);

        // Verify balance validation passed
        assert!(percentage_sell_agent::has_sufficient_balance(resource_addr, signer::address_of(&user)), 5);
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    fun test_execute_percentage_sell_down_trend_success(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create DOWN trend sell agent (stop-loss)
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"APT Stop Loss",
            @0x1, // APT
            MOCK_USDC_ADDR, // USDC
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD,
            TREND_DOWN
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Simulate price drop to trigger stop-loss
        mock_price_update(@0x1, DOWN_TRIGGER_PRICE);

        // Execute percentage sell (stop-loss)
        percentage_sell_agent::execute_percentage_sell(resource_addr, &keeper);

        // Verify execution occurred
        assert!(percentage_sell_agent::get_total_sales(resource_addr) == 1, 1);
        assert!(percentage_sell_agent::get_last_execution_time(resource_addr) > 0, 2);

        // Verify reference price updated to trigger price
        assert!(percentage_sell_agent::get_reference_price(resource_addr) == DOWN_TRIGGER_PRICE, 3);

        // Verify execution price recorded
        assert!(percentage_sell_agent::get_last_execution_price(resource_addr) == DOWN_TRIGGER_PRICE, 4);
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    #[expected_failure(abort_code = 3, location = recadence::percentage_sell_agent)]
    fun test_execute_percentage_sell_threshold_not_reached_up(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create UP trend sell agent with 5% threshold
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"APT Take Profit",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD, // 5%
            TREND_UP
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Simulate small price increase (only 3% up - not enough to trigger 5% threshold)
        let small_rise_price = 1030000000; // $10.30 (3% up)
        mock_price_update(@0x1, small_rise_price);

        // Try to execute (should fail because threshold not reached)
        percentage_sell_agent::execute_percentage_sell(resource_addr, &keeper);
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    #[expected_failure(abort_code = 3, location = recadence::percentage_sell_agent)]
    fun test_execute_percentage_sell_threshold_not_reached_down(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create DOWN trend sell agent with 5% threshold
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"APT Stop Loss",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD, // 5%
            TREND_DOWN
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Simulate small price drop (only 2% down - not enough to trigger 5% threshold)
        let small_drop_price = 980000000; // $9.80 (2% down)
        mock_price_update(@0x1, small_drop_price);

        // Try to execute (should fail because threshold not reached)
        percentage_sell_agent::execute_percentage_sell(resource_addr, &keeper);
    }

    #[test(admin = @0x1111, user = @0x2222, keeper = @0x4444)]
    #[expected_failure(abort_code = 1, location = recadence::percentage_sell_agent)]
    fun test_execute_percentage_sell_insufficient_balance_runtime(admin: signer, user: signer, keeper: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();

        // Create user with minimal balance
        account::create_account_for_test(signer::address_of(&user));
        coin::register<AptosCoin>(&user);
        coin::register<MockUSDC>(&user);

        // Give user just enough to create agent initially
        let minimal_apt = coin::mint<AptosCoin>(SELL_AMOUNT, &account::create_signer_for_test(@0x1));
        coin::deposit(signer::address_of(&user), minimal_apt);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create percentage sell agent
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Balance Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD,
            TREND_UP
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Artificially reduce user's balance below required amount
        let user_apt_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        let excess_withdrawal = coin::withdraw<AptosCoin>(&user, user_apt_balance - (SELL_AMOUNT / 2));
        coin::destroy_for_testing(excess_withdrawal);

        // Simulate price increase and try to execute (should fail due to insufficient balance)
        mock_price_update(@0x1, UP_TRIGGER_PRICE);
        percentage_sell_agent::execute_percentage_sell(resource_addr, &keeper);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_multiple_executions_stop_loss_strategy(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create DOWN trend sell agent (stop-loss)
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Multi Stop Loss",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD, // 5%
            TREND_DOWN
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // First execution: 5% down (stop-loss triggered)
        mock_price_update(@0x1, DOWN_TRIGGER_PRICE);
        percentage_sell_agent::execute_percentage_sell(resource_addr, &keeper);

        // Verify first execution
        assert!(percentage_sell_agent::get_total_sales(resource_addr) == 1, 1);
        assert!(percentage_sell_agent::get_reference_price(resource_addr) == DOWN_TRIGGER_PRICE, 2);

        // Second execution: Another 5% down from new reference price (cascading stop-loss)
        let second_trigger_price = (DOWN_TRIGGER_PRICE * 95) / 100; // 5% down from first trigger
        mock_price_update(@0x1, second_trigger_price);
        percentage_sell_agent::execute_percentage_sell(resource_addr, &keeper);

        // Verify second execution
        assert!(percentage_sell_agent::get_total_sales(resource_addr) == 2, 3);
        assert!(percentage_sell_agent::get_reference_price(resource_addr) == second_trigger_price, 4);

        // Verify total amount sold
        let expected_total_sold = SELL_AMOUNT * 2;
        assert!(percentage_sell_agent::get_total_amount_sold(resource_addr) == expected_total_sold, 5);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_take_profit_and_stop_loss_agents_simultaneously(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create take-profit agent (UP trend)
        let (base1, resource1, percentage1) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Take Profit Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD,
            TREND_UP
        );
        let addr1 = signer::address_of(&resource1);
        base_agent::store_base_agent(&resource1, base1);
        percentage_sell_agent::store_percentage_sell_agent(&resource1, percentage1);

        // Create stop-loss agent (DOWN trend)
        let (base2, resource2, percentage2) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Stop Loss Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD,
            TREND_DOWN
        );
        let addr2 = signer::address_of(&resource2);
        base_agent::store_base_agent(&resource2, base2);
        percentage_sell_agent::store_percentage_sell_agent(&resource2, percentage2);

        // Verify both agents are configured correctly
        assert!(percentage_sell_agent::get_trend_direction(addr1) == TREND_UP, 1);
        assert!(percentage_sell_agent::get_trend_direction(addr2) == TREND_DOWN, 2);

        // Test price rise - only take-profit agent should execute
        mock_price_update(@0x1, UP_TRIGGER_PRICE);
        percentage_sell_agent::execute_percentage_sell(addr1, &keeper);

        // Verify only take-profit agent executed
        assert!(percentage_sell_agent::get_total_sales(addr1) == 1, 3);
        assert!(percentage_sell_agent::get_total_sales(addr2) == 0, 4);

        // Reset price and test price drop - only stop-loss agent should execute
        mock_price_update(@0x1, INITIAL_PRICE);
        percentage_sell_agent::update_reference_price(addr2, INITIAL_PRICE); // Reset reference for stop-loss agent

        mock_price_update(@0x1, DOWN_TRIGGER_PRICE);
        percentage_sell_agent::execute_percentage_sell(addr2, &keeper);

        // Verify only stop-loss agent executed this time
        assert!(percentage_sell_agent::get_total_sales(addr1) == 1, 5);
        assert!(percentage_sell_agent::get_total_sales(addr2) == 1, 6);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_update_percentage_sell_parameters(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create percentage sell agent
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Update Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD,
            TREND_UP
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Update parameters
        let new_amount = SELL_AMOUNT / 2; // Reduce sell amount
        let new_threshold = HIGHER_PERCENTAGE_THRESHOLD; // 10%
        let new_trend = TREND_DOWN; // Change to stop-loss

        percentage_sell_agent::update_percentage_parameters(
            resource_addr,
            &user,
            new_amount,
            new_threshold,
            new_trend
        );

        // Verify updates
        assert!(percentage_sell_agent::get_sell_amount(resource_addr) == new_amount, 1);
        assert!(percentage_sell_agent::get_percentage_threshold(resource_addr) == new_threshold, 2);
        assert!(percentage_sell_agent::get_trend_direction(resource_addr) == new_trend, 3);

        // Verify balance validation still works with new amount
        assert!(percentage_sell_agent::has_sufficient_balance(resource_addr, signer::address_of(&user)), 4);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_percentage_sell_agent_statistics(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create percentage sell agent
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Statistics Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD,
            TREND_UP
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Verify initial statistics
        assert!(percentage_sell_agent::get_total_sales(resource_addr) == 0, 1);
        assert!(percentage_sell_agent::get_total_amount_sold(resource_addr) == 0, 2);
        assert!(percentage_sell_agent::get_last_execution_time(resource_addr) == 0, 3);
        assert!(percentage_sell_agent::get_last_execution_price(resource_addr) == 0, 4);

        // Execute multiple times with increasing prices
        let execution_prices = vector[UP_TRIGGER_PRICE, LARGE_UP_PRICE];
        let i = 0;
        while (i < vector::length(&execution_prices)) {
            let trigger_price = *vector::borrow(&execution_prices, i);
            mock_price_update(@0x1, trigger_price);

            percentage_sell_agent::execute_percentage_sell(resource_addr, &keeper);

            // Verify statistics updated
            assert!(percentage_sell_agent::get_total_sales(resource_addr) == i + 1, 10 + i);
            assert!(percentage_sell_agent::get_last_execution_price(resource_addr) == trigger_price, 20 + i);

            i = i + 1;
        };

        // Verify final statistics
        let expected_total_sold = SELL_AMOUNT * vector::length(&execution_prices);
        assert!(percentage_sell_agent::get_total_amount_sold(resource_addr) == expected_total_sold, 5);
        assert!(percentage_sell_agent::get_last_execution_time(resource_addr) > 0, 6);
    }

    #[test(admin = @0x1111, user = @0x2222)]
    fun test_delete_percentage_sell_agent(admin: signer, user: signer) {
        setup_test_env();
        init_aptos_coin();
        init_mock_tokens();
        let keeper = account::create_signer_for_test(TEST_KEEPER_ADDR);
        let oracle = account::create_signer_for_test(TEST_ORACLE_ADDR);
        setup_accounts_with_balances(&admin, &user, &keeper, &oracle);

        // Initialize platform
        base_agent::initialize_platform(&admin);
        percentage_sell_agent::initialize(&admin);

        // Set initial price
        mock_price_update(@0x1, INITIAL_PRICE);

        // Create percentage sell agent
        let (base_agent_struct, resource_signer, percentage_agent_struct) = percentage_sell_agent::create_percentage_sell_agent(
            &user,
            b"Delete Test Agent",
            @0x1, // APT
            MOCK_USDC_ADDR,
            SELL_AMOUNT,
            PERCENTAGE_THRESHOLD,
            TREND_UP
        );

        let resource_addr = signer::address_of(&resource_signer);

        // Store agents
        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        percentage_sell_agent::store_percentage_sell_agent(&resource_signer, percentage_agent_struct);

        // Verify initially active
        assert!(base_agent::is_agent_active(resource_addr), 1);

        // Get user balance before deletion
        let balance_before = coin::balance<AptosCoin>(signer::address_of(&user));

        // Delete agent
        base_agent::delete_agent_by_addr(resource_addr, &user);

        // Verify agent state is deleted
        assert!(base_agent::get_agent_state(resource_addr) == 3, 2); // DELETED state

        // Verify user stats updated
        let (active_count, _, _) = base_agent::get_user_agent_info(signer::address_of(&user));
        assert!(active_count == 0, 3);

        // Verify any reserved funds are returned
        let balance_after = coin::balance<AptosCoin>(signer::address_of(&user));
        assert!(balance_after >= balance_before, 4);
    }
}
