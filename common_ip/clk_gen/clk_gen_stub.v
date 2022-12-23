// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Mon Dec  5 11:21:55 2022
// Host        : DESKTOP-CB2GNLG running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub -rename_top clk_gen -prefix
//               clk_gen_ clk_gen_stub.v
// Design      : clk_gen
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tcsg324-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module clk_gen(clk_100mhz, clk_200mhz, clk_325mhz, resetn, 
  clk_in1)
/* synthesis syn_black_box black_box_pad_pin="clk_100mhz,clk_200mhz,clk_325mhz,resetn,clk_in1" */;
  output clk_100mhz;
  output clk_200mhz;
  output clk_325mhz;
  input resetn;
  input clk_in1;
endmodule
