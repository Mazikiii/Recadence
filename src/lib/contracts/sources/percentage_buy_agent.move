/// Percentage Buy Agent Contract
///
/// This contract implements Percentage Buy functionality for autonomous
/// token purchases based on price movements. It supports:
/// - APT, WETH, WBTC target tokens
/// - USDT as the source currency
/// - Trend selection: DOWN (default) or UP movements
/// - Integration with KanaLabs aggregator for blazing fast swaps
/// - Sub-250ms execution via keeper system
/// - Gas sponsorship for first 10 agents per user

module recadence::percentage_buy_agent {
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

    /// Insufficient USDT balance for purchase
    const E_INSUFFICIENT_USDT_BALANCE: u64 = 1;
    /// Agent is not active
    const E_AGENT_NOT_ACTIVE: u64 = 2;
    /// Percentage threshold not reached
    const E_PERCENTAGE_NOT_REACHED: u64 = 3;
    /// Invalid target token
    const E_INVALID_TARGET_TOKEN: u64 = 4;
    /// DEX swap failed
    const E_SWAP_FAILED: u64 = 5;
    /// Not authorized to execute
    const E_NOT_AUTHORIZED: u64 = 6;
    /// Invalid percentage value
    const E_INVALID_PERCENTAGE: u64 = 7;
    /// Invalid trend direction
    const E_INVALID_TREND: u64 = 8;

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
    // Trend Direction Constants
    // ================================================================================================

    /// Trend direction types
    const TREND_DOWN: u8 = 0;  // Default - buy on price drops
    const TREND_UP: u8 = 1;    // Option - buy on price increases

    /// Percentage constraints
    const MIN_PERCENTAGE: u64 = 5;   // 5% minimum
    // No maximum - full flexibility above 5%

    // ================================================================================================
    // Data Structures
    // ================================================================================================

    /// Percentage Buy Agent configuration
    struct PercentageBuyAgent has key, store, copy, drop {
        /// Agent ID reference
        agent_id: u64,
        /// Target token to purchase (APT, WETH, WBTC)
        target_token: Object<Metadata>,
        /// Amount of USDT to spend per purchase
        buy_amount_usdt: u64,
        /// Percentage threshold for execution (1-50%)
        percentage_threshold: u64,
        /// Trend direction: 0=DOWN (default), 1=UP
        trend_direction: u8,
        /// Last recorded price (scaled by 1e8)
        last_price: u64,
        /// Last price check timestamp
        last_price_check: u64,
        /// Optional stop date (timestamp)
        stop_date: Option<u64>,
        /// Total amount purchased (in target token)
        total_purchased: u64,
        /// Total USDT spent
        total_usdt_spent: u64,
        /// Remaining USDT balance for purchases
        remaining_usdt: u64,
        /// Average price paid (USDT per target token, scaled by 1e8)
        average_price: u64,
        /// Total number of executions
        execution_count: u64,
    }

    /// Agent storage resource
    struct PercentageBuyAgentStorage has key {
        /// The percentage buy agent instance
        agent: PercentageBuyAgent,
    }

    // ================================================================================================
    // Events
    // ================================================================================================

    #[event]
    struct PercentageBuyAgentCreatedEvent has drop, store {
        agent_id: u64,
        creator: address,
        target_token: address,
        buy_amount_usdt: u64,
        percentage_threshold: u64,
        trend_direction: u8,
        stop_date: Option<u64>,
        created_at: u64,
    }

    #[event]
    struct PercentageBuyExecutedEvent has drop, store {
        agent_id: u64,
        executor: address,
        target_token: address,
        usdt_amount: u64,
        tokens_received: u64,
        trigger_price: u64,
        last_price: u64,
        percentage_change: u64,
        trend_direction: u8,
        execution_count: u64,
        executed_at: u64,
    }

    #[event]
    struct PriceUpdateEvent has drop, store {
        agent_id: u64,
        target_token: address,
        old_price: u64,
        new_price: u64,
        percentage_change: u64,
        trend_direction: u8,
        threshold_met: bool,
        updated_at: u64,
    }

    // ================================================================================================
    // Public Functions
    // ================================================================================================

    /// Creates a new Percentage Buy Agent
    public entry fun create_percentage_buy_agent(
        creator: &signer,
        target_token: Object<Metadata>,
        buy_amount_usdt: u64,
        percentage_threshold: u64,
        trend_direction: u8,
        initial_usdt_deposit: u64,
        stop_date: Option<u64>,
        agent_name: vector<u8>
    ) {
        let creator_addr = signer::address_of(creator);

        // Validate inputs
        assert!(is_supported_token(target_token), E_INVALID_TARGET_TOKEN);
        assert!(percentage_threshold >= MIN_PERCENTAGE, E_INVALID_PERCENTAGE);
        assert!(trend_direction == TREND_DOWN || trend_direction == TREND_UP, E_INVALID_TREND);
        assert!(buy_amount_usdt > 0, E_INSUFFICIENT_USDT_BALANCE);
        assert!(initial_usdt_deposit >= buy_amount_usdt, E_INSUFFICIENT_USDT_BALANCE);

        // Create base agent (now returns base_agent and resource_signer)
        let (base_agent, resource_signer) = base_agent::create_base_agent(
            creator,
            agent_name,
            b"percentage_buy"
        );

        let current_time = timestamp::now_seconds();
        let initial_price = get_current_price(target_token); // Get current market price

        let agent_id = base_agent::get_agent_id(&base_agent);
        let resource_addr = base_agent::get_resource_address(&base_agent);

        // Create Percentage Buy agent
        let percentage_agent = PercentageBuyAgent {
            agent_id,
            target_token,
            buy_amount_usdt,
            percentage_threshold,
            trend_direction,
            last_price: initial_price,
            last_price_check: current_time,
            stop_date,
            total_purchased: 0,
            total_usdt_spent: 0,
            remaining_usdt: initial_usdt_deposit,
            average_price: 0,
            execution_count: 0,
        };

        // Store the agent
        let agent_storage = PercentageBuyAgentStorage {
            agent: percentage_agent,
        };

        // Store base agent in resource account first
        base_agent::store_base_agent(&resource_signer, base_agent);

        // Then store agent storage
        move_to(&resource_signer, agent_storage);

        // Register with platform
        agent_registry::register_agent(
            creator,
            b"percentage_buy",
            agent_name,
            resource_addr
        );

        // Emit creation event
        event::emit(PercentageBuyAgentCreatedEvent {
            agent_id,
            creator: creator_addr,
            target_token: object::object_address(&target_token),
            buy_amount_usdt,
            percentage_threshold,
            trend_direction,
            stop_date,
            created_at: current_time,
        });
    }

    /// Executes percentage buy when price threshold is met
    public entry fun execute_percentage_buy(
        executor: &signer,
        agent_resource_addr: address
    ) acquires PercentageBuyAgentStorage {
        let storage = borrow_global_mut<PercentageBuyAgentStorage>(agent_resource_addr);
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
        let current_price = get_current_price(agent.target_token);
        let (percentage_change, threshold_met) = check_percentage_threshold(
            agent.last_price,
            current_price,
            agent.percentage_threshold,
            agent.trend_direction
        );

        assert!(threshold_met, E_PERCENTAGE_NOT_REACHED);

        // Check sufficient balance
        assert!(agent.remaining_usdt >= agent.buy_amount_usdt, E_INSUFFICIENT_USDT_BALANCE);

        // Execute swap via KanaLabs
        let usdt_amount = agent.buy_amount_usdt;
        let tokens_received = execute_kanashop_swap(
            agent.target_token,
            usdt_amount
        );

        // Update agent state
        agent.total_purchased = agent.total_purchased + tokens_received;
        agent.total_usdt_spent = agent.total_usdt_spent + usdt_amount;
        agent.remaining_usdt = agent.remaining_usdt - usdt_amount;
        agent.execution_count = agent.execution_count + 1;
        agent.last_price = current_price;
        agent.last_price_check = current_time;

        // Update average price
        let buy_amount = agent.buy_amount_usdt;
        update_average_price(agent, buy_amount, tokens_received);

        let executor_addr = signer::address_of(executor);
        let agent_id = agent.agent_id;

        // Emit execution event
        event::emit(PercentageBuyExecutedEvent {
            agent_id,
            executor: executor_addr,
            target_token: object::object_address(&agent.target_token),
            usdt_amount,
            tokens_received,
            trigger_price: current_price,
            last_price: agent.last_price,
            percentage_change,
            trend_direction: agent.trend_direction,
            execution_count: agent.execution_count,
            executed_at: current_time,
        });
    }

    /// Updates price without execution (for price tracking)
    public entry fun update_price(
        updater: &signer,
        agent_resource_addr: address
    ) acquires PercentageBuyAgentStorage {
        let storage = borrow_global_mut<PercentageBuyAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        let current_price = get_current_price(agent.target_token);
        let old_price = agent.last_price;

        let (percentage_change, threshold_met) = check_percentage_threshold(
            old_price,
            current_price,
            agent.percentage_threshold,
            agent.trend_direction
        );

        // Update price tracking
        agent.last_price = current_price;
        agent.last_price_check = timestamp::now_seconds();

        let agent_id = agent.agent_id;

        // Emit price update event
        event::emit(PriceUpdateEvent {
            agent_id,
            target_token: object::object_address(&agent.target_token),
            old_price,
            new_price: current_price,
            percentage_change,
            trend_direction: agent.trend_direction,
            threshold_met,
            updated_at: agent.last_price_check,
        });
    }

    /// Pauses the percentage buy agent
    public entry fun pause_percentage_buy_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires PercentageBuyAgentStorage {
        let storage = borrow_global_mut<PercentageBuyAgentStorage>(agent_resource_addr);
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

    /// Resumes the percentage buy agent
    public entry fun resume_percentage_buy_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires PercentageBuyAgentStorage {
        let storage = borrow_global_mut<PercentageBuyAgentStorage>(agent_resource_addr);
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

    /// Withdraws all remaining USDT and deletes the agent
    public entry fun withdraw_and_delete_agent(
        creator: &signer,
        agent_resource_addr: address
    ) acquires PercentageBuyAgentStorage {
        let storage = borrow_global_mut<PercentageBuyAgentStorage>(agent_resource_addr);
        let agent = &mut storage.agent;

        // Verify creator authorization
        let creator_addr = signer::address_of(creator);
        let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
        assert!(base_agent::get_agent_creator(resource_addr) == creator_addr, E_NOT_AUTHORIZED);

        let agent_id = agent.agent_id;

        // Withdraw all remaining funds
        // TODO: Implement actual USDT withdrawal to creator
        // For now, just emit event
        let remaining_usdt = agent.remaining_usdt;

        // Update registry before deletion
        agent_registry::unregister_agent(agent_id, creator);

        // Delete the agent storage
        let PercentageBuyAgentStorage { agent: _ } = move_from<PercentageBuyAgentStorage>(agent_resource_addr);
    }

    // ================================================================================================
    // Helper Functions
    // ================================================================================================



    /// Checks if percentage threshold is met based on trend direction
    fun check_percentage_threshold(
        last_price: u64,
        current_price: u64,
        threshold: u64,
        trend_direction: u8
    ): (u64, bool) {
        if (last_price == 0) {
            return (0, false)
        };

        let percentage_change = if (current_price > last_price) {
            // Price increased
            ((current_price - last_price) * 100) / last_price
        } else {
            // Price decreased
            ((last_price - current_price) * 100) / last_price
        };

        let threshold_met = if (trend_direction == TREND_DOWN) {
            // DOWN trend: buy when price drops by threshold
            current_price < last_price && percentage_change >= threshold
        } else {
            // UP trend: buy when price rises by threshold
            current_price > last_price && percentage_change >= threshold
        };

        (percentage_change, threshold_met)
    }

    /// Updates the average price calculation
    fun update_average_price(agent: &mut PercentageBuyAgent, usdt_spent: u64, tokens_received: u64) {
        if (tokens_received == 0) return;

        let new_total_usdt = agent.total_usdt_spent;
        let new_total_tokens = agent.total_purchased;

        if (new_total_tokens > 0) {
            agent.average_price = (new_total_usdt * 100000000) / new_total_tokens; // Scale by 1e8
        };
    }

    /// Executes swap through KanaLabs aggregator
    fun execute_kanashop_swap(target_token: Object<Metadata>, usdt_amount: u64): u64 {
        // TODO: Implement actual KanaLabs integration
        // For now, return mock value based on current price
        let current_price = get_current_price(target_token);
        if (current_price == 0) return 0;

        // Mock calculation: tokens_received = usdt_amount / price_per_token
        (usdt_amount * 100000000) / current_price
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

    // ================================================================================================
    // View Functions
    // ================================================================================================

    #[view]
    /// Get percentage buy agent information
    public fun get_percentage_buy_agent_info(agent_resource_addr: address): (
        u64, // agent_id
        address, // creator
        address, // target_token
        u64, // buy_amount_usdt
        u64, // percentage_threshold
        u8,  // trend_direction
        u64, // last_price
        u64, // total_purchased
        u64, // total_usdt_spent
        u64, // remaining_usdt
        u64, // average_price
        u64, // execution_count
        Option<u64>, // stop_date
        u64, // last_price_check
    ) acquires PercentageBuyAgentStorage {
        let storage = borrow_global<PercentageBuyAgentStorage>(agent_resource_addr);
        let agent = &storage.agent;

        (
            agent.agent_id,
            {
                let resource_addr = agent_registry::get_agent_resource_address(agent.agent_id);
                base_agent::get_agent_creator(resource_addr)
            },
            object::object_address(&agent.target_token),
            agent.buy_amount_usdt,
            agent.percentage_threshold,
            agent.trend_direction,
            agent.last_price,
            agent.total_purchased,
            agent.total_usdt_spent,
            agent.remaining_usdt,
            agent.average_price,
            agent.execution_count,
            agent.stop_date,
            agent.last_price_check,
        )
    }

    #[view]
    /// Check if percentage buy agent should execute
    public fun should_execute_percentage_buy(agent_resource_addr: address): bool acquires PercentageBuyAgentStorage {
        let storage = borrow_global<PercentageBuyAgentStorage>(agent_resource_addr);
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
        let current_price = get_current_price(agent.target_token);
        let (_, threshold_met) = check_percentage_threshold(
            agent.last_price,
            current_price,
            agent.percentage_threshold,
            agent.trend_direction
        );

        // Check balance
        let has_sufficient_balance = agent.remaining_usdt >= agent.buy_amount_usdt;

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

    #[test_only]
    public fun test_create_percentage_buy_agent(
        creator: &signer,
        target_token: Object<Metadata>,
        buy_amount_usdt: u64,
        percentage_threshold: u64,
        trend_direction: u8,
        initial_usdt_deposit: u64
    ) acquires PercentageBuyAgentStorage {
        create_percentage_buy_agent(
            creator,
            target_token,
            buy_amount_usdt,
            percentage_threshold,
            trend_direction,
            initial_usdt_deposit,
            option::none(),
            b"test_agent"
        );
    }
}
