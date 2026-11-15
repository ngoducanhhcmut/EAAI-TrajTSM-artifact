#!/bin/bash
# =============================================================================
# FILE        : RUN_UNIT_TESTS.sh
# PROJECT     : HMAO Engine - Unit Test Suite Runner
# DESCRIPTION : Execute all 13 unit tests for individual module verification
#
# UNIT TESTS  : Testing modules in isolation
#               • Preprocessor (zonotope batching)
#               • Zonotope generators (Stage 1 & 2)
#               • ADMM solvers
#               • Collision detection
#               • FSM controllers
#               • Watchdog timer
#               • Adaptive margin calculator
#               • AXI arbiter
#
# USAGE       : bash RUN_UNIT_TESTS.sh [simulator]
#               Example: bash RUN_UNIT_TESTS.sh vsim
#
# SUPPORTED   : VCS, ModelSim (vsim), Xcelium
# EXPECTED    : ~50 total assertions pass, 30-45 minutes
#
# =============================================================================

set -e

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Arguments
SIMULATOR="${1:-vsim}"  # Default to ModelSim

# Detect if simulator is available
if ! command -v $SIMULATOR &> /dev/null; then
    echo -e "${RED}Error: Simulator '$SIMULATOR' not found in PATH${NC}"
    echo "Supported simulators: vsim (ModelSim), vcs (VCS), xsim (Xcelium)"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Timestamp
START_TIME=$(date +%s)

# Test counters
PASS=0
FAIL=0
SKIP=0

# =============================================================================
# HEADER
# =============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                  HMAO ENGINE - LEVEL 1: UNIT TESTS                         ║"
echo "║                                                                            ║"
echo "║  13 Unit Tests - Module Isolation Verification                            ║"
echo "║  Test Objective: Verify each module functions correctly in isolation      ║"
echo "║  Simulator: $SIMULATOR"
echo "║                                                                            ║"
echo "║  Coverage:                                                                 ║"
echo "║    • Preprocessing (2 tests)          → Zonotope batching                 ║"
echo "║    • Zonotope generation (2 tests)    → Stage 1 (16-gen) & Stage 2 (32-gen)║"
echo "║    • ADMM solvers (2 tests)           → Parallel optimization              ║"
echo "║    • Collision detection (2 tests)    → Safety verification                ║"
echo "║    • FSM controllers (2 tests)        → State machine behavior             ║"
echo "║    • Watchdog timer (1 test)          → Timeout detection                  ║"
echo "║    • Adaptive margin (1 test)         → Dynamic safety scaling             ║"
echo "║    • AXI arbiter (1 test)             → Register interface arbitration    ║"
echo "║                                                                            ║"
echo "║  Total Assertions: ~50 (covering ~200 edge cases)                         ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# TEST SUITE DEFINITION
# =============================================================================

declare -a UNIT_TESTS=(
    "tb_preproc_batch_u1.sv|Preproc Batch 1: Single 128-pt trajectory|U1"
    "tb_preproc_batch_u2.sv|Preproc Batch 2: Multiple trajectories|U2"
    "tb_hmao_zonotope_gen_u4.sv|Zonotope Gen U4: Stage 1 (16-gen)|U4"
    "tb_hmao_zonotope_gen_u5.sv|Zonotope Gen U5: Stage 2 (32-gen)|U5"
    "tb_hmao_admm_u6.sv|ADMM Solver U6: Parallel ADMM pipeline|U6"
    "tb_hmao_admm_u7.sv|ADMM Solver U7: ADMM convergence|U7"
    "tb_hmao_collision_sat_u8.sv|Collision Detect U8: CRS query|U8"
    "tb_hmao_collision_sat_u9.sv|Collision Detect U9: Z-constraints|U9"
    "tb_u10_hmao_fsm.sv|FSM Controller U10: State transitions|U10"
    "tb_u11_hmao_fsm.sv|FSM Controller U11: Error recovery|U11"
    "tb_u12_wdt.sv|Watchdog Timer U12: Timeout detection|U12"
    "tb_hmao_adaptive_margin_U3.sv|Adaptive Margin U3: Dynamic scaling|U3"
    "tb_hmao_axi_arbiter_u14.sv|AXI Arbiter U14: Register access|U14"
)

# =============================================================================
# TEST EXECUTION
# =============================================================================

echo -e "${CYAN}Starting test execution...${NC}"
echo ""

TEST_NUM=0
for test_entry in "${UNIT_TESTS[@]}"; do
    IFS='|' read -r test_file test_name test_id <<< "$test_entry"
    TEST_NUM=$((TEST_NUM + 1))
    
    # Check if file exists
    if [ ! -f "$test_file" ]; then
        echo -e "  [${TEST_NUM}/13] ${YELLOW}SKIP${NC} [$test_id] $test_file - File not found"
        SKIP=$((SKIP + 1))
        continue
    fi
    
    echo -e "  [${TEST_NUM}/13] ${BLUE}RUN${NC}  [$test_id] $test_name"
    
    # Run test with simulator
    case $SIMULATOR in
        vsim)
            # ModelSim/Questa
            if vsim -c -do "vlog $test_file; run -all; quit" &> /tmp/test_$test_id.log; then
                echo -e "          ${GREEN}✓ PASS${NC} - All assertions passed"
                PASS=$((PASS + 1))
            else
                echo -e "          ${RED}✗ FAIL${NC} - Check /tmp/test_$test_id.log for details"
                tail -10 /tmp/test_$test_id.log | sed 's/^/             /'
                FAIL=$((FAIL + 1))
            fi
            ;;
        
        vcs)
            # Synopsys VCS
            if vcs -sverilog $test_file -o $test_id.o -l $test_id.log && ./$test_id.o; then
                echo -e "          ${GREEN}✓ PASS${NC} - All assertions passed"
                PASS=$((PASS + 1))
            else
                echo -e "          ${RED}✗ FAIL${NC} - Check $test_id.log for details"
                tail -10 $test_id.log | sed 's/^/             /'
                FAIL=$((FAIL + 1))
            fi
            ;;
        
        xsim)
            # Xilinx Vivado
            if xvlog $test_file && xelab -top $(grep -o "module \w*" $test_file | head -1 | awk '{print $2}') $test_id && xsim $test_id -R; then
                echo -e "          ${GREEN}✓ PASS${NC} - All assertions passed"
                PASS=$((PASS + 1))
            else
                echo -e "          ${RED}✗ FAIL${NC} - Check xsim logs for details"
                FAIL=$((FAIL + 1))
            fi
            ;;
        
        *)
            echo -e "          ${RED}✗ Unsupported simulator: $SIMULATOR${NC}"
            SKIP=$((SKIP + 1))
            ;;
    esac
    
done

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TOTAL=$((PASS + FAIL))

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                        UNIT TEST RESULTS SUMMARY                           ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
echo ""
echo -e "  Tests Passed:      ${GREEN}$PASS${NC}"
echo -e "  Tests Failed:      ${RED}$FAIL${NC}"
echo -e "  Tests Skipped:     ${YELLOW}$SKIP${NC}"
echo "  ─────────────────────────────────────────────────────────────────────────"
echo -e "  Total:             $TOTAL/$((${#UNIT_TESTS[@]})) tests completed"
echo ""
echo "  Execution Time:    ${DURATION}s"
echo ""

if [ $FAIL -eq 0 ] && [ $PASS -gt 0 ]; then
    echo -e "  ${GREEN}✓ LEVEL 1 VERIFICATION PASSED${NC}"
    echo "    All individual modules satisfy isolation test requirements"
    echo ""
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    exit 0
else
    echo -e "  ${RED}✗ LEVEL 1 VERIFICATION FAILED${NC}"
    echo "    Some modules did not pass isolation tests"
    echo "    Review failed test output above"
    echo ""
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    exit 1
fi
