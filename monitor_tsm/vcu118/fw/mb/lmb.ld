/* Claude 10/11/2026: VCU118 MicroBlaze, 128 KB LMB at 0 (reset vector 0x0). */
MEMORY { lmb : ORIGIN = 0x00000000, LENGTH = 0x00020000 }
ENTRY(_start)
SECTIONS {
  .vectors : { *(.vectors) } > lmb
  .text : { *(.text*) } > lmb
  .rodata : { *(.rodata*) } > lmb
  .sdata2 : { _SDA2_BASE_ = . + 0x8000; *(.sdata2*) *(.sbss2*) } > lmb
  .data : { *(.data*) } > lmb
  .sdata : { _SDA_BASE_ = . + 0x8000; *(.sdata*) } > lmb
  .sbss : { *(.sbss*) } > lmb
  .bss : { __bss_start = .; *(.bss*) *(COMMON) __bss_end = .; } > lmb
  . = ALIGN(16); . = . + 0x4000; _stack_top = .;
  _end = .;
  ASSERT(_stack_top <= 0x20000, "LMB overflow")
}
