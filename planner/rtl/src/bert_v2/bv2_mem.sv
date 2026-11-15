//==============================================================================
// bv2_mem.sv — bo nho hanh vi cho BERT V2 (suy ra BRAM). Do tre doc = 2 chu ky
// (thanh ghi dia chi trong RAM + thanh ghi du lieu ra) cho moi loai.
//==============================================================================
`timescale 1ns / 1ps

// RAM 2 cong doc/ghi doc lap (moi cong: ghi tu, doc tu). Doc tre 2.
module bv2_ram_tdp #(
  parameter int W = 32,
  parameter int D = 1024,
  parameter int AW = $clog2(D)
) (
  input  logic          clk,
  input  logic          a_en, a_we,
  input  logic [AW-1:0] a_addr,
  input  logic [W-1:0]  a_wd,
  output logic [W-1:0]  a_rd,
  input  logic          b_en, b_we,
  input  logic [AW-1:0] b_addr,
  input  logic [W-1:0]  b_wd,
  output logic [W-1:0]  b_rd
);
  (* ram_style = "block" *) logic [W-1:0] mem [D];
  logic [W-1:0] a_q, b_q;
  always_ff @(posedge clk) begin
    if (a_en) begin
      if (a_we) mem[a_addr] <= a_wd;
      a_q <= mem[a_addr];
    end
    a_rd <= a_q;
  end
  always_ff @(posedge clk) begin
    if (b_en) begin
      if (b_we) mem[b_addr] <= b_wd;
      b_q <= mem[b_addr];
    end
    b_rd <= b_q;
  end
endmodule : bv2_ram_tdp


// RAM ghi theo BYTE (1 byte/chu ky, chi so byte wb), doc ca tu. Doc tre 2.
module bv2_ram_bytew #(
  parameter int NB = 64,               // so byte moi tu
  parameter int D  = 2560,
  parameter int AW = $clog2(D),
  parameter int BW = $clog2(NB)
) (
  input  logic            clk,
  input  logic            we,
  input  logic [AW-1:0]   waddr,
  input  logic [BW-1:0]   wb,
  input  logic [7:0]      wd,
  input  logic            re,
  input  logic [AW-1:0]   raddr,
  output logic [NB*8-1:0] rd
);
  (* ram_style = "block" *) logic [NB*8-1:0] mem [D];
  logic [NB*8-1:0] q;
  always_ff @(posedge clk) begin
    if (we)
      for (int i = 0; i < NB; i++)
        if (wb == BW'(i)) mem[waddr][i*8 +: 8] <= wd;
  end
  always_ff @(posedge clk) begin
    if (re) q <= mem[raddr];
    rd <= q;
  end
endmodule : bv2_ram_bytew
