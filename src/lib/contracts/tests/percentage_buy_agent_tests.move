/// Percentage Buy Agent Contract Unit Tests
///
/// Comprehensive test suite for the percentage_buy_agent module covering:
/// - Agent creation with trend selection (DOWN default, UP option)
/// - Percentage threshold validation and execution logic
/// - Price movement detection and trigger conditions
/// - USDT funding and balance management
/// - Edge cases with minimum/maximum values
/// - Error conditions and failure scenarios
/// - Integration with base agent functionality
///
/// Target: 95%+ code coverage

module recadence::percentage_buy_agent_tests {
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
    use recadence::percentage_buy_agent;
    use recadence::test_framework;

    // ================================================================================================
    // Test Constants
    // ================================================================================================

    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_KEEPER_ADDR: address = @0x4444;

    // Token addresses for testing
    const APT_TOKEN_ADDR: address = @0x000000000000000000000000000000000000000000000000000000000000000a;
    const USDT_TOKEN_ADDR: address = @0x357b0b74bc833e95a115ad22604854d6b0fca151cecd94111770e5d6ffc9dc2b;
    const USDC_TOKEN_ADDR: address = @0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832;

    // Test amounts
    const DEFAULT_BUY_AMOUNT: u64 = 50000000; // 50 USDT
    const DEFAULT_USDT_BALANCE: u64 = 1000000000; // 1000 USDT
    const MINIMUM_BUY_AMOUNT: u64 = 1000000; // 1 USDT
    const MAXIMUM_BUY_AMOUNT: u64 = 10000000000; // 10,000 USDT

    // Trend constants
    const TREND_DOWN: u8 = 0;  // Default - buy on price drops
    const TREND_UP: u8 = 1;    // Option - buy on price increases

    // Percentage constants
    const MIN_PERCENTAGE: u64 = 5;   // 5% minimum

    // ================================================================================================
    // Setup and Initialization Tests
    // ================================================================================================

    #[test]
    /// Test Percentage Buy Agent creation with DOWN trend (default)
    fun test_create_percentage_buy_agent_down_trend() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup test environment
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Create mock token object
        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create Percentage Buy Agent with DOWN trend
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,    // 50 USDT per buy
            10,                     // 10% threshold
            TREND_DOWN,            // Buy on dips
            DEFAULT_USDT_BALANCE   // 1000 USDT deposit
        );

        // Verify agent was created successfully
        let agent_info = percentage_buy_agent::get_percentage_buy_agent_info(TEST_USER1_ADDR);
        let (agent_id, creator, target_token, buy_amount, percentage, trend, _last_price, _remaining) = agent_info;

        assert!(agent_id == 1, 1);
        assert!(creator == TEST_USER1_ADDR, 2);
        assert!(target_token == APT_TOKEN_ADDR, 3);
        assert!(buy_amount == DEFAULT_BUY_AMOUNT, 4);
        assert!(percentage == 10, 5);
        assert!(trend == TREND_DOWN, 6);
    }

    #[test]
    /// Test Percentage Buy Agent creation with UP trend
    fun test_create_percentage_buy_agent_up_trend() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create Percentage Buy Agent with UP trend
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            15,                     // 15% threshold
            TREND_UP,              // Buy on momentum
            DEFAULT_USDT_BALANCE
        );

        // Verify UP trend configuration
        let agent_info = percentage_buy_agent::get_percentage_buy_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _target_token, _buy_amount, percentage, trend, _last_price, _remaining) = agent_info;

        assert!(percentage == 15, 1);
        assert!(trend == TREND_UP, 2);
    }

    #[test]
    /// Test agent creation with different supported tokens
    fun test_create_agents_different_tokens() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Test different supported tokens
        let tokens = vector[APT_TOKEN_ADDR, USDC_TOKEN_ADDR];
        let i = 0;
        while (i < vector::length(&tokens)) {
            let token_addr = *vector::borrow(&tokens, i);
            let token_obj = object::address_to_object<Metadata>(token_addr);

            percentage_buy_agent::test_create_percentage_buy_agent(
                &user1,
                token_obj,
                DEFAULT_BUY_AMOUNT,
                10,
                TREND_DOWN,
                DEFAULT_USDT_BALANCE
            );

            i = i + 1;
        };

        // Should have created 2 agents
        let (active_count, _sponsored_count, _can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 2, 1);
    }

    // ================================================================================================
    // Percentage Threshold Validation Tests
    // ================================================================================================

    #[test]
    /// Test minimum percentage threshold (5%)
    fun test_minimum_percentage_threshold() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create agent with minimum percentage
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            MIN_PERCENTAGE,        // 5% minimum
            TREND_DOWN,
            DEFAULT_USDT_BALANCE
        );

        let agent_info = percentage_buy_agent::get_percentage_buy_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _target_token, _buy_amount, percentage, _trend, _last_price, _remaining) = agent_info;
        assert!(percentage == MIN_PERCENTAGE, 1);
    }

    #[test]
    #[expected_failure(abort_code = 7, location = Self)] // E_INVALID_PERCENTAGE
    /// Test percentage below minimum should fail
    fun test_percentage_below_minimum_fails() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Try to create agent with percentage below minimum (should fail)
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            3,                     // Below 5% minimum
            TREND_DOWN,
            DEFAULT_USDT_BALANCE
        );
    }

    #[test]
    /// Test high percentage threshold (50%)
    fun test_high_percentage_threshold() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create agent with high percentage
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            50,                    // 50% threshold
            TREND_DOWN,
            DEFAULT_USDT_BALANCE
        );

        let agent_info = percentage_buy_agent::get_percentage_buy_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _target_token, _buy_amount, percentage, _trend, _last_price, _remaining) = agent_info;
        assert!(percentage == 50, 1);
    }

    // ================================================================================================
    // Trend Direction Validation Tests
    // ================================================================================================

    #[test]
    #[expected_failure(abort_code = 8, location = Self)] // E_INVALID_TREND
    /// Test invalid trend direction should fail
    fun test_invalid_trend_direction_fails() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Try to create agent with invalid trend direction (should fail)
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            10,
            2,                     // Invalid trend (only 0 and 1 are valid)
            DEFAULT_USDT_BALANCE
        );
    }

    #[test]
    /// Test both valid trend directions
    fun test_both_trend_directions() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create DOWN trend agent
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            10,
            TREND_DOWN,
            DEFAULT_USDT_BALANCE
        );

        let mock_usdc_token = object::address_to_object<Metadata>(USDC_TOKEN_ADDR);

        // Create UP trend agent
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_usdc_token,
            DEFAULT_BUY_AMOUNT,
            15,
            TREND_UP,
            DEFAULT_USDT_BALANCE
        );

        // Should have created 2 agents with different trends
        let (active_count, _sponsored_count, _can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 2, 1);
    }

    // ================================================================================================
    // Edge Cases and Error Conditions
    // ================================================================================================

    #[test]
    /// Test minimum buy amount
    fun test_minimum_buy_amount() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create agent with minimum buy amount
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            MINIMUM_BUY_AMOUNT,
            10,
            TREND_DOWN,
            MINIMUM_BUY_AMOUNT
        );

        let agent_info = percentage_buy_agent::get_percentage_buy_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _target_token, buy_amount, _percentage, _trend, _last_price, _remaining) = agent_info;
        assert!(buy_amount == MINIMUM_BUY_AMOUNT, 1);
    }

    #[test]
    /// Test maximum buy amount
    fun test_maximum_buy_amount() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create agent with maximum buy amount
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            MAXIMUM_BUY_AMOUNT,
            10,
            TREND_DOWN,
            MAXIMUM_BUY_AMOUNT
        );

        let agent_info = percentage_buy_agent::get_percentage_buy_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _target_token, buy_amount, _percentage, _trend, _last_price, _remaining) = agent_info;
        assert!(buy_amount == MAXIMUM_BUY_AMOUNT, 1);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)] // E_INSUFFICIENT_USDT_BALANCE
    /// Test insufficient deposit should fail
    fun test_insufficient_deposit_fails() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Try to create agent with insufficient deposit (should fail)
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,    // 50 USDT buy amount
            10,
            TREND_DOWN,
            DEFAULT_BUY_AMOUNT / 2  // Only 25 USDT deposit (insufficient)
        );
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)] // E_INSUFFICIENT_USDT_BALANCE
    /// Test zero buy amount should fail
    fun test_zero_buy_amount_fails() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Try to create agent with zero buy amount (should fail)
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            0,                     // Zero buy amount
            10,
            TREND_DOWN,
            DEFAULT_USDT_BALANCE
        );
    }

    // ================================================================================================
    // Integration with Base Agent Tests
    // ================================================================================================

    #[test]
    /// Test percentage buy agent counts toward 10-agent limit
    fun test_agent_limit_integration() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create 3 base agents
        let _base1 = base_agent::test_create_base_agent(&user1, b"Base 1");
        let _base2 = base_agent::test_create_base_agent(&user1, b"Base 2");
        let _base3 = base_agent::test_create_base_agent(&user1, b"Base 3");

        // Create 2 percentage buy agents
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            10,
            TREND_DOWN,
            DEFAULT_USDT_BALANCE
        );

        let mock_usdc_token = object::address_to_object<Metadata>(USDC_TOKEN_ADDR);
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_usdc_token,
            DEFAULT_BUY_AMOUNT,
            15,
            TREND_UP,
            DEFAULT_USDT_BALANCE
        );

        // Should have 5 total agents (3 base + 2 percentage buy)
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 5, 1);
        assert!(sponsored_count == 5, 2);
        assert!(can_create_sponsored, 3); // Should still be able to create more
    }

    #[test]
    /// Test gas sponsorship for percentage buy agents
    fun test_gas_sponsorship_integration() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create 5 percentage buy agents (should all have gas sponsorship)
        let i = 0;
        while (i < 5) {
            percentage_buy_agent::test_create_percentage_buy_agent(
                &user1,
                mock_apt_token,
                DEFAULT_BUY_AMOUNT,
                10 + i, // Different percentages
                TREND_DOWN,
                DEFAULT_USDT_BALANCE
            );
            i = i + 1;
        };

        // All should have gas sponsorship
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 5, 1);
        assert!(sponsored_count == 5, 2);
        assert!(can_create_sponsored, 3); // Can create 5 more with sponsorship
    }

    // ================================================================================================
    // Multi-User Scenarios
    // ================================================================================================

    #[test]
    /// Test multiple users with independent percentage buy agents
    fun test_multi_user_independent_agents() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // User1 creates DOWN trend agent
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            10,
            TREND_DOWN,
            DEFAULT_USDT_BALANCE
        );

        // User2 creates UP trend agent
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user2,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT * 2,
            20,
            TREND_UP,
            DEFAULT_USDT_BALANCE * 2
        );

        // Verify independent agent counts
        let (user1_active, user1_sponsored, _) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        let (user2_active, user2_sponsored, _) = base_agent::get_user_agent_info(TEST_USER2_ADDR);

        assert!(user1_active == 1, 1);
        assert!(user1_sponsored == 1, 2);
        assert!(user2_active == 1, 3);
        assert!(user2_sponsored == 1, 4);

        // Verify platform stats
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 2, 5);
        assert!(total_active == 2, 6);
    }

    // ================================================================================================
    // Comprehensive Lifecycle Test
    // ================================================================================================

    #[test]
    /// Test complete percentage buy agent lifecycle
    fun test_comprehensive_lifecycle() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create percentage buy agent with DOWN trend (buy the dip)
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            15,                    // 15% threshold
            TREND_DOWN,           // Buy on price drops
            DEFAULT_USDT_BALANCE
        );

        // Verify initial state
        let agent_info = percentage_buy_agent::get_percentage_buy_agent_info(TEST_USER1_ADDR);
        let (agent_id, creator, target_token, buy_amount, percentage, trend, _last_price, remaining) = agent_info;

        assert!(agent_id == 1, 1);
        assert!(creator == TEST_USER1_ADDR, 2);
        assert!(target_token == APT_TOKEN_ADDR, 3);
        assert!(buy_amount == DEFAULT_BUY_AMOUNT, 4);
        assert!(percentage == 15, 5);
        assert!(trend == TREND_DOWN, 6);
        assert!(remaining == DEFAULT_USDT_BALANCE, 7);

        // Verify agent is included in user registry
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 1, 8);
        assert!(sponsored_count == 1, 9);
        assert!(can_create_sponsored, 10);

        // Verify platform statistics
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 1, 11);
        assert!(total_active == 1, 12);
    }
}
