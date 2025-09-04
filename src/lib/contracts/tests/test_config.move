/// Test Configuration Module
///
/// Centralized configuration for all test modules in the Recadence platform.
/// This module provides:
/// - Test parameters and constants
/// - Environment configuration
/// - Mock data templates
/// - Test utility functions
/// - Coverage tracking helpers

module recadence::test_config {
    use std::vector;
    use std::option::{Self, Option};
    use std::string::{Self, String};

    // ================================================================================================
    // Test Environment Constants
    // ================================================================================================

    /// Test network configuration
    const TEST_NETWORK: vector<u8> = b"testnet";

    /// Maximum test execution time (seconds)
    const MAX_TEST_EXECUTION_TIME: u64 = 300;

    /// Test coverage target percentage
    const TARGET_COVERAGE_PERCENT: u8 = 95;

    // ================================================================================================
    // Agent Configuration Constants
    // ================================================================================================

    /// Maximum agents per user for testing
    const MAX_AGENTS_PER_USER: u64 = 10;

    /// Gas sponsorship limit for testing
    const GAS_SPONSORSHIP_LIMIT: u64 = 10;

    /// Minimum test amounts
    const MIN_TEST_AMOUNT: u64 = 1000000; // 0.01 tokens

    /// Maximum test amounts
    const MAX_TEST_AMOUNT: u64 = 1000000000000; // 10,000 tokens

    /// Default test amounts
    const DEFAULT_USDT_AMOUNT: u64 = 10000000000; // 100 USDT
    const DEFAULT_APT_AMOUNT: u64 = 1000000000; // 10 APT
    const DEFAULT_BUY_AMOUNT: u64 = 50000000; // 50 USDT
    const DEFAULT_SELL_AMOUNT: u64 = 1000000000; // 10 tokens

    // ================================================================================================
    // Timing Configuration for Tests
    // ================================================================================================

    /// Test timing units
    const TEST_TIMING_MINUTES: u8 = 0;
    const TEST_TIMING_HOURS: u8 = 1;
    const TEST_TIMING_WEEKS: u8 = 2;
    const TEST_TIMING_MONTHS: u8 = 3;

    /// Valid timing ranges for testing
    const MIN_MINUTES: u64 = 15;
    const MAX_MINUTES: u64 = 30;
    const MIN_HOURS: u64 = 1;
    const MAX_HOURS: u64 = 12;
    const MIN_WEEKS: u64 = 1;
    const MAX_WEEKS: u64 = 2;
    const MIN_MONTHS: u64 = 1;
    const MAX_MONTHS: u64 = 6;

    // ================================================================================================
    // Mock Token Addresses
    // ================================================================================================

    /// Mock token addresses for testing
    const MOCK_APT_ADDR: address = @0x1;
    const MOCK_USDT_ADDR: address = @0x357b0b74bc833e95a115ad22604854d6b0fca151cecd94111770e5d6ffc9dc2b;
    const MOCK_USDC_ADDR: address = @0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832;
    const MOCK_WETH_ADDR: address = @0x1234567890abcdef;
    const MOCK_WBTC_ADDR: address = @0xfedcba0987654321;

    // ================================================================================================
    // Test Account Addresses
    // ================================================================================================

    /// Predefined test account addresses
    const TEST_ADMIN: address = @0x1111111111111111;
    const TEST_USER_1: address = @0x2222222222222222;
    const TEST_USER_2: address = @0x3333333333333333;
    const TEST_USER_3: address = @0x4444444444444444;
    const TEST_KEEPER: address = @0x5555555555555555;
    const TEST_UNAUTHORIZED: address = @0x9999999999999999;

    // ================================================================================================
    // Error Code Testing Configuration
    // ================================================================================================

    /// Expected error codes for testing
    const ERROR_AGENT_LIMIT_EXCEEDED: u64 = 1;
    const ERROR_NOT_AUTHORIZED: u64 = 2;
    const ERROR_AGENT_NOT_ACTIVE: u64 = 3;
    const ERROR_AGENT_NOT_PAUSED: u64 = 4;
    const ERROR_INSUFFICIENT_FUNDS: u64 = 5;
    const ERROR_AGENT_NOT_FOUND: u64 = 6;
    const ERROR_INVALID_STATE_TRANSITION: u64 = 7;
    const ERROR_INVALID_TIMING: u64 = 8;

    // ================================================================================================
    // Test Data Structures
    // ================================================================================================

    /// Test scenario configuration
    struct TestScenario has copy, drop {
        name: vector<u8>,
        description: vector<u8>,
        expected_outcome: u8, // 0 = success, 1 = specific error, 2 = any error
        expected_error_code: Option<u64>,
        timeout_seconds: u64,
    }

    /// Mock price data for testing
    struct MockPriceData has copy, drop {
        token_address: address,
        price_usdt: u64, // Price in USDT with 8 decimals
        timestamp: u64,
        volatility: u64, // Percentage volatility for testing
    }

    /// Test execution metrics
    struct TestMetrics has copy, drop {
        tests_run: u64,
        tests_passed: u64,
        tests_failed: u64,
        coverage_percentage: u64,
        execution_time_ms: u64,
    }

    // ================================================================================================
    // Test Configuration Functions
    // ================================================================================================

    /// Get maximum agents per user for testing
    public fun get_max_agents_per_user(): u64 {
        MAX_AGENTS_PER_USER
    }

    /// Get gas sponsorship limit for testing
    public fun get_gas_sponsorship_limit(): u64 {
        GAS_SPONSORSHIP_LIMIT
    }

    /// Get default test amounts
    public fun get_default_test_amounts(): (u64, u64, u64, u64) {
        (DEFAULT_USDT_AMOUNT, DEFAULT_APT_AMOUNT, DEFAULT_BUY_AMOUNT, DEFAULT_SELL_AMOUNT)
    }

    /// Get mock token addresses
    public fun get_mock_token_addresses(): (address, address, address, address, address) {
        (MOCK_APT_ADDR, MOCK_USDT_ADDR, MOCK_USDC_ADDR, MOCK_WETH_ADDR, MOCK_WBTC_ADDR)
    }

    /// Get test account addresses
    public fun get_test_account_addresses(): (address, address, address, address, address, address) {
        (TEST_ADMIN, TEST_USER_1, TEST_USER_2, TEST_USER_3, TEST_KEEPER, TEST_UNAUTHORIZED)
    }

    /// Get timing configuration bounds
    public fun get_timing_bounds(unit: u8): (u64, u64) {
        if (unit == TEST_TIMING_MINUTES) {
            (MIN_MINUTES, MAX_MINUTES)
        } else if (unit == TEST_TIMING_HOURS) {
            (MIN_HOURS, MAX_HOURS)
        } else if (unit == TEST_TIMING_WEEKS) {
            (MIN_WEEKS, MAX_WEEKS)
        } else if (unit == TEST_TIMING_MONTHS) {
            (MIN_MONTHS, MAX_MONTHS)
        } else {
            (0, 0) // Invalid unit
        }
    }

    // ================================================================================================
    // Test Scenario Generation
    // ================================================================================================

    /// Generate base agent test scenarios
    public fun generate_base_agent_scenarios(): vector<TestScenario> {
        let scenarios = vector::empty<TestScenario>();

        // Success scenarios
        vector::push_back(&mut scenarios, TestScenario {
            name: b"create_agent_success",
            description: b"Successfully create a new agent",
            expected_outcome: 0,
            expected_error_code: option::none(),
            timeout_seconds: 30,
        });

        vector::push_back(&mut scenarios, TestScenario {
            name: b"pause_resume_agent",
            description: b"Successfully pause and resume agent",
            expected_outcome: 0,
            expected_error_code: option::none(),
            timeout_seconds: 30,
        });

        // Error scenarios
        vector::push_back(&mut scenarios, TestScenario {
            name: b"exceed_agent_limit",
            description: b"Fail when creating more than 10 agents",
            expected_outcome: 1,
            expected_error_code: option::some(ERROR_AGENT_LIMIT_EXCEEDED),
            timeout_seconds: 60,
        });

        vector::push_back(&mut scenarios, TestScenario {
            name: b"unauthorized_access",
            description: b"Fail when unauthorized user tries to modify agent",
            expected_outcome: 1,
            expected_error_code: option::some(ERROR_NOT_AUTHORIZED),
            timeout_seconds: 30,
        });

        scenarios
    }

    /// Generate DCA agent test scenarios
    public fun generate_dca_scenarios(): vector<TestScenario> {
        let scenarios = vector::empty<TestScenario>();

        // DCA Buy scenarios
        vector::push_back(&mut scenarios, TestScenario {
            name: b"dca_buy_execution",
            description: b"Successfully execute DCA buy operation",
            expected_outcome: 0,
            expected_error_code: option::none(),
            timeout_seconds: 60,
        });

        vector::push_back(&mut scenarios, TestScenario {
            name: b"dca_sell_execution",
            description: b"Successfully execute DCA sell operation",
            expected_outcome: 0,
            expected_error_code: option::none(),
            timeout_seconds: 60,
        });

        // Error scenarios
        vector::push_back(&mut scenarios, TestScenario {
            name: b"insufficient_balance",
            description: b"Fail when insufficient balance for operation",
            expected_outcome: 1,
            expected_error_code: option::some(ERROR_INSUFFICIENT_FUNDS),
            timeout_seconds: 30,
        });

        vector::push_back(&mut scenarios, TestScenario {
            name: b"invalid_timing",
            description: b"Fail when invalid timing configuration provided",
            expected_outcome: 1,
            expected_error_code: option::some(ERROR_INVALID_TIMING),
            timeout_seconds: 30,
        });

        scenarios
    }

    /// Generate integration test scenarios
    public fun generate_integration_scenarios(): vector<TestScenario> {
        let scenarios = vector::empty<TestScenario>();

        vector::push_back(&mut scenarios, TestScenario {
            name: b"multi_user_limits",
            description: b"Test independent agent limits for multiple users",
            expected_outcome: 0,
            expected_error_code: option::none(),
            timeout_seconds: 120,
        });

        vector::push_back(&mut scenarios, TestScenario {
            name: b"gas_sponsorship_integration",
            description: b"Test gas sponsorship across different agent types",
            expected_outcome: 0,
            expected_error_code: option::none(),
            timeout_seconds: 90,
        });

        vector::push_back(&mut scenarios, TestScenario {
            name: b"platform_statistics",
            description: b"Test platform statistics accuracy with mixed operations",
            expected_outcome: 0,
            expected_error_code: option::none(),
            timeout_seconds: 60,
        });

        scenarios
    }

    // ================================================================================================
    // Mock Data Generation
    // ================================================================================================

    /// Generate mock price data for testing
    public fun generate_mock_price_data(): vector<MockPriceData> {
        let prices = vector::empty<MockPriceData>();

        // APT price data
        vector::push_back(&mut prices, MockPriceData {
            token_address: MOCK_APT_ADDR,
            price_usdt: 1000000000, // $10.00
            timestamp: 1640995200,
            volatility: 500, // 5%
        });

        // USDT price data (stable)
        vector::push_back(&mut prices, MockPriceData {
            token_address: MOCK_USDT_ADDR,
            price_usdt: 100000000, // $1.00
            timestamp: 1640995200,
            volatility: 10, // 0.1%
        });

        // WETH price data
        vector::push_back(&mut prices, MockPriceData {
            token_address: MOCK_WETH_ADDR,
            price_usdt: 300000000000, // $3000.00
            timestamp: 1640995200,
            volatility: 800, // 8%
        });

        // WBTC price data
        vector::push_back(&mut prices, MockPriceData {
            token_address: MOCK_WBTC_ADDR,
            price_usdt: 4500000000000, // $45000.00
            timestamp: 1640995200,
            volatility: 1000, // 10%
        });

        prices
    }

    /// Generate test names for coverage tracking
    public fun generate_test_names(): vector<vector<u8>> {
        let names = vector::empty<vector<u8>>();

        // Base agent tests
        vector::push_back(&mut names, b"test_initialize_platform");
        vector::push_back(&mut names, b"test_create_agent_success");
        vector::push_back(&mut names, b"test_create_multiple_agents_up_to_limit");
        vector::push_back(&mut names, b"test_create_agent_beyond_limit_fails");
        vector::push_back(&mut names, b"test_pause_and_resume_agent");
        vector::push_back(&mut names, b"test_complete_agent_lifecycle");

        // DCA Buy agent tests
        vector::push_back(&mut names, b"test_create_dca_buy_agent_success");
        vector::push_back(&mut names, b"test_successful_dca_execution");
        vector::push_back(&mut names, b"test_dca_execution_too_early");
        vector::push_back(&mut names, b"test_multiple_dca_executions");
        vector::push_back(&mut names, b"test_agent_funding");

        // DCA Sell agent tests
        vector::push_back(&mut names, b"test_create_dca_sell_agent_success");
        vector::push_back(&mut names, b"test_successful_dca_sell_execution");
        vector::push_back(&mut names, b"test_agent_token_deposit");
        vector::push_back(&mut names, b"test_average_price_calculation");

        // Integration tests
        vector::push_back(&mut names, b"test_create_exactly_ten_mixed_agents");
        vector::push_back(&mut names, b"test_multiple_users_independent_limits");
        vector::push_back(&mut names, b"test_gas_sponsorship_across_agent_types");
        vector::push_back(&mut names, b"test_platform_statistics_integration");

        names
    }

    // ================================================================================================
    // Test Validation Functions
    // ================================================================================================

    /// Validate test configuration
    public fun validate_test_config(): bool {
        // Check that maximum values are greater than minimum values
        if (MAX_TEST_AMOUNT <= MIN_TEST_AMOUNT) {
            return false
        };

        // Check that default amounts are within bounds
        if (DEFAULT_USDT_AMOUNT < MIN_TEST_AMOUNT || DEFAULT_USDT_AMOUNT > MAX_TEST_AMOUNT) {
            return false
        };

        // Check timing bounds consistency
        if (MIN_MINUTES >= MAX_MINUTES || MIN_HOURS >= MAX_HOURS) {
            return false
        };

        // Check coverage target is reasonable
        if (TARGET_COVERAGE_PERCENT < 80 || TARGET_COVERAGE_PERCENT > 100) {
            return false
        };

        true
    }

    /// Get expected error code for test scenario
    public fun get_expected_error(scenario_name: vector<u8>): Option<u64> {
        if (scenario_name == b"exceed_agent_limit") {
            option::some(ERROR_AGENT_LIMIT_EXCEEDED)
        } else if (scenario_name == b"unauthorized_access") {
            option::some(ERROR_NOT_AUTHORIZED)
        } else if (scenario_name == b"insufficient_balance") {
            option::some(ERROR_INSUFFICIENT_FUNDS)
        } else if (scenario_name == b"invalid_timing") {
            option::some(ERROR_INVALID_TIMING)
        } else {
            option::none()
        }
    }

    // ================================================================================================
    // Test Metrics and Reporting
    // ================================================================================================

    /// Create test metrics structure
    public fun create_test_metrics(
        tests_run: u64,
        tests_passed: u64,
        tests_failed: u64,
        coverage_percentage: u64,
        execution_time_ms: u64
    ): TestMetrics {
        TestMetrics {
            tests_run,
            tests_passed,
            tests_failed,
            coverage_percentage,
            execution_time_ms,
        }
    }

    /// Calculate success rate from metrics
    public fun calculate_success_rate(metrics: &TestMetrics): u64 {
        if (metrics.tests_run == 0) {
            return 0
        };
        (metrics.tests_passed * 100) / metrics.tests_run
    }

    /// Check if coverage target is met
    public fun is_coverage_target_met(metrics: &TestMetrics): bool {
        metrics.coverage_percentage >= (TARGET_COVERAGE_PERCENT as u64)
    }

    /// Get target coverage percentage
    public fun get_target_coverage(): u8 {
        TARGET_COVERAGE_PERCENT
    }

    // ================================================================================================
    // Test Environment Helpers
    // ================================================================================================

    /// Get test network configuration
    public fun get_test_network(): vector<u8> {
        TEST_NETWORK
    }

    /// Get maximum test execution time
    public fun get_max_execution_time(): u64 {
        MAX_TEST_EXECUTION_TIME
    }

    /// Check if address is a test account
    public fun is_test_account(addr: address): bool {
        addr == TEST_ADMIN ||
        addr == TEST_USER_1 ||
        addr == TEST_USER_2 ||
        addr == TEST_USER_3 ||
        addr == TEST_KEEPER ||
        addr == TEST_UNAUTHORIZED
    }

    /// Check if address is a mock token
    public fun is_mock_token(addr: address): bool {
        addr == MOCK_APT_ADDR ||
        addr == MOCK_USDT_ADDR ||
        addr == MOCK_USDC_ADDR ||
        addr == MOCK_WETH_ADDR ||
        addr == MOCK_WBTC_ADDR
    }
}
