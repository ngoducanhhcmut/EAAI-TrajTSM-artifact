# =============================================================================
# FILE        : Makefile
# PROJECT     : HMAO Engine - Firmware Integration Test Suite
# DESCRIPTION : Build system for RISC-V RV32IM firmware
#
# TARGETS     :
#   make firmware      - Build all formats (.elf, .hex, .bin, .lst)
#   make clean         - Remove build artifacts
#   make disasm        - Generate assembly listing
#
# COMPILER    : riscv32-unknown-elf-gcc (cross-compiler)
# ARCH        : RISC-V RV32IM (32-bit with Multiply extension)
# OPTIMIZATION: -O2 (balanced speed/size)
#
# =============================================================================

# Toolchain Configuration
PREFIX          = riscv32-unknown-elf
CC              = $(PREFIX)-gcc
LD              = $(PREFIX)-ld
OBJDUMP         = $(PREFIX)-objdump
OBJCOPY         = $(PREFIX)-objcopy
SIZE            = $(PREFIX)-size
READELF         = $(PREFIX)-readelf

# Build Configuration
ARCH            = -march=rv32im
ABI             = -mabi=ilp32
CFLAGS          = $(ARCH) $(ABI) -O2 -Wall -Wextra -ffreestanding -nostdlib -nostartfiles
LDFLAGS         = -T linker_script.ld -Map=$(BUILD_DIR)/firmware.map

# Build Directory
BUILD_DIR       = build
OUTPUT_PREFIX   = $(BUILD_DIR)/hmao_integration_test

# Source Files
SOURCES         = hmao_integration_test.c boot.s
OBJECTS         = $(SOURCES:%.s=$(BUILD_DIR)/%.o) $(SOURCES:%.c=$(BUILD_DIR)/%.o)

# FORCE rebuild if VERBOSE flag changes
VERBOSE         ?= 0

# Output Formats
ELF_OUTPUT      = $(OUTPUT_PREFIX).elf
HEX_OUTPUT      = $(OUTPUT_PREFIX).hex
BIN_OUTPUT      = $(OUTPUT_PREFIX).bin
LST_OUTPUT      = $(OUTPUT_PREFIX).lst
MAP_OUTPUT      = $(BUILD_DIR)/firmware.map

# =============================================================================
# MAIN TARGETS
# =============================================================================

.PHONY: all firmware clean disasm info size

all: firmware

firmware: $(BUILD_DIR) $(ELF_OUTPUT) $(HEX_OUTPUT) $(BIN_OUTPUT) $(LST_OUTPUT)
	@echo "✓ Build complete"
	@echo "  ELF:   $(ELF_OUTPUT)"
	@echo "  HEX:   $(HEX_OUTPUT)"
	@echo "  BIN:   $(BIN_OUTPUT)"
	@echo "  LST:   $(LST_OUTPUT)"
	@echo "  MAP:   $(MAP_OUTPUT)"

clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "✓ Clean complete"

disasm: $(LST_OUTPUT)
	@echo "✓ Assembly listing generated: $(LST_OUTPUT)"

size: $(ELF_OUTPUT)
	@echo "Firmware Size:"
	@$(SIZE) $(ELF_OUTPUT)

info: $(ELF_OUTPUT)
	@echo "Firmware Information:"
	@echo "─────────────────────"
	@echo "Architecture: RISC-V RV32IM"
	@echo "Compiler:     $(CC)"
	@echo "Flags:        $(CFLAGS)"
	@echo "Linker:       $(LD)"
	@echo ""
	@echo "Symbol Table:"
	@$(READELF) -s $(ELF_OUTPUT) | grep -E "FUNC|OBJECT|Section|_start|main"
	@echo ""
	@echo "Full Info:"
	@$(SIZE) $(ELF_OUTPUT)

# =============================================================================
# BUILD RULES
# =============================================================================

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Compile C source files
$(BUILD_DIR)/%.o: %.c
	@echo "  [CC] $<"
	@$(CC) $(CFLAGS) -c $< -o $@

# Assemble ASM files
$(BUILD_DIR)/%.o: %.s
	@echo "  [AS] $<"
	@$(CC) $(CFLAGS) -c $< -o $@

# Link ELF executable
$(ELF_OUTPUT): $(OBJECTS)
	@echo "  [LD] Linking $(notdir $@)"
ifeq ($(VERBOSE), 1)
	@echo "    Command: $(CC) $(LDFLAGS) $(OBJECTS) -o $@"
endif
	@$(CC) $(LDFLAGS) $(OBJECTS) -o $@
	@echo "  [SIZE] Firmware size:"
	@$(SIZE) $@ | tail -1

# Generate HEX file (for IMEM loader)
$(HEX_OUTPUT): $(ELF_OUTPUT)
	@echo "  [HEX] Generating 32-bit Intel HEX format"
	@$(OBJCOPY) -O ihex $(ELF_OUTPUT) $(HEX_OUTPUT)
	@echo "  ✓ Memory image ready for IMEM loading"

# Generate binary file (raw executable)
$(BIN_OUTPUT): $(ELF_OUTPUT)
	@echo "  [BIN] Generating raw binary"
	@$(OBJCOPY) -O binary --pad-to=0x40000 $(ELF_OUTPUT) $(BIN_OUTPUT)

# Generate assembly listing
$(LST_OUTPUT): $(ELF_OUTPUT)
	@echo "  [LST] Disassembly listing"
	@$(OBJDUMP) -d -S -l $(ELF_OUTPUT) > $(LST_OUTPUT)
	@echo "  ✓ Assembly listing: $(LST_OUTPUT)"

# =============================================================================
# DEPENDENCY TRACKING (minimal)
# =============================================================================

.PHONY: depend

depend:
	@echo "Source dependencies:"
	@echo "  C files: $(filter %.c, $(SOURCES))"
	@echo "  ASM files: $(filter %.s, $(SOURCES))"

# =============================================================================
# HELP
# =============================================================================

.PHONY: help

help:
	@echo "HMAO Engine Firmware Build System"
	@echo "═══════════════════════════════════════════"
	@echo ""
	@echo "Available targets:"
	@echo "  make firmware       Build all output formats"
	@echo "  make clean          Remove build artifacts"
	@echo "  make disasm         Generate assembly listing"
	@echo "  make size           Show firmware size"
	@echo "  make info           Show detailed firmware info"
	@echo "  make help           Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  VERBOSE=1           Show detailed build commands"
	@echo "  PREFIX=path         Cross-compiler prefix (default: riscv32-unknown-elf)"
	@echo ""
	@echo "Examples:"
	@echo "  make firmware              # Build all formats"
	@echo "  make clean && make firmware # Clean rebuild"
	@echo "  make VERBOSE=1 firmware    # Verbose output"
	@echo "  make info                  # Show firmware details"
	@echo ""
	@echo "Output files (in build/ directory):"
	@echo "  hmao_integration_test.elf  - ELF executable (with symbols)"
	@echo "  hmao_integration_test.hex  - Intel HEX format (for IMEM)"
	@echo "  hmao_integration_test.bin  - Raw binary image"
	@echo "  hmao_integration_test.lst  - Disassembly + source listing"
	@echo "  firmware.map               - Link map with symbol addresses"
	@echo ""

.DEFAULT_GOAL := help
