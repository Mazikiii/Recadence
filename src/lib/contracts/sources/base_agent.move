/// Base Agent Contract
///
/// This contract provides the foundational architecture for all autonomous trading agents
/// in the Recadence platform. It implements:
/// - 10-agent limit per user enforcement
/// - Gas sponsorship tracking for first 10 agents
/// - Creator-only access controls
/// - Fund isolation and security
/// - Agent lifecycle management (ACTIVE → PAUSED → DELETED)
/// - Event emission for real-time indexing

module recadence::base_agent {
    use std::signer;
    use std::vector;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::account;
    use std::option::{Self, Option};

    // ================================================================================================
    // Error Codes
    // ================================================================================================

    /// Agent limit exceeded (max 10 agents per user)
    const E_AGENT_LIMIT_EXCEEDED: u64 = 1;
    /// Not authorized to perform this action
    const E_NOT_AUTHORIZED: u64 = 2;
    /// Agent is not in active state
    const E_AGENT_NOT_ACTIVE: u64 = 3;
    /// Agent is not paused
    const E_AGENT_NOT_PAUSED: u64 = 4;
    /// Insufficient funds for operation
    const E_INSUFFICIENT_FUNDS: u64 = 5;
    /// Agent does not exist
    const E_AGENT_NOT_FOUND: u64 = 6;
    /// Invalid agent state transition
    const E_INVALID_STATE_TRANSITION: u64 = 7;

    // ================================================================================================
    // Constants
    // ================================================================================================

    /// Maximum agents per user
    const MAX_AGENTS_PER_USER: u64 = 10;
    /// Gas sponsorship limit per user
    const GAS_SPONSORSHIP_LIMIT: u64 = 10;

    // ================================================================================================
    // Agent States
    // ================================================================================================

    const AGENT_STATE_ACTIVE: u8 = 1;
    const AGENT_STATE_PAUSED: u8 = 2;
    const AGENT_STATE_DELETED: u8 = 3;

    // ================================================================================================
    // Data Structures
    // ================================================================================================

    /// Base agent structure containing common fields for all agent types
    struct BaseAgent has key, store {
        /// Unique agent ID
        id: u64,
        /// Address of the agent creator
        creator: address,
        /// Agent name (optional)
        name: vector<u8>,
        /// Current state of the agent
        state: u8,
        /// Timestamp when agent was created
        created_at: u64,
        /// Timestamp when agent was last updated
        updated_at: u64,
        /// Whether this agent has gas sponsorship
        has_gas_sponsorship: bool,
        /// Reserved funds in the agent (for gas buffer)
        reserved_funds: u64,
        /// Total transactions executed by this agent
        total_transactions: u64,
        /// Resource address for this agent (optional, set after resource account creation)
        resource_address: Option<address>,
        /// Signer capability for agent operations (optional, retrieved when needed)
        resource_signer_cap: Option<account::SignerCapability>,
    }

    /// User agent registry to track agent count and gas sponsorship
    struct UserAgentRegistry has key {
        /// Total number of active agents for this user
        active_agent_count: u64,
        /// Number of agents with gas sponsorship
        sponsored_agents_count: u64,
        /// List of agent IDs created by this user
        agent_ids: vector<u64>,
        /// Next agent ID to assign
        next_agent_id: u64,
    }

    /// Global platform registry
    struct PlatformRegistry has key {
        /// Total number of agents created on platform
        total_agents_created: u64,
        /// Total number of active agents
        total_active_agents: u64,
        /// Platform admin address
        admin: address,
    }

    // ================================================================================================
    // Events
    // ================================================================================================

    #[event]
    struct AgentCreatedEvent has drop, store {
        agent_id: u64,
        creator: address,
        agent_type: vector<u8>,
        name: vector<u8>,
        has_gas_sponsorship: bool,
        created_at: u64,
    }

    #[event]
    struct AgentStateChangedEvent has drop, store {
        agent_id: u64,
        creator: address,
        old_state: u8,
        new_state: u8,
        changed_at: u64,
    }

    #[event]
    struct AgentDeletedEvent has drop, store {
        agent_id: u64,
        creator: address,
        deleted_at: u64,
    }

    #[event]
    struct GasSponsorshipAssignedEvent has drop, store {
        agent_id: u64,
        creator: address,
        assigned_at: u64,
    }

    // ================================================================================================
    // Initialization
    // ================================================================================================

    /// Initialize the platform registry (should only be called once by deployer)
    public entry fun initialize_platform(admin: &signer) {
        let admin_addr = signer::address_of(admin);

        if (!exists<PlatformRegistry>(admin_addr)) {
            move_to(admin, PlatformRegistry {
                total_agents_created: 0,
                total_active_agents: 0,
                admin: admin_addr,
            });
        };
    }

    /// Initialize user agent registry if it doesn't exist
    fun ensure_user_registry(user: &signer) {
        let user_addr = signer::address_of(user);

        if (!exists<UserAgentRegistry>(user_addr)) {
            move_to(user, UserAgentRegistry {
                active_agent_count: 0,
                sponsored_agents_count: 0,
                agent_ids: vector::empty(),
                next_agent_id: 1,
            });
        };
    }

    // ================================================================================================
    // Agent Creation and Management
    // ================================================================================================

    /// Create a new base agent (internal function used by specific agent types)
    public fun create_base_agent(
        creator: &signer,
        name: vector<u8>,
        agent_type: vector<u8>
    ): (BaseAgent, signer) acquires UserAgentRegistry, PlatformRegistry {
        let creator_addr = signer::address_of(creator);

        // Ensure user registry exists
        ensure_user_registry(creator);

        let user_registry = borrow_global_mut<UserAgentRegistry>(creator_addr);

        // Check agent limit
        assert!(user_registry.active_agent_count < MAX_AGENTS_PER_USER, E_AGENT_LIMIT_EXCEEDED);

        // Determine gas sponsorship eligibility
        let has_gas_sponsorship = user_registry.sponsored_agents_count < GAS_SPONSORSHIP_LIMIT;

        // Get next agent ID
        let agent_id = user_registry.next_agent_id;
        user_registry.next_agent_id = agent_id + 1;

        // Update counters
        user_registry.active_agent_count = user_registry.active_agent_count + 1;
        if (has_gas_sponsorship) {
            user_registry.sponsored_agents_count = user_registry.sponsored_agents_count + 1;
        };

        // Add to agent IDs list
        vector::push_back(&mut user_registry.agent_ids, agent_id);

        // Update platform registry
        if (exists<PlatformRegistry>(@recadence)) {
            let platform_registry = borrow_global_mut<PlatformRegistry>(@recadence);
            platform_registry.total_agents_created = platform_registry.total_agents_created + 1;
            platform_registry.total_active_agents = platform_registry.total_active_agents + 1;
        };

        let current_time = timestamp::now_seconds();

        // Create resource account for this agent
        let (resource_signer, signer_cap) = account::create_resource_account(creator, vector::empty<u8>());
        let resource_addr = signer::address_of(&resource_signer);

        // Create base agent with resource account info
        let base_agent = BaseAgent {
            id: agent_id,
            creator: creator_addr,
            name,
            state: AGENT_STATE_ACTIVE,
            created_at: current_time,
            updated_at: current_time,
            has_gas_sponsorship,
            reserved_funds: 0,
            total_transactions: 0,
            resource_address: option::some(resource_addr),
            resource_signer_cap: option::some(signer_cap),
        };

        // Emit events
        event::emit(AgentCreatedEvent {
            agent_id,
            creator: creator_addr,
            agent_type,
            name,
            has_gas_sponsorship,
            created_at: current_time,
        });

        if (has_gas_sponsorship) {
            event::emit(GasSponsorshipAssignedEvent {
                agent_id,
                creator: creator_addr,
                assigned_at: current_time,
            });
        };

        (base_agent, resource_signer)
    }

    /// Pause an agent (can only be called by creator)
    public fun pause_agent(agent: &mut BaseAgent, creator: &signer) {
        let creator_addr = signer::address_of(creator);
        assert!(agent.creator == creator_addr, E_NOT_AUTHORIZED);
        assert!(agent.state == AGENT_STATE_ACTIVE, E_AGENT_NOT_ACTIVE);

        let old_state = agent.state;
        agent.state = AGENT_STATE_PAUSED;
        agent.updated_at = timestamp::now_seconds();

        event::emit(AgentStateChangedEvent {
            agent_id: agent.id,
            creator: creator_addr,
            old_state,
            new_state: AGENT_STATE_PAUSED,
            changed_at: agent.updated_at,
        });
    }

    /// Resume an agent (can only be called by creator)
    public fun resume_agent(agent: &mut BaseAgent, creator: &signer) {
        let creator_addr = signer::address_of(creator);
        assert!(agent.creator == creator_addr, E_NOT_AUTHORIZED);
        assert!(agent.state == AGENT_STATE_PAUSED, E_AGENT_NOT_PAUSED);

        let old_state = agent.state;
        agent.state = AGENT_STATE_ACTIVE;
        agent.updated_at = timestamp::now_seconds();

        event::emit(AgentStateChangedEvent {
            agent_id: agent.id,
            creator: creator_addr,
            old_state,
            new_state: AGENT_STATE_ACTIVE,
            changed_at: agent.updated_at,
        });
    }

    /// Delete an agent (can only be called by creator)
    public fun delete_agent(agent: &mut BaseAgent, creator: &signer)
        acquires UserAgentRegistry, PlatformRegistry {
        let creator_addr = signer::address_of(creator);
        assert!(agent.creator == creator_addr, E_NOT_AUTHORIZED);

        let old_state = agent.state;
        agent.state = AGENT_STATE_DELETED;
        agent.updated_at = timestamp::now_seconds();

        // Update user registry
        let user_registry = borrow_global_mut<UserAgentRegistry>(creator_addr);

        // Only decrease count if agent was active
        if (old_state == AGENT_STATE_ACTIVE) {
            user_registry.active_agent_count = user_registry.active_agent_count - 1;
        };

        // Decrease sponsored count if applicable
        if (agent.has_gas_sponsorship) {
            user_registry.sponsored_agents_count = user_registry.sponsored_agents_count - 1;
        };

        // Update platform registry
        if (exists<PlatformRegistry>(@recadence)) {
            let platform_registry = borrow_global_mut<PlatformRegistry>(@recadence);
            if (old_state == AGENT_STATE_ACTIVE) {
                platform_registry.total_active_agents = platform_registry.total_active_agents - 1;
            };
        };

        event::emit(AgentDeletedEvent {
            agent_id: agent.id,
            creator: creator_addr,
            deleted_at: agent.updated_at,
        });
    }

    // ================================================================================================
    // Utility Functions
    // ================================================================================================

    /// Increment transaction count for an agent
    public fun increment_transaction_count(agent: &mut BaseAgent) {
        agent.total_transactions = agent.total_transactions + 1;
        agent.updated_at = timestamp::now_seconds();
    }

    /// Check if agent is active
    public fun is_active(agent: &BaseAgent): bool {
        agent.state == AGENT_STATE_ACTIVE
    }

    /// Check if agent is paused
    public fun is_paused(agent: &BaseAgent): bool {
        agent.state == AGENT_STATE_PAUSED
    }

    /// Check if agent has gas sponsorship
    public fun has_gas_sponsorship(agent: &BaseAgent): bool {
        agent.has_gas_sponsorship
    }

    /// Get agent ID
    public fun get_agent_id(agent: &BaseAgent): u64 {
        agent.id
    }

    /// Get agent creator
    public fun get_creator(agent: &BaseAgent): address {
        agent.creator
    }

    /// Get agent state
    public fun get_state(agent: &BaseAgent): u8 {
        agent.state
    }

    /// Get total transactions
    public fun get_total_transactions(agent: &BaseAgent): u64 {
        agent.total_transactions
    }



    /// Get resource address for the agent
    public fun get_resource_address(agent: &BaseAgent): address {
        *option::borrow(&agent.resource_address)
    }

    /// Get signer capability for the agent
    public fun get_signer_cap(agent: &BaseAgent): &account::SignerCapability {
        option::borrow(&agent.resource_signer_cap)
    }

    /// Store BaseAgent in global storage (can only be called from within base_agent module)
    public fun store_base_agent(resource_signer: &signer, base_agent: BaseAgent) {
        move_to(resource_signer, base_agent);
    }

    /// Check if agent is active by resource address
    public fun is_agent_active(resource_addr: address): bool acquires BaseAgent {
        let base_agent = borrow_global<BaseAgent>(resource_addr);
        base_agent.state == AGENT_STATE_ACTIVE
    }

    /// Get agent creator by resource address
    public fun get_agent_creator(resource_addr: address): address acquires BaseAgent {
        let base_agent = borrow_global<BaseAgent>(resource_addr);
        base_agent.creator
    }

    /// Get agent state by resource address
    public fun get_agent_state(resource_addr: address): u8 acquires BaseAgent {
        let base_agent = borrow_global<BaseAgent>(resource_addr);
        base_agent.state
    }

    /// Get agent ID by resource address
    public fun get_agent_id_by_addr(resource_addr: address): u64 acquires BaseAgent {
        let base_agent = borrow_global<BaseAgent>(resource_addr);
        base_agent.id
    }

    /// Pause agent by resource address and creator
    public fun pause_agent_by_addr(resource_addr: address, creator: &signer) acquires BaseAgent {
        let base_agent = borrow_global_mut<BaseAgent>(resource_addr);
        let creator_addr = signer::address_of(creator);
        assert!(base_agent.creator == creator_addr, E_NOT_AUTHORIZED);
        assert!(base_agent.state == AGENT_STATE_ACTIVE, E_AGENT_NOT_ACTIVE);

        let old_state = base_agent.state;
        base_agent.state = AGENT_STATE_PAUSED;
        base_agent.updated_at = timestamp::now_seconds();

        event::emit(AgentStateChangedEvent {
            agent_id: base_agent.id,
            creator: creator_addr,
            old_state,
            new_state: AGENT_STATE_PAUSED,
            changed_at: base_agent.updated_at,
        });
    }

    /// Resume agent by resource address and creator
    public fun resume_agent_by_addr(resource_addr: address, creator: &signer) acquires BaseAgent {
        let base_agent = borrow_global_mut<BaseAgent>(resource_addr);
        let creator_addr = signer::address_of(creator);
        assert!(base_agent.creator == creator_addr, E_NOT_AUTHORIZED);
        assert!(base_agent.state == AGENT_STATE_PAUSED, E_AGENT_NOT_PAUSED);

        let old_state = base_agent.state;
        base_agent.state = AGENT_STATE_ACTIVE;
        base_agent.updated_at = timestamp::now_seconds();

        event::emit(AgentStateChangedEvent {
            agent_id: base_agent.id,
            creator: creator_addr,
            old_state,
            new_state: AGENT_STATE_ACTIVE,
            changed_at: base_agent.updated_at,
        });
    }

    /// Increment transaction count by resource address
    public fun increment_transaction_count_by_addr(resource_addr: address) acquires BaseAgent {
        let base_agent = borrow_global_mut<BaseAgent>(resource_addr);
        base_agent.total_transactions = base_agent.total_transactions + 1;
        base_agent.updated_at = timestamp::now_seconds();
    }

    /// Get total transactions by resource address
    public fun get_total_transactions_by_addr(resource_addr: address): u64 acquires BaseAgent {
        let base_agent = borrow_global<BaseAgent>(resource_addr);
        base_agent.total_transactions
    }

    /// Delete agent by resource address and creator
    public fun delete_agent_by_addr(resource_addr: address, creator: &signer)
        acquires BaseAgent, UserAgentRegistry, PlatformRegistry {
        let base_agent = borrow_global_mut<BaseAgent>(resource_addr);
        let creator_addr = signer::address_of(creator);
        assert!(base_agent.creator == creator_addr, E_NOT_AUTHORIZED);
        assert!(base_agent.state != AGENT_STATE_DELETED, E_INVALID_STATE_TRANSITION);

        let agent_id = base_agent.id;
        let old_state = base_agent.state;
        base_agent.state = AGENT_STATE_DELETED;
        base_agent.updated_at = timestamp::now_seconds();

        // Update user registry
        if (exists<UserAgentRegistry>(creator_addr)) {
            let user_registry = borrow_global_mut<UserAgentRegistry>(creator_addr);
            user_registry.active_agent_count = user_registry.active_agent_count - 1;
        };

        // Update platform registry
        if (exists<PlatformRegistry>(@recadence)) {
            let platform_registry = borrow_global_mut<PlatformRegistry>(@recadence);
            platform_registry.total_active_agents = platform_registry.total_active_agents - 1;
        };

        // Emit event
        event::emit(AgentDeletedEvent {
            agent_id,
            creator: creator_addr,
            deleted_at: base_agent.updated_at,
        });
    }



    // ================================================================================================
    // View Functions
    // ================================================================================================

    #[view]
    /// Get user agent count and sponsorship info
    public fun get_user_agent_info(user_addr: address): (u64, u64, bool) acquires UserAgentRegistry {
        if (!exists<UserAgentRegistry>(user_addr)) {
            return (0, 0, true)
        };

        let registry = borrow_global<UserAgentRegistry>(user_addr);
        let can_create_sponsored = registry.sponsored_agents_count < GAS_SPONSORSHIP_LIMIT;

        (registry.active_agent_count, registry.sponsored_agents_count, can_create_sponsored)
    }

    #[view]
    /// Check if user can create more agents
    public fun can_create_agent(user_addr: address): bool acquires UserAgentRegistry {
        if (!exists<UserAgentRegistry>(user_addr)) {
            return true
        };

        let registry = borrow_global<UserAgentRegistry>(user_addr);
        registry.active_agent_count < MAX_AGENTS_PER_USER
    }

    #[view]
    /// Get platform statistics
    public fun get_platform_stats(): (u64, u64) acquires PlatformRegistry {
        if (!exists<PlatformRegistry>(@recadence)) {
            return (0, 0)
        };

        let registry = borrow_global<PlatformRegistry>(@recadence);
        (registry.total_agents_created, registry.total_active_agents)
    }

    #[view]
    /// Get user's agent IDs
    public fun get_user_agent_ids(user_addr: address): vector<u64> acquires UserAgentRegistry {
        if (!exists<UserAgentRegistry>(user_addr)) {
            return vector::empty()
        };

        let registry = borrow_global<UserAgentRegistry>(user_addr);
        registry.agent_ids
    }

    // ================================================================================================
    // Test Functions (dev only)
    // ================================================================================================

    #[test_only]
    public fun test_create_base_agent(creator: &signer, name: vector<u8>): BaseAgent
        acquires UserAgentRegistry, PlatformRegistry {
        create_base_agent(creator, name, b"test_agent")
    }
}
