/// DCA Sell Agent Contract
///
/// This contract implements Dollar Cost Averaging (DCA) Sell functionality for autonomous
/// token sales at regular intervals. It supports:
/// - APT, WETH, WBTC, USDC source tokens
/// - USDT as the target currency
/// - Integration with KanaLabs aggregator for blazing fast swaps
/// - Sub-250ms execution via keeper system
/// - Gas sponsorship for first 10 agents per user

module recadence::dca_sell_agent {
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
    /// Not time for next execution
    const E_NOT_TIME_FOR_EXECUTION: u64 = 3;
    /// Invalid source token
    const E_INVALID_SOURCE_TOKEN: u64 = 4;
    /// DEX swap failed
    const E_SWAP_FAILED: u64 = 5;
    /// Not authorized to execute
    const E_NOT_AUTHORIZED: u64 = 6;

    // ================================================================================================
    // Constants
    // ================================================================================================

    /// Supported token addresses (testnet)
    const APT_TOKEN: address = @0x1;
    const USDC_TOKEN: address = @0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832;
    const USDT_TOKEN: address = @0x357b0b74bc833e95a115ad22604854d6b0fca151cecd94111770e5d6ffc9dc2b;

    /// Gas buffer for operations
    const GAS_BUFFER: u64 = 1000000; // 0.01 APT

    // ================================================================================================
    // Timing Constants
    // ================================================================================================

    /// Timing unit types
    const TIMING_UNIT_MINUTES: u8 = 0;
    const TIMING_UNIT_HOURS: u8 = 1;
    const TIMING_UNIT_WEEKS: u8 = 2;
    const TIMING_UNIT_MONTHS: u8 = 3;

    /// Minimum intervals for each unit type
    const MIN_MINUTES: u64 = 15;
    const MAX_MINUTES: u64 = 30;
    const MIN_HOURS: u64 = 1;
    const MAX_HOURS: u64 = 12;
    const MIN_WEEKS: u64 = 1;
    const MAX_WEEKS: u64 = 2;
    const MIN_MONTHS: u64 = 1;
    const MAX_MONTHS: u64 = 6;

    /// Time conversion constants (seconds)
    const SECONDS_PER_MINUTE: u64 = 60;
    const SECONDS_PER_HOUR: u64 = 3600;
    const SECONDS_PER_DAY: u64 = 86400;
    const SECONDS_PER_WEEK: u64 = 604800;
    const SECONDS_PER_MONTH: u64 = 2592000; // 30 days average

    // ================================================================================================
    // Data Structures
    // ================================================================================================

    /// Flexible timing configuration
    struct TimingConfig has store, copy, drop {
        /// Unit type: 0=minutes, 1=hours, 2=weeks, 3=months
        unit: u8,
        /// Value within the unit's allowed range
        value: u64,
    }

    /// DCA Sell Agent configuration
    struct DCASellAgent has key, store, copy, drop {
        /// Agent ID reference
        agent_id: u64,
        /// Source token to sell (APT, WETH, WBTC, USDC)
        source_token: Object<Metadata>,
        /// Amount of source token to sell per execution
        sell_amount_tokens: u64,
        /// Flexible timing configuration
        timing: TimingConfig,
        /// Last execution timestamp
        last_execution: u64,
        /// Optional stop date (timestamp)
        stop_date: Option<u64>,
        /// Total amount sold (in source tokens)
        total_sold: u64,
        /// Total USDT received from sales
        total_usdt_received: u64,
        /// Remaining source token balance
        remaining_tokens: u64,
        /// Average price received (USDT per source token, scaled by 1e8)
        average_price: u64,
        /// Total number of executions
        execution_count: u64,
    }

    /// Agent storage resource
    struct DCASellAgentStorage has key {
        /// The DCA sell agent instance
        agent: DCASellAgent,
    }

    // ================================================================================================
    // Events
    // ================================================================================================

    #[event]
    struct DCASellAgentCreatedEvent has drop, store {
        agent_id: u64,
        creator: address,
        source_token: address,
        sell_amount_tokens: u64,
        timing_unit: u8,
        timing_value: u64,
        stop_date: Option<u64>,
        created_at: u64,
    }

    #[event]
    struct DCASellExecutedEvent has drop, store {
        agent_id: u64,
        creator: address,
        source_token: address,
        tokens_sold: u64,
        usdt_received: u64,
        execution_price: u64,
        executed_at: u64,
        execution_count: u64,
    }

    #[event]
    struct DCASellAgentStoppedEvent has drop, store {
        agent_id: u64,
        creator: address,
        reason: vector<u8>,
        stopped_at: u64,
    }

    #[event]
    struct FundsWithdrawnEvent has drop, store {
        agent_id: u64,
        creator: address,
        tokens_withdrawn: u64,
        usdt_withdrawn: u64,
        withdrawn_at: u64,
    }

    // ================================================================================================
    // Agent Creation
    // ================================================================================================

    /// Create a new DCA Sell agent
    public entry fun create_dca_sell_agent(
        creator: &signer,
        source_token: Object<Metadata>,
        sell_amount_tokens: u64,
        timing_unit: u8,
        timing_value: u64,
        initial_token_deposit: u64,
        stop_date: Option<u64>,
        agent_name: vector<u8>
    ) {
        let creator_addr = signer::address_of(creator);

        // Validate inputs
        assert!(is_supported_token(source_token), E_INVALID_SOURCE_TOKEN);
        assert!(is_valid_timing(timing_unit, timing_value), E_NOT_TIME_FOR_EXECUTION);
        assert!(sell_amount_tokens > 0, E_INSUFFICIENT_TOKEN_BALANCE);
        assert!(initial_token_deposit >= sell_amount_tokens, E_INSUFFICIENT_TOKEN_BALANCE);

        // Create base agent (now returns base_agent and resource_signer)
        let (base_agent, resource_signer) = base_agent::create_base_agent(
            creator,
            agent_name,
            b"dca_sell"
        );

        let current_time = timestamp::now_seconds();

        // Create DCA Sell agent
        let timing_config = TimingConfig {
            unit: timing_unit,
            value: timing_value,
        };

        let agent_id = base_agent::get_agent_id(&base_agent);
        let resource_addr = base_agent::get_resource_address(&base_agent);

        let dca_agent = DCASellAgent {
            agent_id,
            source_token,
            sell_amount_tokens,
            timing: timing_config,
            last_execution: 0, // Will execute immediately on first trigger
            stop_date,
            total_sold: 0,
            total_usdt_received: 0,
            remaining_tokens: initial_token_deposit,
            average_price: 0,
            execution_count: 0,
        };

        // Store the agent
        let agent_storage = DCASellAgentStorage {
            agent: dca_agent,
        };

        // Store base agent in resource account first
        base_agent::store_base_agent(&resource_signer, base_agent);

        // Then store agent storage
        move_to(&resource_signer, agent_storage);

        // Transfer initial tokens to agent
        transfer_tokens_to_agent(creator, resource_addr, source_token, initial_token_deposit);

        // Register agent in global registry
        // Register with platform
        agent_registry::register_agent(
            creator,
            b"dca_sell",
            agent_name,
            resource_addr
        );

        // Emit creation event
        event::emit(DCASellAgentCreatedEvent {
            agent_id,
            creator: creator_addr,
            source_token: object::object_address(&source_token),
            sell_amount_tokens,
            timing_unit,
            timing_value,
            stop_date,
            created_at: current_time,
        });
    }

    // ================================================================================================
    // Agent Execution
    // ================================================================================================

    /// Execute DCA sell operation (called by keeper or creator)
    public entry fun execute_dca_sell(
        executor: &signer,
        agent_resource_addr: address
    ) acquires DCASellAgentStorage {
        let storage = borrow_global_mut<DCASellAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        // Verify agent is active
        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        assert!(base_agent::is_agent_active(resource_addr), E_AGENT_NOT_ACTIVE);

        let current_time = timestamp::now_seconds();

        // Check if it's time for execution
        let time_since_last = current_time - agent.last_execution;
        let required_interval = calculate_interval_seconds(agent.timing.unit, agent.timing.value);
        assert!(time_since_last >= required_interval, E_NOT_TIME_FOR_EXECUTION);

        // Check if agent should stop due to date
        if (option::is_some(&agent.stop_date)) {
            let stop_time = *option::borrow(&agent.stop_date);
            if (current_time >= stop_time) {
                pause_agent_internal(agent, b"Stop date reached");
                return
            };
        };

        // Check if sufficient token balance
        if (agent.remaining_tokens < agent.sell_amount_tokens) {
            pause_agent_internal(agent, b"Insufficient token balance");
            return
        };

        // Execute the sale
        let usdt_received = execute_swap_token_to_usdt(
            agent_resource_addr,
            agent.source_token,
            agent.sell_amount_tokens
        );

        // Update agent state
        agent.remaining_tokens = agent.remaining_tokens - agent.sell_amount_tokens;
        agent.total_sold = agent.total_sold + agent.sell_amount_tokens;
        agent.total_usdt_received = agent.total_usdt_received + usdt_received;
        agent.execution_count = agent.execution_count + 1;
        agent.last_execution = current_time;

        // Update average price (weighted)
        let sell_amount = agent.sell_amount_tokens;
        update_average_price(agent, sell_amount, usdt_received);

        // Increment transaction count in base agent
        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        base_agent::increment_transaction_count_by_addr(resource_addr);

        // Update registry transaction count
        agent_registry::update_transaction_count(
            agent.agent_id,
            {
                let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
                base_agent::get_total_transactions_by_addr(resource_addr)
            }
        );

        // Emit execution event
        let execution_price = if (agent.sell_amount_tokens > 0) {
            (usdt_received * 100000000) / agent.sell_amount_tokens // Price with 8 decimal places
        } else { 0 };

        event::emit(DCASellExecutedEvent {
            agent_id: agent.agent_id,
            creator: {
                let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
                base_agent::get_agent_creator(resource_addr)
            },
            source_token: object::object_address(&agent.source_token),
            tokens_sold: agent.sell_amount_tokens,
            usdt_received,
            execution_price,
            executed_at: current_time,
            execution_count: agent.execution_count,
        });
    }

    // ================================================================================================
    // Agent Management
    // ================================================================================================

    /// Pause the DCA sell agent
    public entry fun pause_dca_sell_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires DCASellAgentStorage {
        let storage = borrow_global_mut<DCASellAgentStorage>(agent_resource_addr);
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

    /// Resume the DCA sell agent
    public entry fun resume_dca_sell_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires DCASellAgentStorage {
        let storage = borrow_global_mut<DCASellAgentStorage>(agent_resource_addr);
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

    /// Withdraw remaining funds and delete agent
    public entry fun withdraw_and_delete_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires DCASellAgentStorage {
        let storage = borrow_global_mut<DCASellAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        // Verify creator authorization
        let creator_addr = signer::address_of(creator);
        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        assert!(base_agent::get_agent_creator(resource_addr) == creator_addr, E_NOT_AUTHORIZED);

        let agent_id = agent.agent_id;

        // Withdraw all remaining funds
        let tokens_withdrawn = withdraw_tokens_from_agent(
            agent_resource_addr,
            creator_addr,
            agent.source_token,
            agent.remaining_tokens
        );
        let usdt_withdrawn = withdraw_usdt_from_agent(agent_resource_addr, creator_addr);

        // Mark agent as deleted
        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        base_agent::delete_agent_by_addr(resource_addr, creator);

        // Update registry status
        agent_registry::update_agent_status(agent_id, creator, false);

        // Emit withdrawal event
        event::emit(FundsWithdrawnEvent {
            agent_id,
            creator: creator_addr,
            tokens_withdrawn,
            usdt_withdrawn,
            withdrawn_at: timestamp::now_seconds(),
        });
    }

    // ================================================================================================
    // Internal Functions
    // ================================================================================================



    /// Internal function to pause agent with reason
    fun pause_agent_internal(agent: &mut DCASellAgent, reason: vector<u8>) {
        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        let old_state = base_agent::get_agent_state(resource_addr);
        if (old_state == 1) { // Only pause if currently active
            // Note: We can't call base_agent::pause_agent here without a signer
            // This would need to be handled by the keeper system
            event::emit(DCASellAgentStoppedEvent {
                agent_id: agent.agent_id,
                creator: base_agent::get_agent_creator(resource_addr),
                reason,
                stopped_at: timestamp::now_seconds(),
            });
        };
    }

    /// Update the weighted average price
    fun update_average_price(agent: &mut DCASellAgent, tokens_sold: u64, usdt_received: u64) {
        if (tokens_sold == 0) return;

        let previous_total_value = agent.average_price * (agent.total_sold - tokens_sold);
        let current_sale_value = (usdt_received * 100000000) / tokens_sold * tokens_sold;
        let new_total_value = previous_total_value + current_sale_value;

        agent.average_price = new_total_value / agent.total_sold;
    }

    /// Execute swap from source token to USDT using KanaLabs aggregator
    fun execute_swap_token_to_usdt(
        agent_addr: address,
        source_token: Object<Metadata>,
        token_amount: u64
    ): u64 {
        // TODO: Implement KanaLabs aggregator integration
        // This will use the blazing fast KanaLabs API for optimal routing
        //
        // Implementation steps:
        // 1. Get quote from KanaLabs API: ag.kanalabs.io/quotes
        // 2. Execute swap instruction through KanaLabs SDK
        // 3. Handle slippage protection and route optimization
        // 4. Return actual USDT received
        //
        // KanaLabs provides:
        // - Best price aggregation across all Aptos DEXs
        // - Sub-second execution times
        // - Automatic route optimization
        // - Minimal slippage protection

        // Mock calculation for now: assume 1 source token = 10 USDT
        // Replace with actual KanaLabs integration
        token_amount * 10
    }

    /// Transfer tokens to agent using fungible assets
    fun transfer_tokens_to_agent(
        from: &signer,
        to: address,
        token: Object<Metadata>,
        amount: u64
    ) {
        // TODO: Implement actual token transfer using fungible assets
        // This will use primary_fungible_store::transfer with token metadata
        // primary_fungible_store::transfer(from, token, to, amount);
    }

    /// Withdraw tokens from agent using fungible assets
    fun withdraw_tokens_from_agent(
        agent_addr: address,
        to: address,
        token: Object<Metadata>,
        amount: u64
    ): u64 {
        // TODO: Implement actual token withdrawal using fungible assets
        // This will transfer remaining source tokens from agent to user
        // primary_fungible_store::transfer(&agent_signer, token, to, amount);
        // Return actual amount withdrawn
        amount
    }

    /// Withdraw USDT from agent using fungible assets
    fun withdraw_usdt_from_agent(agent_addr: address, to: address): u64 {
        // TODO: Implement actual USDT withdrawal using fungible assets
        // This will transfer all accumulated USDT from agent to user
        // let usdt_metadata = object::address_to_object<Metadata>(USDT_TOKEN);
        // primary_fungible_store::transfer(&agent_signer, usdt_metadata, to, balance);
        // Return actual amount withdrawn
        0
    }

    /// Check if token is supported
    fun is_supported_token(token: Object<Metadata>): bool {
        let token_addr = object::object_address(&token);
        token_addr == APT_TOKEN ||
        token_addr == USDC_TOKEN ||
        token_addr == USDT_TOKEN
    }

    // ================================================================================================
    // View Functions
    // ================================================================================================

    #[view]
    /// Get DCA sell agent information
    public fun get_dca_sell_agent_info(agent_resource_addr: address): (
        u64, // agent_id
        address, // creator
        address, // source_token
        u64, // sell_amount_tokens
        u8, // timing_unit
        u64, // timing_value
        u64, // total_sold
        u64, // total_usdt_received
        u64, // remaining_tokens
        u64, // average_price
        u64, // execution_count
        Option<u64>, // stop_date
        u64, // last_execution
    ) acquires DCASellAgentStorage {
        let storage = borrow_global<DCASellAgentStorage>(agent_resource_addr);
        let agent = &storage.agent;

        (
            agent.agent_id,
            {
                let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
                base_agent::get_agent_creator(resource_addr)
            },
            object::object_address(&agent.source_token),
            agent.sell_amount_tokens,
            agent.timing.unit,
            agent.timing.value,
            agent.total_sold,
            agent.total_usdt_received,
            agent.remaining_tokens,
            agent.average_price,
            agent.execution_count,
            agent.stop_date,
            agent.last_execution,
        )
    }

    #[view]
    /// Check if agent is ready for execution
    public fun is_ready_for_execution(agent_resource_addr: address): bool acquires DCASellAgentStorage {
        let storage = borrow_global<DCASellAgentStorage>(agent_resource_addr);
        let agent = &storage.agent;

        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        if (!base_agent::is_agent_active(resource_addr)) {
            return false
        };

        let current_time = timestamp::now_seconds();

        // Check stop date
        if (option::is_some(&agent.stop_date)) {
            let stop_time = *option::borrow(&agent.stop_date);
            if (current_time >= stop_time) {
                return false
            };
        };

        // Check time interval
        let time_since_last = current_time - agent.last_execution;
        let required_interval = calculate_interval_seconds(agent.timing.unit, agent.timing.value);

        // Check balance
        let has_sufficient_balance = agent.remaining_tokens >= agent.sell_amount_tokens;

        time_since_last >= required_interval && has_sufficient_balance
    }

    // ================================================================================================
    // Timing Validation and Calculation Functions
    // ================================================================================================

    /// Validates timing configuration based on allowed ranges
    fun is_valid_timing(unit: u8, value: u64): bool {
        if (unit == TIMING_UNIT_MINUTES) {
            value == MIN_MINUTES || value == MAX_MINUTES
        } else if (unit == TIMING_UNIT_HOURS) {
            value >= MIN_HOURS && value <= MAX_HOURS
        } else if (unit == TIMING_UNIT_WEEKS) {
            value >= MIN_WEEKS && value <= MAX_WEEKS
        } else if (unit == TIMING_UNIT_MONTHS) {
            value >= MIN_MONTHS && value <= MAX_MONTHS
        } else {
            false
        }
    }

    /// Calculates interval in seconds based on timing configuration
    fun calculate_interval_seconds(unit: u8, value: u64): u64 {
        if (unit == TIMING_UNIT_MINUTES) {
            value * SECONDS_PER_MINUTE
        } else if (unit == TIMING_UNIT_HOURS) {
            value * SECONDS_PER_HOUR
        } else if (unit == TIMING_UNIT_WEEKS) {
            value * SECONDS_PER_WEEK
        } else if (unit == TIMING_UNIT_MONTHS) {
            value * SECONDS_PER_MONTH
        } else {
            0 // Invalid unit
        }
    }

    /// Helper function to get timing display info
    public fun get_timing_info(unit: u8, value: u64): (vector<u8>, u64) {
        let unit_name = if (unit == TIMING_UNIT_MINUTES) {
            b"minutes"
        } else if (unit == TIMING_UNIT_HOURS) {
            b"hours"
        } else if (unit == TIMING_UNIT_WEEKS) {
            b"weeks"
        } else if (unit == TIMING_UNIT_MONTHS) {
            b"months"
        } else {
            b"unknown"
        };
        (unit_name, value)
    }

    #[view]
    /// Get supported tokens
    public fun get_supported_tokens(): vector<address> {
        vector[APT_TOKEN, USDC_TOKEN, USDT_TOKEN]
    }

    // ================================================================================================
    // Test Functions (dev only)
    // ================================================================================================

    #[test_only]
    public fun test_create_dca_sell_agent(
        creator: &signer,
        source_token: Object<Metadata>,
        sell_amount_tokens: u64,
        timing_unit: u8,
        timing_value: u64,
        initial_token_deposit: u64
    ) {
        create_dca_sell_agent(
            creator,
            source_token,
            sell_amount_tokens,
            timing_unit,
            timing_value,
            initial_token_deposit,
            option::none(),
            b"test_agent"
        );
    }
}
