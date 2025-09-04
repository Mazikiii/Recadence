/// Base Agent Contract Unit Tests
///
/// Comprehensive test suite for the base_agent module covering:
/// - Agent creation and lifecycle management
/// - 10-agent limit enforcement
/// - Gas sponsorship tracking and limits
/// - State transitions (ACTIVE → PAUSED → DELETED)
/// - Creator-only access controls
/// - Edge cases and error conditions
/// - Integration with agent registry
///
/// Target: 95%+ code coverage

module recadence::base_agent_tests {
    use std::signer;
    use std::vector;
    use std::option;
    use aptos_framework::account;
    use aptos_framework::timestamp;

    use recadence::base_agent::{Self, BaseAgent};
    use recadence::test_framework;

    // ================================================================================================
    // Test Constants
    // ================================================================================================

    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_UNAUTHORIZED_ADDR: address = @0x9999;

    // ================================================================================================
    // Initialization Tests
    // ================================================================================================

    #[test]
    /// Test platform initialization by admin
    fun test_initialize_platform() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);

        // Initialize platform
        base_agent::initialize_platform(&admin);

        // Verify platform stats
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 0, 1);
        assert!(total_active == 0, 2);
    }

    #[test]
    /// Test multiple platform initialization attempts (should be idempotent)
    fun test_initialize_platform_multiple_times() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);

        // Initialize multiple times
        base_agent::initialize_platform(&admin);
        base_agent::initialize_platform(&admin);
        base_agent::initialize_platform(&admin);

        // Should still work correctly
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 0, 1);
        assert!(total_active == 0, 2);
    }

    // ================================================================================================
    // Agent Creation Tests
    // ================================================================================================

    #[test]
    /// Test successful agent creation
    fun test_create_agent_success() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // Create agent
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Verify agent properties
        assert!(base_agent::get_agent_id(&agent) == 1, 1);
        assert!(base_agent::get_creator(&agent) == TEST_USER1_ADDR, 2);
        assert!(base_agent::is_active(&agent), 3);
        assert!(!base_agent::is_paused(&agent), 4);
        assert!(base_agent::has_gas_sponsorship(&agent), 5);
        assert!(base_agent::get_total_transactions(&agent) == 0, 6);

        // Verify user registry
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 1, 7);
        assert!(sponsored_count == 1, 8);
        assert!(can_create_sponsored, 9);

        // Verify platform stats
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 1, 10);
        assert!(total_active == 1, 11);
    }

    #[test]
    /// Test creating multiple agents up to the limit
    fun test_create_multiple_agents_up_to_limit() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // Create 10 agents (the limit)
        let i = 0;
        while (i < 10) {
            let name = b"Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8)); // ASCII numbers
            let agent = base_agent::test_create_base_agent(&user, name);

            // Verify agent ID increments
            assert!(base_agent::get_agent_id(&agent) == (i + 1), 100 + i);
            // All first 10 agents should have gas sponsorship
            assert!(base_agent::has_gas_sponsorship(&agent), 200 + i);

            i = i + 1;
        };

        // Verify user registry after creating 10 agents
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 10, 12);
        assert!(sponsored_count == 10, 13);
        assert!(!can_create_sponsored, 14); // Should not be able to create more sponsored agents

        // Should not be able to create more agents
        assert!(!base_agent::can_create_agent(TEST_USER1_ADDR), 15);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)] // E_AGENT_LIMIT_EXCEEDED
    /// Test creating agent beyond 10-agent limit should fail
    fun test_create_agent_beyond_limit_fails() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // Create 10 agents (the limit)
        let i = 0;
        while (i < 10) {
            let name = b"Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let _agent = base_agent::test_create_base_agent(&user, name);
            i = i + 1;
        };

        // Attempting to create 11th agent should fail
        let _agent = base_agent::test_create_base_agent(&user, b"Agent 11");
    }

    #[test]
    /// Test different users can each create 10 agents independently
    fun test_multiple_users_independent_limits() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user1 = account::create_signer_for_test(TEST_USER1_ADDR);
        let user2 = account::create_signer_for_test(TEST_USER2_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // User1 creates 5 agents
        let i = 0;
        while (i < 5) {
            let name = b"User1 Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let _agent = base_agent::test_create_base_agent(&user1, name);
            i = i + 1;
        };

        // User2 creates 7 agents
        let i = 0;
        while (i < 7) {
            let name = b"User2 Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let _agent = base_agent::test_create_base_agent(&user2, name);
            i = i + 1;
        };

        // Verify independent limits
        let (user1_active, user1_sponsored, user1_can_sponsor) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(user1_active == 5, 1);
        assert!(user1_sponsored == 5, 2);
        assert!(user1_can_sponsor, 3);

        let (user2_active, user2_sponsored, user2_can_sponsor) = base_agent::get_user_agent_info(TEST_USER2_ADDR);
        assert!(user2_active == 7, 4);
        assert!(user2_sponsored == 7, 5);
        assert!(user2_can_sponsor, 6);

        // Both should still be able to create more agents
        assert!(base_agent::can_create_agent(TEST_USER1_ADDR), 7);
        assert!(base_agent::can_create_agent(TEST_USER2_ADDR), 8);

        // Platform stats should reflect total
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 12, 9);
        assert!(total_active == 12, 10);
    }

    // ================================================================================================
    // State Transition Tests
    // ================================================================================================

    #[test]
    /// Test valid state transitions: ACTIVE → PAUSED → ACTIVE
    fun test_pause_and_resume_agent() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Initial state should be ACTIVE
        assert!(base_agent::is_active(&agent), 1);
        assert!(!base_agent::is_paused(&agent), 2);
        assert!(base_agent::get_state(&agent) == 1, 3); // AGENT_STATE_ACTIVE

        // Pause the agent
        base_agent::pause_agent(&agent, &user);
        assert!(!base_agent::is_active(&agent), 4);
        assert!(base_agent::is_paused(&agent), 5);
        assert!(base_agent::get_state(&agent) == 2, 6); // AGENT_STATE_PAUSED

        // Resume the agent
        base_agent::resume_agent(&agent, &user);
        assert!(base_agent::is_active(&agent), 7);
        assert!(!base_agent::is_paused(&agent), 8);
        assert!(base_agent::get_state(&agent) == 1, 9); // AGENT_STATE_ACTIVE
    }

    #[test]
    #[expected_failure(abort_code = 2, location = Self)] // E_NOT_AUTHORIZED
    /// Test unauthorized user cannot pause agent
    fun test_pause_agent_unauthorized_fails() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);
        let unauthorized = account::create_signer_for_test(TEST_UNAUTHORIZED_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Unauthorized user tries to pause agent
        base_agent::pause_agent(&agent, &unauthorized);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = Self)] // E_AGENT_NOT_ACTIVE
    /// Test pausing already paused agent fails
    fun test_pause_already_paused_agent_fails() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Pause the agent
        base_agent::pause_agent(&agent, &user);

        // Try to pause again (should fail)
        base_agent::pause_agent(&agent, &user);
    }

    #[test]
    #[expected_failure(abort_code = 4, location = Self)] // E_AGENT_NOT_PAUSED
    /// Test resuming active agent fails
    fun test_resume_active_agent_fails() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Try to resume active agent (should fail)
        base_agent::resume_agent(&agent, &user);
    }

    #[test]
    /// Test complete state lifecycle: ACTIVE → PAUSED → ACTIVE → DELETED
    fun test_complete_agent_lifecycle() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // ACTIVE → PAUSED
        base_agent::pause_agent(&agent, &user);
        assert!(base_agent::is_paused(&agent), 1);

        // PAUSED → ACTIVE
        base_agent::resume_agent(&agent, &user);
        assert!(base_agent::is_active(&agent), 2);

        // ACTIVE → DELETED
        base_agent::delete_agent(&agent, &user);
        assert!(base_agent::get_state(&agent) == 3, 3); // AGENT_STATE_DELETED

        // Verify user registry updated
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 0, 4); // Active count should decrease
        assert!(sponsored_count == 0, 5); // Sponsored count should decrease
        assert!(can_create_sponsored, 6); // Should be able to create sponsored agents again

        // Verify platform stats updated
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 1, 7); // Total created doesn't decrease
        assert!(total_active == 0, 8); // Active count decreases
    }

    #[test]
    /// Test deleting paused agent
    fun test_delete_paused_agent() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Pause then delete
        base_agent::pause_agent(&agent, &user);
        base_agent::delete_agent(&agent, &user);

        assert!(base_agent::get_state(&agent) == 3, 1); // AGENT_STATE_DELETED

        // Verify counts properly updated (paused agent deletion)
        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 0, 2); // Should still decrease even if was paused
        assert!(sponsored_count == 0, 3);
    }

    // ================================================================================================
    // Gas Sponsorship Tests
    // ================================================================================================

    #[test]
    /// Test gas sponsorship for first 10 agents and transition after
    fun test_gas_sponsorship_transition() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // Create exactly 10 agents and verify sponsorship
        let agents = vector::empty<BaseAgent>();
        let i = 0;
        while (i < 10) {
            let name = b"Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let agent = base_agent::test_create_base_agent(&user, name);
            assert!(base_agent::has_gas_sponsorship(&agent), 100 + i);
            vector::push_back(&agents, agent);
            i = i + 1;
        };

        // Verify user info shows correct sponsorship
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 10, 1);
        assert!(sponsored_count == 10, 2);
        assert!(!can_create_sponsored, 3); // Should be at sponsorship limit
    }

    #[test]
    /// Test gas sponsorship reclaim after agent deletion
    fun test_gas_sponsorship_reclaim_after_deletion() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // Create 5 agents (all should have sponsorship)
        let agents = vector::empty<BaseAgent>();
        let i = 0;
        while (i < 5) {
            let name = b"Agent ";
            vector::append(&name, vector::singleton((48 + i) as u8));
            let agent = base_agent::test_create_base_agent(&user, name);
            vector::push_back(&agents, agent);
            i = i + 1;
        };

        // Delete 2 agents
        let agent1 = vector::pop_back(&agents);
        let agent2 = vector::pop_back(&agents);
        base_agent::delete_agent(&agent1, &user);
        base_agent::delete_agent(&agent2, &user);

        // Verify sponsorship count decreased
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 3, 1);
        assert!(sponsored_count == 3, 2); // Should decrease when sponsored agents are deleted
        assert!(can_create_sponsored, 3); // Should be able to create more sponsored agents
    }

    // ================================================================================================
    // Transaction Count Tests
    // ================================================================================================

    #[test]
    /// Test transaction count incrementation
    fun test_increment_transaction_count() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Initial count should be 0
        assert!(base_agent::get_total_transactions(&agent) == 0, 1);

        // Increment transaction count
        base_agent::increment_transaction_count(&agent);
        assert!(base_agent::get_total_transactions(&agent) == 1, 2);

        // Increment again
        base_agent::increment_transaction_count(&agent);
        assert!(base_agent::get_total_transactions(&agent) == 2, 3);

        // Multiple increments
        let i = 0;
        while (i < 10) {
            base_agent::increment_transaction_count(&agent);
            i = i + 1;
        };
        assert!(base_agent::get_total_transactions(&agent) == 12, 4);
    }

    // ================================================================================================
    // View Function Tests
    // ================================================================================================

    #[test]
    /// Test view functions for new user (no registry yet)
    fun test_view_functions_new_user() {
        // Test user with no registry
        let (active_count, sponsored_count, can_create_sponsored) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(active_count == 0, 1);
        assert!(sponsored_count == 0, 2);
        assert!(can_create_sponsored, 3);

        assert!(base_agent::can_create_agent(TEST_USER1_ADDR), 4);

        let agent_ids = base_agent::get_user_agent_ids(TEST_USER1_ADDR);
        assert!(vector::length(&agent_ids) == 0, 5);
    }

    #[test]
    /// Test platform stats without initialization
    fun test_platform_stats_uninitialized() {
        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 0, 1);
        assert!(total_active == 0, 2);
    }

    #[test]
    /// Test user agent IDs tracking
    fun test_user_agent_ids_tracking() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // Create 3 agents
        let agent1 = base_agent::test_create_base_agent(&user, b"Agent 1");
        let agent2 = base_agent::test_create_base_agent(&user, b"Agent 2");
        let agent3 = base_agent::test_create_base_agent(&user, b"Agent 3");

        // Get agent IDs
        let agent_ids = base_agent::get_user_agent_ids(TEST_USER1_ADDR);
        assert!(vector::length(&agent_ids) == 3, 1);
        assert!(*vector::borrow(&agent_ids, 0) == base_agent::get_agent_id(&agent1), 2);
        assert!(*vector::borrow(&agent_ids, 1) == base_agent::get_agent_id(&agent2), 3);
        assert!(*vector::borrow(&agent_ids, 2) == base_agent::get_agent_id(&agent3), 4);
    }

    // ================================================================================================
    // Edge Cases and Error Conditions
    // ================================================================================================

    #[test]
    /// Test agent creation with empty name
    fun test_create_agent_empty_name() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // Create agent with empty name (should work)
        let agent = base_agent::test_create_base_agent(&user, b"");
        assert!(base_agent::get_agent_id(&agent) == 1, 1);
    }

    #[test]
    /// Test agent creation with very long name
    fun test_create_agent_long_name() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // Create very long name (255 characters)
        let long_name = vector::empty<u8>();
        let i = 0;
        while (i < 255) {
            vector::push_back(&long_name, 65); // 'A' character
            i = i + 1;
        };

        let agent = base_agent::test_create_base_agent(&user, long_name);
        assert!(base_agent::get_agent_id(&agent) == 1, 1);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = Self)] // E_NOT_AUTHORIZED
    /// Test unauthorized delete fails
    fun test_delete_agent_unauthorized_fails() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);
        let unauthorized = account::create_signer_for_test(TEST_UNAUTHORIZED_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Unauthorized user tries to delete agent
        base_agent::delete_agent(&agent, &unauthorized);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = Self)] // E_NOT_AUTHORIZED
    /// Test unauthorized resume fails
    fun test_resume_agent_unauthorized_fails() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user = account::create_signer_for_test(TEST_USER1_ADDR);
        let unauthorized = account::create_signer_for_test(TEST_UNAUTHORIZED_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);
        let agent = base_agent::test_create_base_agent(&user, b"Test Agent");

        // Pause agent first
        base_agent::pause_agent(&agent, &user);

        // Unauthorized user tries to resume agent
        base_agent::resume_agent(&agent, &unauthorized);
    }

    // ================================================================================================
    // Integration Tests
    // ================================================================================================

    #[test]
    /// Test full multi-user scenario with various operations
    fun test_multi_user_full_scenario() {
        let admin = account::create_signer_for_test(TEST_ADMIN_ADDR);
        let user1 = account::create_signer_for_test(TEST_USER1_ADDR);
        let user2 = account::create_signer_for_test(TEST_USER2_ADDR);

        // Setup
        base_agent::initialize_platform(&admin);

        // User1 creates 3 agents
        let user1_agent1 = base_agent::test_create_base_agent(&user1, b"User1 Agent 1");
        let user1_agent2 = base_agent::test_create_base_agent(&user1, b"User1 Agent 2");
        let user1_agent3 = base_agent::test_create_base_agent(&user1, b"User1 Agent 3");

        // User2 creates 2 agents
        let user2_agent1 = base_agent::test_create_base_agent(&user2, b"User2 Agent 1");
        let user2_agent2 = base_agent::test_create_base_agent(&user2, b"User2 Agent 2");

        // User1 pauses one agent
        base_agent::pause_agent(&user1_agent1, &user1);

        // User2 deletes one agent
        base_agent::delete_agent(&user2_agent1, &user2);

        // Simulate some transactions
        base_agent::increment_transaction_count(&user1_agent2);
        base_agent::increment_transaction_count(&user1_agent2);

        // Verify final state
        let (user1_active, user1_sponsored, _) = base_agent::get_user_agent_info(TEST_USER1_ADDR);
        assert!(user1_active == 3, 1); // 1 paused + 2 active = 3 total active originally

        let (user2_active, user2_sponsored, _) = base_agent::get_user_agent_info(TEST_USER2_ADDR);
        assert!(user2_active == 1, 2); // 1 deleted, 1 remaining

        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 5, 3); // All created agents
        assert!(total_active == 4, 4); // 3 from user1 + 1 from user2

        // Verify transaction counts
        assert!(base_agent::get_total_transactions(&user1_agent2) == 2, 5);
        assert!(base_agent::get_total_transactions(&user1_agent3) == 0, 6);
        assert!(base_agent::get_total_transactions(&user2_agent2) == 0, 7);
    }
}
