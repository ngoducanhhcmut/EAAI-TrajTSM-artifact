//==============================================================================
// File: dual_port_ram.sv
// Description: Parameterized True Dual-Port RAM
//              Infers Xilinx RAMB36E2 / RAMB18E2 via (* ram_style = "block" *)
//              Used throughout new architecture for ping-pong, LN1_q, K/V
//              scratch, QK^T scratch, bias, scale, LN params BRAMs.
//
// Reused from: planning_framework_final/rtl/src/memory/dual_port_ram.sv
// Date:        2026-03-25
//==============================================================================

`timescale 1ns / 1ps

module dual_port_ram #(
  parameter int    DATA_WIDTH      = 32,
  parameter int    DEPTH           = 1024,
  parameter int    ADDR_WIDTH      = $clog2(DEPTH),
  parameter bit    REGISTERED_OUTPUT = 1,   // 1 = BRAM output register (latency=2)
  parameter string COLLISION_MODE  = "WRITE_FIRST",
  parameter string INIT_FILE       = ""     // optional $readmemh hex init (simulation only)
)(
  // Port A (write priority)
  input  logic                     clk_a,
  input  logic                     rst_a_n,
  input  logic                     ena,
  input  logic                     wea,
  input  logic [ADDR_WIDTH-1:0]    addra,
  input  logic [DATA_WIDTH-1:0]    dina,
  output logic [DATA_WIDTH-1:0]    douta,

  // Port B (read priority)
  input  logic                     clk_b,
  input  logic                     rst_b_n,
  input  logic                     enb,
  input  logic                     web,
  input  logic [ADDR_WIDTH-1:0]    addrb,
  input  logic [DATA_WIDTH-1:0]    dinb,
  output logic [DATA_WIDTH-1:0]    doutb
);

  // CMODE: 0=WRITE_FIRST, 1=READ_FIRST, 2=NO_CHANGE
  localparam int CMODE = (COLLISION_MODE == "READ_FIRST")  ? 1 :
                         (COLLISION_MODE == "NO_CHANGE")   ? 2 : 0;

  // cascade_height=2 limits the RAMB36E2 CASDOUTB->CASDINB chain depth.
  // Without it Vivado cascades all 8 BRAMs of the 32768x8 ping-pong buffer
  // serially: 1.130 ns for the first hop + 6 x 0.210 ns + 0.117 ns ~= 2.69 ns,
  // i.e. ~45% of a 6 ns period spent purely reading the memory. That chain was
  // the source of both remaining setup violations in the integrated BD run
  // (u_pp_a/mem_reg_bram_0 -> u_cls and -> u_bert/gen_ln_units[7].u_ln).
  // Depth 2 trades a small output MUX for ~1.1 ns of slack on that path.
  (* ram_style = "block" *)
  (* cascade_height = 2 *)
  logic [DATA_WIDTH-1:0] mem [DEPTH];

  logic [DATA_WIDTH-1:0] douta_int;
  logic [DATA_WIDTH-1:0] doutb_int;

  // ==========================================================================
  // [Fix AB] Khoi tao bo nho cho MO PHONG.
  //
  // Truoc day toan bo khoi nay nam trong `ifndef SYNTHESIS`. Nhung MOI lan chay
  // kiem chung deu dinh nghia CA `SYNTHESIS` VA `GOLDEN_FUNCTIONAL`
  // (scripts/run_verify_synth_branch.tcl dong 145-146), nen ca hai viec bi bo qua:
  //
  //   1. `mem[i] = '0` khong chay -> doc o chua ghi tra ve X.
  //   2. `$readmemh` khong chay -> `u_proj_bram` (INIT_FILE="proj_bram.hex",
  //      va cong ghi bi buoc chet `wea(1'b0)`) KHONG CO GI CA, toan X.
  //
  // Hau qua da do duoc: feature_projector doc trong so X -> ghi X vao ping-pong
  // -> BERT tinh tren X -> CLS ra X. Do la ly do cls_buf[0] = cls_buf[1] =
  // 'Xb800000' khi tat viec tiem CLS, va RMS(BERT - golden) = 0,987.
  //
  // Nhanh `elsif SYNTHESIS` de TRONG co y: giu netlist tong hop y nguyen nhu
  // truoc (khi tong hop that, GOLDEN_FUNCTIONAL khong duoc dinh nghia nen
  // INIT_FILE = "" -> truoc gio cung chi co xoa-ve-0, ma BRAM von mac dinh la 0).
  // ==========================================================================
`ifdef GOLDEN_FUNCTIONAL
  initial begin
    for (int i = 0; i < DEPTH; i++) mem[i] = '0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end
`elsif SYNTHESIS
  // tong hop that: khong khoi tao trong RTL (khong doi netlist)
`else
  initial begin
    for (int i = 0; i < DEPTH; i++) mem[i] = '0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end
`endif

  //============================================================================
  // Port A
  //============================================================================
  /* verilator lint_off MULTIDRIVEN */
  always_ff @(posedge clk_a) begin
    if (ena) begin
      if (wea) begin
        mem[addra] <= dina;
        if (CMODE == 0) douta_int <= dina;       // WRITE_FIRST: read-through
        else if (CMODE == 1) douta_int <= mem[addra]; // READ_FIRST: old value
        // NO_CHANGE: don't update douta_int on write
      end else begin
        douta_int <= mem[addra];
      end
    end
  end

  /* verilator lint_on MULTIDRIVEN */
  //============================================================================
  // Port B
  //============================================================================
  /* verilator lint_off MULTIDRIVEN */
  always_ff @(posedge clk_b) begin
    if (enb) begin
      if (web) begin
        mem[addrb] <= dinb;
        if (CMODE == 0) doutb_int <= dinb;
        else if (CMODE == 1) doutb_int <= mem[addrb];
      end else begin
        doutb_int <= mem[addrb];
      end
    end
  end

  /* verilator lint_on MULTIDRIVEN */
  //============================================================================
  // Optional output register (BRAM OREG)
  //============================================================================
  generate
    if (REGISTERED_OUTPUT) begin : g_oreg
      logic [DATA_WIDTH-1:0] douta_reg;
      logic [DATA_WIDTH-1:0] doutb_reg;

      always_ff @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) douta_reg <= '0;
        else          douta_reg <= douta_int;
      end

      always_ff @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) doutb_reg <= '0;
        else          doutb_reg <= doutb_int;
      end

      assign douta = douta_reg;
      assign doutb = doutb_reg;
    end else begin : g_noreg
      assign douta = douta_int;
      assign doutb = doutb_int;
    end
  endgenerate

endmodule : dual_port_ram

//==============================================================================
// End of File
//==============================================================================
