/*------------------------------------------------------------------------------

NOTE:

- ipClk may be between 100 MHz and 143 MHz
- The clock going to the SDRAM device must lead ipCLK by 90 degrees
- The timing constraints and capacitive loading must be set as follows:

  - Output delay from -0.9 to 1.6 ns (opCKE, bpDQ*, etc.)
  - Input delay from 3.0 to 5.9 ns (bpDQ*)
  - Set up a multi-cycle requirement on the input path
  - Set the output ports to 3.8 pF (op*)
  - Set the bidirectional ports to 6.0 pF (bp*)
  - Set the clock port to 3.5 pF (External to this module)
------------------------------------------------------------------------------*/

module IS42S16320D(
  input            ipClk, // Assume 100 MHz
  input            ipReset,

  // Avalon Interface
  input      [24:0]ipAddress,
  input      [ 1:0]ipByteEnable,
  output reg       opWaitRequest,

  input      [15:0]ipWriteData,
  input            ipWrite,

  input            ipRead,
  output reg [15:0]opReadData,
  output reg       opReadDataValid,

  // Physical SDRAM Interface
  output           opCKE,
  output reg       opnCS,
  output reg       opnRAS,
  output reg       opnCAS,
  output reg       opnWE,
  output reg [12:0]opA,
  output reg [ 1:0]opBA,
  output reg [ 1:0]opDQM,
  inout      [15:0]bpDQ
);
//------------------------------------------------------------------------------

reg        enDQ;
reg  [15:0]opDQ;
wire [15:0]ipDQ = bpDQ;
assign bpDQ = enDQ ? opDQ : 16'hZ;
//------------------------------------------------------------------------------

reg [24:0]Buffer_Address;
reg [ 1:0]Buffer_ByteEnable;
reg [15:0]Buffer_WriteData;
reg       Buffer_Write;
reg       Buffer_Read;

localparam CAS_Latency     =  3;
localparam Banks           =  4;
localparam RowsAdrWidth    = 13;
localparam ColumnsAdrWidth = 10;

localparam RefreshPeriod    = 750; // < 7.8125 us
localparam PrechargeTimeout = 9500; // < 100 us
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
COMMAND Command = NOP;

assign opCKE = 1'b1;
assign {opnCS, opnRAS, opnCAS, opnWE} = Command;
//------------------------------------------------------------------------------

reg       Reset;
reg [14:0]Count;
reg [ 9:0]RefreshCount;
reg [ 3:0]RefreshBacklog;
reg [13:0]PrechargeCount;

reg [12:0]PageAddress;

logic [3:0]ReadCommands;
assign ReadCommands[0] = (Command == READ);

typedef enum{
  Powerup, Init,
  Idle,
  SetupRead, Reading,
  SetupWrite, Writing,
  Precharge, Refresh
} STATE;
STATE State;

always @(posedge ipClk) begin
  Reset <= ipReset;

  if(Reset) begin
    opWaitRequest   <=  1'b1;
    opReadData      <= 16'hx;
    opReadDataValid <=  1'b0;

    Buffer_Address    <= 13'hX;
    Buffer_ByteEnable <=  2'hX;
    Buffer_WriteData  <= 16'hX;
    Buffer_Write      <=  1'b0;
    Buffer_Read       <=  1'b0;

    Command <= NOP;
    opBA    <=  2'hx;
    opA     <= 13'hx;
    opDQM   <=  2'h3;
    enDQ    <=  1'b0;
    opDQ    <= 16'bX;

    Count          <= 0;
    RefreshCount   <= 0;
    RefreshBacklog <= 0;
    PrechargeCount <= 0;

    PageAddress <= 13'hx;

    ReadCommands[3:1] <= 0;

    State <= Powerup;
  //----------------------------------------------------------------------------

  end else begin
    if(Command == REF) begin
      if(|RefreshBacklog) RefreshBacklog <= RefreshBacklog - 1;

    end else if(RefreshCount == RefreshPeriod) begin
      RefreshCount <= 0;
      if(~&RefreshBacklog) RefreshBacklog <= RefreshBacklog + 1;

    end else begin
      RefreshCount <= RefreshCount + 1;
    end
    //--------------------------------------------------------------------------

    if     ( Command == ACT) PrechargeCount <= PrechargeTimeout;
    else if(|PrechargeCount) PrechargeCount <= PrechargeCount - 1;
    //--------------------------------------------------------------------------

    case(State)
      Powerup: begin
        if(&Count) State <= Init; // > 200 us
        Count <= Count + 1;
      end
      //------------------------------------------------------------------------

      Init: begin // Page 23 Initialise and Load Mode Register
        opDQM <=  2'h3;
        enDQ  <=  1'd0;
        opDQ  <= 16'bX;

        case(Count[6:0])
          0: begin
            Command <= PRE;
            opA     <= 13'bx_x1xx_xxxx_xxxx;
            opBA    <=  2'h3;
          end

          3, 12, 21, 30, 39, 48, 57, 66: begin
            Command <= REF;
            opBA    <=  2'hx;
            opA     <= 13'hx;
          end

          75: begin
            Command     <= MRS;
            {opBA, opA} <= {5'b0,  // Reserved
                            1'b1,  // Single Location Access
                            2'd0,  // Standard Operation
                            3'd3,  // CAS Latency 3
                            1'b0,  // Sequential
                            3'd0}; // Burst length of 1
          end

          77: begin
            Command <= NOP;
            opBA    <=  2'hx;
            opA     <= 13'hx;
            State   <= Idle;
          end

          default: begin
            Command <= NOP;
            opBA    <=  2'hx;
            opA     <= 13'hx;
          end
        endcase

        Count <= Count + 1;
      end
      //------------------------------------------------------------------------

      Idle: begin
        if(~opWaitRequest) begin
          Buffer_Address    <= ipAddress;
          Buffer_ByteEnable <= ipByteEnable;
          Buffer_WriteData  <= ipWriteData;
          Buffer_Write      <= ipWrite;
          Buffer_Read       <= ipRead;
        end

        Count <= 0;

        Command <= NOP;
        opBA    <=  2'hx;
        opA     <= 13'hx;
        opDQM   <=  2'h3;
        enDQ    <=  1'd0;
        opDQ    <= 16'bX;

        if(|RefreshBacklog) begin
          opWaitRequest <= 1'b1;
          State <= Refresh;

        end else if(opWaitRequest && Buffer_Read) begin
          State <= SetupRead;

        end else if(opWaitRequest && Buffer_Write) begin
          State <= SetupWrite;

        end else if(~opWaitRequest && ipRead) begin
          opWaitRequest <= 1;
          State <= SetupRead;

        end else if(~opWaitRequest && ipWrite) begin
          opWaitRequest <= 1;
          State <= SetupWrite;

        end else begin
          opWaitRequest <= 0;
        end
      end
      //------------------------------------------------------------------------

      SetupRead: begin
        PageAddress <= Buffer_Address[24:12];

        opDQM <=  2'h0;
        enDQ  <=  1'd0;
        opDQ  <= 16'bX;

        case(Count[3:0])
          0: begin
            Command <= ACT;
            opA     <= Buffer_Address[24:12];
            opBA    <= 2'h0;
          end

          2: begin
            Command <= ACT;
            opA     <= Buffer_Address[24:12];
            opBA    <= 2'h1;
          end

          4: begin
            Command <= ACT;
            opA     <= Buffer_Address[24:12];
            opBA    <= 2'h2;
          end

          6: begin
            Command <= ACT;
            opA     <= Buffer_Address[24:12];
            opBA    <= 2'h3;
          end

          9: begin
            opWaitRequest <= 0;
            Command <= READ;
            opBA    <= Buffer_Address[11:10];
            opA     <= {3'd0, Buffer_Address[9:0]};
            State   <= Reading;
          end

          default: begin
            Command <= NOP;
            opA     <= 13'hx;
            opBA    <=  2'hx;
          end
        endcase
        Count <= Count + 1;
      end
      //------------------------------------------------------------------------

      Reading: begin
        Buffer_Address    <= ipAddress;
        Buffer_ByteEnable <= ipByteEnable;
        Buffer_WriteData  <= ipWriteData;
        Buffer_Write      <= ipWrite;
        Buffer_Read       <= ipRead;

        Count <= 0;

        if(&RefreshBacklog || ~|PrechargeCount) begin
          opWaitRequest <= 1;
          Command       <= NOP;
          State         <= Precharge;

        end else if(ipRead) begin
          if(ipAddress[24:12] == PageAddress) begin
            Command <= READ;
            opBA    <= ipAddress[11:10];
            opA     <= {3'd0, ipAddress[9:0]};
            opDQM   <=  2'h0;
            enDQ    <=  1'd0;
            opDQ    <= 16'bX;

          end else begin
            opWaitRequest <= 1;
            Command       <= NOP;
            State         <= Precharge;
          end

        end else if(ipWrite) begin
          opWaitRequest <= 1;
          Command       <= NOP;
          State         <= Precharge;

        end else begin
          Command <= NOP;
        end
      end
      //------------------------------------------------------------------------

      SetupWrite: begin
        PageAddress <= Buffer_Address[24:12];

        case(Count[3:0])
          0: begin
            Command <= ACT;
            opA     <= Buffer_Address[24:12];
            opBA    <=  2'h0;
            opDQM   <=  2'h3;
            enDQ    <=  1'd0;
            opDQ    <= 16'bX;
          end

          2: begin
            Command <= ACT;
            opA     <= Buffer_Address[24:12];
            opBA    <=  2'h1;
            opDQM   <=  2'h3;
            enDQ    <=  1'd0;
            opDQ    <= 16'bX;
          end

          4: begin
            Command <= ACT;
            opA     <= Buffer_Address[24:12];
            opBA    <=  2'h2;
            opDQM   <=  2'h3;
            enDQ    <=  1'd0;
            opDQ    <= 16'bX;
          end

          6: begin
            Command <= ACT;
            opA     <= Buffer_Address[24:12];
            opBA    <=  2'h3;
            opDQM   <=  2'h3;
            enDQ    <=  1'd0;
            opDQ    <= 16'bX;
          end

          9: begin
            opWaitRequest <= 0;
            Command <= WRITE;
            opBA    <= Buffer_Address[11:10];
            opA     <= {3'd0, Buffer_Address[9:0]};
            opDQM   <= ~Buffer_ByteEnable;
            enDQ    <= 1'd1;
            opDQ    <= Buffer_WriteData;
            State   <= Writing;
          end

          default: begin
            Command <= NOP;
            opA     <= 13'hx;
            opBA    <=  2'hx;
            opDQM   <=  2'h3;
            enDQ    <=  1'd0;
            opDQ    <= 16'bX;
          end
        endcase
        Count <= Count + 1;
      end
      //------------------------------------------------------------------------

      Writing: begin
        Buffer_Address    <= ipAddress;
        Buffer_ByteEnable <= ipByteEnable;
        Buffer_WriteData  <= ipWriteData;
        Buffer_Write      <= ipWrite;
        Buffer_Read       <= ipRead;

        Count <= 0;

        if(&RefreshBacklog || ~|PrechargeCount) begin
          opWaitRequest <= 1;
          Command       <= NOP;
          State         <= Precharge;

        end else if(ipWrite) begin
          if(ipAddress[24:12] == PageAddress) begin
            Command <= WRITE;
            opBA    <= ipAddress[11:10];
            opA     <= {3'd0, ipAddress[9:0]};
            opDQM   <= ~ipByteEnable;
            enDQ    <=  1'd1;
            opDQ    <= ipWriteData;

          end else begin
            opWaitRequest <= 1;
            Command       <= NOP;
            State         <= Precharge;
          end

        end else if(ipRead) begin
          opWaitRequest <= 1;
          Command       <= NOP;
          State         <= Precharge;

        end else begin
          Command <= NOP;
        end
      end
      //------------------------------------------------------------------------

      Precharge: begin
        enDQ  <=  1'd0;
        opDQ  <= 16'bX;

        if(|ReadCommands) begin
          Command <= NOP;

        end else begin
          opDQM <= 2'h3;

          case(Count[1:0])
            1: begin
              Command <= PRE;
              opA     <= 13'bx_x1xx_xxxx_xxxx;
              opBA    <=  2'h3;
            end

            2: begin
              Command <= NOP;
              opBA    <=  2'hx;
              opA     <= 13'hx;
              State   <= Idle;
            end

            default: begin
              Command <= NOP;
              opBA    <=  2'hx;
              opA     <= 13'hx;
            end
          endcase
          Count <= Count + 1;
        end
      end
      //------------------------------------------------------------------------

      Refresh: begin // Page 24 Auto-Refresh Cycle
        opBA  <=  2'hx;
        opA   <= 13'hx;
        opDQM <=  2'h3;
        enDQ  <=  1'd0;
        opDQ  <= 16'bX;

        case(Count[3:0])
          0: begin
            Command <= REF;
          end

          8: begin
            Command <= NOP;
            State   <= Idle;
          end

          default: begin
            Command <= NOP;
          end
        endcase
        Count <= Count + 1;
      end
      //------------------------------------------------------------------------

      default:;
    endcase
    //--------------------------------------------------------------------------

    opReadData <= ipDQ;
    { opReadDataValid, ReadCommands[3:1] } <= ReadCommands;
  end
end
//------------------------------------------------------------------------------

endmodule
//------------------------------------------------------------------------------

