/* =============================================================================
 * FILE        : linker_script.ld
 * PROJECT     : HMAO Engine - RISC-V Integration Test Firmware
 * DESCRIPTION : Linker script for RISC-V firmware binary
 * ============================================================================= */

/* Memory layout (typical for SoC testbench):
   - IMEM (Instruction Memory): 64KB @ 0x0000_0000
   - DMEM (Data Memory):       256KB @ 0x1000_0000
   - HMAO Registers:            64KB @ 0xA410_0000
   - Trajectory Buffer:         64KB @ 0x8030_0000
   - World Model:               8MB  @ 0x8040_0000
*/

MEMORY {
    /* Instruction memory (64 KB) */
    IMEM  (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    
    /* Data memory (256 KB) */
    DMEM  (rwx) : ORIGIN = 0x10000000, LENGTH = 256K
}

SECTIONS {
    /* =====================================================================
     * Text Section (Code) - in IMEM
     * ===================================================================== */
    .text : {
        *(.text.init)       /* Entry point first */
        *(.text)            /* General code */
        *(.text.*)          /* Specific text sections */
        *(.rodata)          /* Read-only data (strings, tables) */
        *(.rodata.*)
    } > IMEM
    
    /* =====================================================================
     * Data Section - in DMEM
     * ===================================================================== */
    .data : {
        *(.data)
        *(.data.*)
    } > DMEM AT > IMEM
    
    /* =====================================================================
     * BSS Section (Uninitialized data) - in DMEM
     * ===================================================================== */
    .bss : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > DMEM
    
    /* =====================================================================
     * Symbols for linker
     * ===================================================================== */
    __bss_start = ADDR(.bss);
    __bss_end = ADDR(.bss) + SIZEOF(.bss);
    __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
    
    /* =====================================================================
     * Debug sections (optional, for debugging)
     * ===================================================================== */
    .debug_info     0 : { *(.debug_info) }
    .debug_abbrev   0 : { *(.debug_abbrev) }
    .debug_line     0 : { *(.debug_line) }
    .debug_frame    0 : { *(.debug_frame) }
    .debug_str      0 : { *(.debug_str) }
    .debug_loc      0 : { *(.debug_loc) }
    
    /DISCARD/ : {
        *(.gnu.attributes)
        *(.note.GNU-stack)
        *(.gnu_debuglink)
        *(.gnu.lto_*)
    }
}

/* Global pointer for relaxation */
__global_pointer$ = ADDR(.data) + (SIZEOF(.data) + SIZEOF(.bss)) / 2;
