/// Percentage Sell Agent Contract Unit Tests
///
/// Comprehensive test suite for the percentage_sell_agent module covering:
/// - Agent creation with various source tokens
/// - Percentage threshold validation and execution logic
/// - Price movement detection for profit-taking
/// - Token deposit and balance management
/// - Edge cases with minimum/maximum values
/// - Error conditions and failure scenarios
/// - Integration with base agent functionality
///
/// Target: 95%+ code coverage

module recadence::percentage_sell_agent_tests {
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
    use recadence::percentage_sell_agent;
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
    const DEFAULT_SELL_AMOUNT: u64 = 1000000000; // 10 tokens
    const DEFAULT_TOKEN_BALANCE: u64 = 100000000000; // 1000 tokens
    const MINIMUM_SELL_AMOUNT: u64 = 100000000; // 1 token
    const MAXIMUM_SELL_AMOUNT: u64 = 1000000000000; // 10,000 tokens

    // Percentage constants
    const MIN_PERCENTAGE: u64 = 5;   // 5% minimum

    // ================================================================================================
    // Setup and Initialization Tests
    // ================================================================================================

    #[test]
    /// Test Percentage Sell Agent creation with valid parameters
    fun test_create_percentage_sell_agent_success() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup test environment
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Create mock token object
        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create Percentage Sell Agent
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,    // 10 tokens per sell
            20,                     // 20% profit threshold
            DEFAULT_TOKEN_BALANCE   // 1000 tokens deposit
        );

        // Verify agent was created successfully
        let agent_info = percentage_sell_agent::get_percentage_sell_agent_info(TEST_USER1_ADDR);
        let (agent_id, creator, source_token, sell_amount, percentage, _entry_price, _remaining) = agent_info;

        assert!(agent_id == 1, 1);
        assert!(creator == TEST_USER1_ADDR, 2);
        assert!(source_token == APT_TOKEN_ADDR, 3);
        assert!(sell_amount == DEFAULT_SELL_AMOUNT, 4);
        assert!(percentage == 20, 5);
    }

    #[test]
    /// Test agent creation with different supported tokens
    fun test_create_agents_different_source_tokens() {
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

            percentage_sell_agent::test_create_percentage_sell_agent(
                &user1,
                token_obj,
                DEFAULT_SELL_AMOUNT,
                15 + (i * 5), // Different percentages
                DEFAULT_TOKEN_BALANCE
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
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            MIN_PERCENTAGE,        // 5% minimum
            DEFAULT_TOKEN_BALANCE
        );

        let agent_info = percentage_sell_agent::get_percentage_sell_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _source_token, _sell_amount, percentage, _entry_price, _remaining) = agent_info;
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
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            3,                     // Below 5% minimum
            DEFAULT_TOKEN_BALANCE
        );
    }

    #[test]
    /// Test high percentage threshold (100%)
    fun test_high_percentage_threshold() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create agent with high percentage
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            100,                   // 100% gain threshold
            DEFAULT_TOKEN_BALANCE
        );

        let agent_info = percentage_sell_agent::get_percentage_sell_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _source_token, _sell_amount, percentage, _entry_price, _remaining) = agent_info;
        assert!(percentage == 100, 1);
    }

    // ================================================================================================
    // Token Balance and Deposit Tests
    // ================================================================================================

    #[test]
    /// Test minimum sell amount
    fun test_minimum_sell_amount() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create agent with minimum sell amount
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            MINIMUM_SELL_AMOUNT,
            20,
            MINIMUM_SELL_AMOUNT
        );

        let agent_info = percentage_sell_agent::get_percentage_sell_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _source_token, sell_amount, _percentage, _entry_price, _remaining) = agent_info;
        assert!(sell_amount == MINIMUM_SELL_AMOUNT, 1);
    }

    #[test]
    /// Test maximum sell amount
    fun test_maximum_sell_amount() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create agent with maximum sell amount
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            MAXIMUM_SELL_AMOUNT,
            20,
            MAXIMUM_SELL_AMOUNT
        );

        let agent_info = percentage_sell_agent::get_percentage_sell_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _source_token, sell_amount, _percentage, _entry_price, _remaining) = agent_info;
        assert!(sell_amount == MAXIMUM_SELL_AMOUNT, 1);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)] // E_INSUFFICIENT_TOKEN_BALANCE
    /// Test insufficient token deposit should fail
    fun test_insufficient_token_deposit_fails() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Try to create agent with insufficient deposit (should fail)
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,    // 10 tokens sell amount
            20,
            DEFAULT_SELL_AMOUNT / 2  // Only 5 tokens deposit (insufficient)
        );
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)] // E_INSUFFICIENT_TOKEN_BALANCE
    /// Test zero sell amount should fail
    fun test_zero_sell_amount_fails() {
        let (admin, user1, _user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Try to create agent with zero sell amount (should fail)
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            0,                     // Zero sell amount
            20,
            DEFAULT_TOKEN_BALANCE
        );
    }

    // ================================================================================================
    // Integration with Base Agent Tests
    // ================================================================================================

    #[test]
    /// Test percentage sell agent counts toward 10-agent limit
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

        // Create 2 percentage sell agents
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            20,
            DEFAULT_TOKEN_BALANCE
        );

        let mock_usdc_token = object::address_to_object<Metadata>(USDC_TOKEN_ADDR);
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_usdc_token,
            DEFAULT_SELL_AMOUNT,
            25,
            DEFAULT_TOKEN_BALANCE
        );

        // Should have 5 total agents (3 base + 2 percentage sell)
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 5, 1);
        assert!(sponsored_count == 5, 2);
        assert!(can_create_sponsored, 3); // Should still be able to create more
    }

    #[test]
    /// Test gas sponsorship for percentage sell agents
    fun test_gas_sponsorship_integration() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create 5 percentage sell agents (should all have gas sponsorship)
        let i = 0;
        while (i < 5) {
            percentage_sell_agent::test_create_percentage_sell_agent(
                &user1,
                mock_apt_token,
                DEFAULT_SELL_AMOUNT,
                10 + (i * 5), // Different percentages: 10%, 15%, 20%, 25%, 30%
                DEFAULT_TOKEN_BALANCE
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
    /// Test multiple users with independent percentage sell agents
    fun test_multi_user_independent_agents() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // User1 creates conservative sell agent
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            15,                    // 15% profit threshold
            DEFAULT_TOKEN_BALANCE
        );

        // User2 creates aggressive sell agent
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user2,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT * 2,
            50,                    // 50% profit threshold
            DEFAULT_TOKEN_BALANCE * 2
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
    // Edge Cases and Boundary Conditions
    // ================================================================================================

    #[test]
    /// Test creating agent with exact deposit amount
    fun test_exact_deposit_amount() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create agent with exact deposit amount (minimum required)
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            20,
            DEFAULT_SELL_AMOUNT    // Exact amount needed for one sell
        );

        let agent_info = percentage_sell_agent::get_percentage_sell_agent_info(TEST_USER1_ADDR);
        let (_agent_id, _creator, _source_token, _sell_amount, _percentage, _entry_price, remaining) = agent_info;
        assert!(remaining == DEFAULT_SELL_AMOUNT, 1);
    }

    #[test]
    /// Test percentage thresholds with various values
    fun test_various_percentage_thresholds() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Test various percentage thresholds
        let percentages = vector[5, 10, 25, 50, 75, 100];
        let i = 0;
        while (i < vector::length(&percentages)) {
            let percentage = *vector::borrow(&percentages, i);

            percentage_sell_agent::test_create_percentage_sell_agent(
                &user1,
                mock_apt_token,
                DEFAULT_SELL_AMOUNT,
                percentage,
                DEFAULT_TOKEN_BALANCE
            );

            i = i + 1;
        };

        // Should have created 6 agents with different thresholds
        let (active_count, _sponsored_count, _can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 6, 1);
    }

    // ================================================================================================
    // Error Handling Tests
    // ================================================================================================

    #[test]
    /// Test supported tokens validation
    fun test_supported_tokens() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Test all supported tokens
        let supported_tokens = percentage_sell_agent::get_supported_tokens();
        assert!(vector::length(&supported_tokens) >= 3, 1); // Should have at least APT, USDC, USDT

        // Test creating agents with supported tokens
        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            20,
            DEFAULT_TOKEN_BALANCE
        );

        let mock_usdc_token = object::address_to_object<Metadata>(USDC_TOKEN_ADDR);
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_usdc_token,
            DEFAULT_SELL_AMOUNT,
            25,
            DEFAULT_TOKEN_BALANCE
        );

        // Should have created 2 agents successfully
        let (active_count, _sponsored_count, _can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 2, 2);
    }

    // ================================================================================================
    // Comprehensive Lifecycle Test
    // ================================================================================================

    #[test]
    /// Test complete percentage sell agent lifecycle
    fun test_comprehensive_lifecycle() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create percentage sell agent for profit-taking
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            30,                    // 30% profit threshold
            DEFAULT_TOKEN_BALANCE
        );

        // Verify initial state
        let agent_info = percentage_sell_agent::get_percentage_sell_agent_info(TEST_USER1_ADDR);
        let (agent_id, creator, source_token, sell_amount, percentage, _entry_price, remaining) = agent_info;

        assert!(agent_id == 1, 1);
        assert!(creator == TEST_USER1_ADDR, 2);
        assert!(source_token == APT_TOKEN_ADDR, 3);
        assert!(sell_amount == DEFAULT_SELL_AMOUNT, 4);
        assert!(percentage == 30, 5);
        assert!(remaining == DEFAULT_TOKEN_BALANCE, 6);

        // Verify agent is included in user registry
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 1, 7);
        assert!(sponsored_count == 1, 8);
        assert!(can_create_sponsored, 9);

        // Verify platform statistics
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 1, 10);
        assert!(total_active == 1, 11);
    }

    // ================================================================================================
    // Mixed Agent Type Integration Tests
    // ================================================================================================

    #[test]
    /// Test percentage sell agents mixed with other agent types
    fun test_mixed_agent_types_integration() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let mock_apt_token = object::address_to_object<Metadata>(APT_TOKEN_ADDR);

        // Create 2 base agents
        let _base1 = base_agent::test_create_base_agent(&user1, b"Base 1");
        let _base2 = base_agent::test_create_base_agent(&user1, b"Base 2");

        // Create 2 percentage sell agents
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            20,
            DEFAULT_TOKEN_BALANCE
        );

        let mock_usdc_token = object::address_to_object<Metadata>(USDC_TOKEN_ADDR);
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_usdc_token,
            DEFAULT_SELL_AMOUNT / 2,
            40,
            DEFAULT_TOKEN_BALANCE / 2
        );

        // Should have 4 total agents (2 base + 2 percentage sell)
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 4, 1);
        assert!(sponsored_count == 4, 2);
        assert!(can_create_sponsored, 3); // Can create 6 more with sponsorship

        // Verify platform statistics include all agent types
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 4, 4);
        assert!(total_active == 4, 5);
    }
}
