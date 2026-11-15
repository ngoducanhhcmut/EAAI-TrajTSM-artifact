/* =============================================================================
 * FILE        : linker_script.ld
 * PROJECT     : HMAO Engine - Firmware Integration Test Suite
 * DESCRIPTION : Linker script for RISC-V RV32IM firmware
 *
 * MEMORY LAYOUT:
 *   IMEM: 0x00000000 - 0x0000FFFF (64KB)    - Code, read-only data
 *   DMEM: 0x10000000 - 0x1003FFFF (256KB)   - Data, heap, stack
 *
 * SECTIONS:
 *   .text    - Program code (in IMEM)
 *   .rodata  - Read-only data (in IMEM)
 *   .data    - Initialized data (in DMEM)
 *   .bss     - Uninitialized data (in DMEM)
 *   .sdata   - Small data (in DMEM)
 *   .sbss    - Small uninitialized data (in DMEM)
 *
 * =============================================================================*/

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 0x10000   /* 64KB instruction memory */
    DMEM (rw)  : ORIGIN = 0x10000000, LENGTH = 0x40000   /* 256KB data memory */
}

ENTRY(_start)

SECTIONS
{
    /* =========================================================================
     * CODE SECTION (in IMEM)
     * =========================================================================*/
    
    .text :
    {
        *(.text.init)           /* Startup code first */
        *(.text)                /* All code sections */
        *(.text.*)              /* Code subsections */
        *(.gnu.linkonce.t.*)
        
        . = ALIGN(4);
        PROVIDE(_text_end = .);
    } > IMEM
    
    /* =========================================================================
     * READ-ONLY DATA SECTION (in IMEM)
     * =========================================================================*/
    
    .rodata :
    {
        *(.rodata)              /* Read-only data */
        *(.rodata.*)            /* Subsections */
        *(.gnu.linkonce.r.*)
        
        . = ALIGN(4);
        PROVIDE(_rodata_end = .);
    } > IMEM
    
    /* =========================================================================
     * INIT ARRAY (constructors - in IMEM)
     * =========================================================================*/
    
    .init_array :
    {
        PROVIDE(__init_array_start = .);
        *(.init_array)
        *(.init_array.*)
        PROVIDE(__init_array_end = .);
    } > IMEM
    
    /* =========================================================================
     * INITIALIZED DATA SECTION (in DMEM)
     * Copy from IMEM to DMEM at startup
     * =========================================================================*/
    
    .data :
    {
        PROVIDE(_data_start = .);
        *(.data)                /* Initialized data */
        *(.data.*)              /* Subsections */
        *(.gnu.linkonce.d.*)
        
        . = ALIGN(4);
        PROVIDE(_data_end = .);
    } > DMEM AT > IMEM
    
    PROVIDE(_data_load_start = LOADADDR(.data));
    PROVIDE(_data_load_end = LOADADDR(.data) + SIZEOF(.data));
    
    /* =========================================================================
     * SMALL DATA SECTION (.sdata - for GP-relative access)
     * =========================================================================*/
    
    .sdata :
    {
        PROVIDE(_sdata_start = .);
        *(.sdata)
        *(.sdata.*)
        
        . = ALIGN(4);
        PROVIDE(_sdata_end = .);
        PROVIDE(_gp = . + 0x800);  /* GP relative to this point */
    } > DMEM AT > IMEM
    
    /* =========================================================================
     * UNINITIALIZED DATA SECTION (BSS)
     * =========================================================================*/
    
    .bss (NOLOAD) :
    {
        PROVIDE(_bss_start = .);
        *(.bss)                 /* Uninitialized data */
        *(.bss.*)               /* Subsections */
        *(.sbss)                /* Small uninitialized data */
        *(.sbss.*)
        *(COMMON)               /* Common symbols */
        
        . = ALIGN(4);
        PROVIDE(_bss_end = .);
    } > DMEM
    
    /* =========================================================================
     * HEAP AND STACK
     * =========================================================================*/
    
    .heap (NOLOAD) :
    {
        PROVIDE(_heap_start = .);
        . = . + 0x2000;         /* 8KB heap */
        . = ALIGN(4);
        PROVIDE(_heap_end = .);
    } > DMEM
    
    /* Stack grows downward from end of DMEM */
    PROVIDE(_stack_end = ORIGIN(DMEM) + LENGTH(DMEM));
    
    /* =========================================================================
     * DEBUG SECTIONS (excluded from final image)
     * =========================================================================*/
    
    /* Remove debug info from final image */
    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
    }
    
    /* Keep debug info for debugging tools */
    .debug_info         0 : { *(.debug_info) }
    .debug_abbrev       0 : { *(.debug_abbrev) }
    .debug_line         0 : { *(.debug_line) }
    .debug_frame        0 : { *(.debug_frame) }
    .debug_str          0 : { *(.debug_str) }
    .debug_loc          0 : { *(.debug_loc) }
    .debug_ranges       0 : { *(.debug_ranges) }
    .debug_aranges      0 : { *(.debug_aranges) }
}

/* =============================================================================
 * SYMBOLS FOR STARTUP CODE
 * =============================================================================*/

PROVIDE(__bss_start = _bss_start);
PROVIDE(__bss_end = _bss_end);
PROVIDE(__global_pointer$ = _gp);
PROVIDE(__text_start = LOADADDR(.text));
PROVIDE(__text_end = _text_end);
PROVIDE(__data_start = _data_start);
PROVIDE(__data_end = _data_end);
PROVIDE(__rodata_start = LOADADDR(.rodata));
PROVIDE(__rodata_end = _rodata_end);
PROVIDE(__heap_start = _heap_start);
PROVIDE(__heap_end = _heap_end);
PROVIDE(__stack_start = _heap_end);
PROVIDE(__stack_end = _stack_end);
