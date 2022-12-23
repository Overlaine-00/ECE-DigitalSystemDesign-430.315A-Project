/*
 * SNU ECE Digital Systems Design
 *
 * mac.v
 */

`timescale 1ns / 1ps

module mac #(
  parameter integer A_BITWIDTH = 8,
  parameter integer B_BITWIDTH = A_BITWIDTH,
  parameter integer OUT_BITWIDTH = 26
) (
  input clk,
  input rstn,
  input en,
  input signed [A_BITWIDTH-1:0] din_a,
  input signed [B_BITWIDTH-1:0] din_b,
  input pause,
  
  output reg signed [OUT_BITWIDTH-1:0] dout
);
  // define states
  localparam STATE_IDLE = 1'b0;
  localparam STATE_COMP = 1'b1;
  
  reg state;

  // internal registers
  
  // control path
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state <= STATE_IDLE;
    end else begin
      case (state)
        STATE_IDLE: begin
          if (en) begin
            state <= STATE_COMP;
          end else begin
            state <= STATE_IDLE;
          end
        end
  
        STATE_COMP: begin
          if(!en) begin
            
            state <= STATE_IDLE;
          end else begin
            state <= STATE_COMP;
          end
        end
        
  
        default:;
      endcase
    end
  end
  
  // data path
  always @ (posedge clk or negedge rstn) begin
    if (!rstn) begin
      dout <= {OUT_BITWIDTH{1'b0}};
    end else begin
      case (state)
        STATE_IDLE: begin
          dout <= {OUT_BITWIDTH{1'b0}};
        end
        
        STATE_COMP: begin
          if(!pause) begin
            dout <= dout + din_a * din_b;
          end else begin
            dout <= dout;
          end
        end
        
        default:;
      endcase
    end
  end

endmodule
