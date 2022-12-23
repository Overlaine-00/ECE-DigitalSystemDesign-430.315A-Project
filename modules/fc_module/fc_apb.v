/*
* fc_apb.v
*/

module fc_apb
  (
    input wire PCLK,
    input wire PRESETB,        // APB asynchronous reset (0: reset, 1: normal)
    input wire [31:0] PADDR,   // APB address
    input wire PSEL,           // APB select
    input wire PENABLE,        // APB enable
    input wire PWRITE,         // APB write enable
    input wire [31:0] PWDATA,  // APB write data
    output wire [31:0] PRDATA,  // CPU interface out

    input wire [31:0] clk_counter,
    input wire [31:0] max_index,
    input wire [0:0] fc_done,
    
    output reg [0:0] fc_start,

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports as you need
    //////////////////////////////////////////////////////////////////////////
    
    input input_recv_done,
    input bias_recv_done,
    input cal_done,
    
    
    output reg [2:0]  apb_command,
    output reg [10:0] receive_size
    
    
  );

  wire state_enable;
  wire state_enable_pre;
  reg [31:0] prdata_reg;
  
  assign state_enable = PSEL & PENABLE;
  assign state_enable_pre = PSEL & ~PENABLE;
  
  ////////////////////////////////////////////////////////////////////////////
  // TODO : Write your code here
  ////////////////////////////////////////////////////////////////////////////
  
  // READ OUTPUT
  always @(posedge PCLK, negedge PRESETB) begin
    if (PRESETB == 1'b0) begin
      prdata_reg <= 32'h00000000;
    end
    else begin
      if (~PWRITE & state_enable_pre) begin
        case ({PADDR[31:2], 2'h0})
          /*READOUT*/
          32'h00000008 : prdata_reg <= clk_counter; // Do not fix!
          32'h0000000c : prdata_reg <= {{31{1'b0}},fc_done};
          32'h00000014 : prdata_reg <= {{31{1'b0}},input_recv_done};
          32'h00000018 : prdata_reg <= {{31{1'b0}},bias_recv_done};
          32'h0000001c : prdata_reg <= {{31{1'b0}},cal_done};
          32'h00000020 : prdata_reg <= max_index;
          default: prdata_reg <= 32'h0;
        endcase
      end
      else begin
        prdata_reg <= 32'h0;
      end
    end
  end
  
  assign PRDATA = (~PWRITE & state_enable) ? prdata_reg : 32'h00000000;
  
  // WRITE ACCESS
  always @(posedge PCLK, negedge PRESETB) begin
    if (PRESETB == 1'b0) begin
      /*WRITERES*/
      fc_start <= 1'b0;
      apb_command <= 3'b0;
      receive_size <= 11'b0;
    end
    else begin
      if (PWRITE & state_enable) begin
        case ({PADDR[31:2], 2'h0})
          /*WRITEIN*/
          32'h00000000 : begin
            if(PWDATA == 32'h00000005) begin
              fc_start <= 1'b1;
            end else
            if(PWDATA == 32'h00000001) begin
              apb_command <= 3'b001;
            end else
            if(PWDATA == 32'h00000002) begin
              apb_command <= 3'b010;
            end else
            if(PWDATA == 32'h00000003) begin
              apb_command <= 3'b011;
            end else 
            if(PWDATA == 32'h00000004) begin
              apb_command <= 3'b100;
            end else 
            if(PWDATA == 32'h00000000) begin
              fc_start <= 1'b0;
              apb_command <= 3'b0;
              receive_size <= 11'b0;
            end 
          end
          32'h00000004 : begin
            receive_size <= PWDATA;
          end
          default: ;
        endcase
      end
    end
  end
endmodule
  
