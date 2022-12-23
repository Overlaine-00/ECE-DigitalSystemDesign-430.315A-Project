`timescale 1ns / 1ps


module vdma_controller #
  (
    parameter integer C_M_AXI_ADDR_WIDTH  = 32,
    parameter integer C_M_AXI_DATA_WIDTH  = 32
  )
  (
    input wire  INIT_AXI_TXN, // Initiate AXI transactions
    output wire  TXN_DONE,     // Asserts when AXI transactions is complete
    input wire  M_AXI_ACLK,     // AXI clock signal
    input wire  M_AXI_ARESETN,     // AXI active low reset signal
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_AWADDR,     // Master Interface Write Address Channel ports. Write address (issued by master)
    output wire [2 : 0] M_AXI_AWPROT,
    output wire  M_AXI_AWVALID,
    input wire  M_AXI_AWREADY,
    output wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_WDATA,    // Master Interface Write Data Channel ports. Write data (issued by master)
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI_WSTRB,
    output wire  M_AXI_WVALID,     // Write valid. This signal indicates that valid write data and strobes are available.
    input wire  M_AXI_WREADY,     // Write ready. This signal indicates that the slave can accept the write data.

    input wire [1 : 0] M_AXI_BRESP,
    input wire  M_AXI_BVALID,
    output wire  M_AXI_BREADY,     // Response ready. This signal indicates that the master can accept a write response.

    output wire [2 : 0] M_AXI_ARPROT,

    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_ARADDR,     // Master Interface Read Address Channel ports. Read address (issued by master)
    output wire  M_AXI_ARVALID,
    input wire  M_AXI_ARREADY,
    input wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_RDATA,     // Master Interface Read Data Channel ports. Read data (issued by slave)
    input wire [1 : 0] M_AXI_RRESP,     // Read response. This signal indicates the status of the read transfer.
    input wire  M_AXI_RVALID,     // Read valid. This signal indicates that the channel is signaling the required read data.
    output wire  M_AXI_RREADY,     // Read ready. This signal indicates that the master can accept the read data and response information.

    input wire [C_M_AXI_ADDR_WIDTH-1:0] i_data,
    input wire [C_M_AXI_ADDR_WIDTH-1:0] i_addr
  );


  localparam [1:0]    IDLE = 2'b00, 
    WRITE = 2'b01;



  // AXI4-LITE signals
  reg   axi_awvalid; //write address valid
  reg   axi_wvalid;//write data valid
  reg   axi_arvalid; //read address valid
  reg   axi_rready; //read data acceptance
  reg   axi_bready; //write response acceptance
  reg [C_M_AXI_ADDR_WIDTH-1 : 0]  axi_awaddr; //write address
  reg [C_M_AXI_DATA_WIDTH-1 : 0]  axi_wdata; //write data
  reg [C_M_AXI_ADDR_WIDTH-1 : 0]  axi_araddr; //read addresss
  reg   start_single_write; //A pulse to initiate a write transaction
  reg   start_single_read; //A pulse to initiate a read transaction
  reg   write_issued; //Asserts when a single beat write transaction is issued and remains asserted till the completion of write trasaction.
  reg   init_txn_ff;
  reg   init_txn_ff2;
  reg   init_txn_edge;
  wire    init_txn_pulse;


  reg [1:0]   mst_exec_state;
  reg         write_done;


  // I/O Connections assignments

  //Adding the offset address to the base addr of the slave
  assign M_AXI_AWADDR = axi_awaddr;
  //AXI 4 write data
  assign M_AXI_WDATA  = axi_wdata;
  assign M_AXI_AWPROT = 3'b000;
  assign M_AXI_AWVALID  = axi_awvalid;
  //Write Data(W)
  assign M_AXI_WVALID = axi_wvalid;
  //Set all byte strobes in this example
  assign M_AXI_WSTRB  = 4'b1111;
  //Write Response (B)
  assign M_AXI_BREADY = axi_bready;
  //Read Address (AR)
  assign M_AXI_ARADDR = axi_araddr;
  assign M_AXI_ARVALID  = axi_arvalid;
  assign M_AXI_ARPROT = 3'b001;
  //Read and Read Response (R)
  assign M_AXI_RREADY = axi_rready;
  //Example design I/O
  assign init_txn_pulse = (!init_txn_ff2) && init_txn_ff;
  assign TXN_DONE = write_done;


  //Generate a pulse to initiate AXI transaction.
  always @(posedge M_AXI_ACLK) begin                                                                        
    // Initiates AXI transaction delay    
    if (M_AXI_ARESETN == 0 ) begin                                                                    
      init_txn_ff <= 1'b0;                                                   
      init_txn_ff2 <= 1'b0;                                                   
    end   

    else begin  
      init_txn_ff <= INIT_AXI_TXN;
      init_txn_ff2 <= init_txn_ff;                                                                 
    end                                                                      
  end     


  //--------------------
  //Write Address Channel
  //--------------------

  always @(posedge M_AXI_ACLK) begin                                                                        
    //Only VALID signals must be deasserted during reset per AXI spec          
    //Consider inverting then registering active-low reset for higher fmax     
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1) begin                                                                    
      axi_awvalid <= 1'b0;                                                   
    end       

    //Signal a new address/data command is available by user logic           
    else begin                                                                    
      if (start_single_write) begin                                                                
        axi_awvalid <= 1'b1;                                               
      end      

      //Address accepted by interconnect/slave (issue of M_AXI_AWREADY by slave)
      else if (M_AXI_AWREADY && axi_awvalid) begin                                                                
        axi_awvalid <= 1'b0;                                               
      end                                                                  
    end                                                                      
  end


  //--------------------
  //Write Data Channel
  //--------------------

  always @(posedge M_AXI_ACLK) begin                                                                         
    if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1) begin                                                                     
      axi_wvalid <= 1'b0;                                                     
    end     

    //Signal a new address/data command is available by user logic              
    else if (start_single_write) begin                                                                     
      axi_wvalid <= 1'b1;                                                     
    end          

    //Data accepted by interconnect/slave (issue of M_AXI_WREADY by slave)      
    else if (M_AXI_WREADY && axi_wvalid) begin                                                                     
      axi_wvalid <= 1'b0;                                                      
    end                                                                       
  end                                                                           


  //----------------------------
  //Write Response (B) Channel
  //----------------------------

  always @(posedge M_AXI_ACLK) begin                                                                
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1) begin                                                            
      axi_bready <= 1'b0;                                            
    end                                

    // accept/acknowledge bresp with axi_bready by the master          
    // when M_AXI_BVALID is asserted by slave                          
    else if (M_AXI_BVALID && ~axi_bready) begin                                                            
      axi_bready <= 1'b1;                                            
    end                  

    // deassert after one clock cycle                                  
    else if (axi_bready) begin                                                            
      axi_bready <= 1'b0;                                            
    end                             

    // retain the previous value                                       
    else                                                               
      axi_bready <= axi_bready;                                        
  end         


  // A new axi_arvalid is asserted when there is a valid read address available by the master.               
  // start_single_read triggers a new read transaction                                                                   
  always @(posedge M_AXI_ACLK) begin                                                                            
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1) begin                                                                        
      axi_arvalid <= 1'b0;                                                       
    end                             

    //Signal a new read address command is available by user logic                 
    else if (start_single_read) begin                                                                        
      axi_arvalid <= 1'b1;                                                       
    end                                

    //RAddress accepted by interconnect/slave (issue of M_AXI_ARREADY by slave)    
    else if (M_AXI_ARREADY && axi_arvalid) begin                                                                        
      axi_arvalid <= 1'b0;                                                       
    end                                                                          
    // retain the previous value                                                   
  end                                                                              



  //--------------------------------
  //Read Data (and Response) Channel
  //--------------------------------

  always @(posedge M_AXI_ACLK) begin                                                                 
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1) begin                                                             
      axi_rready <= 1'b0;                                             
    end                           

    // accept/acknowledge rdata/rresp with axi_rready by the master     
    // when M_AXI_RVALID is asserted by slave                           
    else if (M_AXI_RVALID && ~axi_rready) begin                                                             
      axi_rready <= 1'b1;                                             
    end                                

    // deassert after one clock cycle                                   
    else if (axi_rready) begin                                                             
      axi_rready <= 1'b0;                                             
    end                                                               
    // retain the previous value                                        
  end                                                                   




  //--------------------------------
  //User Logic
  //--------------------------------

  //Write Addresses                                        
  always @(posedge M_AXI_ACLK) begin                                                     
    if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1) begin                                                 
      axi_awaddr <= i_addr;                                   // addr
    end                             
  end                                                       


  // Write data                                      
  always @(posedge M_AXI_ACLK) begin                                                     
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1 ) begin                                                 
      axi_wdata <= i_data;                                    // data
    end     
  end                                                  


  //implement master command interface state machine                         
  always @ ( posedge M_AXI_ACLK) begin                                                                             
    if (M_AXI_ARESETN == 1'b0) begin                                                                         
      // reset condition                                                            
      // All the signals are assigned default values under reset condition          
      mst_exec_state  <= IDLE;                                            
      start_single_write <= 1'b0;                                                 
      write_issued  <= 1'b0;                                                      
      start_single_read  <= 1'b0;    

      write_done <= 1'b0;                                                                                                 
    end                                                                           

    else begin                                                                         
      // state transition                                                          
      case (mst_exec_state)                                                       
        IDLE: begin                                                            
          // This state is responsible to initiate AXI transaction when init_txn_pulse is asserted 
          if (init_txn_pulse == 1'b1) begin                                                                 
            mst_exec_state  <= WRITE;                                      
          end                                                                   
          else begin                                                                 
            mst_exec_state  <= IDLE;                                    
          end                                                                   
        end    

        WRITE: begin
          if (write_done) begin                                                      
            mst_exec_state <= IDLE;                
          end  

          else begin
            mst_exec_state  <= WRITE;

            if (~axi_awvalid && ~axi_wvalid && ~M_AXI_BVALID && ~start_single_write && ~write_issued) begin
              start_single_write <= 1'b1;                                   
              write_issued  <= 1'b1;                                        
            end 

            else if (axi_bready) begin                                                           
              write_issued  <= 1'b0;                
              write_done <= 1'b1;                        
            end

            else begin                                                           
              start_single_write <= 1'b0; //Negate to generate a pulse      
            end                                                             
          end
        end     

        default: begin                                                                  
        mst_exec_state  <= IDLE;                                     
        end 

      endcase      

      if (write_done) begin
        write_done <= 1'b0;
      end                                                    
    end                                                                             
  end                                                    

endmodule
