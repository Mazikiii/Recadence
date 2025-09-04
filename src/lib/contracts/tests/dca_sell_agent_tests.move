/// DCA Sell Agent Contract Unit Tests
///
/// Comprehensive test suite for the dca_sell_agent module covering:
/// - Agent creation with various source tokens and timing configurations
/// - Token balance validation and management
/// - DCA sell execution logic and timing validation
/// - DEX integration for token-to-USDT swaps
/// - Average price calculation over multiple sales
/// - Edge cases with minimum/maximum values
/// - Error conditions and failure scenarios
/// - Integration with base agent functionality
///
/// Target: 95%+ code coverage

module recadence::dca_sell_agent_tests {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::string;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::{Self, Object};

    use recadence::base_agent::{Self, BaseAgent};
    use recadence::dca_sell_agent;
    use recadence::test_framework;

    // ================================================================================================
    // Test Constants
    // ================================================================================================

    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_KEEPER_ADDR: address = @0x4444;

    // Token addresses for testing
    const APT_TOKEN_ADDR: address = @0x1;
    const USDT_TOKEN_ADDR: address = @0x357b0b74bc833e95a115ad22604854d6b0fca151cecd94111770e5d6ffc9dc2b;
    const USDC_TOKEN_ADDR: address = @0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832;
    const WETH_TOKEN_ADDR: address = @0x1234; // Mock WETH address
    const WBTC_TOKEN_ADDR: address = @0x5678; // Mock WBTC address

    // Test amounts
    const DEFAULT_SELL_AMOUNT: u64 = 1000000000; // 10 APT/tokens
    const DEFAULT_TOKEN_BALANCE: u64 = 100000000000; // 1000 tokens
    const MINIMUM_SELL_AMOUNT: u64 = 100000000; // 1 token
    const MAXIMUM_SELL_AMOUNT: u64 = 1000000000000; // 10,000 tokens

    // Timing constants
    const TIMING_UNIT_MINUTES: u8 = 0;
    const TIMING_UNIT_HOURS: u8 = 1;
    const TIMING_UNIT_WEEKS: u8 = 2;
    const TIMING_UNIT_MONTHS: u8 = 3;

    // ================================================================================================
    // Setup and Initialization Tests
    // ================================================================================================

    #[test]
    /// Test DCA Sell Agent creation with valid parameters
    fun test_create_dca_sell_agent_success() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup test environment
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Get test data
        let (name, sell_amount, timing_unit, timing_value, stop_date) =
            test_framework::generate_dca_sell_test_data();

        // Create DCA Sell Agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            name,
            APT_TOKEN_ADDR, // Source APT
            sell_amount,
            timing_unit,
            timing_value,
            stop_date
        );

        // Verify agent properties
        assert!(dca_sell_agent::get_agent_id(&agent) == 1, 1);
        assert!(dca_sell_agent::get_creator(&agent) == TEST_USER1_ADDR, 2);
        assert!(dca_sell_agent::get_source_token_address(&agent) == APT_TOKEN_ADDR, 3);
        assert!(dca_sell_agent::get_sell_amount_tokens(&agent) == sell_amount, 4);
        assert!(dca_sell_agent::get_timing_unit(&agent) == timing_unit, 5);
        assert!(dca_sell_agent::get_timing_value(&agent) == timing_value, 6);
        assert!(dca_sell_agent::is_active(&agent), 7);

        // Verify initial state
        assert!(dca_sell_agent::get_total_sold(&agent) == 0, 8);
        assert!(dca_sell_agent::get_total_usdt_received(&agent) == 0, 9);
        assert!(dca_sell_agent::get_execution_count(&agent) == 0, 10);
    }

    #[test]
    /// Test DCA Sell Agent creation with different source tokens
    fun test_create_agents_different_source_tokens() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Test different source tokens
        let source_tokens = vector[APT_TOKEN_ADDR, USDC_TOKEN_ADDR, WETH_TOKEN_ADDR, WBTC_TOKEN_ADDR];
        let token_names = vector[b"APT Sell Agent", b"USDC Sell Agent", b"WETH Sell Agent", b"WBTC Sell Agent"];

        let i = 0;
        while (i < vector::length(&source_tokens)) {
            let source_token = *vector::borrow(&source_tokens, i);
            let name = *vector::borrow(&token_names, i);

            let agent = dca_sell_agent::create_dca_sell_agent(
                &user1,
                name,
                source_token,
                DEFAULT_SELL_AMOUNT,
                TIMING_UNIT_HOURS,
                24,
                option::none()
            );

            assert!(dca_sell_agent::get_source_token_address(&agent) == source_token, 100 + i);

            i = i + 1;
        };
    }

    #[test]
    /// Test DCA Sell Agent creation with different timing units
    fun test_create_agents_different_timing_units() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Test different timing units
        let timing_configs = vector[
            (TIMING_UNIT_MINUTES, 30u64), // 30 minutes
            (TIMING_UNIT_HOURS, 6u64),    // 6 hours
            (TIMING_UNIT_WEEKS, 1u64),    // 1 week
            (TIMING_UNIT_MONTHS, 2u64)    // 2 months
        ];

        let i = 0;
        while (i < vector::length(&timing_configs)) {
            let (unit, value) = *vector::borrow(&timing_configs, i);

            let name = b"DCA Sell Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));

            let agent = dca_sell_agent::create_dca_sell_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_SELL_AMOUNT,
                unit,
                value,
                option::none()
            );

            assert!(dca_sell_agent::get_timing_unit(&agent) == unit, 100 + i);
            assert!(dca_sell_agent::get_timing_value(&agent) == value, 200 + i);

            i = i + 1;
        };
    }

    // ================================================================================================
    // Timing Configuration Tests
    // ================================================================================================

    #[test]
    #[expected_failure(abort_code = 8, location = Self)] // Invalid timing configuration
    /// Test invalid timing configuration - minutes out of range
    fun test_invalid_timing_minutes_too_low() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Try to create agent with invalid timing (10 minutes, below minimum 15)
        let _agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Invalid Timing Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_MINUTES,
            10, // Below minimum
            option::none()
        );
    }

    #[test]
    #[expected_failure(abort_code = 8, location = Self)]
    /// Test invalid timing configuration - weeks out of range
    fun test_invalid_timing_weeks_too_high() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Try to create agent with invalid timing (3 weeks, above maximum 2)
        let _agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Invalid Timing Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_WEEKS,
            3, // Above maximum
            option::none()
        );
    }

    #[test]
    /// Test valid timing boundaries
    fun test_valid_timing_boundaries() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Test minimum and maximum valid values for each unit
        let valid_configs = vector[
            (TIMING_UNIT_MINUTES, 15u64), // Minimum minutes
            (TIMING_UNIT_MINUTES, 30u64), // Maximum minutes
            (TIMING_UNIT_HOURS, 1u64),    // Minimum hours
            (TIMING_UNIT_HOURS, 12u64),   // Maximum hours
            (TIMING_UNIT_WEEKS, 1u64),    // Minimum weeks
            (TIMING_UNIT_WEEKS, 2u64),    // Maximum weeks
            (TIMING_UNIT_MONTHS, 1u64),   // Minimum months
            (TIMING_UNIT_MONTHS, 6u64)    // Maximum months
        ];

        let i = 0;
        while (i < vector::length(&valid_configs)) {
            let (unit, value) = *vector::borrow(&valid_configs, i);

            let name = b"Boundary Test ";
            vector::append(&name, vector::singleton((48 + i) as u8));

            let agent = dca_sell_agent::create_dca_sell_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_SELL_AMOUNT,
                unit,
                value,
                option::none()
            );

            assert!(dca_sell_agent::get_timing_unit(&agent) == unit, 100 + i);
            assert!(dca_sell_agent::get_timing_value(&agent) == value, 200 + i);

            i = i + 1;
        };
    }

    // ================================================================================================
    // Token Balance and Funding Tests
    // ================================================================================================

    #[test]
    /// Test agent token deposit functionality
    fun test_agent_token_deposit() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Token Deposit Test Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Initial balance should be 0
        assert!(dca_sell_agent::get_remaining_tokens(&agent) == 0, 1);

        // Deposit tokens
        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);
        assert!(dca_sell_agent::get_remaining_tokens(&agent) == DEFAULT_TOKEN_BALANCE, 2);

        // Deposit again (should add to existing balance)
        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);
        assert!(dca_sell_agent::get_remaining_tokens(&agent) == DEFAULT_TOKEN_BALANCE * 2, 3);
    }

    #[test]
    /// Test withdrawing tokens from agent
    fun test_withdraw_tokens() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create and fund agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Withdraw Test Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);

        // Withdraw partial amount
        let withdraw_amount = DEFAULT_TOKEN_BALANCE / 2;
        dca_sell_agent::withdraw_tokens(&agent, &user1, withdraw_amount);

        assert!(dca_sell_agent::get_remaining_tokens(&agent) == DEFAULT_TOKEN_BALANCE - withdraw_amount, 1);

        // Withdraw remaining amount
        dca_sell_agent::withdraw_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE - withdraw_amount);
        assert!(dca_sell_agent::get_remaining_tokens(&agent) == 0, 2);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = Self)] // E_INSUFFICIENT_FUNDS
    /// Test withdrawing more than available balance fails
    fun test_withdraw_more_than_balance() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create and fund agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Withdraw Fail Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);

        // Try to withdraw more than balance
        dca_sell_agent::withdraw_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE + 1);
    }

    // ================================================================================================
    // DCA Execution Tests
    // ================================================================================================

    #[test]
    /// Test successful DCA sell execution
    fun test_successful_dca_sell_execution() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &keeper);

        // Create DCA sell agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Test DCA Sell Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1, // Every hour
            option::none()
        );

        // Deposit tokens to the agent
        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);

        // Mock successful DEX response (sell 10 APT for 100 USDT)
        let mock_response = test_framework::mock_successful_swap(
            DEFAULT_SELL_AMOUNT,     // 10 APT sold
            10000000000              // 100 USDT received (8 decimals)
        );

        // Advance time to make execution ready
        test_framework::advance_time_by_hours(&admin, 2);

        // Execute DCA sell
        dca_sell_agent::execute_dca_sell(&agent, &keeper, mock_response);

        // Verify execution results
        assert!(dca_sell_agent::get_execution_count(&agent) == 1, 1);
        assert!(dca_sell_agent::get_total_sold(&agent) == DEFAULT_SELL_AMOUNT, 2);
        assert!(dca_sell_agent::get_total_usdt_received(&agent) == 10000000000, 3);
        assert!(dca_sell_agent::get_remaining_tokens(&agent) == DEFAULT_TOKEN_BALANCE - DEFAULT_SELL_AMOUNT, 4);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = Self)] // E_NOT_TIME_FOR_EXECUTION
    /// Test DCA sell execution before timing interval
    fun test_dca_sell_execution_too_early() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create DCA sell agent with 24-hour interval
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Test DCA Sell Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            24,
            option::none()
        );

        // Deposit tokens
        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);

        // Try to execute immediately (should fail)
        let mock_response = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 10000000000);
        dca_sell_agent::execute_dca_sell(&agent, &keeper, mock_response);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)] // E_INSUFFICIENT_TOKEN_BALANCE
    /// Test DCA sell execution with insufficient token balance
    fun test_dca_sell_execution_insufficient_balance() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create DCA sell agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Test DCA Sell Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Deposit insufficient tokens
        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_SELL_AMOUNT / 2);

        // Advance time
        test_framework::advance_time_by_hours(&admin, 2);

        // Try to execute (should fail due to insufficient tokens)
        let mock_response = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 10000000000);
        dca_sell_agent::execute_dca_sell(&agent, &keeper, mock_response);
    }

    #[test]
    /// Test multiple DCA sell executions over time
    fun test_multiple_dca_sell_executions() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create DCA sell agent with 1-hour intervals
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Multi Execution Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Deposit tokens for multiple executions
        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_SELL_AMOUNT * 5);

        let total_sold = 0u64;
        let total_received = 0u64;

        // Execute 3 times
        let i = 0;
        while (i < 3) {
            // Advance time
            test_framework::advance_time_by_hours(&admin, 1);

            // Mock different USDT amounts received each time (different prices)
            let usdt_received = 10000000000 + (i * 1000000000); // 100, 110, 120 USDT
            let mock_response = test_framework::mock_successful_swap(
                DEFAULT_SELL_AMOUNT,
                usdt_received
            );

            // Execute DCA sell
            dca_sell_agent::execute_dca_sell(&agent, &keeper, mock_response);

            total_sold = total_sold + DEFAULT_SELL_AMOUNT;
            total_received = total_received + usdt_received;

            // Verify cumulative totals
            assert!(dca_sell_agent::get_execution_count(&agent) == i + 1, 100 + i);
            assert!(dca_sell_agent::get_total_sold(&agent) == total_sold, 200 + i);
            assert!(dca_sell_agent::get_total_usdt_received(&agent) == total_received, 300 + i);

            i = i + 1;
        };
    }

    // ================================================================================================
    // Agent State Management Tests
    // ================================================================================================

    #[test]
    /// Test pausing and resuming DCA sell agent
    fun test_pause_resume_dca_sell_agent() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create DCA sell agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Pause Test Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Verify initial active state
        assert!(dca_sell_agent::is_active(&agent), 1);

        // Pause agent
        dca_sell_agent::pause_agent(&agent, &user1);
        assert!(!dca_sell_agent::is_active(&agent), 2);
        assert!(dca_sell_agent::is_paused(&agent), 3);

        // Resume agent
        dca_sell_agent::resume_agent(&agent, &user1);
        assert!(dca_sell_agent::is_active(&agent), 4);
        assert!(!dca_sell_agent::is_paused(&agent), 5);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = Self)] // E_AGENT_NOT_ACTIVE
    /// Test DCA sell execution on paused agent fails
    fun test_execute_dca_sell_on_paused_agent() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create and pause agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Paused Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);
        dca_sell_agent::pause_agent(&agent, &user1);

        // Advance time and try to execute (should fail)
        test_framework::advance_time_by_hours(&admin, 2);
        let mock_response = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 10000000000);
        dca_sell_agent::execute_dca_sell(&agent, &keeper, mock_response);
    }

    // ================================================================================================
    // Stop Date Tests
    // ================================================================================================

    #[test]
    /// Test agent with stop date functionality
    fun test_agent_with_stop_date() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent with stop date in 2 hours
        let current_time = test_framework::get_mock_timestamp(TEST_ADMIN_ADDR);
        let stop_date = option::some(current_time + 7200); // 2 hours from now

        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Stop Date Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            stop_date
        );

        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);

        // Execute once before stop date
        test_framework::advance_time_by_hours(&admin, 1);
        let mock_response = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 10000000000);
        dca_sell_agent::execute_dca_sell(&agent, &keeper, mock_response);

        assert!(dca_sell_agent::get_execution_count(&agent) == 1, 1);

        // Advance past stop date
        test_framework::advance_time_by_hours(&admin, 2);

        // Agent should auto-pause
        assert!(!dca_sell_agent::is_active(&agent), 2);
    }

    // ================================================================================================
    // Average Price Calculation Tests
    // ================================================================================================

    #[test]
    /// Test average price calculation with multiple executions
    fun test_average_price_calculation() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Average Price Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT, // 10 APT each time
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_SELL_AMOUNT * 3);

        // First execution: 10 APT -> 100 USDT (10 USDT per APT)
        test_framework::advance_time_by_hours(&admin, 1);
        let response1 = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 10000000000); // 100 USDT
        dca_sell_agent::execute_dca_sell(&agent, &keeper, response1);

        // Second execution: 10 APT -> 200 USDT (20 USDT per APT)
        test_framework::advance_time_by_hours(&admin, 1);
        let response2 = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 20000000000); // 200 USDT
        dca_sell_agent::execute_dca_sell(&agent, &keeper, response2);

        // Average should be: (100 + 200) USDT / (10 + 10) APT = 300/20 = 15 USDT per APT
        let average_price = dca_sell_agent::get_average_price(&agent);
        let expected_average = (30000000000 * 100000000) / (DEFAULT_SELL_AMOUNT * 2); // Scaled calculation

        assert!(average_price == expected_average, 1);
    }

    // ================================================================================================
    // Edge Cases and Error Conditions
    // ================================================================================================

    #[test]
    /// Test minimum sell amount
    fun test_minimum_sell_amount() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent with minimum sell amount
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Min Amount Agent",
            APT_TOKEN_ADDR,
            MINIMUM_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        assert!(dca_sell_agent::get_sell_amount_tokens(&agent) == MINIMUM_SELL_AMOUNT, 1);
    }

    #[test]
    /// Test maximum sell amount
    fun test_maximum_sell_amount() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent with maximum sell amount
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Max Amount Agent",
            APT_TOKEN_ADDR,
            MAXIMUM_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        assert!(dca_sell_agent::get_sell_amount_tokens(&agent) == MAXIMUM_SELL_AMOUNT, 1);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = Self)] // E_SWAP_FAILED
    /// Test DCA sell execution with failed DEX swap
    fun test_dca_sell_execution_swap_failure() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create and fund agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Swap Fail Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_TOKEN_BALANCE);

        // Advance time
        test_framework::advance_time_by_hours(&admin, 2);

        // Execute with failed swap response
        let failed_response = test_framework::mock_failed_swap();
        dca_sell_agent::execute_dca_sell(&agent, &keeper, failed_response);
    }

    #[test]
    /// Test auto-pause when insufficient tokens remain
    fun test_auto_pause_insufficient_tokens() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent
        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Auto Pause Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Deposit exactly enough for one execution
        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_SELL_AMOUNT);

        // Execute once
        test_framework::advance_time_by_hours(&admin, 1);
        let mock_response = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 10000000000);
        dca_sell_agent::execute_dca_sell(&agent, &keeper, mock_response);

        // Agent should auto-pause due to insufficient tokens for next execution
        assert!(!dca_sell_agent::is_active(&agent), 1);
        assert!(dca_sell_agent::get_remaining_tokens(&agent) == 0, 2);
    }

    // ================================================================================================
    // Integration Tests
    // ================================================================================================

    #[test]
    /// Test comprehensive DCA sell agent lifecycle
    fun test_comprehensive_dca_sell_lifecycle() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent with stop date
        let current_time = test_framework::get_mock_timestamp(TEST_ADMIN_ADDR);
        let stop_date = option::some(current_time + 10800); // 3 hours from now

        let agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"Lifecycle Agent",
            WETH_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            stop_date
        );

        // Deposit tokens
        dca_sell_agent::deposit_tokens(&agent, &user1, DEFAULT_SELL_AMOUNT * 5);

        // Execute twice before stop date
        test_framework::advance_time_by_hours(&admin, 1);
        let response1 = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 30000000000); // 300 USDT
        dca_sell_agent::execute_dca_sell(&agent, &keeper, response1);

        test_framework::advance_time_by_hours(&admin, 1);
        let response2 = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 32000000000); // 320 USDT
        dca_sell_agent::execute_dca_sell(&agent, &keeper, response2);

        // Pause agent manually
        dca_sell_agent::pause_agent(&agent, &user1);

        // Advance past stop date
        test_framework::advance_time_by_hours(&admin, 2);

        // Resume and verify state
        dca_sell_agent::resume_agent(&agent, &user1);

        // Verify final state
        assert!(dca_sell_agent::get_execution_count(&agent) == 2, 1);
        assert!(dca_sell_agent::get_total_sold(&agent) == DEFAULT_SELL_AMOUNT * 2, 2);
        assert!(dca_sell_agent::get_total_usdt_received(&agent) == 62000000000, 3); // 300 + 320
        assert!(dca_sell_agent::get_remaining_tokens(&agent) == DEFAULT_SELL_AMOUNT * 3, 4);

        // Withdraw remaining tokens
        dca_sell_agent::withdraw_tokens(&agent, &user1, DEFAULT_SELL_AMOUNT * 3);
        assert!(dca_sell_agent::get_remaining_tokens(&agent) == 0, 5);

        // Delete agent
        dca_sell_agent::delete_agent(&agent, &user1);
        assert!(dca_sell_agent::get_state(&agent) == 3, 6); // DELETED state
    }

    #[test]
    /// Test multi-user scenario with different tokens
    fun test_multi_user_different_tokens() {
        let (admin, user1, user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // User1 creates APT sell agent
        let apt_agent = dca_sell_agent::create_dca_sell_agent(
            &user1,
            b"User1 APT Agent",
            APT_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT,
            TIMING_UNIT_HOURS,
            2,
            option::none()
        );

        // User2 creates WETH sell agent
        let weth_agent = dca_sell_agent::create_dca_sell_agent(
            &user2,
            b"User2 WETH Agent",
            WETH_TOKEN_ADDR,
            DEFAULT_SELL_AMOUNT / 10, // Smaller amount for WETH
            TIMING_UNIT_HOURS,
            3,
            option::none()
        );

        // Deposit tokens to both agents
        dca_sell_agent::deposit_tokens(&apt_agent, &user1, DEFAULT_TOKEN_BALANCE);
        dca_sell_agent::deposit_tokens(&weth_agent, &user2, DEFAULT_TOKEN_BALANCE / 10);

        // Execute both agents
        test_framework::advance_time_by_hours(&admin, 3);

        let apt_response = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT, 10000000000);
        dca_sell_agent::execute_dca_sell(&apt_agent, &keeper, apt_response);

        let weth_response = test_framework::mock_successful_swap(DEFAULT_SELL_AMOUNT / 10, 30000000000);
        dca_sell_agent::execute_dca_sell(&weth_agent, &keeper, weth_response);

        // Verify independent execution
        assert!(dca_sell_agent::get_execution_count(&apt_agent) == 1, 1);
        assert!(dca_sell_agent::get_execution_count(&weth_agent) == 1, 2);
        assert!(dca_sell_agent::get_total_usdt_received(&apt_agent) == 10000000000, 3);
        assert!(dca_sell_agent::get_total_usdt_received(&weth_agent) == 30000000000, 4);
    }
}
