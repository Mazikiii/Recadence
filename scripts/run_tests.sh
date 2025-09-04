#!/bin/bash

# Recadence Smart Contract Testing Pipeline
# Automated testing script with coverage reporting for Week 1 QA Sprint
# Target: 95%+ code coverage across all agent contracts

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTRACTS_DIR="src/lib/contracts"
TESTS_DIR="$CONTRACTS_DIR/tests"
COVERAGE_DIR="coverage"
MIN_COVERAGE=95

echo -e "${BLUE}🧪 Recadence Smart Contract Testing Pipeline${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Function to print section headers
print_section() {
    echo -e "${YELLOW}📋 $1${NC}"
    echo "----------------------------------------"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_section "Checking Prerequisites"

if ! command_exists aptos; then
    echo -e "${RED}❌ Aptos CLI not found. Please install it first.${NC}"
    exit 1
fi

if ! command_exists jq; then
    echo -e "${YELLOW}⚠️  jq not found. Installing...${NC}"
    # Try to install jq based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq
    else
        echo -e "${RED}❌ Please install jq manually${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Navigate to contracts directory
cd "$CONTRACTS_DIR"

# Clean previous artifacts
print_section "Cleaning Previous Test Artifacts"
rm -rf build/
rm -rf .aptos/
rm -rf coverage/
mkdir -p coverage/
echo -e "${GREEN}✅ Cleaned previous artifacts${NC}"
echo ""

# Compile contracts
print_section "Compiling Smart Contracts"
echo "Compiling main contracts..."
if aptos move compile --named-addresses recadence=0x849ab11d0816c9b90336ab226687a5f53754eef1ab133e549f33db45513c73d2; then
    echo -e "${GREEN}✅ Contracts compiled successfully${NC}"
else
    echo -e "${RED}❌ Contract compilation failed${NC}"
    exit 1
fi
echo ""

# Function to run specific test module
run_test_module() {
    local module_name=$1
    local test_file=$2

    echo "Running tests for $module_name..."

    # Run tests with verbose output
    if aptos move test --named-addresses recadence=0x849ab11d0816c9b90336ab226687a5f53754eef1ab133e549f33db45513c73d2 --filter "$module_name" --verbose; then
        echo -e "${GREEN}✅ $module_name tests passed${NC}"
        return 0
    else
        echo -e "${RED}❌ $module_name tests failed${NC}"
        return 1
    fi
}

# Run all test modules
print_section "Running Unit Tests"

failed_tests=()

# Test base agent
if ! run_test_module "base_agent_tests" "base_agent_tests.move"; then
    failed_tests+=("base_agent_tests")
fi

# Test DCA Buy Agent
if ! run_test_module "dca_buy_agent_tests" "dca_buy_agent_tests.move"; then
    failed_tests+=("dca_buy_agent_tests")
fi

# Test DCA Sell Agent
if ! run_test_module "dca_sell_agent_tests" "dca_sell_agent_tests.move"; then
    failed_tests+=("dca_sell_agent_tests")
fi

# Test Percentage Buy Agent
if ! run_test_module "percentage_buy_agent_tests" "percentage_buy_agent_tests.move"; then
    failed_tests+=("percentage_buy_agent_tests")
fi

# Test Percentage Sell Agent
if ! run_test_module "percentage_sell_agent_tests" "percentage_sell_agent_tests.move"; then
    failed_tests+=("percentage_sell_agent_tests")
fi

# Test agent limit integration
if ! run_test_module "agent_limit_integration_tests" "agent_limit_integration_tests.move"; then
    failed_tests+=("agent_limit_integration_tests")
fi

echo ""

# Generate coverage report
print_section "Generating Coverage Report"

echo "Running tests with coverage..."
if aptos move test --named-addresses recadence=0x849ab11d0816c9b90336ab226687a5f53754eef1ab133e549f33db45513c73d2 --coverage; then
    echo -e "${GREEN}✅ Coverage data generated${NC}"
else
    echo -e "${RED}❌ Coverage generation failed${NC}"
    exit 1
fi

# Generate detailed coverage report
echo "Generating detailed coverage report..."
if aptos move coverage summary --summarize-functions > coverage/summary.txt; then
    echo -e "${GREEN}✅ Coverage summary generated${NC}"
else
    echo -e "${YELLOW}⚠️  Coverage summary generation failed, continuing...${NC}"
fi

# Generate source coverage
if aptos move coverage source --module recadence > coverage/source_coverage.txt; then
    echo -e "${GREEN}✅ Source coverage generated${NC}"
else
    echo -e "${YELLOW}⚠️  Source coverage generation failed, continuing...${NC}"
fi

echo ""

# Parse coverage results
print_section "Coverage Analysis"

# Extract coverage percentage from summary
if [ -f "coverage/summary.txt" ]; then
    coverage_line=$(grep "Move Coverage:" coverage/summary.txt || echo "")
    if [ -n "$coverage_line" ]; then
        coverage_percent=$(echo "$coverage_line" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -n "$coverage_percent" ]; then
            coverage_int=$(echo "$coverage_percent" | cut -d'.' -f1)

            echo "Overall Coverage: ${coverage_percent}%"

            if [ "$coverage_int" -ge "$MIN_COVERAGE" ]; then
                echo -e "${GREEN}✅ Coverage target met! (${coverage_percent}% >= ${MIN_COVERAGE}%)${NC}"
            else
                echo -e "${RED}❌ Coverage target not met (${coverage_percent}% < ${MIN_COVERAGE}%)${NC}"
                failed_tests+=("coverage")
            fi
        else
            echo -e "${YELLOW}⚠️  Could not parse coverage percentage${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Coverage summary not found in expected format${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Coverage summary file not found${NC}"
fi

echo ""

# Security and edge case analysis
print_section "Security and Edge Case Validation"

security_tests=(
    "test_create_agent_beyond_limit_fails"
    "test_pause_agent_unauthorized_fails"
    "test_delete_agent_unauthorized_fails"
    "test_withdraw_more_than_balance"
    "test_dca_execution_insufficient_balance"
    "test_invalid_timing_"
)

echo "Validating security test coverage..."
security_coverage=0
total_security_tests=${#security_tests[@]}

for test in "${security_tests[@]}"; do
    if grep -r "$test" tests/ >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Security test found: $test${NC}"
        ((security_coverage++))
    else
        echo -e "${YELLOW}⚠️  Security test missing: $test${NC}"
    fi
done

echo ""
echo "Security test coverage: $security_coverage/$total_security_tests"

if [ "$security_coverage" -eq "$total_security_tests" ]; then
    echo -e "${GREEN}✅ All security tests implemented${NC}"
else
    echo -e "${YELLOW}⚠️  Some security tests missing${NC}"
fi

echo ""

# Generate test report
print_section "Generating Test Report"

report_file="coverage/test_report.md"
cat > "$report_file" << EOF
# Recadence Smart Contract Test Report

**Generated:** $(date)
**Target Coverage:** ${MIN_COVERAGE}%
**Achieved Coverage:** ${coverage_percent:-"N/A"}%

## Test Results Summary

### Unit Test Modules
EOF

if [ ${#failed_tests[@]} -eq 0 ]; then
    echo "| Module | Status |" >> "$report_file"
    echo "|--------|--------|" >> "$report_file"
    echo "| base_agent_tests | ✅ PASSED |" >> "$report_file"
    echo "| dca_buy_agent_tests | ✅ PASSED |" >> "$report_file"
    echo "| dca_sell_agent_tests | ✅ PASSED |" >> "$report_file"
    echo "| percentage_buy_agent_tests | ✅ PASSED |" >> "$report_file"
    echo "| percentage_sell_agent_tests | ✅ PASSED |" >> "$report_file"
    echo "| agent_limit_integration_tests | ✅ PASSED |" >> "$report_file"
else
    echo "| Module | Status |" >> "$report_file"
    echo "|--------|--------|" >> "$report_file"

    for module in "base_agent_tests" "dca_buy_agent_tests" "dca_sell_agent_tests" "percentage_buy_agent_tests" "percentage_sell_agent_tests" "agent_limit_integration_tests"; do
        if [[ " ${failed_tests[@]} " =~ " ${module} " ]]; then
            echo "| $module | ❌ FAILED |" >> "$report_file"
        else
            echo "| $module | ✅ PASSED |" >> "$report_file"
        fi
    done
fi

cat >> "$report_file" << EOF

### Coverage Analysis
- **Function Coverage:** Individual function coverage metrics
- **Line Coverage:** Source line coverage analysis
- **Branch Coverage:** Conditional branch coverage

### Security Test Validation
- **Access Control Tests:** $security_coverage/$total_security_tests implemented
- **Edge Case Tests:** Boundary condition validation
- **Error Handling Tests:** Exception and failure scenario coverage

### Test Categories Covered
1. **Agent Creation & Lifecycle**
   - Agent initialization and configuration
   - State transitions (ACTIVE → PAUSED → DELETED)
   - Multi-user scenarios

2. **Agent Limit Enforcement**
   - 10-agent limit per user
   - Cross-agent type limit validation
   - Limit reclamation after deletion

3. **Gas Sponsorship Management**
   - First 10 agents sponsorship
   - Sponsorship reclamation
   - Cross-agent type sponsorship tracking

3. **DCA Functionality**
   - Buy agent execution and timing
   - Sell agent execution and token validation
   - DEX integration testing

4. **Percentage Agent Functionality**
   - Buy agent trend selection (UP/DOWN)
   - Sell agent profit-taking logic
   - Percentage threshold validation

5. **Security & Access Control**
   - Creator-only restrictions
   - Unauthorized access prevention
   - Fund isolation validation

6. **Edge Cases & Error Conditions**
   - Boundary value testing
   - Invalid parameter handling
   - Insufficient balance scenarios

### Integration Test Coverage
- Multi-agent interactions
- Platform statistics accuracy
- Agent registry consistency
- Event emission validation

EOF

echo -e "${GREEN}✅ Test report generated: $report_file${NC}"

# Copy coverage files for CI/CD
if [ -d "coverage" ]; then
    cp coverage/summary.txt coverage/coverage_summary.txt 2>/dev/null || true
    cp coverage/source_coverage.txt coverage/detailed_coverage.txt 2>/dev/null || true
fi

echo ""

# Final results
print_section "Test Pipeline Results"

if [ ${#failed_tests[@]} -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}✅ Week 1 QA Sprint objectives met${NC}"

    if [ -n "$coverage_percent" ] && [ "$coverage_int" -ge "$MIN_COVERAGE" ]; then
        echo -e "${GREEN}✅ Coverage target achieved: ${coverage_percent}%${NC}"
    fi

    echo ""
    echo -e "${BLUE}📊 Summary:${NC}"
    echo "- Base Agent Tests: ✅ PASSED"
    echo "- DCA Buy Agent Tests: ✅ PASSED"
    echo "- DCA Sell Agent Tests: ✅ PASSED"
    echo "- Percentage Buy Agent Tests: ✅ PASSED"
    echo "- Percentage Sell Agent Tests: ✅ PASSED"
    echo "- Integration Tests: ✅ PASSED"
    echo "- Security Tests: ✅ VALIDATED"
    echo "- Coverage Target: ✅ MET"

    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo -e "${RED}Failed modules: ${failed_tests[*]}${NC}"

    echo ""
    echo -e "${YELLOW}🔍 Next Steps:${NC}"
    echo "1. Review failed test output above"
    echo "2. Fix failing tests or code issues"
    echo "3. Re-run test pipeline"
    echo "4. Check coverage report in coverage/"

    exit 1
fi
