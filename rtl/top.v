/*`timescale 1ns / 1ps

module aes(
	input clk,
	input nreset,
	
	input          data_v_i, 
	input [127:0]  data_i,    
	input [127:0]  key_i,    
	output         res_v_o,  
	output [127:0] res_o     
	);

	reg  [127:0] state_q;
	wire [127:0] state_d;
	
	reg [127:0] key_input_q; 
	
	reg  [3:0] round_q; //Counter reg which keeps track of the round
	wire [3:0] round_d;
	wire       round_en_w;
	wire       is_finished_w;
	wire       is_last_round_w;
	
	
	// SubBytes
	wire [127:0] sub_bytes_w;
	wire [31:0]  conceptual_rows_w[3:0];
	
	// ShiftRow
	wire [127:0] shift_rows_w;
	wire [31:0]  shifted_conceptual_rows_w[3:0];
	
	// MixColumns
	wire [127:0] mix_columns_w;
	
	// AddRoundKey
	wire [127:0] add_round_key_data_in_w;
	wire [127:0] add_round_key_out_w;
	
	// key
	reg  [127:0] round_key_q;
	
    // --- MANUAL HOLD FIX: Intermediate Wires to Force a Gate Delay ---
    wire [127:0] round_key_next_comb_w; // Combinational output of ks
	wire [127:0] round_key_d;             // Padded output fed to register D-pin
    wire [7:0]   rcon_next_comb_w;        // Combinational output of ks
    wire [7:0]   rcon_d;                  // Padded output fed to register D-pin
    // ------------------------------------------------------------------
    
	wire [127:0] current_round_key_w;
	reg  [7:0]   rcon_q;
	wire [7:0]   current_rcon_w;

    localparam STATE_IDLE       = 4'd0;
    localparam STATE_LAST_ROUND = 4'd10; // The 10th round (state 10)
    localparam STATE_FINISHED   = 4'd11; // The cycle where output is valid (state 11)
    
    assign is_last_round_w = (round_q == STATE_LAST_ROUND);
    assign is_finished_w  = (round_q == STATE_FINISHED);
    
    assign round_en_w = (round_q != STATE_IDLE) | data_v_i;
    
	
	always @(posedge clk) begin
    if (data_v_i) begin
        key_input_q <= key_i;
    end
	end
	
    
    assign round_d = is_finished_w ? STATE_IDLE :   
                      ((round_q == STATE_IDLE && !data_v_i) ? STATE_IDLE : // If idle and no data, stay IDLE
                      round_q + 1);                             // Otherwise, increment the counter
    

    always @(posedge clk) 
    begin
        if (!nreset) 
            round_q <= STATE_IDLE;
        else if (round_en_w) 
            round_q <= round_d;
    end 
    
    always @(posedge clk)
    begin
         state_q <= state_d;
    end 

    //16B are fed parallely into 16 sbox instances
	genvar sb_i;
	generate 
		for (sb_i=0; sb_i<16; sb_i=sb_i+1) begin : loop_gen_sb_i				
			sbox m_sbox(
				.data_i( state_q[(sb_i*8)+7:(sb_i*8)]),
				.data_o( sub_bytes_w[(sb_i*8)+7:(sb_i*8)])
		        	);
		end
	endgenerate
	
	
	genvar sr_r;
	generate 
		for (sr_r=0; sr_r<4; sr_r=sr_r+1) begin : loop_gen_sr_r
			assign conceptual_rows_w[sr_r] = { sub_bytes_w[3*32+8*sr_r+7:3*32+8*sr_r],
						       sub_bytes_w[2*32+8*sr_r+7:2*32+8*sr_r],
						       sub_bytes_w[32+8*sr_r+7:32+8*sr_r],
						       sub_bytes_w[8*sr_r+7:8*sr_r] };
			assign { shift_rows_w[3*32+8*sr_r+7:3*32+8*sr_r],
						shift_rows_w[2*32+8*sr_r+7:2*32+8*sr_r],
						shift_rows_w[1*32+8*sr_r+7:1*32+8*sr_r],
						shift_rows_w[0*32+8*sr_r+7:0*32+8*sr_r] } = shifted_conceptual_rows_w[sr_r];
		end
	endgenerate
		
	assign shifted_conceptual_rows_w[0]  =  conceptual_rows_w[0];
	assign shifted_conceptual_rows_w[3]  =  { conceptual_rows_w[3][23:16], conceptual_rows_w[3][15:8],  conceptual_rows_w[3][7:0] ,  conceptual_rows_w[3][31:24] }; // row1 0,1,2,3 -> 1,2,3,0
	assign shifted_conceptual_rows_w[2]  =  { conceptual_rows_w[2][15:8],  conceptual_rows_w[2][7:0],   conceptual_rows_w[2][31:24], conceptual_rows_w[2][23:16] }; // row2 0,1,2,3 -> 2,3,0,1
	assign shifted_conceptual_rows_w[1]  =  { conceptual_rows_w[1][7:0] ,  conceptual_rows_w[1][31:24], conceptual_rows_w[1][23:16], conceptual_rows_w[1][15:8] };  // row3 0,1,2,3 -> 3,0,1,2 : d,c,b,a -> a,d,cs
	
	
	genvar mc_c; // collumn [ 3, 2, 1, 0 ]
	generate 
		for (mc_c=0; mc_c<4; mc_c=mc_c+1) begin : loop_gen_mc_c
			mixw m_mixw ( 
				.w_i(    shift_rows_w[  mc_c*32+31:mc_c*32] ), 
				.mixw_o( mix_columns_w[mc_c*32+31:mc_c*32])
			);
		end
	endgenerate
	
	// AddRoundKey : bitwise XOR
	// Skip mix columns for last round, the mixColumns computation is actually performed by the combinational logic
	// but not used
	assign add_round_key_data_in_w = data_v_i ? data_i :( is_last_round_w ?  shift_rows_w : mix_columns_w );
	assign add_round_key_out_w = add_round_key_data_in_w ^ current_round_key_w;
	assign state_d = add_round_key_out_w;
	
	// Key calculation 	
	assign current_round_key_w = data_v_i ? key_i        : round_key_q;
	assign current_rcon_w      = data_v_i ? 8'b0000_0001 : rcon_q;
	
	ks m_ks(
		 .key_i     (current_round_key_w),
		 .key_rcon_i(current_rcon_w),
		 .key_next_o(round_key_next_comb_w), // Feed through new combinational wire
		 .key_rcon_o(rcon_next_comb_w)        // Feed through new combinational wire
                 );
                 
    // --- MANUAL HOLD FIX: Force a logical gate delay to satisfy hold time ---
    // XORing with zero is guaranteed to be synthesized as an XOR or a non-inverting buffer
    // This adds the necessary delay to the fast path.
    assign round_key_d = round_key_next_comb_w ^ 128'h0;
    assign rcon_d      = rcon_next_comb_w ^ 8'h0;
    // -------------------------------------------------------------------------
    
	 always @(posedge clk) begin
		 if ( round_en_w ) begin : key_dff
			round_key_q <= round_key_d; // <-- Now correctly driven by the delayed signal
			rcon_q      <= rcon_d;      // <-- Now correctly driven by the delayed signal
		 end
	 end
	
	// output
	assign res_v_o = is_finished_w; // aes is on the 11 th round
	assign res_o   = state_q;

endmodule*/

`timescale 1ns / 1ps

module aes(
	input clk,
	input nreset,
	
	input          data_v_i, // input valid
	input [127:0]  data_i,   // message to decode
	input [127:0]  key_i,    // key
	output         res_v_o,  // result valid
	output [127:0] res_o     // result
	);

	reg  [127:0] data_q;
	wire [127:0] data_next;
	
	reg  [3:0] fsm_q;
	wire [3:0] fsm_next;
	wire       fsm_en;
	wire       finished_v;
	wire       last_iter_v;
	
	wire       unused_fsm_sum_msb;
	
	
	// SubBytes
	wire [127:0] sub_bytes;
	wire [31:0]  sub_bytes_row[3:0];
	// ShiftRow
	wire [127:0] shift_row;
	wire [31:0]  shift_row_row[3:0];
	// ShiftRow
	wire [127:0] mix_columns;
	// AddRoundKey
	wire [127:0] round_key_next;
	wire [127:0] round_key;
	// key
	reg  [127:0] key_q;
	wire [127:0] key_next;
	wire [127:0] key_current;
	reg  [7:0]   key_rcon_q;
	wire [7:0]   key_rcon_next;
	wire [7:0]   key_rcon_current;
	
	assign fsm_en = |(fsm_q) | data_v_i;
	// increment the fsm next value unless we are on the 11th round ( fsm_q == 4'b1011 is 11 in dec )
	// if we are on the 11 th round we write out the output value and set to valid 
	assign finished_v = fsm_q[3] & fsm_q[1] & fsm_q[0];
	assign {unused_fsm_sum_msb,fsm_next} = finished_v ? 5'b00000 : fsm_q + 4'b0001 ;
	// last iteration to bypass last algo on 10th pass ( fsm_q == 4'b1010 is 10 in dec )
	assign last_iter_v = fsm_q[3] & fsm_q[1]; 
	
	always@(posedge clk) 
	begin : fsm_dff
		if (!nreset) 
			fsm_q <= 4'b0000;
		else
		if ( fsm_en ) 
			fsm_q <= fsm_next;
	end 
	
	// --- FIXED: MAIN DATA REGISTER ---
	always @(posedge clk)
		begin : data_dff
		if (!nreset) 
			data_q <= 128'b0; // RESET: Data State to 0
		else
		 data_q <= data_next;
	end 
	
	// Sbox
	genvar sb_i;
	generate 
		for (sb_i=0; sb_i<16; sb_i=sb_i+1) begin : loop_gen_sb_i				
			sbox m_sbox(
				.data_i( data_q[(sb_i*8)+7:(sb_i*8)]),
				//.data_i( 8'h0),
				.data_o( sub_bytes[(sb_i*8)+7:(sb_i*8)])
		        	);
		end
	endgenerate
	
	// ShiftRows : rows : [ 3,
	//			2,
	//			1,
	//			0 ]
	genvar sr_r;
	generate 
		for (sr_r=0; sr_r<4; sr_r=sr_r+1) begin : loop_gen_sr_r
			assign sub_bytes_row[sr_r] = { sub_bytes[3*32+8*sr_r+7:3*32+8*sr_r],
						       sub_bytes[2*32+8*sr_r+7:2*32+8*sr_r],
						       sub_bytes[32+8*sr_r+7:32+8*sr_r],
						       sub_bytes[8*sr_r+7:8*sr_r] };
			assign { shift_row[3*32+8*sr_r+7:3*32+8*sr_r],
						shift_row[2*32+8*sr_r+7:2*32+8*sr_r],
						shift_row[1*32+8*sr_r+7:1*32+8*sr_r],
						shift_row[0*32+8*sr_r+7:0*32+8*sr_r] } = shift_row_row[sr_r];
		end
	endgenerate
		
	assign shift_row_row[0]  =  sub_bytes_row[0]; // row0 no shift
	assign shift_row_row[3]  =  { sub_bytes_row[3][23:16], sub_bytes_row[3][15:8],  sub_bytes_row[3][7:0] ,  sub_bytes_row[3][31:24] }; // row1 0,1,2,3 -> 1,2,3,0
	assign shift_row_row[2]  =  { sub_bytes_row[2][15:8],  sub_bytes_row[2][7:0],   sub_bytes_row[2][31:24], sub_bytes_row[2][23:16] }; // row2 0,1,2,3 -> 2,3,0,1
	assign shift_row_row[1]  =  { sub_bytes_row[1][7:0] ,  sub_bytes_row[1][31:24], sub_bytes_row[1][23:16], sub_bytes_row[1][15:8] };  // row3 0,1,2,3 -> 3,0,1,2 : d,c,b,a -> a,d,cs
	// MixColumns
	genvar mc_c; // collumn [ 3, 2, 1, 0 ]
	generate 
		for (mc_c=0; mc_c<4; mc_c=mc_c+1) begin : loop_gen_mc_c
			
			mixw m_mixw ( 
				.w_i(    shift_row[  mc_c*32+31:mc_c*32] ), 
				.mixw_o( mix_columns[mc_c*32+31:mc_c*32])
			);
		end
	endgenerate
	
	// AddRoundKey : bitwise XOR
	// bypass mix columns for last round
	assign round_key_next = data_v_i ? data_i :( last_iter_v ?  shift_row : mix_columns );
	assign round_key = round_key_next ^ key_current;
	assign data_next = round_key;
	
	// Key calculation 	
	assign key_current      = data_v_i ? key_i        : key_q;
	assign key_rcon_current = data_v_i ? 8'b0000_0001 : key_rcon_q;
	
	ks m_ks(
		 .key_i     (key_current),
		 .key_rcon_i(key_rcon_current),
		 .key_next_o(key_next),
		 .key_rcon_o(key_rcon_next)
                 );
	 // --- FIXED: KEY REGISTERS ---
	 always @(posedge clk) begin
		 if (!nreset) begin // RESET: Key State to 0
			key_q      <= 128'b0;
			key_rcon_q <= 8'b0;
		 end else if ( fsm_en ) begin : key_dff
			key_q      <= key_next;
			key_rcon_q <= key_rcon_next;
		 end
	 end
	 // -----------------------------
	
	// output
	assign res_v_o = finished_v; // aes is on the 11 th round
	assign res_o   = data_q;

endmodule