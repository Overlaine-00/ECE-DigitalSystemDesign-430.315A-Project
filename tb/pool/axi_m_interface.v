
`timescale 1 ns / 1 ps

module axi_m_interface #
(
    parameter integer C_M_AXI_ADDR_WIDTH	= 32,
    parameter integer C_M_AXI_DATA_WIDTH	= 32
)
(
    input wire [27:0] input_address,
    input wire [31:0] write_data,
    output reg [31:0] read_data,
    input wire  INIT_AXI_READ,
    input wire  INIT_AXI_WRITE,
    output wire  WRITE_DONE,
    output wire  READ_DONE,
    input wire  M_AXI_ACLK,
    input wire  M_AXI_ARESETN,
    
    // Master Interface Write Address Channel ports. 
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_AWADDR,
    output wire  M_AXI_AWVALID,
    input wire  M_AXI_AWREADY,
    
    // Master Interface Write Data Channel ports.
    output wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI_WSTRB,
    output wire  M_AXI_WVALID,
    input wire  M_AXI_WREADY,
    
    // Master Interface Write Response Channel ports. 
    input wire [1 : 0] M_AXI_BRESP,
    input wire  M_AXI_BVALID,
    output wire  M_AXI_BREADY,
    
    // Master Interface Read Address Channel ports. 
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_ARADDR,
    output wire  M_AXI_ARVALID,
    input wire  M_AXI_ARREADY,
    
    // Master Interface Read Data Channel ports.
    input wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_RDATA,
    input wire [1 : 0] M_AXI_RRESP,
    input wire  M_AXI_RVALID,
    output wire  M_AXI_RREADY
);


	localparam [1:0]    IDLE = 2'b00, 
                        WRITE = 2'b01, // This state is write transaction,
                        READ = 2'b10; // This state is read transaction


	// execution state (current state)
	reg [1:0] mst_exec_state;

    // AXI4-LITE signals
	reg  	axi_awvalid;
	reg  	axi_wvalid;
	reg  	axi_arvalid;
	reg  	axi_rready;
	reg  	axi_bready;
	reg [C_M_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg [C_M_AXI_DATA_WIDTH-1 : 0] 	axi_wdata;
	reg [C_M_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	wire  	write_resp_error;
	wire  	read_resp_error;
	
	reg  	init_write_ff;
	reg     init_write_ff2;
	reg     init_read_ff;
    reg     init_read_ff2;
    wire    init_write_pulse;
    wire    init_read_pulse;
    
    reg     write_done;
    reg     read_done;
	
    //----------------------------
	// I/O Connections assignments
	//----------------------------
	
	// Write Address(AW)
	assign M_AXI_AWADDR	= axi_awaddr;
	assign M_AXI_AWVALID = axi_awvalid;
	//Write Data(W)
	assign M_AXI_WDATA	= axi_wdata;		
	assign M_AXI_WVALID	= axi_wvalid;	
	assign M_AXI_WSTRB	= 4'b1111;
	assign M_AXI_BREADY	= axi_bready;
	assign M_AXI_ARADDR	= axi_araddr;
	assign M_AXI_ARVALID = axi_arvalid;
	assign M_AXI_RREADY	= axi_rready;
	assign WRITE_DONE = write_done;
	assign READ_DONE = read_done;
	assign init_write_pulse	= (!init_write_ff2) && init_write_ff;
	assign init_read_pulse	= (!init_read_ff2) && init_read_ff;

	//Generate a pulse to start AXI write/read transaction.
	always @(posedge M_AXI_ACLK)										      
	  begin                                                                        
	    // Initiates AXI write/read transaction delay    
	    if (M_AXI_ARESETN == 0 )                                                   
	      begin                                                                    
	        init_write_ff <= 1'b0;                                                   
	        init_write_ff2 <= 1'b0;
	        
	        init_read_ff <= 1'b0;                                                   
            init_read_ff2 <= 1'b0;                                                     
	      end                                                                               
	    else                                                                       
	      begin  
	        init_write_ff <= INIT_AXI_WRITE;
	        init_write_ff2 <= init_write_ff;
	        
	        init_read_ff <= INIT_AXI_READ;
            init_read_ff2 <= init_read_ff;                                                                   
	      end                                                                      
	  end
	  


	//--------------------
	//Write Address Channel
	//--------------------

	  always @(posedge M_AXI_ACLK)										      
	  begin                                                                        
	    if (M_AXI_ARESETN == 0)                                               
	      begin                                                                    
	        axi_awvalid <= 1'b0;                                               
	      end 
	    else                                                                       
          begin                                                                    
            if (init_write_pulse)                                                
              begin                                                                
                axi_awvalid <= 1'b1;                                               
              end                                                                  
            else if (M_AXI_AWREADY && axi_awvalid)                                 
              begin                                                                
                axi_awvalid <= 1'b0;                                               
              end                                                                  
          end                                                                                                                          
	  end                                                                          
	                                                                               
	                                                                              

	//--------------------
	//Write Data Channel
	//--------------------

	   always @(posedge M_AXI_ACLK)                                        
	   begin                                                                         
	     if (M_AXI_ARESETN == 0)                                                    
	       begin                                                                     
	         axi_wvalid <= 1'b0;                                              
	       end                                                                      
	     else if (init_write_pulse)                                                
          begin                                                                     
            axi_wvalid <= 1'b1;                                                     
          end                                                                       
        else if (M_AXI_WREADY && axi_wvalid)                                        
          begin                                                                     
           axi_wvalid <= 1'b0;                                                      
          end                                                                                             
	   end                                                                           


	//----------------------------
	//Write Response (B) Channel
	//----------------------------

	  always @(posedge M_AXI_ACLK)                                    
	  begin                                                                
	    if (M_AXI_ARESETN == 0 || init_write_pulse  == 1'b1)                                           
	      begin                                                            
	        axi_bready <= 1'b0;                                            
	      end                                                                
	    else if (M_AXI_BVALID && ~axi_bready)                              
	      begin                                                            
	        axi_bready <= 1'b1;                                            
	      end                                                               
	    else if (axi_bready)                                               
	      begin                                                            
	        axi_bready <= 1'b0;                                            
	      end                                                               
	    else                                                               
	      axi_bready <= axi_bready;                                        
	  end                                                                  
	                                                                       
	//Flag write errors                                                    
	assign write_resp_error = (axi_bready & M_AXI_BVALID & M_AXI_BRESP[1]);


	//----------------------------
	//Read Address Channel
	//----------------------------                                                                  
	                                                                                   
	  always @(posedge M_AXI_ACLK)                                                     
	  begin                                                                            
	    if (M_AXI_ARESETN == 0)                                                       
	      begin                                                                        
	        axi_arvalid <= 1'b0;                                                       
	      end                                                                          
	    else if (init_read_pulse)                                                    
	      begin                                                                        
	        axi_arvalid <= 1'b1;                                                       
	      end                                                                 
	    else if (M_AXI_ARREADY && axi_arvalid)                                         
	      begin                                                                        
	        axi_arvalid <= 1'b0;                                                       
	      end                                                                                                                            
	  end                                                                              


	//--------------------------------
	//Read Data (and Response) Channel
	//--------------------------------

	  always @(posedge M_AXI_ACLK)                                    
	  begin                                                                 
	    if (M_AXI_ARESETN == 0 || init_read_pulse == 1'b1)                                            
	      begin                                                             
	        axi_rready <= 1'b0;                                             
	      end                                                                                     
	    else if (M_AXI_RVALID && ~axi_rready)                               
	      begin                                                             
	        axi_rready <= 1'b1;                                             
	      end                                                                                           
	    else if (axi_rready)                                                
	      begin                                                             
	        axi_rready <= 1'b0;                                             
	      end                                                                                                 
	  end                                                                   
	                                                                        
	//Flag write errors                                                     
	assign read_resp_error = (axi_rready & M_AXI_RVALID & M_AXI_RRESP[1]);  


	//--------------------------------
	// Logics
	//--------------------------------
       
        //Write Addresses               
        always @(posedge M_AXI_ACLK) begin                                                     
            if (M_AXI_ARESETN == 0) begin                                      
                axi_awaddr <= 0;              
            end 
            else if (init_write_pulse) begin
                axi_awaddr <= input_address;
            end
            else begin
                axi_awaddr <= axi_awaddr;
            end                                     
        end               
        
        //Write Data                   
        always @(posedge M_AXI_ACLK) begin                                                     
            if (M_AXI_ARESETN == 0) begin 
                axi_wdata <= 0;                 
            end 
            else if (init_write_pulse) begin
                axi_wdata <= write_data;
            end
            else begin
                axi_wdata <= axi_wdata;
            end                                     
        end                               
	                                                                                                                       
        // Read Address
        always @(posedge M_AXI_ACLK) begin                                                     
            if (M_AXI_ARESETN == 0) begin                                                
                axi_araddr <= 0;        
            end 
            else if (init_read_pulse) begin
                axi_araddr <= input_address;
            end   
            else begin
                axi_araddr <= axi_araddr;
            end                                    
        end
	   
	   // Read Data
	   always @(posedge M_AXI_ACLK) begin
            if (M_AXI_ARESETN == 0 || init_read_pulse == 1'b1) begin                                                         
                read_data <= 0;
            end
            else if (M_AXI_RVALID && axi_rready) begin
                read_data <= M_AXI_RDATA;
            end
            else begin
              read_data <= read_data;
            end
        end
	                                                                
	                   
	  //implement master command interface state machine                         
	  always @ ( posedge M_AXI_ACLK)                                                    
	  begin                                                                             
	    if (M_AXI_ARESETN == 1'b0)                                                     
	      begin                                                                         
	        mst_exec_state  <= IDLE;                                            
	      end                                                                           
	    else                                                                            
	      begin                                                                         
	       // state transition                                                          
	        case (mst_exec_state)                                                       
	                                                                                    
	          IDLE: begin                                  
	            if ( init_write_pulse == 1'b1 )                                     
	              begin                                                                 
	                mst_exec_state  <= WRITE;                                      
	              end                                                                   
	            else if ( init_read_pulse == 1'b1 )                                     
                  begin                                                                 
                    mst_exec_state  <= READ;                                      
                  end                                                                   
                else                                                                    
	              begin                                                                 
	                mst_exec_state  <= IDLE;                                    
	              end                                                                   
	          end                                                                          
	          WRITE: begin                                                                                        
	            if (write_done)                                                        
	              begin                                                                 
	                mst_exec_state <= IDLE;//                                      
	              end                                                                   
	            else                                                                    
	              begin                                                                 
	                mst_exec_state  <= WRITE;                                                    
	              end                                                                   
	          end
	                                                                                    
	          READ: begin                                                                                       
	             if (read_done)                                                        
	               begin                                                                
	                 mst_exec_state <= IDLE;                                    
	               end                                                                  
	             else                                                                   
	               begin                                                                   
	                 mst_exec_state  <= READ;                                                                                         
	               end                                                                  
	           end                                                                                                                                    
	           default :                                                                
	             begin                                                                  
	               mst_exec_state  <= IDLE;                                     
	             end                                                                    
	        endcase                                                                     
	    end                                                                             
	  end //MASTER_EXECUTION_PROC                                                                                                                    
	                                                                                                                                                
	                                                                                    
	  always @(posedge M_AXI_ACLK)                                                      
	  begin                                                                             
	    if (M_AXI_ARESETN == 0 || init_write_pulse == 1'b1)                                                         
	      write_done <= 1'b0;                                                  
	    else if (M_AXI_BVALID && axi_bready)                              
	      write_done <= 1'b1;                                                          
	    else                                                                            
	      write_done <= 1'b0;                                                   
	  end                                                                               
                                                                                                                            
                                                                                                                                                                                                     
	  always @(posedge M_AXI_ACLK)                                                      
	  begin                                                                             
	    if (M_AXI_ARESETN == 0 || init_read_pulse == 1'b1) begin                                                  
	       read_done <= 1'b0;                                                    
	    end                                      
	    else if (M_AXI_RVALID && axi_rready)                         
	      read_done <= 1'b1;                                           
	    else                                                                    
	      read_done <= 1'b0;                                       
	  end                                                                             


	endmodule
