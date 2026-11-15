/* Linker script for tsm_demo (chep tu planning_test) — R5 bare-metal on ZCU104
 * Code/data at 0x40000000, well above DDR weight region 0x0-0x018A6000.
 */

_STACK_SIZE            = 0x4000;
_HEAP_SIZE             = 0x8000;
_IRQ_STACK_SIZE        = 0x400;
_FIQ_STACK_SIZE        = 0x400;
_ABORT_STACK_SIZE      = 0x400;
_SUPERVISOR_STACK_SIZE = 0x800;
_UNDEF_STACK_SIZE      = 0x400;

MEMORY
{
   ddr_code : ORIGIN = 0x40000000, LENGTH = 0x04000000
}

ENTRY(_vector_table)

SECTIONS
{
   .vectors : {
      KEEP (*(.vectors))
      *(.boot)
   } > ddr_code

   .text : {
      *(.text)
      *(.text.*)
      *(.gnu.linkonce.t.*)
      *(.plt)
      *(.gnu_warning)
      *(.gcc_execpt_table)
      *(.glue_7)
      *(.glue_7t)
      *(.vfp11_veneer)
      *(.ARM.extab)
      *(.gnu.linkonce.armextab.*)
   } > ddr_code

   .init : { KEEP (*(.init)) } > ddr_code
   .fini : { KEEP (*(.fini)) } > ddr_code

   .rodata : {
      __rodata_start = .;
      *(.rodata)
      *(.rodata.*)
      *(.gnu.linkonce.r.*)
      __rodata_end = .;
   } > ddr_code

   .data : {
      __data_start = .;
      *(.data)
      *(.data.*)
      *(.gnu.linkonce.d.*)
      *(.jcr)
      *(.got)
      *(.got.plt)
      __data_end = .;
   } > ddr_code

   .ctors : {
      __CTOR_LIST__ = .;
      KEEP (*crtbegin.o(.ctors))
      KEEP (*(EXCLUDE_FILE(*crtend.o) .ctors))
      KEEP (*(SORT(.ctors.*)))
      KEEP (*(.ctors))
      __CTOR_END__ = .;
   } > ddr_code

   .dtors : {
      __DTOR_LIST__ = .;
      KEEP (*crtbegin.o(.dtors))
      KEEP (*(EXCLUDE_FILE(*crtend.o) .dtors))
      KEEP (*(SORT(.dtors.*)))
      KEEP (*(.dtors))
      __DTOR_END__ = .;
   } > ddr_code

   .eh_frame : { *(.eh_frame) } > ddr_code

   .ARM.exidx : {
      __exidx_start = .;
      *(.ARM.exidx*)
      *(.gnu.linkonce.armexidix.*.*)
      __exidx_end = .;
   } > ddr_code

   .preinit_array : {
      __preinit_array_start = .;
      KEEP (*(SORT(.preinit_array.*)))
      KEEP (*(.preinit_array))
      __preinit_array_end = .;
   } > ddr_code

   .init_array : {
      __init_array_start = .;
      KEEP (*(SORT(.init_array.*)))
      KEEP (*(.init_array))
      __init_array_end = .;
   } > ddr_code

   .fini_array : {
      __fini_array_start = .;
      KEEP (*(SORT(.fini_array.*)))
      KEEP (*(.fini_array))
      __fini_array_end = .;
   } > ddr_code

   .sdata : {
      __sdata_start = .;
      *(.sdata)
      *(.sdata.*)
      *(.gnu.linkonce.s.*)
      __sdata_end = .;
   } > ddr_code

   .sbss (NOLOAD) : {
      __sbss_start = .;
      *(.sbss)
      *(.sbss.*)
      *(.gnu.linkonce.sb.*)
      __sbss_end = .;
   } > ddr_code

   .bss (NOLOAD) : {
      . = ALIGN(4);
      __bss_start__ = .;
      *(.bss)
      *(.bss.*)
      *(.gnu.linkonce.b.*)
      *(COMMON)
      . = ALIGN(4);
      __bss_end__ = .;
   } > ddr_code

   _SDA_BASE_ = __sdata_start + ((__sbss_end - __sdata_start) / 2);

   .heap (NOLOAD) : {
      . = ALIGN(16);
      _heap_start = .;
      . += _HEAP_SIZE;
      _heap_end = .;
   } > ddr_code

   .stack (NOLOAD) : {
      . = ALIGN(16);
      _stack_end = .;
      . += _STACK_SIZE;
      _stack = .;
      __stack = _stack;
      . = ALIGN(16);
      _irq_stack_end = .;
      . += _IRQ_STACK_SIZE;
      __irq_stack = .;
      _supervisor_stack_end = .;
      . += _SUPERVISOR_STACK_SIZE;
      . = ALIGN(16);
      __supervisor_stack = .;
      _abort_stack_end = .;
      . += _ABORT_STACK_SIZE;
      . = ALIGN(16);
      __abort_stack = .;
      _fiq_stack_end = .;
      . += _FIQ_STACK_SIZE;
      . = ALIGN(16);
      __fiq_stack = .;
      _undef_stack_end = .;
      . += _UNDEF_STACK_SIZE;
      . = ALIGN(16);
      __undef_stack = .;
   } > ddr_code

   _end = .;
}
