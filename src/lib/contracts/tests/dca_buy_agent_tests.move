/// DCA Buy Agent Contract Unit Tests
///
/// Comprehensive test suite for the dca_buy_agent module covering:
/// - Agent creation with various timing configurations
/// - DCA execution logic and timing validation
/// - DEX integration and swap functionality
/// - Token balance management and validation
/// - Edge cases with minimum/maximum values
/// - Error conditions and failure scenarios
/// - Integration with base agent functionality
///
/// Target: 95%+ code coverage

module recadence::dca_buy_agent_tests {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::string;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::{Self, Object};

    use recadence::base_agent::{Self, BaseAgent};
    use recadence::dca_buy_agent;
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
    const WETH_TOKEN_ADDR: address = @0x1234; // Mock WETH address
    const WBTC_TOKEN_ADDR: address = @0x5678; // Mock WBTC address

    // Test amounts
    const DEFAULT_BUY_AMOUNT: u64 = 50000000; // 50 USDT
    const DEFAULT_USDT_BALANCE: u64 = 1000000000; // 1000 USDT
    const MINIMUM_BUY_AMOUNT: u64 = 1000000; // 1 USDT
    const MAXIMUM_BUY_AMOUNT: u64 = 10000000000; // 10,000 USDT

    // Timing constants
    const TIMING_UNIT_MINUTES: u8 = 0;
    const TIMING_UNIT_HOURS: u8 = 1;
    const TIMING_UNIT_WEEKS: u8 = 2;
    const TIMING_UNIT_MONTHS: u8 = 3;

    // ================================================================================================
    // Setup and Initialization Tests
    // ================================================================================================

    #[test]
    /// Test DCA Buy Agent creation with valid parameters
    fun test_create_dca_buy_agent_success() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup test environment
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Get test data
        let (name, buy_amount, timing_unit, timing_value, stop_date) =
            test_framework::generate_dca_buy_test_data();

        // Create DCA Buy Agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            name,
            APT_TOKEN_ADDR, // Target APT
            buy_amount,
            timing_unit,
            timing_value,
            stop_date
        );

        // Verify agent properties
        assert!(dca_buy_agent::get_agent_id(&agent) == 1, 1);
        assert!(dca_buy_agent::get_creator(&agent) == TEST_USER1_ADDR, 2);
        assert!(dca_buy_agent::get_target_token_address(&agent) == APT_TOKEN_ADDR, 3);
        assert!(dca_buy_agent::get_buy_amount_usdt(&agent) == buy_amount, 4);
        assert!(dca_buy_agent::get_timing_unit(&agent) == timing_unit, 5);
        assert!(dca_buy_agent::get_timing_value(&agent) == timing_value, 6);
        assert!(dca_buy_agent::is_active(&agent), 7);

        // Verify initial state
        assert!(dca_buy_agent::get_total_purchased(&agent) == 0, 8);
        assert!(dca_buy_agent::get_total_usdt_spent(&agent) == 0, 9);
        assert!(dca_buy_agent::get_execution_count(&agent) == 0, 10);
    }

    #[test]
    /// Test DCA Buy Agent creation with different timing units
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

            let name = b"DCA Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));

            let agent = dca_buy_agent::create_dca_buy_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_BUY_AMOUNT,
                unit,
                value,
                option::none()
            );

            assert!(dca_buy_agent::get_timing_unit(&agent) == unit, 100 + i);
            assert!(dca_buy_agent::get_timing_value(&agent) == value, 200 + i);

            i = i + 1;
        };
    }

    #[test]
    /// Test DCA Buy Agent creation with different target tokens
    fun test_create_agents_different_target_tokens() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Test different target tokens
        let target_tokens = vector[APT_TOKEN_ADDR, WETH_TOKEN_ADDR, WBTC_TOKEN_ADDR];
        let token_names = vector[b"APT Agent", b"WETH Agent", b"WBTC Agent"];

        let i = 0;
        while (i < vector::length(&target_tokens)) {
            let target_token = *vector::borrow(&target_tokens, i);
            let name = *vector::borrow(&token_names, i);

            let agent = dca_buy_agent::create_dca_buy_agent(
                &user1,
                name,
                target_token,
                DEFAULT_BUY_AMOUNT,
                TIMING_UNIT_HOURS,
                24,
                option::none()
            );

            assert!(dca_buy_agent::get_target_token_address(&agent) == target_token, 100 + i);

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
        let _agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Invalid Timing Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_MINUTES,
            10, // Below minimum
            option::none()
        );
    }

    #[test]
    #[expected_failure(abort_code = 8, location = Self)]
    /// Test invalid timing configuration - hours out of range
    fun test_invalid_timing_hours_too_high() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Try to create agent with invalid timing (24 hours, above maximum 12)
        let _agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Invalid Timing Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            24, // Above maximum
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

            let agent = dca_buy_agent::create_dca_buy_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_BUY_AMOUNT,
                unit,
                value,
                option::none()
            );

            assert!(dca_buy_agent::get_timing_unit(&agent) == unit, 100 + i);
            assert!(dca_buy_agent::get_timing_value(&agent) == value, 200 + i);

            i = i + 1;
        };
    }

    // ================================================================================================
    // DCA Execution Tests
    // ================================================================================================

    #[test]
    /// Test successful DCA execution
    fun test_successful_dca_execution() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &keeper);

        // Create DCA agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Test DCA Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1, // Every hour
            option::none()
        );

        // Fund the agent
        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);

        // Mock successful DEX response
        let mock_response = test_framework::mock_successful_swap(
            DEFAULT_BUY_AMOUNT,
            5000000000 // 50 APT tokens received
        );

        // Advance time to make execution ready
        test_framework::advance_time_by_hours(&admin, 2);

        // Execute DCA
        dca_buy_agent::execute_dca(&agent, &keeper, mock_response);

        // Verify execution results
        assert!(dca_buy_agent::get_execution_count(&agent) == 1, 1);
        assert!(dca_buy_agent::get_total_usdt_spent(&agent) == DEFAULT_BUY_AMOUNT, 2);
        assert!(dca_buy_agent::get_total_purchased(&agent) == 5000000000, 3);
        assert!(dca_buy_agent::get_remaining_usdt(&agent) == DEFAULT_USDT_BALANCE - DEFAULT_BUY_AMOUNT, 4);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = Self)] // E_NOT_TIME_FOR_EXECUTION
    /// Test DCA execution before timing interval
    fun test_dca_execution_too_early() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create DCA agent with 24-hour interval
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Test DCA Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            24,
            option::none()
        );

        // Fund the agent
        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);

        // Try to execute immediately (should fail)
        let mock_response = test_framework::mock_successful_swap(DEFAULT_BUY_AMOUNT, 5000000000);
        dca_buy_agent::execute_dca(&agent, &keeper, mock_response);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)] // E_INSUFFICIENT_USDT_BALANCE
    /// Test DCA execution with insufficient USDT balance
    fun test_dca_execution_insufficient_balance() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create DCA agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Test DCA Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Fund agent with insufficient amount
        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_BUY_AMOUNT / 2);

        // Advance time
        test_framework::advance_time_by_hours(&admin, 2);

        // Try to execute (should fail due to insufficient funds)
        let mock_response = test_framework::mock_successful_swap(DEFAULT_BUY_AMOUNT, 5000000000);
        dca_buy_agent::execute_dca(&agent, &keeper, mock_response);
    }

    #[test]
    /// Test multiple DCA executions over time
    fun test_multiple_dca_executions() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create DCA agent with 1-hour intervals
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Multi Execution Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Fund agent for multiple executions
        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_BUY_AMOUNT * 5);

        let total_purchased = 0u64;
        let total_spent = 0u64;

        // Execute 3 times
        let i = 0;
        while (i < 3) {
            // Advance time
            test_framework::advance_time_by_hours(&admin, 1);

            // Mock different amounts received each time
            let tokens_received = 1000000000 * (i + 1); // 10, 20, 30 APT
            let mock_response = test_framework::mock_successful_swap(
                DEFAULT_BUY_AMOUNT,
                tokens_received
            );

            // Execute DCA
            dca_buy_agent::execute_dca(&agent, &keeper, mock_response);

            total_purchased = total_purchased + tokens_received;
            total_spent = total_spent + DEFAULT_BUY_AMOUNT;

            // Verify cumulative totals
            assert!(dca_buy_agent::get_execution_count(&agent) == i + 1, 100 + i);
            assert!(dca_buy_agent::get_total_purchased(&agent) == total_purchased, 200 + i);
            assert!(dca_buy_agent::get_total_usdt_spent(&agent) == total_spent, 300 + i);

            i = i + 1;
        };
    }

    // ================================================================================================
    // Agent State Management Tests
    // ================================================================================================

    #[test]
    /// Test pausing and resuming DCA agent
    fun test_pause_resume_dca_agent() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create DCA agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Pause Test Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Verify initial active state
        assert!(dca_buy_agent::is_active(&agent), 1);

        // Pause agent
        dca_buy_agent::pause_agent(&agent, &user1);
        assert!(!dca_buy_agent::is_active(&agent), 2);
        assert!(dca_buy_agent::is_paused(&agent), 3);

        // Resume agent
        dca_buy_agent::resume_agent(&agent, &user1);
        assert!(dca_buy_agent::is_active(&agent), 4);
        assert!(!dca_buy_agent::is_paused(&agent), 5);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = Self)] // E_AGENT_NOT_ACTIVE
    /// Test DCA execution on paused agent fails
    fun test_execute_dca_on_paused_agent() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create and pause agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Paused Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);
        dca_buy_agent::pause_agent(&agent, &user1);

        // Advance time and try to execute (should fail)
        test_framework::advance_time_by_hours(&admin, 2);
        let mock_response = test_framework::mock_successful_swap(DEFAULT_BUY_AMOUNT, 5000000000);
        dca_buy_agent::execute_dca(&agent, &keeper, mock_response);
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

        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Stop Date Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            stop_date
        );

        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);

        // Execute once before stop date
        test_framework::advance_time_by_hours(&admin, 1);
        let mock_response = test_framework::mock_successful_swap(DEFAULT_BUY_AMOUNT, 5000000000);
        dca_buy_agent::execute_dca(&agent, &keeper, mock_response);

        assert!(dca_buy_agent::get_execution_count(&agent) == 1, 1);

        // Advance past stop date
        test_framework::advance_time_by_hours(&admin, 2);

        // Execution should auto-pause the agent
        assert!(!dca_buy_agent::is_active(&agent), 2);
    }

    // ================================================================================================
    // Funding and Balance Tests
    // ================================================================================================

    #[test]
    /// Test agent funding functionality
    fun test_agent_funding() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Funding Test Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        // Initial balance should be 0
        assert!(dca_buy_agent::get_remaining_usdt(&agent) == 0, 1);

        // Fund agent
        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);
        assert!(dca_buy_agent::get_remaining_usdt(&agent) == DEFAULT_USDT_BALANCE, 2);

        // Fund again (should add to existing balance)
        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);
        assert!(dca_buy_agent::get_remaining_usdt(&agent) == DEFAULT_USDT_BALANCE * 2, 3);
    }

    #[test]
    /// Test withdrawing funds from agent
    fun test_withdraw_funds() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create and fund agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Withdraw Test Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);

        // Withdraw partial amount
        let withdraw_amount = DEFAULT_USDT_BALANCE / 2;
        dca_buy_agent::withdraw_funds(&agent, &user1, withdraw_amount);

        assert!(dca_buy_agent::get_remaining_usdt(&agent) == DEFAULT_USDT_BALANCE - withdraw_amount, 1);

        // Withdraw remaining amount
        dca_buy_agent::withdraw_funds(&agent, &user1, DEFAULT_USDT_BALANCE - withdraw_amount);
        assert!(dca_buy_agent::get_remaining_usdt(&agent) == 0, 2);
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
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Withdraw Fail Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);

        // Try to withdraw more than balance
        dca_buy_agent::withdraw_funds(&agent, &user1, DEFAULT_USDT_BALANCE + 1);
    }

    // ================================================================================================
    // Edge Cases and Error Conditions
    // ================================================================================================

    #[test]
    /// Test minimum buy amount
    fun test_minimum_buy_amount() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent with minimum buy amount
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Min Amount Agent",
            APT_TOKEN_ADDR,
            MINIMUM_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        assert!(dca_buy_agent::get_buy_amount_usdt(&agent) == MINIMUM_BUY_AMOUNT, 1);
    }

    #[test]
    /// Test maximum buy amount
    fun test_maximum_buy_amount() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent with maximum buy amount
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Max Amount Agent",
            APT_TOKEN_ADDR,
            MAXIMUM_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        assert!(dca_buy_agent::get_buy_amount_usdt(&agent) == MAXIMUM_BUY_AMOUNT, 1);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = Self)] // E_SWAP_FAILED
    /// Test DCA execution with failed DEX swap
    fun test_dca_execution_swap_failure() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create and fund agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Swap Fail Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_USDT_BALANCE);

        // Advance time
        test_framework::advance_time_by_hours(&admin, 2);

        // Execute with failed swap response
        let failed_response = test_framework::mock_failed_swap();
        dca_buy_agent::execute_dca(&agent, &keeper, failed_response);
    }

    #[test]
    /// Test average price calculation with multiple executions
    fun test_average_price_calculation() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent
        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Average Price Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT, // 50 USDT each time
            TIMING_UNIT_HOURS,
            1,
            option::none()
        );

        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_BUY_AMOUNT * 3);

        // First execution: 50 USDT -> 5 APT (10 USDT per APT)
        test_framework::advance_time_by_hours(&admin, 1);
        let response1 = test_framework::mock_successful_swap(DEFAULT_BUY_AMOUNT, 500000000); // 5 APT
        dca_buy_agent::execute_dca(&agent, &keeper, response1);

        // Second execution: 50 USDT -> 10 APT (5 USDT per APT)
        test_framework::advance_time_by_hours(&admin, 1);
        let response2 = test_framework::mock_successful_swap(DEFAULT_BUY_AMOUNT, 1000000000); // 10 APT
        dca_buy_agent::execute_dca(&agent, &keeper, response2);

        // Average should be: (50 + 50) USDT / (5 + 10) APT = 100/15 = 6.67 USDT per APT
        let average_price = dca_buy_agent::get_average_price(&agent);
        let expected_average = (DEFAULT_BUY_AMOUNT * 2 * 100000000) / (500000000 + 1000000000); // Scaled calculation

        assert!(average_price == expected_average, 1);
    }

    // ================================================================================================
    // Integration Tests
    // ================================================================================================

    #[test]
    /// Test comprehensive DCA agent lifecycle
    fun test_comprehensive_dca_lifecycle() {
        let (admin, user1, _user2, keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        // Create agent with stop date
        let current_time = test_framework::get_mock_timestamp(TEST_ADMIN_ADDR);
        let stop_date = option::some(current_time + 10800); // 3 hours from now

        let agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"Lifecycle Agent",
            WETH_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            TIMING_UNIT_HOURS,
            1,
            stop_date
        );

        // Fund agent
        dca_buy_agent::fund_agent(&agent, &user1, DEFAULT_BUY_AMOUNT * 5);

        // Execute twice before stop date
        test_framework::advance_time_by_hours(&admin, 1);
        let response1 = test_framework::mock_successful_swap(DEFAULT_BUY_AMOUNT, 166666667); // ~0.167 WETH
        dca_buy_agent::execute_dca(&agent, &keeper, response1);

        test_framework::advance_time_by_hours(&admin, 1);
        let response2 = test_framework::mock_successful_swap(DEFAULT_BUY_AMOUNT, 200000000); // 0.2 WETH
        dca_buy_agent::execute_dca(&agent, &keeper, response2);

        // Pause agent manually
        dca_buy_agent::pause_agent(&agent, &user1);

        // Advance past stop date
        test_framework::advance_time_by_hours(&admin, 2);

        // Resume and verify state
        dca_buy_agent::resume_agent(&agent, &user1);

        // Verify final state
        assert!(dca_buy_agent::get_execution_count(&agent) == 2, 1);
        assert!(dca_buy_agent::get_total_usdt_spent(&agent) == DEFAULT_BUY_AMOUNT * 2, 2);
        assert!(dca_buy_agent::get_total_purchased(&agent) == 166666667 + 200000000, 3);
        assert!(dca_buy_agent::get_remaining_usdt(&agent) == DEFAULT_BUY_AMOUNT * 3, 4);

        // Withdraw remaining funds
        dca_buy_agent::withdraw_funds(&agent, &user1, DEFAULT_BUY_AMOUNT * 3);
        assert!(dca_buy_agent::get_remaining_usdt(&agent) == 0, 5);

        // Delete agent
        dca_buy_agent::delete_agent(&agent, &user1);
        assert!(dca_buy_agent::get_state(&agent) == 3, 6); // DELETED state
    }
}
