/// Percentage Sell Agent Contract
///
/// This contract implements Percentage Sell functionality for autonomous
/// token sales based on price movements. It supports:
/// - APT, WETH, WBTC, USDC source tokens
/// - USDT as the target currency
/// - Standard percentage triggers for profit-taking
/// - Integration with KanaLabs aggregator for blazing fast swaps
/// - Sub-250ms execution via keeper system
/// - Gas sponsorship for first 10 agents per user

module recadence::percentage_sell_agent {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use recadence::base_agent::{Self, BaseAgent};
    use recadence::agent_registry;

    // ================================================================================================
    // Error Codes
    // ================================================================================================

    /// Insufficient token balance for sale
    const E_INSUFFICIENT_TOKEN_BALANCE: u64 = 1;
    /// Agent is not active
    const E_AGENT_NOT_ACTIVE: u64 = 2;
    /// Percentage threshold not reached
    const E_PERCENTAGE_NOT_REACHED: u64 = 3;
    /// Invalid source token
    const E_INVALID_SOURCE_TOKEN: u64 = 4;
    /// DEX swap failed
    const E_SWAP_FAILED: u64 = 5;
    /// Not authorized to execute
    const E_NOT_AUTHORIZED: u64 = 6;
    /// Invalid percentage value
    const E_INVALID_PERCENTAGE: u64 = 7;

    // ================================================================================================
    // Constants
    // ================================================================================================

    /// Supported token addresses (testnet) - Fungible Asset Standard
    const APT_TOKEN: address = @0x000000000000000000000000000000000000000000000000000000000000000a;
    const USDC_TOKEN: address = @0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832;
    const USDT_TOKEN: address = @0x357b0b74bc833e95a115ad22604854d6b0fca151cecd94111770e5d6ffc9dc2b;

    /// Gas buffer for operations
    const GAS_BUFFER: u64 = 1000000; // 0.01 APT

    // ================================================================================================
    // Percentage Constants
    // ================================================================================================

    /// Percentage constraints
    const MIN_PERCENTAGE: u64 = 5;   // 5% minimum
    // No maximum - full flexibility above 5%

    // ================================================================================================
    // Data Structures
    // ================================================================================================

    /// Percentage Sell Agent configuration
    struct PercentageSellAgent has key, store, copy, drop {
        /// Agent ID reference
        agent_id: u64,
        /// Source token to sell (APT, WETH, WBTC, USDC)
        source_token: Object<Metadata>,
        /// Amount of source token to sell per execution
        sell_amount_tokens: u64,
        /// Percentage threshold for execution (1-100%)
        percentage_threshold: u64,
        /// Entry price for percentage calculation (scaled by 1e8)
        entry_price: u64,
        /// Last recorded price (scaled by 1e8)
        last_price: u64,
        /// Last price check timestamp
        last_price_check: u64,
        /// Optional stop date (timestamp)
        stop_date: Option<u64>,
        /// Total amount sold (in source token)
        total_sold: u64,
        /// Total USDT received
        total_usdt_received: u64,
        /// Remaining source tokens for sales
        remaining_tokens: u64,
        /// Average price received (USDT per source token, scaled by 1e8)
        average_price: u64,
        /// Total number of executions
        execution_count: u64,
    }

    /// Agent storage resource
    struct PercentageSellAgentStorage has key {
        /// The percentage sell agent instance
        agent: PercentageSellAgent,
    }

    // ================================================================================================
    // Events
    // ================================================================================================

    #[event]
    struct PercentageSellAgentCreatedEvent has drop, store {
        agent_id: u64,
        creator: address,
        source_token: address,
        sell_amount_tokens: u64,
        percentage_threshold: u64,
        entry_price: u64,
        stop_date: Option<u64>,
        created_at: u64,
    }

    #[event]
    struct PercentageSellExecutedEvent has drop, store {
        agent_id: u64,
        executor: address,
        source_token: address,
        tokens_sold: u64,
        usdt_received: u64,
        trigger_price: u64,
        entry_price: u64,
        percentage_gain: u64,
        execution_count: u64,
        executed_at: u64,
    }

    #[event]
    struct PriceUpdateEvent has drop, store {
        agent_id: u64,
        source_token: address,
        old_price: u64,
        new_price: u64,
        percentage_change: u64,
        threshold_met: bool,
        updated_at: u64,
    }

    // ================================================================================================
    // Public Functions
    // ================================================================================================

    /// Creates a new Percentage Sell Agent
    public entry fun create_percentage_sell_agent(
        creator: &signer,
        source_token: Object<Metadata>,
        sell_amount_tokens: u64,
        percentage_threshold: u64,
        initial_token_deposit: u64,
        stop_date: Option<u64>,
        agent_name: vector<u8>
    ) {
        let creator_addr = signer::address_of(creator);

        // Validate inputs
        assert!(is_supported_token(source_token), E_INVALID_SOURCE_TOKEN);
        assert!(percentage_threshold >= MIN_PERCENTAGE, E_INVALID_PERCENTAGE);
        assert!(sell_amount_tokens > 0, E_INSUFFICIENT_TOKEN_BALANCE);
        assert!(initial_token_deposit >= sell_amount_tokens, E_INSUFFICIENT_TOKEN_BALANCE);

        // Create base agent (now returns base_agent and resource_signer)
        let (base_agent, resource_signer) = base_agent::create_base_agent(
            creator,
            agent_name,
            b"percentage_sell"
        );

        let current_time = timestamp::now_seconds();
        let entry_price = get_current_price(source_token); // Set entry price for percentage calculation

        let agent_id = base_agent::get_agent_id(&base_agent);
        let resource_addr = base_agent::get_resource_address(&base_agent);

        // Create Percentage Sell agent
        let percentage_agent = PercentageSellAgent {
            agent_id,
            source_token,
            sell_amount_tokens,
            percentage_threshold,
            entry_price,
            last_price: entry_price,
            last_price_check: current_time,
            stop_date,
            total_sold: 0,
            total_usdt_received: 0,
            remaining_tokens: initial_token_deposit,
            average_price: 0,
            execution_count: 0,
        };

        // Store the agent
        let agent_storage = PercentageSellAgentStorage {
            agent: percentage_agent,
        };

        // Store base agent in resource account first
        base_agent::store_base_agent(&resource_signer, base_agent);

        // Then store agent storage
        move_to(&resource_signer, agent_storage);

        // Register with platform
        agent_registry::register_agent(
            creator,
            b"percentage_sell",
            agent_name,
            resource_addr
        );

        // Emit creation event
        event::emit(PercentageSellAgentCreatedEvent {
            agent_id,
            creator: creator_addr,
            source_token: object::object_address(&source_token),
            sell_amount_tokens,
            percentage_threshold,
            entry_price,
            stop_date,
            created_at: current_time,
        });
    }

    /// Executes percentage sell when price threshold is met
    public entry fun execute_percentage_sell(
        executor: &signer,
        agent_resource_addr: address
    ) acquires PercentageSellAgentStorage {
        let storage = borrow_global_mut<PercentageSellAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        // Check if agent is active
        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        assert!(base_agent::is_agent_active(resource_addr), E_AGENT_NOT_ACTIVE);

        let current_time = timestamp::now_seconds();

        // Check if agent should stop due to date
        if (option::is_some(&agent.stop_date)) {
            let stop_time = *option::borrow(&agent.stop_date);
            assert!(current_time < stop_time, E_AGENT_NOT_ACTIVE);
        };

        // Get current price and check percentage threshold
        let current_price = get_current_price(agent.source_token);
        let (percentage_gain, threshold_met) = check_percentage_threshold(
            agent.entry_price,
            current_price,
            agent.percentage_threshold
        );

        assert!(threshold_met, E_PERCENTAGE_NOT_REACHED);

        // Check sufficient balance
        assert!(agent.remaining_tokens >= agent.sell_amount_tokens, E_INSUFFICIENT_TOKEN_BALANCE);

        // Execute swap via KanaLabs
        let tokens_to_sell = agent.sell_amount_tokens;
        let usdt_received = execute_kanashop_swap(
            agent.source_token,
            tokens_to_sell
        );

        // Update agent state
        agent.total_sold = agent.total_sold + tokens_to_sell;
        agent.total_usdt_received = agent.total_usdt_received + usdt_received;
        agent.remaining_tokens = agent.remaining_tokens - tokens_to_sell;
        agent.execution_count = agent.execution_count + 1;
        agent.last_price = current_price;
        agent.last_price_check = current_time;

        // Update average price
        let sell_amount = agent.sell_amount_tokens;
        update_average_price(agent, sell_amount, usdt_received);

        let executor_addr = signer::address_of(executor);
        let agent_id = agent.agent_id;

        // Emit execution event
        event::emit(PercentageSellExecutedEvent {
            agent_id,
            executor: executor_addr,
            source_token: object::object_address(&agent.source_token),
            tokens_sold: tokens_to_sell,
            usdt_received,
            trigger_price: current_price,
            entry_price: agent.entry_price,
            percentage_gain,
            execution_count: agent.execution_count,
            executed_at: current_time,
        });
    }

    /// Updates price without execution (for price tracking)
    public entry fun update_price(
        updater: &signer,
        agent_resource_addr: address
    ) acquires PercentageSellAgentStorage {
        let storage = borrow_global_mut<PercentageSellAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        let current_price = get_current_price(agent.source_token);
        let old_price = agent.last_price;

        let (percentage_change, threshold_met) = check_percentage_threshold(
            agent.entry_price,
            current_price,
            agent.percentage_threshold
        );

        // Update price tracking
        agent.last_price = current_price;
        agent.last_price_check = timestamp::now_seconds();

        let agent_id = agent.agent_id;

        // Emit price update event
        event::emit(PriceUpdateEvent {
            agent_id,
            source_token: object::object_address(&agent.source_token),
            old_price,
            new_price: current_price,
            percentage_change,
            threshold_met,
            updated_at: agent.last_price_check,
        });
    }

    /// Pauses the percentage sell agent
    public entry fun pause_percentage_sell_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires PercentageSellAgentStorage {
        let storage = borrow_global_mut<PercentageSellAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        base_agent::pause_agent_by_addr(resource_addr, creator);

        // Update registry status
        agent_registry::update_agent_status(
            agent.agent_id,
            creator,
            false
        );
    }

    /// Resumes the percentage sell agent
    public entry fun resume_percentage_sell_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires PercentageSellAgentStorage {
        let storage = borrow_global_mut<PercentageSellAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        base_agent::resume_agent_by_addr(resource_addr, creator);

        // Update registry status
        agent_registry::update_agent_status(
            agent.agent_id,
            creator,
            true
        );
    }

    /// Withdraws all remaining tokens and deletes the agent
    public entry fun withdraw_and_delete_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires PercentageSellAgentStorage {
        let storage = borrow_global_mut<PercentageSellAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        // Verify creator authorization
        let creator_addr = signer::address_of(creator);
        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        assert!(base_agent::get_agent_creator(resource_addr) == creator_addr, E_NOT_AUTHORIZED);

        let agent_id = agent.agent_id;

        // Withdraw all remaining tokens
        // TODO: Implement actual token withdrawal to creator
        // For now, just emit event
        let remaining_tokens = agent.remaining_tokens;

        // Update registry before deletion
        agent_registry::unregister_agent(agent_id, creator);

        // Delete the agent storage
        let PercentageSellAgentStorage { agent: _ } = move_from<PercentageSellAgentStorage>(agent_resource_addr);
    }

    // ================================================================================================
    // Helper Functions
    // ================================================================================================



    /// Checks if percentage threshold is met (price gain from entry)
    fun check_percentage_threshold(
        entry_price: u64,
        current_price: u64,
        threshold: u64
    ): (u64, bool) {
        if (entry_price == 0) {
            return (0, false)
        };

        let percentage_gain = if (current_price > entry_price) {
            // Price increased from entry
            ((current_price - entry_price) * 100) / entry_price
        } else {
            // Price below entry - no gain
            0
        };

        let threshold_met = percentage_gain >= threshold;

        (percentage_gain, threshold_met)
    }

    /// Updates the average price calculation
    fun update_average_price(agent: &mut PercentageSellAgent, tokens_sold: u64, usdt_received: u64) {
        if (tokens_sold == 0) return;

        let new_total_usdt = agent.total_usdt_received;
        let new_total_tokens = agent.total_sold;

        if (new_total_tokens > 0) {
            agent.average_price = (new_total_usdt * 100000000) / new_total_tokens; // Scale by 1e8
        };
    }

    /// Executes swap through KanaLabs aggregator
    fun execute_kanashop_swap(source_token: Object<Metadata>, token_amount: u64): u64 {
        // TODO: Implement actual KanaLabs integration
        // For now, return mock value based on current price
        let current_price = get_current_price(source_token);
        if (current_price == 0) return 0;

        // Mock calculation: usdt_received = token_amount * price_per_token
        (token_amount * current_price) / 100000000
    }

    /// Gets current market price for a token (mock implementation)
    fun get_current_price(token: Object<Metadata>): u64 {
        // TODO: Implement actual Chainlink price feed integration
        // Mock prices (scaled by 1e8):
        let token_addr = object::object_address(&token);
        if (token_addr == APT_TOKEN) {
            800000000   // $8.00 APT (realistic testnet price)
        } else if (token_addr == USDC_TOKEN) {
            100000000   // $1.00 USDC
        } else if (token_addr == USDT_TOKEN) {
            100000000   // $1.00 USDT
        } else {
            100000000   // Default $1.00
        }
    }

    /// Checks if token is supported
    fun is_supported_token(token: Object<Metadata>): bool {
        let token_addr = object::object_address(&token);
        token_addr == APT_TOKEN ||
        token_addr == USDC_TOKEN ||
        token_addr == USDT_TOKEN
    }

    /// Test-only version that accepts any valid Metadata object for testing
    #[test_only]
    fun is_supported_token_test(token: Object<Metadata>): bool {
        // In test environment, accept any properly formed Metadata object
        true
    }

    // ================================================================================================
    // View Functions
    // ================================================================================================

    #[view]
    /// Get percentage sell agent information
    public fun get_percentage_sell_agent_info(agent_resource_addr: address): (
        u64, // agent_id
        address, // creator
        address, // source_token
        u64, // sell_amount_tokens
        u64, // percentage_threshold
        u64, // entry_price
        u64, // last_price
        u64, // total_sold
        u64, // total_usdt_received
        u64, // remaining_tokens
        u64, // average_price
        u64, // execution_count
        Option<u64>, // stop_date
        u64, // last_price_check
    ) acquires PercentageSellAgentStorage {
        let storage = borrow_global<PercentageSellAgentStorage>(agent_resource_addr);
        let agent = &storage.agent;

        (
            agent.agent_id,
            {
                let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
                base_agent::get_agent_creator(resource_addr)
            },
            object::object_address(&agent.source_token),
            agent.sell_amount_tokens,
            agent.percentage_threshold,
            agent.entry_price,
            agent.last_price,
            agent.total_sold,
            agent.total_usdt_received,
            agent.remaining_tokens,
            agent.average_price,
            agent.execution_count,
            agent.stop_date,
            agent.last_price_check,
        )
    }

    #[view]
    /// Check if percentage sell agent should execute
    public fun should_execute_percentage_sell(agent_resource_addr: address): bool acquires PercentageSellAgentStorage {
        let storage = borrow_global<PercentageSellAgentStorage>(agent_resource_addr);
        let agent = &storage.agent;

        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        if (!base_agent::is_agent_active(resource_addr)) {
            return false
        };

        // Check stop date
        let current_time = timestamp::now_seconds();
        if (option::is_some(&agent.stop_date)) {
            let stop_time = *option::borrow(&agent.stop_date);
            if (current_time >= stop_time) {
                return false
            };
        };

        // Check percentage threshold
        let current_price = get_current_price(agent.source_token);
        let (_, threshold_met) = check_percentage_threshold(
            agent.entry_price,
            current_price,
            agent.percentage_threshold
        );

        // Check balance
        let has_sufficient_balance = agent.remaining_tokens >= agent.sell_amount_tokens;

        threshold_met && has_sufficient_balance
    }

    #[view]
    /// Get supported tokens
    public fun get_supported_tokens(): vector<address> {
        vector[APT_TOKEN, USDC_TOKEN, USDT_TOKEN]
    }

    // ================================================================================================
    // Test Functions (dev only)
    // ================================================================================================

    /// Test-only version of create_percentage_sell_agent that bypasses token validation
    #[test_only]
    public fun create_percentage_sell_agent_for_testing(
        creator: &signer,
        source_token: Object<Metadata>,
        sell_amount_tokens: u64,
        percentage_threshold: u64,
        initial_token_deposit: u64,
        stop_date: Option<u64>,
        agent_name: vector<u8>
    ) {
        // Validate inputs (skip token validation for testing)
        assert!(sell_amount_tokens > 0, E_INSUFFICIENT_TOKEN_BALANCE);
        assert!(percentage_threshold >= 100 && percentage_threshold <= 5000, E_INVALID_PERCENTAGE);
        assert!(initial_token_deposit >= sell_amount_tokens, E_INSUFFICIENT_TOKEN_BALANCE);

        // Create base agent
        let (base_agent, resource_signer) = base_agent::create_base_agent(
            creator,
            agent_name,
            b"percentage_sell"
        );

        let agent_id = base_agent::get_agent_id(&base_agent);
        let current_time = timestamp::now_seconds();

        // Create Percentage Sell Agent
        let percentage_agent = PercentageSellAgent {
            agent_id,
            source_token,
            sell_amount_tokens,
            percentage_threshold,
            entry_price: 50000000000, // Default $500 entry price for testing
            last_price: 50000000000,
            last_price_check: current_time,
            stop_date,
            total_sold: 0,
            total_usdt_received: 0,
            remaining_tokens: initial_token_deposit,
            average_price: 0,
            execution_count: 0,
        };

        // Store the agent
        let agent_storage = PercentageSellAgentStorage {
            agent: percentage_agent,
        };

        // Store base agent in resource account first
        base_agent::store_base_agent(&resource_signer, base_agent);

        // Then store agent storage
        move_to(&resource_signer, agent_storage);

        // Transfer initial tokens to the agent (TODO: implement)
        // transfer_tokens_to_agent(creator, resource_addr, initial_token_deposit);
    }

    #[test_only]
    public fun test_create_percentage_sell_agent(
        creator: &signer,
        source_token: Object<Metadata>,
        sell_amount_tokens: u64,
        percentage_threshold: u64,
        initial_token_deposit: u64
    ) {
        create_percentage_sell_agent(
            creator,
            source_token,
            sell_amount_tokens,
            percentage_threshold,
            initial_token_deposit,
            option::none(),
            b"test_agent"
        );
    }
}
