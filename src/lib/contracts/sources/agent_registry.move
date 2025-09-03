/// Agent Registry Contract
///
/// This contract manages the registration and coordination of all agent types
/// in the Recadence platform. It provides:
/// - Centralized agent registration for all types
/// - Agent discovery and enumeration
/// - Platform-wide agent statistics
/// - Agent type validation and management

module recadence::agent_registry {
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::table::{Self, Table};
    use recadence::base_agent::{Self, BaseAgent};

    // ================================================================================================
    // Error Codes
    // ================================================================================================

    /// Agent type not supported
    const E_UNSUPPORTED_AGENT_TYPE: u64 = 1;
    /// Agent not found in registry
    const E_AGENT_NOT_FOUND: u64 = 2;
    /// Not authorized to perform this action
    const E_NOT_AUTHORIZED: u64 = 3;
    /// Agent type already registered
    const E_AGENT_TYPE_EXISTS: u64 = 4;

    // ================================================================================================
    // Constants
    // ================================================================================================

    /// Supported agent types
    const AGENT_TYPE_DCA_BUY: vector<u8> = b"dca_buy";
    const AGENT_TYPE_DCA_SELL: vector<u8> = b"dca_sell";
    const AGENT_TYPE_PERCENTAGE_BUY: vector<u8> = b"percentage_buy";
    const AGENT_TYPE_PERCENTAGE_SELL: vector<u8> = b"percentage_sell";

    // ================================================================================================
    // Data Structures
    // ================================================================================================

    /// Registry entry for each agent
    struct AgentRegistryEntry has store, drop {
        /// Agent ID
        agent_id: u64,
        /// Agent creator
        creator: address,
        /// Agent type
        agent_type: vector<u8>,
        /// Agent name
        name: vector<u8>,
        /// Resource account where agent contract is stored
        resource_account: address,
        /// Timestamp when registered
        registered_at: u64,
        /// Whether agent is currently active
        is_active: bool,
        /// Total transactions executed
        total_transactions: u64,
    }

    /// Agent type metadata
    struct AgentTypeInfo has store, drop {
        /// Type name
        type_name: vector<u8>,
        /// Type description
        description: vector<u8>,
        /// Whether this type is enabled
        enabled: bool,
        /// Total agents of this type
        total_count: u64,
        /// Active agents of this type
        active_count: u64,
    }

    /// Main registry resource
    struct AgentRegistry has key {
        /// Table mapping agent_id to registry entry
        agents: Table<u64, AgentRegistryEntry>,
        /// Table mapping creator address to list of agent IDs
        agents_by_creator: Table<address, vector<u64>>,
        /// Table mapping agent type to list of agent IDs
        agents_by_type: Table<vector<u8>, vector<u64>>,
        /// Supported agent types
        agent_types: Table<vector<u8>, AgentTypeInfo>,
        /// Total agents registered
        total_agents: u64,
        /// Total active agents
        total_active: u64,
        /// Next available agent ID
        next_agent_id: u64,
        /// Registry admin
        admin: address,
    }

    // ================================================================================================
    // Events
    // ================================================================================================

    #[event]
    struct AgentRegisteredEvent has drop, store {
        agent_id: u64,
        creator: address,
        agent_type: vector<u8>,
        name: vector<u8>,
        resource_account: address,
        registered_at: u64,
    }

    #[event]
    struct AgentStatusUpdatedEvent has drop, store {
        agent_id: u64,
        creator: address,
        old_status: bool,
        new_status: bool,
        updated_at: u64,
    }

    #[event]
    struct AgentTypeRegisteredEvent has drop, store {
        type_name: vector<u8>,
        description: vector<u8>,
        registered_at: u64,
    }

    // ================================================================================================
    // Initialization
    // ================================================================================================

    /// Initialize the agent registry (called once by deployer)
    public entry fun initialize_registry(admin: &signer) {
        let admin_addr = signer::address_of(admin);

        if (!exists<AgentRegistry>(admin_addr)) {
            let registry = AgentRegistry {
                agents: table::new(),
                agents_by_creator: table::new(),
                agents_by_type: table::new(),
                agent_types: table::new(),
                total_agents: 0,
                total_active: 0,
                next_agent_id: 1,
                admin: admin_addr,
            };

            move_to(admin, registry);

            // Register default agent types
            register_default_agent_types(&mut registry);
        };
    }

    /// Register the default supported agent types
    fun register_default_agent_types(registry: &mut AgentRegistry) {
        let current_time = timestamp::now_seconds();

        // DCA Buy Agent
        let dca_buy_info = AgentTypeInfo {
            type_name: AGENT_TYPE_DCA_BUY,
            description: b"Dollar Cost Averaging Buy Agent - Automatically purchases tokens at regular intervals",
            enabled: true,
            total_count: 0,
            active_count: 0,
        };
        table::add(&mut registry.agent_types, AGENT_TYPE_DCA_BUY, dca_buy_info);
        table::add(&mut registry.agents_by_type, AGENT_TYPE_DCA_BUY, vector::empty<u64>());

        // DCA Sell Agent
        let dca_sell_info = AgentTypeInfo {
            type_name: AGENT_TYPE_DCA_SELL,
            description: b"Dollar Cost Averaging Sell Agent - Automatically sells tokens at regular intervals",
            enabled: true,
            total_count: 0,
            active_count: 0,
        };
        table::add(&mut registry.agent_types, AGENT_TYPE_DCA_SELL, dca_sell_info);
        table::add(&mut registry.agents_by_type, AGENT_TYPE_DCA_SELL, vector::empty<u64>());

        // Percentage Buy Agent
        let perc_buy_info = AgentTypeInfo {
            type_name: AGENT_TYPE_PERCENTAGE_BUY,
            description: b"Percentage Buy Agent - Buys tokens when price moves by specified percentage (UP/DOWN trends)",
            enabled: true,
            total_count: 0,
            active_count: 0,
        };
        table::add(&mut registry.agent_types, AGENT_TYPE_PERCENTAGE_BUY, perc_buy_info);
        table::add(&mut registry.agents_by_type, AGENT_TYPE_PERCENTAGE_BUY, vector::empty<u64>());

        // Percentage Sell Agent
        let perc_sell_info = AgentTypeInfo {
            type_name: AGENT_TYPE_PERCENTAGE_SELL,
            description: b"Percentage Sell Agent - Sells tokens when price moves by specified percentage",
            enabled: true,
            total_count: 0,
            active_count: 0,
        };
        table::add(&mut registry.agent_types, AGENT_TYPE_PERCENTAGE_SELL, perc_sell_info);
        table::add(&mut registry.agents_by_type, AGENT_TYPE_PERCENTAGE_SELL, vector::empty<u64>());

        // Emit registration events
        event::emit(AgentTypeRegisteredEvent {
            type_name: AGENT_TYPE_DCA_BUY,
            description: b"Dollar Cost Averaging Buy Agent",
            registered_at: current_time,
        });

        event::emit(AgentTypeRegisteredEvent {
            type_name: AGENT_TYPE_DCA_SELL,
            description: b"Dollar Cost Averaging Sell Agent",
            registered_at: current_time,
        });

        event::emit(AgentTypeRegisteredEvent {
            type_name: AGENT_TYPE_PERCENTAGE_BUY,
            description: b"Percentage Buy Agent with trend selection",
            registered_at: current_time,
        });

        event::emit(AgentTypeRegisteredEvent {
            type_name: AGENT_TYPE_PERCENTAGE_SELL,
            description: b"Percentage Sell Agent",
            registered_at: current_time,
        });
    }

    // ================================================================================================
    // Agent Registration
    // ================================================================================================

    /// Register a new agent in the registry
    public fun register_agent(
        creator: &signer,
        agent_type: vector<u8>,
        name: vector<u8>,
        resource_account: address,
        base_agent: &BaseAgent
    ) acquires AgentRegistry {
        let creator_addr = signer::address_of(creator);
        let registry = borrow_global_mut<AgentRegistry>(@recadence);

        // Validate agent type
        assert!(table::contains(&registry.agent_types, agent_type), E_UNSUPPORTED_AGENT_TYPE);
        assert!(is_agent_type_enabled(agent_type, registry), E_UNSUPPORTED_AGENT_TYPE);

        let agent_id = base_agent::get_agent_id(base_agent);
        let current_time = timestamp::now_seconds();

        // Create registry entry
        let entry = AgentRegistryEntry {
            agent_id,
            creator: creator_addr,
            agent_type: agent_type,
            name,
            resource_account,
            registered_at: current_time,
            is_active: base_agent::is_active(base_agent),
            total_transactions: 0,
        };

        // Add to main agents table
        table::add(&mut registry.agents, agent_id, entry);

        // Add to creator's agent list
        if (!table::contains(&registry.agents_by_creator, creator_addr)) {
            table::add(&mut registry.agents_by_creator, creator_addr, vector::empty<u64>());
        };
        let creator_agents = table::borrow_mut(&mut registry.agents_by_creator, creator_addr);
        vector::push_back(creator_agents, agent_id);

        // Add to agent type list
        let type_agents = table::borrow_mut(&mut registry.agents_by_type, agent_type);
        vector::push_back(type_agents, agent_id);

        // Update counters
        registry.total_agents = registry.total_agents + 1;
        if (base_agent::is_active(base_agent)) {
            registry.total_active = registry.total_active + 1;
        };

        // Update agent type counters
        let type_info = table::borrow_mut(&mut registry.agent_types, agent_type);
        type_info.total_count = type_info.total_count + 1;
        if (base_agent::is_active(base_agent)) {
            type_info.active_count = type_info.active_count + 1;
        };

        // Emit event
        event::emit(AgentRegisteredEvent {
            agent_id,
            creator: creator_addr,
            agent_type,
            name,
            resource_account,
            registered_at: current_time,
        });
    }

    /// Update agent status in registry
    public fun update_agent_status(
        agent_id: u64,
        creator: &signer,
        is_active: bool
    ) acquires AgentRegistry {
        let creator_addr = signer::address_of(creator);
        let registry = borrow_global_mut<AgentRegistry>(@recadence);

        assert!(table::contains(&registry.agents, agent_id), E_AGENT_NOT_FOUND);

        let entry = table::borrow_mut(&mut registry.agents, agent_id);
        assert!(entry.creator == creator_addr, E_NOT_AUTHORIZED);

        let old_status = entry.is_active;
        entry.is_active = is_active;

        // Update global counters
        if (old_status && !is_active) {
            // Agent became inactive
            registry.total_active = registry.total_active - 1;

            // Update agent type counter
            let type_info = table::borrow_mut(&mut registry.agent_types, entry.agent_type);
            type_info.active_count = type_info.active_count - 1;
        } else if (!old_status && is_active) {
            // Agent became active
            registry.total_active = registry.total_active + 1;

            // Update agent type counter
            let type_info = table::borrow_mut(&mut registry.agent_types, entry.agent_type);
            type_info.active_count = type_info.active_count + 1;
        };

        event::emit(AgentStatusUpdatedEvent {
            agent_id,
            creator: creator_addr,
            old_status,
            new_status: is_active,
            updated_at: timestamp::now_seconds(),
        });
    }

    /// Update agent transaction count
    public fun update_transaction_count(
        agent_id: u64,
        new_count: u64
    ) acquires AgentRegistry {
        let registry = borrow_global_mut<AgentRegistry>(@recadence);

        assert!(table::contains(&registry.agents, agent_id), E_AGENT_NOT_FOUND);

        let entry = table::borrow_mut(&mut registry.agents, agent_id);
        entry.total_transactions = new_count;
    }

    // ================================================================================================
    // Utility Functions
    // ================================================================================================

    /// Check if agent type is enabled
    fun is_agent_type_enabled(agent_type: vector<u8>, registry: &AgentRegistry): bool {
        if (!table::contains(&registry.agent_types, agent_type)) {
            return false
        };

        let type_info = table::borrow(&registry.agent_types, agent_type);
        type_info.enabled
    }

    /// Validate agent type
    public fun is_valid_agent_type(agent_type: vector<u8>): bool {
        agent_type == AGENT_TYPE_DCA_BUY ||
        agent_type == AGENT_TYPE_DCA_SELL ||
        agent_type == AGENT_TYPE_PERCENTAGE_BUY ||
        agent_type == AGENT_TYPE_PERCENTAGE_SELL
    }

    // ================================================================================================
    // View Functions
    // ================================================================================================

    #[view]
    /// Get agent registry entry
    public fun get_agent_info(agent_id: u64): (address, vector<u8>, vector<u8>, address, bool, u64)
        acquires AgentRegistry {
        let registry = borrow_global<AgentRegistry>(@recadence);

        assert!(table::contains(&registry.agents, agent_id), E_AGENT_NOT_FOUND);

        let entry = table::borrow(&registry.agents, agent_id);
        (
            entry.creator,
            entry.agent_type,
            entry.name,
            entry.resource_account,
            entry.is_active,
            entry.total_transactions
        )
    }

    #[view]
    /// Get agents by creator
    public fun get_agents_by_creator(creator: address): vector<u64> acquires AgentRegistry {
        let registry = borrow_global<AgentRegistry>(@recadence);

        if (!table::contains(&registry.agents_by_creator, creator)) {
            return vector::empty()
        };

        *table::borrow(&registry.agents_by_creator, creator)
    }

    #[view]
    /// Get agents by type
    public fun get_agents_by_type(agent_type: vector<u8>): vector<u64> acquires AgentRegistry {
        let registry = borrow_global<AgentRegistry>(@recadence);

        if (!table::contains(&registry.agents_by_type, agent_type)) {
            return vector::empty()
        };

        *table::borrow(&registry.agents_by_type, agent_type)
    }

    #[view]
    /// Get platform statistics
    public fun get_platform_stats(): (u64, u64) acquires AgentRegistry {
        let registry = borrow_global<AgentRegistry>(@recadence);
        (registry.total_agents, registry.total_active)
    }

    #[view]
    /// Get agent type information
    public fun get_agent_type_info(agent_type: vector<u8>): (vector<u8>, bool, u64, u64)
        acquires AgentRegistry {
        let registry = borrow_global<AgentRegistry>(@recadence);

        assert!(table::contains(&registry.agent_types, agent_type), E_UNSUPPORTED_AGENT_TYPE);

        let type_info = table::borrow(&registry.agent_types, agent_type);
        (
            type_info.description,
            type_info.enabled,
            type_info.total_count,
            type_info.active_count
        )
    }

    #[view]
    /// Get all supported agent types
    public fun get_supported_agent_types(): vector<vector<u8>> {
        vector[
            AGENT_TYPE_DCA_BUY,
            AGENT_TYPE_DCA_SELL,
            AGENT_TYPE_PERCENTAGE_BUY,
            AGENT_TYPE_PERCENTAGE_SELL
        ]
    }

    // ================================================================================================
    // Admin Functions
    // ================================================================================================

    /// Enable/disable agent type (admin only)
    public entry fun set_agent_type_enabled(
        admin: &signer,
        agent_type: vector<u8>,
        enabled: bool
    ) acquires AgentRegistry {
        let admin_addr = signer::address_of(admin);
        let registry = borrow_global_mut<AgentRegistry>(@recadence);

        assert!(registry.admin == admin_addr, E_NOT_AUTHORIZED);
        assert!(table::contains(&registry.agent_types, agent_type), E_UNSUPPORTED_AGENT_TYPE);

        let type_info = table::borrow_mut(&mut registry.agent_types, agent_type);
        type_info.enabled = enabled;
    }
}
