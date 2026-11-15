MEMORY { ram : ORIGIN = 0x50000000, LENGTH = 0x01000000 }
ENTRY(_start)
SECTIONS {
  .vectors : { *(.vectors) } > ram
  .text : { *(.text*) } > ram
  .rodata : { *(.rodata*) } > ram
  .sdata2 : { _SDA2_BASE_ = . + 0x8000; *(.sdata2*) *(.sbss2*) } > ram
  .data : { *(.data*) } > ram
  .sdata : { _SDA_BASE_ = . + 0x8000; *(.sdata*) } > ram
  .sbss : { *(.sbss*) } > ram
  .bss : { *(.bss*) *(COMMON) } > ram
  . = ALIGN(16); . = . + 0x10000; _stack_top = .;
  _end = .;
}
