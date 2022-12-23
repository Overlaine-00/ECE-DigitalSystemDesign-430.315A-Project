module pool_module #
 (
      parameter integer C_S00_AXIS_TDATA_WIDTH   = 32

 )
 (   //AXI-STREAM
    input wire                                            clk,
    input wire                                            rstn,
    output wire                                           S_AXIS_TREADY,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]             S_AXIS_TDATA,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]         S_AXIS_TKEEP,
    input wire                                            S_AXIS_TUSER,
    input wire                                            S_AXIS_TLAST,
    input wire                                            S_AXIS_TVALID,
    input wire                                            M_AXIS_TREADY,
    output wire                                           M_AXIS_TUSER,
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]            M_AXIS_TDATA,
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        M_AXIS_TKEEP,
    output wire                                           M_AXIS_TLAST,
    output wire                                           M_AXIS_TVALID,

     //Control
    input                                                 pool_start,
    output reg                                            pool_done,
    input[5:0]                                            flen,
    input[8:0]                                            in_channel
    
  );

  reg                                           m_axis_tuser;
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]            m_axis_tdata;
  reg [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        m_axis_tkeep;
  reg                                           m_axis_tlast;
  reg                                           m_axis_tvalid;
  reg                                           s_axis_tready;

  assign S_AXIS_TREADY = s_axis_tready;
  assign M_AXIS_TLAST = m_axis_tlast;
  assign M_AXIS_TVALID = m_axis_tvalid;
  assign M_AXIS_TDATA = {m_axis_tdata[7:0], m_axis_tdata[15:8], m_axis_tdata[23:16], m_axis_tdata[31:24]};
  assign M_AXIS_TUSER = 1'b0;
  assign M_AXIS_TKEEP = {(C_S00_AXIS_TDATA_WIDTH/8) {1'b1}};

  // START
  localparam IDLE = 3'd0, RECEIVE_1 = 3'd1, RECEIVE_2 = 3'd2, RECEIVE_S1 = 3'd3, RECEIVE_S2 = 3'd4, SEND = 3'd5, DONE = 3'd6;
  reg [3:0] receive_counter;
  reg [5:0] send_counter;
  reg [5:0] in_channel_send_counter;
  reg [8:0] channel_counter;
  reg [2:0] state, next_state;
  

  always @(posedge clk or negedge rstn) begin
    if(!rstn)  state <= IDLE;
    else state <= next_state;
  end

  always @(*) begin
    case(state)
      IDLE:  next_state = (pool_start) ? (flen == 4) ? RECEIVE_S1 : RECEIVE_1 : IDLE;
      RECEIVE_1: next_state = (receive_counter == flen / 4 - 1 && S_AXIS_TVALID) ? RECEIVE_2 : RECEIVE_1;
      RECEIVE_2: next_state = (receive_counter == flen / 4 - 1 && S_AXIS_TVALID) ? SEND : RECEIVE_2;
      RECEIVE_S1: next_state = (receive_counter == 3 && S_AXIS_TVALID) ? RECEIVE_S2 : RECEIVE_S1;
      RECEIVE_S2: next_state = SEND;
      SEND: begin
        if(!m_axis_tvalid) next_state = SEND;
        else begin
          if(flen == 4) begin
            if(M_AXIS_TREADY)  next_state = (channel_counter == in_channel - 1) ? DONE :  RECEIVE_S1;
            else next_state = SEND;
          end
          else begin
            if((send_counter == flen / 8 - 1) && (M_AXIS_TREADY)) next_state = ((in_channel_send_counter == flen * flen / 16 - 1) && (channel_counter == in_channel - 1)) ? DONE : RECEIVE_1;
            else next_state = SEND;
          end 
        end
      end
      DONE: next_state = (pool_start == 0) ? IDLE : DONE;
      default: next_state = IDLE;
    endcase
  end
  
  always @(posedge clk) begin
    case(state)
      IDLE: begin
        in_channel_send_counter <= 0;
        send_counter <= 0;
        m_axis_tlast <= 0;
        m_axis_tvalid <= 0;
        channel_counter <= 0;
        s_axis_tready <= 0;
        receive_counter <= 0;
        pool_done <= 0;
      end
      RECEIVE_1: begin
        if(!s_axis_tready) begin
          s_axis_tready <= 1;
        end
        else if(S_AXIS_TVALID) begin
          s_axis_tready <= (next_state != RECEIVE_2);
          receive_counter <= (next_state == RECEIVE_2) ? 0 : receive_counter + 1;
        end
      end

      RECEIVE_2: begin
        if(!s_axis_tready) begin
          s_axis_tready <= 1;
        end
        else if(S_AXIS_TVALID) begin
          s_axis_tready <= (next_state != SEND);
          receive_counter <= (next_state == SEND) ? 0 : receive_counter + 1;
        end
      end

      RECEIVE_S1: begin
        if(!s_axis_tready) begin
          s_axis_tready <= 1;
        end
        else if(S_AXIS_TVALID) begin
          receive_counter <= (next_state == RECEIVE_S2) ? 0 : receive_counter + 1;
          s_axis_tready <= (next_state != RECEIVE_S2);
        end
      end

      RECEIVE_S2: begin
      end

      SEND: begin
        if(flen == 4) begin
          if(m_axis_tvalid) begin 
            if(next_state != SEND) begin
              m_axis_tlast <= 0;
              m_axis_tvalid <= 0;
            end
            if(m_axis_tvalid && M_AXIS_TREADY) channel_counter <= channel_counter + 1;
          end
          else begin
            m_axis_tlast <= (channel_counter == in_channel - 1) ? 1 : m_axis_tlast;
            m_axis_tvalid <= 1;
          end
        end
        else begin
          if(m_axis_tvalid) begin
            if(next_state != SEND) m_axis_tvalid <= 0;
            if(M_AXIS_TREADY) begin 
              if(in_channel_send_counter == flen * flen / 16 - 1) begin 
                if(channel_counter == in_channel - 1) begin 
                  channel_counter <= 0;
                  m_axis_tlast <= 0;
                end
                else channel_counter <= channel_counter + 1;
                in_channel_send_counter <= 0;
              end
              else begin 
                if(in_channel_send_counter == flen * flen / 16 - 2 && channel_counter == in_channel - 1) m_axis_tlast <= 1;
                in_channel_send_counter <= in_channel_send_counter + 1;
              end
              send_counter <= (send_counter == flen / 8 -1) ? 0 : send_counter + 1;
            end
          end
          else  m_axis_tvalid <= 1;
        end
      end

      DONE: begin
        pool_done <= 1;
        m_axis_tlast <= 0;
      end
    endcase
  end

  
  wire[31:0] S_AXIS_TDATA_4;
  assign S_AXIS_TDATA_4 = {S_AXIS_TDATA[7:0], S_AXIS_TDATA[15:8], S_AXIS_TDATA[23:16], S_AXIS_TDATA[31:24]};
  
  wire[7:0] max_r1, max_r2;
  assign max_r1 = (S_AXIS_TDATA_4[31:24] > S_AXIS_TDATA_4[23:16]) ? S_AXIS_TDATA_4[31:24] : S_AXIS_TDATA_4[23:16];
  assign max_r2 = (S_AXIS_TDATA_4[15:8] > S_AXIS_TDATA_4[7:0]) ? S_AXIS_TDATA_4[15:8] : S_AXIS_TDATA_4[7:0];
  
  reg[7:0] buffer [15:0];


  always @(posedge clk) begin
    if(state == RECEIVE_1 && S_AXIS_TVALID) begin
      buffer[receive_counter * 2] <= max_r1;
      buffer[receive_counter * 2 + 1] <= max_r2;
    end
    else if(state == RECEIVE_2 && S_AXIS_TVALID) begin
      buffer[receive_counter * 2] <= (buffer[receive_counter * 2] > max_r1) ? buffer[receive_counter * 2] : max_r1;
      buffer[receive_counter * 2 + 1] <= (buffer[receive_counter * 2 + 1] > max_r2) ? buffer[receive_counter * 2 + 1] : max_r2;
    end
    else if(state == RECEIVE_S1 && S_AXIS_TVALID) begin
      buffer[receive_counter * 2] <= max_r1;
      buffer[receive_counter * 2 + 1] <= max_r2;
     end
     else if(state == RECEIVE_S2) begin
      buffer[0] <= (buffer[0] > buffer[2]) ? buffer[0] : buffer[2];
      buffer[1] <= (buffer[1] > buffer[3]) ? buffer[1] : buffer[3];
      buffer[2] <= (buffer[4] > buffer[6]) ? buffer[4] : buffer[6];
      buffer[3] <= (buffer[5] > buffer[7]) ? buffer[5] : buffer[7];
    end
  end


  always @(posedge clk) begin
    if(state == SEND) begin
      if(!m_axis_tvalid) begin
        m_axis_tdata[31:24] <= buffer[0];
        m_axis_tdata[23:16] <= buffer[1];
        m_axis_tdata[15:8] <= buffer[2];
        m_axis_tdata[7:0] <= buffer[3];
      end
      else if(M_AXIS_TREADY && next_state == SEND) begin
        m_axis_tdata[31:24] <= buffer[send_counter * 4 + 4];
        m_axis_tdata[23:16] <= buffer[send_counter * 4 + 5];
        m_axis_tdata[15:8] <= buffer[send_counter * 4 + 6];
        m_axis_tdata[7:0] <= buffer[send_counter * 4 + 7];
      end
    end
    else begin
      m_axis_tdata <= 0;
    end
  end
 
endmodule