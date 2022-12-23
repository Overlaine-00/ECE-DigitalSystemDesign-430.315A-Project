/*
 * SNU ECE Digital Systems Design
 *
 * fc_module.v
 */

`timescale 1ns / 1ps

module fc_module 
(
  input             clk,                 
  input             rstn,                
  
  input  [10:0]     receive_size,
  input             fc_start,
  input  [2:0]      apb_command,
  
  input             M_AXIS_TREADY,
  input  [31:0]     S_AXIS_TDATA,
  input             S_AXIS_TVALID,
  input             S_AXIS_TLAST,
  input  [3:0]      S_AXIS_TKEEP,
  input             S_AXIS_TUSER,
  
  
  output            S_AXIS_TREADY,
  output [31:0]     M_AXIS_TDATA,
  output            M_AXIS_TVALID,
  output            M_AXIS_TLAST,
  output [3:0]      M_AXIS_TKEEP,  
  output            M_AXIS_TUSER,
  
  output reg        input_recv_done,
  output reg        bias_recv_done,
  output reg        cal_done,
  output reg        fclayer_done,
  
  output reg        start_response,
  
  output reg [31:0] max_index
);
  reg [10:0]        input_size;
  reg [10:0]        output_size;

  reg               s_axis_tready;
  reg [31:0]        m_axis_tdata;
  reg               m_axis_tvalid;
  reg               m_axis_tlast;
  
  assign S_AXIS_TREADY  = s_axis_tready;
  assign M_AXIS_TDATA   = m_axis_tdata;
  assign M_AXIS_TVALID  = m_axis_tvalid;
  assign M_AXIS_TLAST   = m_axis_tlast;
  assign M_AXIS_TKEEP   = {4{1'b1}};
  assign M_AXIS_TUSER   = 1'b0;

  // define states
  localparam STATE_IDLE         = 3'd0;
  localparam STATE_INPUT_RECV   = 3'd1; // Receive data from testbench and write data to BRAM
  localparam STATE_BIAS_RECV    = 3'd2; // Read input from BRAM and set input
  localparam STATE_CALCULATE    = 3'd3; // Read weight from BRAM and set weight
  localparam STATE_SEND         = 3'd4; // Accumulate productions of weight and value for one output.
  localparam STATE_FCDONE       = 3'd5; // Send result data to testbench
  
  localparam RECV_INPUT     = 3'd1;
  localparam RECV_BIAS      = 3'd2;
  localparam CALCULATE      = 3'd4;
  localparam SEND           = 3'd3;
  localparam FINISH         = 3'd0;
  
  reg [2:0]         fc_state; // Memory Unit Controller state

  reg               last_layer;
  reg               cal_start;
  reg               what_to_cal;
  reg               cal_save;
  reg               bias_calc;
  reg [1:0]         cal_choose;
  reg               data_set;
  reg [1:0]         delay;
  reg               pause;
  reg               send_done;
  reg signed [25:0] biggest_data;
  reg signed [25:0] result_to_compare;

  reg [8:0]         input_addr;
  reg [6:0]         bias_addr;
  reg [8:0]         weight_First_addr;
  reg [8:0]         weight_Second_addr;
  reg [6:0]         out_addr;
  reg [31:0]        out_in;
  wire [31:0]       input_out, bias_out, weight_First_out, weight_Second_out, out_out;
  wire              input_en, input_we, bias_en, bias_we, weight_First_en, weight_First_we, weight_Second_en, weight_Second_we, out_en, out_we;
  
  assign input_en           = (fc_state == STATE_INPUT_RECV) || (fc_state == STATE_CALCULATE);
  assign bias_en            = (fc_state == STATE_BIAS_RECV) || (fc_state == STATE_CALCULATE);
  assign weight_First_en    = (fc_state == STATE_CALCULATE);
  assign weight_Second_en   = (fc_state == STATE_CALCULATE);
  assign out_en             = (fc_state == STATE_CALCULATE) || (fc_state == STATE_SEND);
  
  assign input_we           = (fc_state == STATE_INPUT_RECV && !input_recv_done);
  assign bias_we            = (fc_state == STATE_BIAS_RECV && !bias_recv_done);
  assign weight_First_we    = !cal_choose[0];
  assign weight_Second_we   = !cal_choose[1];
  assign out_we             = cal_save;
  
  
  sram_32x512   inputSRAM(.clka(clk), .ena(input_en), .wea(input_we), .addra(input_addr), .dina(S_AXIS_TDATA), .douta(input_out));
  sram_32x128   biasSRAM(.clka(clk), .ena(bias_en), .wea(bias_we), .addra(bias_addr), .dina(S_AXIS_TDATA), .douta(bias_out));
  sram_32x512   weightFirstSRAM(.clka(clk), .ena(weight_First_en), .wea(weight_First_we), .addra(weight_First_addr), .dina(S_AXIS_TDATA), .douta(weight_First_out));
  sram_32x512   weightSecondSRAM(.clka(clk), .ena(weight_Second_en), .wea(weight_Second_we), .addra(weight_Second_addr), .dina(S_AXIS_TDATA), .douta(weight_Second_out));
  sram_32x128   outSRAM(.clka(clk), .ena(out_en), .wea(out_we), .addra(out_addr), .dina(out_in), .douta(out_out));
  
  reg [31:0]        data_a_temp;
  reg [31:0]        data_b_temp;
  
  // Compute Unit
  reg               mac_en;          // enable MAC Unit
  wire [7:0]        data_a;          // input to the MAC Unit
  wire [7:0]        data_b;          // input to the MAC Unit


  wire signed [25:0] result_accurate;

  // Multiply-Accumulate (MAC) Unit
  mac u_mac (
    .clk  (clk),
    .rstn (rstn),
    .en   (mac_en),
    .din_a(data_a), 
    .din_b(data_b),
    .pause(pause),

    .dout (result_accurate)
  );

  wire [7:0]        result_quantized;
  assign result_quantized = (result_accurate[25] == 0) ? (result_accurate[24:13] == 12'b000000000000 ? {result_accurate[25],result_accurate[13:6]} : 8'b01111111)  : (result_accurate[24:13] == 12'b111111111111 ? (last_layer ? ({result_accurate[25],result_accurate[12:6]}+8'b00000001): {result_accurate[25],result_accurate[12:6]}) : 8'b10000000) /*TODO*/;
  //(result_accurate[25] == 0) ? (result_accurate[24:13] == 12'b000000000000 ? {result_accurate[25],result_accurate[12:6]} : 8'b01111111)  : (result_accurate[24:13] == 12'b111111111111 ? (last_layer && result_accurate[5:0] == 6'b111111 ? ({result_accurate[25],result_accurate[12:6]}+8'b00000001): {result_accurate[25],result_accurate[12:6]}) : 8'b10000000) /*TODO*/;
  //(result_accurate[25] == 0) ? (result_accurate[24:13] == 12'b000000000000 ? {result_accurate[25],result_accurate[12:6]} : 8'b01111111)  : (result_accurate[24:13] == 12'b111111111111 ? (last_layer ? ({result_accurate[25],result_accurate[12:6]}+8'b00000001): {result_accurate[25],result_accurate[12:6]}) : 8'b10000000) /*TODO*/;
  reg [10:0]       cal_counter;
  reg [10:0]       element_counter;    
  reg [10:0]       out_counter;        
  
  assign data_a = bias_calc ? 8'b01000000 : data_a_temp[8*cal_counter[1:0]+:8];
  assign data_b = bias_calc ? bias_out[8*out_counter[1:0]+:8] : data_b_temp[8*cal_counter[1:0]+:8];
  
  
  
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      fc_state <= STATE_IDLE;
      max_index <= 32'b0;
    end else begin
      if(fc_start) begin
        start_response <= 1'b1;
      end
      
      case (fc_state)
        // wait for the testbench to send the data
        STATE_IDLE: begin 
          input_recv_done <= 1'b0;
          bias_recv_done <= 1'b0;
          cal_done <= 1'b0;
          fclayer_done <= 1'b0;
          
        
          input_size <= 1'b0;
          output_size <= 1'b0;
          
          s_axis_tready <= 1'b0;
          m_axis_tdata <= {32{1'b0}};
          m_axis_tvalid <= 1'b0;
          m_axis_tlast <= 1'b0;
          
          last_layer <= 1'b0;
          cal_start <= 1'b0;
          what_to_cal <= 1'b0;
          cal_save <= 1'b0;
          bias_calc <= 1'b0;
          cal_choose <= 2'b0;
          data_set <= 1'b0;
          delay <= 2'b0;
          pause <= 1'b1;
          send_done <= 1'b0;
          biggest_data <= 26'b0;
          result_to_compare <= 26'b0;
          
          
          
          input_addr <= 9'b0;
          bias_addr <= 7'b0;
          weight_First_addr <= 9'b0;
          weight_Second_addr <= 9'b0;
          out_addr <= 7'b0;
          out_in <= 32'b0;
          
          data_a_temp <= {32{1'b0}};
          data_b_temp <= {32{1'b0}};
          
          mac_en <= 1'b0;
          
          cal_counter <= 11'b0;
          element_counter <= 11'b0;
          out_counter <= 11'b0;
                    
          if(apb_command == RECV_INPUT ) begin
            fc_state <= STATE_INPUT_RECV;
          end
        end
  
        // receive data from the testbench and write it to the BRAM
        STATE_INPUT_RECV: begin
          if(input_recv_done) begin
            element_counter <= 11'b0;
            s_axis_tready <= 1'b0;
            input_addr <= 9'b0;
            max_index <= 32'b0;
            if(apb_command == RECV_BIAS) begin
              input_recv_done <= 1'b0;
              fc_state <= STATE_BIAS_RECV;
            end
          end 
          else if(!s_axis_tready) begin
            s_axis_tready <= 1'b1;
          end
          else if(S_AXIS_TVALID) begin
            if(element_counter == (receive_size>>2)-1) begin
              s_axis_tready <= 1'b0;
              element_counter <= 11'b0;
              input_size <= receive_size;
              input_addr <= 9'b0;
              input_recv_done <= 1'b1;
            end else begin
              element_counter <= element_counter + 1;
              input_addr <= input_addr + 1;
            end
          end
        end
  
        // read input activation from the BRAM and set register
        STATE_BIAS_RECV: begin
          if(bias_recv_done) begin
            element_counter <=11'b0;
            s_axis_tready <= 1'b0;
            bias_addr <= 7'b0;
            if(apb_command == CALCULATE) begin
              bias_recv_done <= 1'b0;
              fc_state <= STATE_CALCULATE;
            end
          end 
          else if(!s_axis_tready) begin
            s_axis_tready = 1'b1;
            if(receive_size == 10) last_layer <= 1'b1;
          end
          else if(S_AXIS_TVALID) begin    
            if(last_layer) begin
              if(element_counter == (receive_size>>2)) begin
                s_axis_tready <= 1'b0;
                element_counter <= 11'b0;
                bias_addr <= 7'b0;
                output_size <= receive_size;
                bias_recv_done <= 1'b1;
              end else begin
                element_counter <= element_counter + 1;
                bias_addr <= bias_addr + 1;
              end
            end else
            if(element_counter == (receive_size>>2)-1) begin
              s_axis_tready <= 1'b0;
              element_counter <= 11'b0;
              bias_addr <= 7'b0;
              output_size <= receive_size;
              bias_recv_done <= 1'b1;
            end else begin
              element_counter <= element_counter + 1;
              bias_addr <= bias_addr + 1;
            end
          end
        end
  
        // read weight from the BRAM and set register
        STATE_CALCULATE : begin
          if(cal_done) begin
            out_addr <= 7'b0;
            bias_addr <= 7'b0;
            input_addr <= 9'b0;
            weight_First_addr <= 9'b0;
            weight_Second_addr <= 9'b0;
            s_axis_tready <= 1'b0;
            element_counter <= 11'b0;
            cal_counter <= 11'b0;
            mac_en <= 1'b0;
            cal_choose <= 2'b00;
            out_counter <= 11'b0;
            delay <= 2'b0;
            if(apb_command == SEND) begin
              fc_state <= STATE_SEND;
              cal_done <= 1'b0;
            end
          end 
          else begin
            if(cal_save) begin
              out_addr <= out_addr + 1;
              out_in <= {32{1'b0}};
              bias_addr <= bias_addr + 1;
              cal_save <= 1'b0;
              cal_start <= 1'b0;
              delay <= 2'b0;
              if(out_counter == output_size) cal_done <= 1'b1;
            end else if(last_layer && out_counter == output_size) begin
              cal_save <= 1'b1;
              out_in[31:16] <= 16'b0;
            end
            else if(cal_start && out_counter[1:0] == 2'b00) cal_save <= 1'b1;
            else if(cal_choose != 2'b00) begin
              if(!data_set) begin
                if(delay != 2'b10) delay <= delay + 1;
                else begin
                  data_set <= 1'b1; 
                  data_a_temp <= input_out;
                  if(what_to_cal) data_b_temp <= weight_Second_out;
                  else data_b_temp <= weight_First_out;
                  pause <= 1'b0;
                  mac_en <= 1'b1;
                  delay <= 2'b0;
                end
              end else if(!what_to_cal && cal_choose[0]) begin
                if(cal_counter == input_size) begin
                  if(delay == 2'b00) begin
                    mac_en <= 1'b0;
                    pause <= 1'b1;
                    bias_calc <= 1'b0;
                    delay <= delay + 1;
                  end else if(delay == 2'b01) begin
                    result_to_compare <= result_accurate;
                    delay <= delay + 1;
                  end else if(delay == 2'b10) begin
                    if(last_layer && (result_to_compare > biggest_data)) begin
                      biggest_data <= result_to_compare;
                      max_index <= out_counter + 1;
                    end
                    out_in[8*out_counter[1:0]+:8] <= result_quantized;
                    delay <= delay + 1;
                  end else begin
                    mac_en <= 1'b1;
                    delay <= 2'b0;
                    cal_counter <= 11'b0;
                    cal_choose[0] <= 1'b0;
                    what_to_cal <= 1'b1;
                    weight_First_addr <= 9'b0;
                    input_addr <= 9'b0;
                    out_counter <= out_counter + 1;
                    
                    data_set <= 1'b0;
                    if(!cal_start) cal_start <= 1'b1;
                  end
                end else if(cal_counter == input_size-1) begin
                  cal_counter <= cal_counter + 1;
                  bias_calc <= 1'b1;
                end else begin
                  cal_counter <= cal_counter + 1;
                  if(cal_counter[1:0] == 2'b11) begin
                    weight_First_addr <= weight_First_addr + 1;
                    input_addr <= input_addr + 1;
                    pause <= 1'b1;
                    data_set <= 1'b0;
                  end
                end
              end else if(what_to_cal && cal_choose[1]) begin
                if(cal_counter == input_size) begin
                  if(delay == 2'b00) begin
                    mac_en <= 1'b0;
                    pause <= 1'b1;
                    bias_calc <= 1'b0;
                    delay <= delay + 1;
                  end else if(delay == 2'b01) begin
                    result_to_compare <= result_accurate;
                    delay <= delay + 1;
                  end else if(delay == 2'b10) begin
                    if(last_layer && (result_to_compare > biggest_data)) begin
                      biggest_data <= result_to_compare;
                      max_index <= out_counter + 1;
                    end
                    out_in[8*out_counter[1:0]+:8] <= result_quantized;
                    delay <= delay + 1;
                  end else begin
                    mac_en <= 1'b1;
                    delay <= 2'b0;
                    cal_counter <= 11'b0;
                    cal_choose[1] <= 1'b0;
                    what_to_cal <= 1'b0;
                    weight_Second_addr <= 9'b0;
                    input_addr <= 9'b0;
                    out_counter <= out_counter + 1;
                    data_set <= 1'b0;
                    if(!cal_start) cal_start <= 1'b1;
                  end
                end else if(cal_counter == input_size-1) begin
                  cal_counter <= cal_counter + 1;
                  bias_calc <= 1'b1;
                end else begin
                  cal_counter <= cal_counter + 1;
                  if(cal_counter[1:0] == 2'b11) begin
                    weight_Second_addr <= weight_Second_addr + 1;
                    input_addr <= input_addr + 1;
                    pause <= 1'b1;
                    data_set <= 1'b0;
                  end
                end
              end
            end
            
            
            if(cal_choose == 2'b11) s_axis_tready <= 1'b0;
            else if(!s_axis_tready) begin
              s_axis_tready <= 1'b1;
              if(!cal_choose[0]) weight_First_addr <= 9'b0;
              else weight_Second_addr <= 9'b0;
            end else if(S_AXIS_TVALID) begin
              if(element_counter == (input_size>>2)-1) begin
                s_axis_tready <= 1'b0;
                element_counter <= 11'b0;
                if(!cal_choose[0]) begin
                  weight_First_addr <= 9'b0;
                  cal_choose[0] <= 1'b1;
                end else begin
                  weight_Second_addr <= 9'b0;
                  cal_choose[1] <= 1'b1;
                end
              end else begin
                element_counter <= element_counter + 1;
                if(!cal_choose[0]) weight_First_addr <= weight_First_addr + 1;
                else weight_Second_addr <= weight_Second_addr + 1;
              end
            end
          end
        end
        
        
        
        STATE_SEND : begin
          if(send_done) begin
            element_counter <= 11'b0;
            fc_state <= STATE_FCDONE;
          end else begin
            if(!m_axis_tvalid) begin
              if(delay != 2'b10) delay <= delay + 1;
              else begin
              if(last_layer) begin
                m_axis_tdata = out_out;
              end else begin // relu
                m_axis_tdata[31:24] = out_out[31] ? 8'b0 : out_out[31:24];
                m_axis_tdata[23:16] = out_out[23] ? 8'b0 : out_out[23:16];
                m_axis_tdata[15:8] = out_out[15] ? 8'b0 : out_out[15:8];
                m_axis_tdata[7:0] = out_out[7] ? 8'b0 : out_out[7:0];
              end
              delay <= 2'b0;
              m_axis_tvalid <= 1'b1;
              end
            end else if(M_AXIS_TREADY) begin
              element_counter <= element_counter + 1;
              out_addr <= out_addr + 1;
              m_axis_tvalid <= 1'b0;
              if(last_layer) begin
                if(element_counter == (output_size>>2)-1) begin
                  m_axis_tlast <= 1'b1;
                end
                else if(element_counter == (output_size>>2)) begin
                  m_axis_tlast <= 1'b0;
                  send_done <= 1'b1;
                  m_axis_tdata <= {32{1'b0}};
                end
              end
              else begin
                if(element_counter == (output_size>>2)-2) begin
                  m_axis_tlast <= 1'b1;
                end
                else if(element_counter == (output_size>>2)-1) begin
                  m_axis_tlast <= 1'b0;
                  send_done <= 1'b1;
                  m_axis_tdata <= {32{1'b0}};
                end
              end
            end
           end
         end
        
            
            
          STATE_FCDONE : begin
            if(apb_command <= 0) begin
              fc_state <= STATE_IDLE;
              fclayer_done <= 1'b0;
            end else begin
              fc_state <= STATE_FCDONE;
              fclayer_done <= 1'b1;
            end
          end
      endcase
    end
  end

  
    
  
endmodule
