/*
* conv_module.v
*/

module conv_module 
  #(
    parameter integer C_S00_AXIS_TDATA_WIDTH = 32
  )
  (
    input wire clk,
    input wire rstn,

    output wire S_AXIS_TREADY,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] S_AXIS_TDATA,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] S_AXIS_TKEEP, 
    input wire S_AXIS_TUSER, 
    input wire S_AXIS_TLAST, 
    input wire S_AXIS_TVALID, 

    input wire M_AXIS_TREADY, 
    output wire M_AXIS_TUSER, 
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] M_AXIS_TDATA, 
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] M_AXIS_TKEEP, 
    output wire M_AXIS_TLAST, 
    output wire M_AXIS_TVALID, 

    input conv_start, 
    output conv_done,

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports if you need them
    //////////////////////////////////////////////////////////////////////////
    input feature_respond,
    input bias_respond,
    input weight_respond,
    input conv_respond,

    input [2:0] command,
    input [8:0] in_ch,
    input [8:0] out_ch,
    input [5:0] flen,

    output reg feature_done,
    output reg bias_done,
    output reg weight_done
  );
  
  reg                                           m_axis_tuser;
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]            m_axis_tdata;
  reg [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        m_axis_tkeep;
  reg                                           m_axis_tlast;
  reg                                           m_axis_tvalid;
  reg                                           s_axis_tready;
  
  assign S_AXIS_TREADY = s_axis_tready;
  assign M_AXIS_TDATA = m_axis_tdata;
  assign M_AXIS_TLAST = m_axis_tlast;
  assign M_AXIS_TVALID = m_axis_tvalid;
  assign M_AXIS_TUSER = 1'b0;
  assign M_AXIS_TKEEP = {(C_S00_AXIS_TDATA_WIDTH/8) {1'b1}};

  ////////////////////////////////////////////////////////////////////////////
  // TODO : Write your code here
  ////////////////////////////////////////////////////////////////////////////

  // same as "output reg conv_done;"
  reg conv_done_reg;
  assign conv_done = conv_done_reg;

  localparam IDLE=3'd0, RECEIVE_FEATURE=3'd1, RECEIVE_BIAS=3'd2, RECEIVE_WEIGHTS=3'd3, DONE = 3'd4;
  localparam READ_WEIGHT=3'd1, CAL = 3'd2, WRITE_RESULT = 3'd3;

  //systolic array logic (need to improve)
  reg resetn, pe_en;
  wire resetn_total;

  assign resetn_total = resetn & rstn;

  reg signed [7:0] in_a;
  reg signed [7:0] in_b [31:0];
  wire signed [26:0] sum [31:0];

  wire signed [7:0] out_a [31:0];
    
  pe pe_start(.clk(clk),.resetn(resetn_total),.en(pe_en),.in_a(in_a),.in_b(in_b[0]),.sum(sum[0]),.out_a(out_a[0]));
    
  genvar k;
  generate
      for (k=1; k<32; k=k+1) begin : pe_block
          pe u_pe(.clk(clk),.resetn(resetn_total),.en(pe_en),.in_a(out_a[k-1]),.in_b(in_b[k]),.sum(sum[k]),.out_a(out_a[k]));
      end
  endgenerate
  ///////////////////////////////////////////
  /////////////////////////////////////////
  

  //state transition logic
  reg [2:0] state;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) state <= IDLE;
    else begin
      case(state)
        IDLE: begin
          if (S_AXIS_TVALID && command == 1) state <= RECEIVE_FEATURE;  //conv_start
          else state <= IDLE;
        end
        RECEIVE_FEATURE: begin
          if (feature_respond) state <= RECEIVE_BIAS;
          else state <= RECEIVE_FEATURE;
        end
        RECEIVE_BIAS: begin
          if (bias_respond) state <= RECEIVE_WEIGHTS;
          else state <= RECEIVE_BIAS;
        end
        RECEIVE_WEIGHTS: begin
          if (weight_respond) state <= DONE;
          else state <= RECEIVE_WEIGHTS;
        end
        DONE: begin
          if (conv_respond) state <= IDLE;
          else state <= DONE;
        end
      endcase
    end
  end

  reg [2:0] state2;
  reg [8:0] counter_1;
  reg [8:0] counter_2;

  reg read_weight_done;
  reg cal_done;
  reg write_result_done;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state2 <= IDLE;
      counter_1 <= 0;
      counter_2 <= 0;
    end
    else begin
      case(state2)
        IDLE: begin
          if (state == RECEIVE_WEIGHTS && command == 3 && S_AXIS_TVALID) state2 <= READ_WEIGHT;
          else state2 <= IDLE;
        end
        READ_WEIGHT: begin
          if (read_weight_done) begin
            state2 <= CAL;
            counter_1 <= (counter_1 == in_ch) ? 1 : counter_1 + 1;
            counter_2 <= (counter_1 == in_ch) ? counter_2 + 1 : counter_2;
          end
          else state2 <= READ_WEIGHT;
        end
        CAL: begin
          if (cal_done) state2 <= (counter_1 == in_ch) ? WRITE_RESULT : READ_WEIGHT;
          else state2 <= CAL;
        end
        WRITE_RESULT: begin
          if (write_result_done) state2 <= (counter_2 == out_ch-1) ? DONE : READ_WEIGHT;
          else state2 <= WRITE_RESULT;
        end
        DONE: begin
          if (weight_done && weight_respond) begin
            state2 <= IDLE; counter_1 <= 0; counter_2 <= 0;
          end
          else state2 <= DONE;
        end
      endcase
    end
  end
  ////////////////////////////////////////////

  // sram logic
  reg [13:0] b_addr;
  reg [31:0] d_in;
  wire [31:0] d_out;
  reg en;
  reg we;

  reg [31:0] feature_din, bias_din, weight_din;
  reg [13:0] feature_addr, bias_addr, weight_addr, output_addr;
  reg feature_en, bias_en, weight_en, output_en;
  reg feature_we, bias_we, weight_we, output_we;

  reg tready_f, tready_b, tready_w;

  reg [13:0] cnt_f, cnt_b;
  reg f_start, b_start;
  reg f_end, b_end;

  bram_32x16384 u_bram_32x16384(
    .addra(b_addr),
    .clka(clk),
    .dina(d_in),
    .douta(d_out),
    .ena(en),
    .wea(we)
  );

  reg [13:0] image_total_size, image_size, base_addr;

  always @(*) begin
    image_total_size = in_ch * flen * flen;
    image_size = flen * flen;
    base_addr = 14'h3FFE-((out_ch * flen * flen)>>2);
  end

  always @(*) begin
    case (state)
      RECEIVE_FEATURE: begin
        s_axis_tready = tready_f;
        en = feature_en;
        we = feature_we;
        d_in = feature_din;
        b_addr = feature_addr;
      end
      RECEIVE_BIAS: begin
        s_axis_tready = tready_b;
        en = bias_en;
        we = bias_we;
        d_in = bias_din;
        b_addr = bias_addr;
      end
      RECEIVE_WEIGHTS: begin
        s_axis_tready = tready_w;
        en = weight_en;
        we = weight_we;
        d_in =  weight_din;
        b_addr = weight_addr;
      end
      DONE: begin
        en = output_en;
        we = output_we;
        b_addr = output_addr;
      end
      default: begin
        s_axis_tready = 0;
        en = 0;
        we = 0;
        d_in = 0;
        b_addr = 0;
      end
    endcase
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn || feature_respond) begin
      tready_f <= 0;

      cnt_f <= 0;
      f_start <= 0;
      f_end <= 0;
      
      feature_we <= 0;
      feature_en <= 0;
      feature_addr <= 0;
      feature_din <= 0;

      feature_done <= 0;
    end
    else if (state == RECEIVE_FEATURE) begin
      if (!f_start) begin
        f_start <= 1;
        tready_f <= 1;
      end
      else begin
        if (f_end) begin
          tready_f <= 0;
          feature_we <= 0;
          feature_en <= 0;
          cnt_f <= 0;
          feature_addr <= 0;
          feature_din <= 0;
          feature_done <= 1;
        end
        else begin
          tready_f <= 1;
          feature_we <= 1;
          feature_en <= 1;
          if (S_AXIS_TVALID) begin
            cnt_f <= cnt_f + 1;
            feature_addr <= cnt_f;
            feature_din<={S_AXIS_TDATA[7:0],S_AXIS_TDATA[15:8],S_AXIS_TDATA[23:16],S_AXIS_TDATA[31:24]};
            if (S_AXIS_TLAST) f_end <= 1;
          end
          else begin
            cnt_f <= cnt_f;
            feature_addr <= cnt_f;
          end
        end
      end
    end
  end
  
  always @(posedge clk or negedge rstn) begin
    if (!rstn || bias_respond) begin
      tready_b<=0;
      
      cnt_b<=0;
      b_start<=0;
      b_end<=0;
      
      bias_we<=0;
      bias_en<=0;
      bias_addr<=0;
      bias_din<=0;

      bias_done<=0;
    end
    else if (state == RECEIVE_BIAS) begin
      if (!b_start) begin
        cnt_b  <=(image_total_size>>2);
        bias_addr<=(image_total_size>>2);
        b_start<=1;
        tready_b<=1;
      end
      else begin
        if (b_end) begin
          tready_b<=0;
          bias_we<=0;
          bias_en<=0;
          cnt_b<=0;
          bias_addr<=0;
          bias_din<=0;
          bias_done<=1;
        end
        else begin
          tready_b<=1;
          bias_we<=1;
          bias_en<=1;
          if (S_AXIS_TVALID) begin
            cnt_b<=cnt_b+1;
            bias_addr<=cnt_b;
            bias_din<=S_AXIS_TDATA;
            if (S_AXIS_TLAST) b_end<=1; 
          end
          else begin
            cnt_b<=cnt_b;
            bias_addr<=cnt_b;
          end
        end
      end
    end
  end
  ///////////////////////////////////

  integer i, j;

  // output logic
  reg [1:0] output_delay;
  reg output_delay2;
  reg [13:0] cnt;

  always @(posedge clk) begin
    if(!rstn) begin
      m_axis_tvalid<=0;
      m_axis_tlast<=0;
      m_axis_tdata<=0;
      output_addr<=0;
      output_en<=0;
      output_we<=0;
      output_delay<=0;
      output_delay2<=0;
      cnt<=0;
      conv_done_reg<=0;
    end
    else begin
      if (conv_done_reg) begin
        m_axis_tvalid<=0;
        m_axis_tdata<=0;
        output_addr<=0;
        output_en<=0;
        output_we<=0;
        output_delay<=0;
        output_delay2<=0;
        cnt<=0;
        if(conv_respond) begin
          m_axis_tlast<=0;
          conv_done_reg<=0;
        end
      end
      else if (state == DONE) begin
        case(output_delay)
          2'b00: begin
            if(M_AXIS_TREADY) begin
              cnt <=14'h3FFE;
              output_addr<=14'h3FFE;
              output_en<=1;
              output_we<=0;
              output_delay<=output_delay+1;        
            end
          end
          2'b01: begin
            output_addr<=output_addr-1;
            output_delay<=output_delay+1;
          end
          2'b10: begin
            output_addr<=output_addr-1;
            output_delay<=output_delay+1;
            m_axis_tvalid<=1;
            m_axis_tdata<=d_out;
          end
          2'b11: begin
            if (M_AXIS_TREADY) begin
              if (m_axis_tvalid) begin
                m_axis_tvalid<=1;
                m_axis_tdata<=d_out;
                cnt<=cnt-1;
                output_addr<=output_addr-1;
                if (output_addr == base_addr) begin
                  m_axis_tlast<=1;
                  conv_done_reg<=1;
                end
              end
              else if (!output_delay2) begin
                output_delay2<=1;
                m_axis_tvalid<=1;
                m_axis_tdata<=d_out;
                cnt<=cnt-1;
                output_addr<=output_addr-1;
              end
              else begin
                output_delay2<=0;
                cnt<=cnt+1;
                output_addr<=output_addr-1;
              end
            end
            else begin
              m_axis_tvalid<=0;
              output_addr<=cnt;
              output_delay2<=1;
            end
          end        
        endcase
      end
    end
  end
  ///////////////////////////////////////////////////////

  // calculate by weight
  reg w_start;

  reg signed [7:0] input_vector [0:41];
  reg signed [7:0] input_matrix [0:31][0:41];     
  reg signed [26:0] save_bin [0:31][0:31];

  reg [13:0] wr_addr, wc_addr, ww_addr;
  reg [1:0] delay;
  reg delay2;
  reg delay3;

  reg [31:0] temp_b;                  
  reg temp_b_done;

  reg [31:0] weights;
  reg [1:0] state_nine;
  reg [1:0] cnt_l;  

  reg [5:0] cnt_w_s;
  reg [4:0] cnt_w_r;
  reg [4:0] cnt_w_c;
  reg [1:0] first, second;

  reg w_done;
  reg flag;

  reg [5:0]  cnt2,cnt3;

  reg [4:0] row, col;
  reg flag1, flag2;
  reg [31:0] temp_w;

  always @(*) begin
    case(state2)
      READ_WEIGHT: weight_addr = wr_addr;
      CAL: weight_addr = wc_addr;
      WRITE_RESULT: weight_addr = ww_addr;
      default: weight_addr = 0;
    endcase
    cnt2 = cnt_w_r+first-1;
    cnt3 = cnt_w_c+second-1;
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      tready_w <= 0;
      weight_done <= 0;

      weight_we <= 0;
      weight_en <= 0;
      weight_din <= 0;

      w_start <= 0;

      read_weight_done <= 0;
      cal_done <= 0;
      write_result_done <= 0;

      wr_addr <= 0; wc_addr <= 0; ww_addr <= 0;
      delay <= 0; delay2 <= 0; delay3 <= 0;

      temp_b <= 0;
      temp_b_done <= 0;
      temp_w <= 0;
      w_done <= 0;
      weights <= 0;

      state_nine <= 0;
      cnt_l <= 0;

      flag <= 0; flag1 <= 0; flag2 <= 0;
      cnt_w_s <= 0; cnt_w_r <= 0; cnt_w_c <= 0;
      first <= 0; second <= 0;

      row <= 0; col <= 0;
      in_a <= 0; pe_en <= 1; resetn <= 1;

      for (i=0; i<42; i=i+1) begin
        input_vector[i] <= 0;
      end

      for (i=0; i<32; i=i+1) begin
        for (j=0; j<42; j=j+1) begin
          input_matrix[i][j] <= 0;
        end
        for (j=0; j<32; j=j+1) begin
          save_bin[i][j] <= 0;
        end
        in_b[i] <= 0;
      end
    end

    else begin
      case(state2)
        IDLE: begin
          weight_done <= 0;
        end

        READ_WEIGHT: begin
          if (!w_start) begin
            w_start <= 1;
            wr_addr <= (image_total_size>>2)-1;
            ww_addr <= 14'h3FFF;
          end
          else if (!read_weight_done) begin
            cal_done <= 0;
            write_result_done <= 0;

            case(state_nine)
              2'b00: begin
                case(cnt_l)
                  2'b00: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                  end
                  2'b01: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                    input_vector[0] <= S_AXIS_TDATA[7:0];
                    input_vector[1] <= S_AXIS_TDATA[15:8];
                    input_vector[2] <= S_AXIS_TDATA[23:16];
                    input_vector[3] <= S_AXIS_TDATA[31:24];
                  end
                  2'b10: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                    input_vector[4] <= S_AXIS_TDATA[7:0];
                    input_vector[5] <= S_AXIS_TDATA[15:8];
                    input_vector[6] <= S_AXIS_TDATA[23:16];
                    input_vector[7] <= S_AXIS_TDATA[31:24];
                  end
                  2'b11: begin
                    tready_w <= 0;
                    cnt_l <= 0;
                    weights <= S_AXIS_TDATA;
                    input_vector[8] <= S_AXIS_TDATA[7:0];
                    state_nine <= state_nine + 1;
                    read_weight_done <= 1;
                  end
                  default: ;
                endcase
              end
              2'b01: begin
                case(cnt_l)
                  2'b00: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                    input_vector[0] <= weights[15:8];
                    input_vector[1] <= weights[23:16];
                    input_vector[2] <= weights[31:24];
                  end
                  2'b01: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                    input_vector[3] <= S_AXIS_TDATA[7:0];
                    input_vector[4] <= S_AXIS_TDATA[15:8];
                    input_vector[5] <= S_AXIS_TDATA[23:16];
                    input_vector[6] <= S_AXIS_TDATA[31:24];
                  end
                  2'b10: begin
                    tready_w <= 0;
                    cnt_l <= cnt_l + 1;
                    weights <= S_AXIS_TDATA;
                    input_vector[7] <= S_AXIS_TDATA[7:0];
                    input_vector[8] <= S_AXIS_TDATA[15:8];
                  end
                  2'b11: begin
                    state_nine <= state_nine + 1;
                    cnt_l <= 0;
                    read_weight_done <= 1;
                  end
                  default: ;
                endcase
              end
              2'b10: begin
                case(cnt_l)
                  2'b00: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                    input_vector[0] <= weights[23:16];
                    input_vector[1] <= weights[31:24];
                  end
                  2'b01: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                    input_vector[2] <= S_AXIS_TDATA[7:0];
                    input_vector[3] <= S_AXIS_TDATA[15:8];
                    input_vector[4] <= S_AXIS_TDATA[23:16];
                    input_vector[5] <= S_AXIS_TDATA[31:24];
                  end
                  2'b10: begin
                    tready_w <= 0;
                    cnt_l <= cnt_l + 1;
                    weights <= S_AXIS_TDATA;
                    input_vector[6] <= S_AXIS_TDATA[7:0];
                    input_vector[7] <= S_AXIS_TDATA[15:8];
                    input_vector[8] <= S_AXIS_TDATA[23:16];
                  end
                  2'b11: begin
                    state_nine <= state_nine + 1;
                    cnt_l <= 0;
                    read_weight_done <= 1;
                  end
                  default: ;
                endcase
              end
              2'b11: begin
                case(cnt_l)
                  2'b00: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                    input_vector[0] <= weights[31:24];
                  end
                  2'b01: begin
                    tready_w <= 1;
                    cnt_l <= cnt_l + 1;
                    input_vector[1] <= S_AXIS_TDATA[7:0];
                    input_vector[2] <= S_AXIS_TDATA[15:8];
                    input_vector[3] <= S_AXIS_TDATA[23:16];
                    input_vector[4] <= S_AXIS_TDATA[31:24];
                  end
                  2'b10: begin
                    tready_w <= 0;
                    cnt_l <= cnt_l + 1;
                    input_vector[5] <= S_AXIS_TDATA[7:0];
                    input_vector[6] <= S_AXIS_TDATA[15:8];
                    input_vector[7] <= S_AXIS_TDATA[23:16];
                    input_vector[8] <= S_AXIS_TDATA[31:24];
                  end
                  2'b11: begin
                    state_nine <= 0;
                    cnt_l <= 0;
                    read_weight_done <= 1;
                  end
                  default: ;
                endcase
              end
            endcase

            // out_ch 4?????? ???ея? bia 4?? ????.
            if ((counter_1 == 1) && (counter_2[1:0] == 0)) begin
              case(delay)
                2'b00: begin
                  if (!temp_b_done) begin
                    delay <= delay + 1;
                    weight_en <= 1;
                    weight_we <= 0;
                    wr_addr <= wr_addr + 1;
                  end
                end
                2'b01: delay <= delay + 1;
                2'b10: begin
                  delay <= delay + 1;
                  temp_b <= d_out;
                end
                2'b11: begin
                  delay <= 0;
                  weight_en <= 0;
                  temp_b_done <= 1;
                end
              endcase
            end
          end
        end

        CAL: begin
          if (!cal_done) begin
            if (w_done) begin
              if (cnt_w_s == (flen + 10)) begin
                if (delay2) begin
                  delay2 <= 0;
                  resetn <= 1; pe_en <= 1;
                  w_done <= 0;
                  cnt_w_s <= 0;

                  cnt_w_r <= (cnt_w_r == flen-1) ? 0 : cnt_w_r + 1;
                  cal_done <= (cnt_w_r == flen-1);
                end
                else begin
                  delay2 <= 1;
                  resetn <= 0; pe_en <= 0;
                  for (i=0; i<32; i=i+1) begin
                    save_bin[cnt_w_r][i] <= save_bin[cnt_w_r][i] + sum[i];
                  end
                end
              end
              else begin
                for (i=0; i<32; i=i+1) begin
                  in_b[i] <= input_matrix[i][cnt_w_s];
                end
                cnt_w_s <= cnt_w_s + 1;
                in_a <= input_vector[cnt_w_s];
              end
            end
            else begin
              if (flag) begin
                w_done <= 1;
                flag <= 0;
                weight_en <= 0;
              end
              else begin
                if (first == 3) begin
                  first <= 0;
                  cnt_w_c <= (cnt_w_c == flen-1) ? 0 : cnt_w_c + 1;
                  flag <= (cnt_w_c == flen-1);
                  if (counter_1 == in_ch) begin
                    input_vector[9] <= 8'b01000000;
                    case(counter_2[1:0])
                      2'b00: begin
                        input_matrix[cnt_w_c][cnt_w_c+9] <= temp_b[7:0]; 
                      end
                      2'b01: begin
                        input_matrix[cnt_w_c][cnt_w_c+9] <= temp_b[15:8];
                      end
                      2'b10: begin
                        input_matrix[cnt_w_c][cnt_w_c+9] <= temp_b[23:16];
                      end
                      2'b11: begin
                        input_matrix[cnt_w_c][cnt_w_c+9] <= temp_b[31:24];
                      end
                      default: ;
                    endcase
                  end
                  else begin
                    input_vector[9] <= 0;
                    input_matrix[cnt_w_c][cnt_w_c+9] <= 0;
                  end
                end
                else begin
                  if (second == 3) begin
                    second <= 0;
                    first <= first + 1;
                  end
                  else begin
                    case(delay)
                      2'b00: begin
                        weight_en <= 1;
                        weight_we <= 0;
                        wc_addr <= (counter_1-1)*(image_size>>2)+(flen>>2)*cnt2[4:0]+cnt3[4:2]; //wc_addr
                        delay <= delay + 1;
                        read_weight_done <= 0;
                        temp_b_done <= 0;
                      end
                      2'b01: delay <= delay + 1;
                      2'b10: begin
                        if ((cnt2 >= 0) && (cnt2 <= flen-1) && (cnt3 >=0) && (cnt3 <= flen-1)) begin
                          case(cnt3[1:0])
                            2'b00: input_matrix[cnt_w_c][cnt_w_c+(3*first)+second] <= d_out[31:24];
                            2'b01: input_matrix[cnt_w_c][cnt_w_c+(3*first)+second] <= d_out[23:16];
                            2'b10: input_matrix[cnt_w_c][cnt_w_c+(3*first)+second] <= d_out[15:8];
                            2'b11: input_matrix[cnt_w_c][cnt_w_c+(3*first)+second] <= d_out[7:0];
                          endcase
                        end
                        else input_matrix[cnt_w_c][cnt_w_c+(3*first)+second] <= 0;

                        delay <= 0;
                        second <= second + 1;
                      end
                      default: ;
                    endcase
                  end
                end
              end
            end
          end
        end
        
        WRITE_RESULT: begin
          if (flag1) begin
            flag1 <= 0;
            weight_en <= 0;
            weight_we <= 0;
            weight_din <= 0;
            write_result_done <= 1;
          end
          else if (flag2) begin
            flag2 <= 0;
            row <= (row == flen-1) ? 0 : row+1;
            flag1 <= (row == flen-1);
          end
          else if (!write_result_done) begin
            if (delay3) begin
              delay3 <= 0;
              col <= (col == flen-4) ? 0 : col+4;
              flag2 <= (col == flen-4);
              weight_en <= 1;
              weight_din <= temp_w;
              for (i=0; i<4; i=i+1) begin
                save_bin[row][col+i] <= 0;
              end
            end
            else begin
              // quantization & relu unit
              temp_w[7:0] <= (save_bin[row][col][26]) ? 0 : (save_bin[row][col][25:13] == 0) ? {1'b0, save_bin[row][col][12:6]} : 8'b01111111;
              temp_w[15:8] <= (save_bin[row][col+1][26]) ? 0 : (save_bin[row][col+1][25:13] == 0) ? {1'b0, save_bin[row][col+1][12:6]} : 8'b01111111;
              temp_w[23:16] <= (save_bin[row][col+2][26]) ? 0 : (save_bin[row][col+2][25:13] == 0) ? {1'b0, save_bin[row][col+2][12:6]} : 8'b01111111;
              temp_w[31:24] <= (save_bin[row][col+3][26]) ? 0 : (save_bin[row][col+3][25:13] == 0) ? {1'b0, save_bin[row][col+3][12:6]} : 8'b01111111;

              delay3 <= 1;
              weight_en <= 0;
              weight_we <= 1;
              cal_done <= 0;
              ww_addr <= ww_addr - 1;
            end
          end
        end

        DONE: begin
          temp_b <= 0;
          weights <= 0;
          state_nine <= 0;
          w_start <= 0;
          write_result_done <= 0;
          cnt_l <= 0;
          weight_done <= (~weight_respond);

          for (i=0; i<42; i=i+1) begin
            input_vector[i] <= 0;
          end

          for (i=0; i<32; i=i+1) begin
            for (j=0; j<42; j=j+1) begin
              input_matrix[i][j] <= 0;
            end
          end
        end
      endcase
    end
  end
endmodule