# ============================================================================
# FILE        : Makefile
# PROJECT     : HMAO Engine - RISC-V Integration Test Firmware
# DESCRIPTION : Build script for HMAO integration test firmware
# ============================================================================

# ============================================================================
# CONFIGURATION
# ============================================================================

PROGRAM_NAME := hmao_integration_test
CROSS_COMPILE := riscv32-unknown-elf-
CC := $(CROSS_COMPILE)gcc
AR := $(CROSS_COMPILE)ar
LD := $(CROSS_COMPILE)ld
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump

# Firmware directories
FW_DIR := .
BUILD_DIR := build
OBJ_DIR := $(BUILD_DIR)/obj
BIN_DIR := $(BUILD_DIR)/bin

# RISC-V ISA configuration
RISC_ARCH := rv32im
RISC_ABI := ilp32

# Compiler flags
CFLAGS := -march=$(RISC_ARCH) -mabi=$(RISC_ABI)
CFLAGS += -O2 -Wall -Wextra
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -nostdlib -nostartfiles
CFLAGS += -I$(FW_DIR)

# Linker flags
LDFLAGS := -march=$(RISC_ARCH) -mabi=$(RISC_ABI)
LDFLAGS += --gc-sections
LDFLAGS += -T$(FW_DIR)/linker_script.ld

# Optimization flags
OPTIMIZE := -O2

# ============================================================================
# SOURCE FILES
# ============================================================================

C_SOURCES := $(FW_DIR)/hmao_integration_test.c

ASM_SOURCES := $(FW_DIR)/boot.s

OBJECTS := $(addprefix $(OBJ_DIR)/,$(notdir $(C_SOURCES:.c=.o)))
OBJECTS += $(addprefix $(OBJ_DIR)/,$(notdir $(ASM_SOURCES:.s=.o)))

ELF_TARGET := $(BIN_DIR)/$(PROGRAM_NAME).elf
HEX_TARGET := $(BIN_DIR)/$(PROGRAM_NAME).hex
BIN_TARGET := $(BIN_DIR)/$(PROGRAM_NAME).bin
LST_TARGET := $(BIN_DIR)/$(PROGRAM_NAME).lst

# ============================================================================
# BUILD RULES
# ============================================================================

.PHONY: all clean firmware disassembly

all: firmware

firmware: $(BIN_DIR) $(OBJ_DIR) $(BIN_TARGET) $(HEX_TARGET) $(LST_TARGET)
	@echo "[BUILD] HMAO Integration Test Firmware Complete"
	@echo "  ELF:       $(ELF_TARGET)"
	@echo "  Binary:    $(BIN_TARGET)"
	@echo "  Hex:       $(HEX_TARGET)"
	@echo "  Disasm:    $(LST_TARGET)"

$(BIN_DIR):
	@mkdir -p $(BIN_DIR)

$(OBJ_DIR):
	@mkdir -p $(OBJ_DIR)

# Compile C sources
$(OBJ_DIR)/%.o: $(FW_DIR)/%.c
	@echo "[CC] $<"
	$(CC) $(CFLAGS) $(OPTIMIZE) -c $< -o $@

# Assemble ASM sources
$(OBJ_DIR)/%.o: $(FW_DIR)/%.s
	@echo "[AS] $<"
	$(CC) $(CFLAGS) -c $< -o $@

# Link ELF
$(ELF_TARGET): $(OBJECTS)
	@echo "[LD] Linking $(PROGRAM_NAME).elf"
	$(LD) $(LDFLAGS) $(OBJECTS) -o $(ELF_TARGET)
	@echo "[SIZE] Firmware size:"
	@$(CROSS_COMPILE)size $(ELF_TARGET)

# Convert to HEX
$(HEX_TARGET): $(ELF_TARGET)
	@echo "[HEX] Converting to Intel HEX format"
	$(OBJCOPY) -O ihex $(ELF_TARGET) $(HEX_TARGET)

# Convert to BIN
$(BIN_TARGET): $(ELF_TARGET)
	@echo "[BIN] Converting to binary format"
	$(OBJCOPY) -O binary $(ELF_TARGET) $(BIN_TARGET)

# Disassembly
$(LST_TARGET): $(ELF_TARGET)
	@echo "[DISASM] Generating disassembly"
	$(OBJDUMP) -d -S $(ELF_TARGET) > $(LST_TARGET)

disassembly: $(LST_TARGET)
	@echo "Disassembly saved to $(LST_TARGET)"

clean:
	@echo "[CLEAN] Removing build artifacts"
	rm -rf $(BUILD_DIR)

# ============================================================================
# UTILITY TARGETS
# ============================================================================

info:
	@echo "HMAO Integration Test Firmware Build Information:"
	@echo "  Target Architecture: $(RISC_ARCH)"
	@echo "  Target ABI: $(RISC_ABI)"
	@echo "  Cross Compiler: $(CROSS_COMPILE)"
	@echo "  Build Directory: $(BUILD_DIR)"
	@echo "  Optimization Level: $(OPTIMIZE)"

print-%:
	@echo "$* = $($*)"

.PHONY: info print-%
