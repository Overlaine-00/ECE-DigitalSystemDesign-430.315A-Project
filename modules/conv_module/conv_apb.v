/*
* conv_apb.v
*/

module conv_apb 
  (
    input wire PCLK,           // APB clock
    input wire PRESETB,        // APB asynchronous reset (0: reset, 1: normal)
    input wire [31:0] PADDR,   // APB address
    input wire PSEL,           // APB select
    input wire PENABLE,        // APB enable
    input wire PWRITE,         // APB write enable
    input wire [31:0] PWDATA,  // APB write data
    output wire [31:0] PRDATA,

    input wire [31:0] clk_counter,
    input wire [0:0] conv_done,
    output reg [0:0] conv_start,

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports if you need them
    //////////////////////////////////////////////////////////////////////////
    input feature_done,
    input bias_done,
    input weight_done,

    output reg feature_respond,
    output reg bias_respond,
    output reg weight_respond,
    output reg conv_respond,
    
    output reg [2:0]  command,
    output reg [8:0]  in_ch,
    output reg [8:0]  out_ch,
    output reg [5:0]  flen
    
  );
  
  wire state_enable;
  wire state_enable_pre;
  reg [31:0] prdata_reg;
  
  assign state_enable = PSEL & PENABLE;
  assign state_enable_pre = PSEL & ~PENABLE;

  //////////////////////////////////////////////////////////////////////////
  // TODO : Write your code here
  //////////////////////////////////////////////////////////////////////////
  
  // READ OUTPUT
  always @(posedge PCLK, negedge PRESETB) begin
    if (PRESETB == 1'b0) begin
      prdata_reg <= 32'h00000000;
    end
    else begin
      if (~PWRITE & state_enable_pre) begin
        case ({PADDR[31:2], 2'h0})
          /*READOUT*/
          32'h00000000 : prdata_reg <= {31'h0,conv_start};
          32'h00000004 : prdata_reg <= {31'd0,conv_done};
          32'h00000008 : prdata_reg <= clk_counter; //Do not fix!
          32'h00000020 : prdata_reg <= {31'h0,feature_done};
          32'h00000024 : prdata_reg <= {31'h0,bias_done};
          32'h00000028 : prdata_reg <= {31'h0,weight_done};
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
      conv_start <= 0;
      command <= 0;
    end
    else begin
      if (PWRITE & state_enable) begin
        case ({PADDR[31:2], 2'h0})
          /*WRITEIN*/
          32'h00000000 : begin
            case(PWDATA)
                32'h00000000: begin
                    conv_start <= 0;
                    command <= 0;
                    in_ch <= 0;
                    out_ch <= 0;
                    flen <= 0;
                    feature_respond <= 0;
                    bias_respond <= 0;
                    weight_respond <= 0;
                    conv_respond <= 0;
                end
                32'h00000001: begin
                    conv_start <= 1;
                    command <= 1;
                end
                32'h00000002: command <= 2;
                32'h00000003: command <= 3;
                32'h00000004: command <= 4;
            endcase
          end
          32'h00000004 : in_ch <= PWDATA;
          32'h00000008 : out_ch <= PWDATA;
          32'h0000000c : flen <= PWDATA;
          32'h00000010 : feature_respond <= PWDATA;
          32'h00000014 : bias_respond <= PWDATA;
          32'h00000018 : weight_respond <= PWDATA;
          32'h0000001c : conv_respond <= PWDATA;
        endcase
      end
    end
  end

endmodule
