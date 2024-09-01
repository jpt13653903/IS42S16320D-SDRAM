/*------------------------------------------------------------------------------

Typical run-time: 1 ms
------------------------------------------------------------------------------*/

`timescale 1ns/1ps
//------------------------------------------------------------------------------

function void report(string Message);
  $timeformat(-9, 2, " ns", 3);
  $display("%t: %s", $time, Message);
endfunction
//------------------------------------------------------------------------------

module IS42S16320D_TB;
//------------------------------------------------------------------------------

reg ipClk     = 0;
reg SDRAM_Clk = 0;

always begin
  SDRAM_Clk <= 1; #1.75ns;
  ipClk     <= 1; #1.75ns;
  SDRAM_Clk <= 0; #1.75ns;
  ipClk     <= 0; #1.75ns;
end
//------------------------------------------------------------------------------

reg ipReset = 1;
initial #50 ipReset <= 0;
//------------------------------------------------------------------------------

const realtime t_CK    =  7.0ns;
const realtime t_AC    =  5.4ns;
const realtime t_CH    =  2.5ns;
const realtime t_CL    =  2.5ns;
const realtime t_OH    =  2.7ns;
const realtime t_LZ    =  0.0ns;
const realtime t_HZ    =  5.4ns;
const realtime t_DS    =  1.5ns;
const realtime t_DH    =  0.8ns;
const realtime t_AS    =  1.5ns;
const realtime t_AH    =  0.8ns;
const realtime t_CKS   =  1.5ns;
const realtime t_CKH   =  0.8ns;
const realtime t_CMS   =  1.5ns;
const realtime t_CMH   =  0.8ns;
const realtime t_RC    = 60.0ns;
const realtime t_RAS   = 37.0ns;
const realtime t_RP    = 15.0ns;
const realtime t_RCD   = 15.0ns;
const realtime t_RRD   = 14.0ns;
const realtime t_DPL   = 14.0ns;
const realtime t_DAL   = 29.0ns;
const realtime t_MRD   = 14.0ns;
const realtime t_DDE   =  7.0ns;
const realtime t_XSR   = 67.0ns;
const realtime t_T_min =  0.3ns;
const realtime t_T_max =  1.2ns;
const realtime t_REF   = 64.0ms;
const realtime t_PCB   =  3.0ns; // Includes the FPGA IO delay
//------------------------------------------------------------------------------

reg  [24:0]ipAddress;
wire       opWaitRequest;

reg  [15:0]ipWriteData;
reg        ipWrite;

reg        ipRead;
wire [15:0]opReadData;
wire       opReadDataValid;

wire               opCKE;
wire               opnCS;
wire               opnRAS;
wire               opnCAS;
wire               opnWE;
wire [12:0]        opA;
wire [ 1:0]        opBA;
wire [ 1:0]        opDQM;
wire [15:0] #t_PCB bpDQ;

IS42S16320D DUT(
  .ipClk          (ipClk),
  .ipReset        (ipReset),

  .ipAddress      (ipAddress),
  .opWaitRequest  (opWaitRequest),

  .ipWriteData    (ipWriteData),
  .ipWrite        (ipWrite),

  .ipRead         (ipRead),
  .opReadData     (opReadData),
  .opReadDataValid(opReadDataValid),

  .opCKE          (opCKE),
  .opnCS          (opnCS),
  .opnRAS         (opnRAS),
  .opnCAS         (opnCAS),
  .opnWE          (opnWE),
  .opA            (opA),
  .opBA           (opBA),
  .opDQM          (opDQM),
  .bpDQ           (bpDQ)
);
//------------------------------------------------------------------------------

initial begin
  ipAddress   <= ~25'h0;
  ipWriteData <= 16'h5677;
  ipWrite     <=  1'b0;
  ipRead      <=  1'b0;

  #200us;

  report("Writing...");
  @(posedge ipClk);
  repeat(16384) begin
    ipWriteData <= ipWriteData + 1;
    ipAddress   <= ipAddress   + 1;
    ipWrite     <= 1;
    do @(posedge ipClk); while(opWaitRequest);
  end
  ipAddress <= ~25'h0;
  ipWrite   <= 0;

  report("Reading...");
  @(posedge ipClk);
  repeat(16384) begin
    ipAddress <= ipAddress + 1;
    ipRead    <= 1;
    do @(posedge ipClk); while(opWaitRequest);
  end
  ipAddress <= ~25'h0;
  ipRead    <= 0;

  report("Simulation complete...");
end
//------------------------------------------------------------------------------

// SDRAM Emulation
wire        #2ns CKE  = opCKE;
wire        #2ns nCS  = opnCS;
wire        #2ns nRAS = opnRAS;
wire        #2ns nCAS = opnCAS;
wire        #2ns nWE  = opnWE;
wire [12:0] #2ns A    = opA;
wire [ 1:0] #2ns BA   = opBA;
wire [ 1:0] #2ns DQM  = opDQM;
wire [15:0] #2ns DQ   = bpDQ;
//------------------------------------------------------------------------------

typedef enum logic[3:0] {
  DESL  = 4'b1xxx,
  NOP   = 4'b0111,
  BST   = 4'b0110,
  READ  = 4'b0101,
  WRITE = 4'b0100,
  ACT   = 4'b0011,
  PRE   = 4'b0010, // A10 = 1 => PALL
  REF   = 4'b0001,
  MRS   = 4'b0000  // A10 = 0; BA = 0
} COMMAND;
wire [3:0]Command = {nCS, nRAS, nCAS, nWE};

reg [ 2:0]ReadCommand;
reg [15:0]DQ_buf;
reg [15:0]DQ_buf_delayed;

integer Memory = 0;

always @(posedge SDRAM_Clk) begin
  ReadCommand = {ReadCommand[1:0], (Command == READ)};

  #t_OH;
  if(ReadCommand[2]) DQ_buf <= 16'hX;
  else               DQ_buf <= 16'hZ;

  #(t_AC - t_OH);
  if(ReadCommand[2]) DQ_buf <= Memory;
  else               DQ_buf <= 16'hZ;

  Memory++;
end
assign bpDQ = DQ_buf;
//------------------------------------------------------------------------------

endmodule
//------------------------------------------------------------------------------

