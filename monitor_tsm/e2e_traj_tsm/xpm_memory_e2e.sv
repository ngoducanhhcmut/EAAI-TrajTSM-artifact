// Testbench-only model of the exact common-clock XPM configuration used by planning_top.
// Xsim uses the vendor model instead. No ECC, initialization or alternative modes.
`timescale 1ns/1ps
module xpm_memory_tdpram #(
  parameter MEMORY_SIZE=64, MEMORY_PRIMITIVE="ultra", CLOCKING_MODE="common_clock",
  parameter WRITE_DATA_WIDTH_A=64,READ_DATA_WIDTH_A=64,BYTE_WRITE_WIDTH_A=64,ADDR_WIDTH_A=1,
  parameter WRITE_DATA_WIDTH_B=64,READ_DATA_WIDTH_B=64,BYTE_WRITE_WIDTH_B=64,ADDR_WIDTH_B=1,
  parameter READ_LATENCY_A=2,READ_LATENCY_B=2,WRITE_MODE_A="no_change",WRITE_MODE_B="no_change",
  parameter MEMORY_INIT_FILE="none",USE_MEM_INIT=0
) (
  input logic clka,clkb,rsta,rstb,ena,enb,wea,web,
  input logic [ADDR_WIDTH_A-1:0] addra,
  input logic [ADDR_WIDTH_B-1:0] addrb,
  input logic [WRITE_DATA_WIDTH_A-1:0] dina,
  input logic [WRITE_DATA_WIDTH_B-1:0] dinb,
  output logic [READ_DATA_WIDTH_A-1:0] douta,
  output logic [READ_DATA_WIDTH_B-1:0] doutb,
  input logic regcea,regceb,sleep,injectsbiterra,injectdbiterra,injectsbiterrb,injectdbiterrb
);
  logic [63:0] mem[0:MEMORY_SIZE/64-1],qa,qb;
  initial begin
    if(CLOCKING_MODE!="common_clock" || READ_LATENCY_A!=2 || READ_LATENCY_B!=2 ||
       WRITE_MODE_A!="no_change" || WRITE_MODE_B!="no_change" ||
       WRITE_DATA_WIDTH_A!=64 || WRITE_DATA_WIDTH_B!=64 || READ_DATA_WIDTH_A!=64 ||
       READ_DATA_WIDTH_B!=64 || BYTE_WRITE_WIDTH_A!=64 || BYTE_WRITE_WIDTH_B!=64 || USE_MEM_INIT!=0)
      $fatal(1,"unsupported XPM model configuration");
  end
  // Common-clock, registered-output, no_change behavior. Simultaneous write
  // collisions are forbidden; the production arbiter prevents them.
  always @(posedge clka) begin
    if(sleep || injectsbiterra || injectdbiterra || injectsbiterrb || injectdbiterrb)
      $fatal(1,"unsupported XPM mode");
    if(ena) begin
      if(wea) mem[addra]<=dina;
      else qa<=mem[addra];
    end
    if(enb) begin
      if(web) mem[addrb]<=dinb;
      else qb<=mem[addrb];
    end
    if(rsta) douta<=0;else if(regcea) douta<=qa;
    if(rstb) doutb<=0;else if(regceb) doutb<=qb;
    if(ena && enb && wea && web && addra==addrb) $fatal(1,"XPM write collision");
  end
endmodule
