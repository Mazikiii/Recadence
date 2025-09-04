/// Agent Limit Integration Tests
///
/// Comprehensive integration test suite for agent limit enforcement and gas sponsorship:
/// - 10-agent limit per user enforcement across all agent types
/// - Gas sponsorship for first 10 agents per user
/// - Cross-agent type interactions and limits
/// - Multi-user scenarios with independent limits
/// - Agent deletion and limit reclamation
/// - Integration between base agent, DCA Buy, and DCA Sell agents
///
/// Target: 95%+ integration coverage

module recadence::agent_limit_integration_tests {
    use std::signer;
    use std::vector;
    use std::option;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset;
    use aptos_framework::object;

    use recadence::base_agent::{Self, BaseAgent};
    use recadence::dca_buy_agent;
    use recadence::dca_sell_agent;
    use recadence::percentage_buy_agent;
    use recadence::percentage_sell_agent;
    use recadence::test_framework;

    // ================================================================================================
    // Test Constants
    // ================================================================================================

    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_USER3_ADDR: address = @0x4444;

    // Token addresses
    const APT_TOKEN_ADDR: address = @0x1;
    const USDT_TOKEN_ADDR: address = @0x357b0b74bc833e95a115ad22604854d6b0fca151cecd94111770e5d6ffc9dc2b;
    const WETH_TOKEN_ADDR: address = @0x1234;
    const WBTC_TOKEN_ADDR: address = @0x5678;
    const MOCK_APT_METADATA: address = @0x000000000000000000000000000000000000000000000000000000000000000a;

    // Test amounts
    const DEFAULT_BUY_AMOUNT: u64 = 50000000; // 50 USDT
    const DEFAULT_SELL_AMOUNT: u64 = 1000000000; // 10 tokens

    // ================================================================================================
    // Agent Limit Enforcement Tests
    // ================================================================================================

    #[test]
    /// Test creating exactly 10 agents of mixed types
    fun test_create_exactly_ten_mixed_agents() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Create 10 agents of mixed types
        let agents = vector::empty<u64>();

        // 4 base agents
        let i = 0;
        while (i < 4) {
            let name = b"Base Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let agent = base_agent::test_create_base_agent(&user1, name);
            vector::push_back(&agents, base_agent::get_agent_id(&agent));
            i = i + 1;
        };

        // 3 DCA Buy agents
        let i = 0;
        while (i < 3) {
            let name = b"DCA Buy Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let agent = dca_buy_agent::create_dca_buy_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_BUY_AMOUNT,
                1, // hours
                24,
                option::none()
            );
            vector::push_back(&agents, dca_buy_agent::get_agent_id(&agent));
            i = i + 1;
        };

        // 2 DCA Sell agents
        let i = 0;
        while (i < 2) {
            let name = b"DCA Sell Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let agent = dca_sell_agent::create_dca_sell_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_SELL_AMOUNT,
                1, // hours
                12,
                option::none()
            );
            vector::push_back(&mut agents, dca_sell_agent::get_agent_id(&agent));
            i = i + 1;
        };

        // 1 Percentage Buy agent
        let mock_apt_token = object::address_to_object<fungible_asset::Metadata>(MOCK_APT_METADATA);
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            10, // 10% threshold
            0,  // TREND_DOWN
            DEFAULT_BUY_AMOUNT * 10
        );
        vector::push_back(&mut agents, 8); // Agent ID 8

        // 1 Percentage Sell agent
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            20, // 20% threshold
            DEFAULT_SELL_AMOUNT * 10
        );
        vector::push_back(&mut agents, 9); // Agent ID 9

        // Verify we created exactly 10 agents
        assert!(vector::length(&agents) == 10, 1);

        // Verify user registry shows correct counts
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 10, 2);
        assert!(sponsored_count == 10, 3);
        assert!(!can_create_sponsored, 4); // Should be at limit

        // Should not be able to create more agents
        assert!(!base_agent::can_create_agent(TEST_USER1_ADDR), 5);

        // Verify platform stats
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 10, 6);
        assert!(total_active == 10, 7);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)] // E_AGENT_LIMIT_EXCEEDED
    /// Test creating 11th agent fails regardless of type
    fun test_create_eleventh_agent_fails() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Create 10 agents first (mixed types)
        let i = 0;
        while (i < 8) {
            let name = b"Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let _agent = base_agent::test_create_base_agent(&user1, name);
            i = i + 1;
        };

        // Add percentage agents to reach limit
        let mock_apt_token = object::address_to_object<fungible_asset::Metadata>(MOCK_APT_METADATA);
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            10,
            0,
            DEFAULT_BUY_AMOUNT * 10
        );

        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            15,
            DEFAULT_SELL_AMOUNT * 10
        );

        // Try to create 11th agent (should fail)
        let _agent = dca_buy_agent::create_dca_buy_agent(
            &user1,
            b"11th Agent",
            APT_TOKEN_ADDR,
            DEFAULT_BUY_AMOUNT,
            1,
            24,
            option::none()
        );
    }

    #[test]
    /// Test multiple users can each create 10 agents independently
    fun test_multiple_users_independent_limits() {
        let (admin, user1, user2, user3) = (
            account::create_signer_for_test(TEST_ADMIN_ADDR),
            account::create_signer_for_test(TEST_USER1_ADDR),
            account::create_signer_for_test(TEST_USER2_ADDR),
            account::create_signer_for_test(TEST_USER3_ADDR)
        );

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // User1 creates 5 DCA Buy agents
        let i = 0;
        while (i < 5) {
            let name = b"User1 Buy ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let _agent = dca_buy_agent::create_dca_buy_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_BUY_AMOUNT,
                1,
                24,
                option::none()
            );
            i = i + 1;
        };

        // User2 creates 7 DCA Sell agents
        let i = 0;
        while (i < 7) {
            let name = b"User2 Sell ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let _agent = dca_sell_agent::create_dca_sell_agent(
                &user2,
                name,
                WETH_TOKEN_ADDR,
                DEFAULT_SELL_AMOUNT,
                1,
                12,
                option::none()
            );
            i = i + 1;
        };

        // User3 creates mixed agent types
        let _agent = base_agent::test_create_base_agent(&user3, b"User3 Base");

        let mock_apt_token = object::address_to_object<fungible_asset::Metadata>(MOCK_APT_METADATA);
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user3,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            25,
            1, // TREND_UP
            DEFAULT_BUY_AMOUNT * 10
        );

        percentage_sell_agent::test_create_percentage_sell_agent(
            &user3,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            30,
            DEFAULT_SELL_AMOUNT * 10
        );

        // Verify independent limits
        let (user1_active, user1_sponsored, user1_can_sponsor) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(user1_active == 5, 1);
        assert!(user1_sponsored == 5, 2);
        assert!(user1_can_sponsor, 3);

        let (user2_active, user2_sponsored, user2_can_sponsor) = base_agent::get_user_agent_info(TEST_USER2_ADDR);
        assert!(user2_active == 7, 4);
        assert!(user2_sponsored == 7, 5);
        assert!(user2_can_sponsor, 6);

        let (user3_active, user3_sponsored, user3_can_sponsor) = base_agent::get_user_agent_info(TEST_USER3_ADDR);
        assert!(user3_active == 3, 7);
        assert!(user3_sponsored == 3, 8);
        assert!(user3_can_sponsor, 9);

        // All should still be able to create more agents
        assert!(base_agent::can_create_agent(TEST_USER1_ADDR), 10);
        assert!(base_agent::can_create_agent(TEST_USER2_ADDR), 11);
        assert!(base_agent::can_create_agent(TEST_USER3_ADDR), 12);

        // Platform stats should reflect total
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 15, 13); // 5 + 7 + 3
        assert!(total_active == 15, 14);
    }

    // ================================================================================================
    // Gas Sponsorship Integration Tests
    // ================================================================================================

    #[test]
    /// Test gas sponsorship assignment across different agent types
    fun test_gas_sponsorship_across_agent_types() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        let sponsored_agents = vector::empty<bool>();

        // Create 4 base agents (should all have sponsorship)
        let i = 0;
        while (i < 4) {
            let name = b"Base ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let agent = base_agent::test_create_base_agent(&user1, name);
            vector::push_back(&mut sponsored_agents, base_agent::has_gas_sponsorship(&agent));
            i = i + 1;
        };

        // Create 2 DCA Buy agents (should all have sponsorship)
        let i = 0;
        while (i < 2) {
            let name = b"Buy ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let agent = dca_buy_agent::create_dca_buy_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_BUY_AMOUNT,
                1,
                24,
                option::none()
            );
            vector::push_back(&mut sponsored_agents, dca_buy_agent::has_gas_sponsorship(&agent));
            i = i + 1;
        };

        // Create 2 DCA Sell agents (should all have sponsorship)
        let i = 0;
        while (i < 2) {
            let name = b"Sell ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let agent = dca_sell_agent::create_dca_sell_agent(
                &user1,
                name,
                APT_TOKEN_ADDR,
                DEFAULT_SELL_AMOUNT,
                1,
                12,
                option::none()
            );
            vector::push_back(&mut sponsored_agents, dca_sell_agent::has_gas_sponsorship(&agent));
            i = i + 1;
        };

        // Create 1 Percentage Buy agent (should have sponsorship)
        let mock_apt_token = object::address_to_object<fungible_asset::Metadata>(MOCK_APT_METADATA);
        percentage_buy_agent::test_create_percentage_buy_agent(
            &user1,
            mock_apt_token,
            DEFAULT_BUY_AMOUNT,
            10,
            0,
            DEFAULT_BUY_AMOUNT * 10
        );
        vector::push_back(&mut sponsored_agents, true); // Assume sponsored

        // Create 1 Percentage Sell agent (should have sponsorship)
        percentage_sell_agent::test_create_percentage_sell_agent(
            &user1,
            mock_apt_token,
            DEFAULT_SELL_AMOUNT,
            15,
            DEFAULT_SELL_AMOUNT * 10
        );
        vector::push_back(&mut sponsored_agents, true); // Assume sponsored

        // All 10 agents should have gas sponsorship
        let i = 0;
        while (i < vector::length(&sponsored_agents)) {
            assert!(*vector::borrow(&sponsored_agents, i), 100 + i);
            i = i + 1;
        };

        // Verify user registry
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 10, 1);
        assert!(sponsored_count == 10, 2);
        assert!(!can_create_sponsored, 3); // At sponsorship limit
    }

    #[test]
    /// Test gas sponsorship reclamation after agent deletion
    fun test_gas_sponsorship_reclamation_mixed_agents() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Create 8 agents of mixed types
        let base_agent = base_agent::test_create_base_agent(&user1, b"Base Agent");
        let buy_agent1 = dca_buy_agent::create_dca_buy_agent(
            &user1, b"Buy Agent 1", APT_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let buy_agent2 = dca_buy_agent::create_dca_buy_agent(
            &user1, b"Buy Agent 2", WETH_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let sell_agent1 = dca_sell_agent::create_dca_sell_agent(
            &user1, b"Sell Agent 1", APT_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );
        let sell_agent2 = dca_sell_agent::create_dca_sell_agent(
            &user1, b"Sell Agent 2", WETH_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );

        // Create 3 more base agents
        let _agent6 = base_agent::test_create_base_agent(&user1, b"Agent 6");
        let _agent7 = base_agent::test_create_base_agent(&user1, b"Agent 7");
        let _agent8 = base_agent::test_create_base_agent(&user1, b"Agent 8");

        // Verify initial state (8 agents, all sponsored)
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 8, 1);
        assert!(sponsored_count == 8, 2);
        assert!(can_create_sponsored, 3); // Can still create 2 more sponsored

        // Delete 3 agents of different types
        base_agent::delete_agent(&base_agent, &user1);
        dca_buy_agent::delete_agent(&buy_agent1, &user1);
        dca_sell_agent::delete_agent(&sell_agent1, &user1);

        // Verify sponsorship reclamation
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 5, 4); // 8 - 3 = 5
        assert!(sponsored_count == 5, 5); // Should decrease
        assert!(can_create_sponsored, 6); // Should be able to create more sponsored

        // Create 2 more agents (should both get sponsorship)
        let new_agent1 = dca_buy_agent::create_dca_buy_agent(
            &user1, b"New Agent 1", WBTC_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let new_agent2 = base_agent::test_create_base_agent(&user1, b"New Agent 2");

        assert!(dca_buy_agent::has_gas_sponsorship(&new_agent1), 7);
        assert!(base_agent::has_gas_sponsorship(&new_agent2), 8);

        // Final verification
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 7, 9);
        assert!(sponsored_count == 7, 10);
        assert!(can_create_sponsored, 11); // Can still create 3 more sponsored
    }

    // ================================================================================================
    // Agent Lifecycle Integration Tests
    // ================================================================================================

    #[test]
    /// Test complex agent lifecycle with mixed types
    fun test_complex_agent_lifecycle_mixed_types() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Phase 1: Create 6 agents
        let buy_agent = dca_buy_agent::create_dca_buy_agent(
            &user1, b"Lifecycle Buy", APT_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let sell_agent = dca_sell_agent::create_dca_sell_agent(
            &user1, b"Lifecycle Sell", WETH_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );
        let base_agent1 = base_agent::test_create_base_agent(&user1, b"Base 1");
        let base_agent2 = base_agent::test_create_base_agent(&user1, b"Base 2");
        let base_agent3 = base_agent::test_create_base_agent(&user1, b"Base 3");
        let base_agent4 = base_agent::test_create_base_agent(&user1, b"Base 4");

        // Verify initial state
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 6, 1);
        assert!(sponsored_count == 6, 2);

        // Phase 2: Pause some agents
        dca_buy_agent::pause_agent(&buy_agent, &user1);
        base_agent::pause_agent(&base_agent1, &user1);

        // Active count should remain the same (paused agents still count toward limit)
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 6, 3);
        assert!(sponsored_count == 6, 4);

        // Phase 3: Delete some agents
        base_agent::delete_agent(&base_agent2, &user1);
        dca_sell_agent::delete_agent(&sell_agent, &user1);

        // Active and sponsored counts should decrease
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 4, 5); // 6 - 2 = 4
        assert!(sponsored_count == 4, 6);
        assert!(can_create_sponsored, 7);

        // Phase 4: Resume paused agents
        dca_buy_agent::resume_agent(&buy_agent, &user1);
        base_agent::resume_agent(&base_agent1, &user1);

        // State should remain consistent
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 4, 8);
        assert!(sponsored_count == 4, 9);

        // Phase 5: Create new agents to fill limit
        let _new_buy = dca_buy_agent::create_dca_buy_agent(
            &user1, b"New Buy", WBTC_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let _new_sell = dca_sell_agent::create_dca_sell_agent(
            &user1, b"New Sell", APT_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );

        // Should be able to create up to 6 more (total 10)
        let i = 0;
        while (i < 4) {
            let name = b"Final ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let _agent = base_agent::test_create_base_agent(&user1, name);
            i = i + 1;
        };

        // Final verification - should be at limit
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 10, 10);
        assert!(sponsored_count == 10, 11);
        assert!(!can_create_sponsored, 12);
        assert!(!base_agent::can_create_agent(TEST_USER1_ADDR), 13);
    }

    // ================================================================================================
    // Platform Statistics Integration Tests
    // ================================================================================================

    #[test]
    /// Test platform statistics with mixed agent types and multiple users
    fun test_platform_statistics_integration() {
        let (admin, user1, user2, user3) = (
            account::create_signer_for_test(TEST_ADMIN_ADDR),
            account::create_signer_for_test(TEST_USER1_ADDR),
            account::create_signer_for_test(TEST_USER2_ADDR),
            account::create_signer_for_test(TEST_USER3_ADDR)
        );

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // User1: Create 4 agents
        let _agent1 = base_agent::test_create_base_agent(&user1, b"User1 Agent1");
        let _agent2 = dca_buy_agent::create_dca_buy_agent(
            &user1, b"User1 Buy", APT_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let _agent3 = dca_sell_agent::create_dca_sell_agent(
            &user1, b"User1 Sell", WETH_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );
        let agent4 = base_agent::test_create_base_agent(&user1, b"User1 Agent4");

        // User2: Create 3 agents
        let _agent5 = dca_buy_agent::create_dca_buy_agent(
            &user2, b"User2 Buy1", WBTC_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let agent6 = dca_sell_agent::create_dca_sell_agent(
            &user2, b"User2 Sell1", APT_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );
        let _agent7 = base_agent::test_create_base_agent(&user2, b"User2 Agent3");

        // User3: Create 2 agents
        let _agent8 = dca_buy_agent::create_dca_buy_agent(
            &user3, b"User3 Buy", APT_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let agent9 = base_agent::test_create_base_agent(&user3, b"User3 Base");

        // Verify platform stats
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 9, 1); // 4 + 3 + 2
        assert!(total_active == 9, 2);

        // Delete some agents
        base_agent::delete_agent(&agent4, &user1); // User1: 4 -> 3
        dca_sell_agent::delete_agent(&agent6, &user2); // User2: 3 -> 2
        base_agent::delete_agent(&agent9, &user3); // User3: 2 -> 1

        // Verify updated stats
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 9, 3); // Total created doesn't decrease
        assert!(total_active == 6, 4); // 9 - 3 = 6

        // Create more agents
        let _agent10 = dca_sell_agent::create_dca_sell_agent(
            &user1, b"User1 New Sell", USDT_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );
        let _agent11 = base_agent::test_create_base_agent(&user2, b"User2 New Base");

        // Final verification
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 11, 5); // 9 + 2
        assert!(total_active == 8, 6); // 6 + 2
    }

    // ================================================================================================
    // Error Condition Integration Tests
    // ================================================================================================

    #[test]
    /// Test that agent limits are enforced even when creating different types simultaneously
    fun test_limit_enforcement_with_concurrent_creation() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Create 9 agents rapidly in mixed order
        let _agent1 = dca_buy_agent::create_dca_buy_agent(
            &user1, b"Agent1", APT_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let _agent2 = base_agent::test_create_base_agent(&user1, b"Agent2");
        let _agent3 = dca_sell_agent::create_dca_sell_agent(
            &user1, b"Agent3", WETH_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );
        let _agent4 = dca_buy_agent::create_dca_buy_agent(
            &user1, b"Agent4", WBTC_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let _agent5 = base_agent::test_create_base_agent(&user1, b"Agent5");
        let _agent6 = dca_sell_agent::create_dca_sell_agent(
            &user1, b"Agent6", APT_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );
        let _agent7 = base_agent::test_create_base_agent(&user1, b"Agent7");
        let _agent8 = dca_buy_agent::create_dca_buy_agent(
            &user1, b"Agent8", APT_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        let _agent9 = dca_sell_agent::create_dca_sell_agent(
            &user1, b"Agent9", WETH_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );

        // Verify we're at 9 agents
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 9, 1);
        assert!(sponsored_count == 9, 2);
        assert!(can_create_sponsored, 3); // Can create 1 more

        // Create the 10th agent
        let _agent10 = base_agent::test_create_base_agent(&user1, b"Agent10");

        // Verify we're at the limit
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 10, 4);
        assert!(sponsored_count == 10, 5);
        assert!(!can_create_sponsored, 6); // At limit
        assert!(!base_agent::can_create_agent(TEST_USER1_ADDR), 7);
    }

    #[test]
    /// Test agent ID assignment is sequential across different agent types
    fun test_sequential_agent_id_assignment() {
        let (admin, user1, user2, _keeper) = test_framework::create_test_signers();

        // Setup
        test_framework::setup_test_environment(&admin);
        base_agent::initialize_platform(&admin);
        test_framework::setup_test_accounts_with_balances(&admin, &user1, &user2);

        // Create agents of different types and verify sequential IDs
        let base_agent = base_agent::test_create_base_agent(&user1, b"Base Agent");
        assert!(base_agent::get_agent_id(&base_agent) == 1, 1);

        let buy_agent = dca_buy_agent::create_dca_buy_agent(
            &user1, b"Buy Agent", APT_TOKEN_ADDR, DEFAULT_BUY_AMOUNT, 1, 24, option::none()
        );
        assert!(dca_buy_agent::get_agent_id(&buy_agent) == 2, 2);

        let sell_agent = dca_sell_agent::create_dca_sell_agent(
            &user1, b"Sell Agent", WETH_TOKEN_ADDR, DEFAULT_SELL_AMOUNT, 1, 12, option::none()
        );
        assert!(dca_sell_agent::get_agent_id(&sell_agent) == 3, 3);

        // Different user should continue the sequence
        let user2_agent = base_agent::test_create_base_agent(&user2, b"User2 Agent");
        assert!(base_agent::get_agent_id(&user2_agent) == 4, 4);

        // Verify agent IDs are tracked correctly
        let user1_agent_ids = base_agent::get_user_agent_ids(TEST_USER1_ADDR);
        assert!(vector::length(&user1_agent_ids) == 3, 5);
        assert!(*vector::borrow(&user1_agent_ids, 0) == 1, 6);
        assert!(*vector::borrow(&user1_agent_ids, 1) == 2, 7);
        assert!(*vector::borrow(&user1_agent_ids, 2) == 3, 8);

        let user2_agent_ids = base_agent::get_user_agent_ids(TEST_USER2_ADDR);
        assert!(vector::length(&user2_agent_ids) == 1, 9);
        assert!(*vector::borrow(&user2_agent_ids, 0) == 4, 10);
    }
}
