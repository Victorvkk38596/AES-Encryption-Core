`timescale 1ns / 1ps

//Little Endian is followed here [word3, word2, word1, word0]

//This module is only invoked for word indices that are multiples of 4 (Nk = 4 in 128 bit)
module aes_key_first_col(
	input  wire [31:0] key_w3_i,
	input  wire [7:0]  key_rcon_i,
	output wire [31:0] key_w3_next_o,
	output wire [7:0]  key_rcon_o
	);
	
	wire [31:0] key_rot;
	wire [31:0] key_sbox;
	wire [31:0] key_xor;

	//ROTWORD, circular rotation of 1B
	assign key_rot[31:24] = key_w3_i[7:0];
	assign key_rot[23:16] = key_w3_i[31:24];
	assign key_rot[15:8]  = key_w3_i[23:16];
	assign key_rot[7:0]   = key_w3_i[15:8];

	//SBOX mapping
	genvar i;
	generate
		for(i=0; i<4; i=i+1) begin : loop_gen_key_sbox
			sbox m_key_sbox(
				.data_i(key_rot[(i*8)+7:(i*8)]),
				.data_o(key_sbox[(i*8)+7:(i*8)])
			);
		end
	endgenerate

	//XORing with the 1st byte of rcon, rest are 0 anway
	assign key_xor = { key_sbox[31:8], key_sbox[7:0] ^ key_rcon_i };

	wire overflow = key_rcon_i[7];
	wire [7:0] shifted_rcon = {key_rcon_i[6:0], 1'b0};
	assign key_rcon_o = (overflow == 1'b1) ? (shifted_rcon ^ 8'h1b) : shifted_rcon;

	assign key_w3_next_o   = key_xor;
	
endmodule 


// This module remains unchanged as the interface to aes_key_first_col is identical.
module ks(
	input  wire [127:0] key_i,
	input  wire [7:0]   key_rcon_i,
	output wire [127:0] key_next_o,
	output wire [7:0]   key_rcon_o
	);
	wire [31:0] key_col[3:0];
	wire [31:0] key_col_w3;
	wire [31:0] key_col_next[3:0];
	wire [7:0]  key_rcon_next;
		
		
	genvar i; // row
	generate
		for(i=0; i<4; i=i+1) begin : loop_gen_key_col
			// input
			assign key_col[i] = key_i[(i*32)+31:(i*32)];
			// output
			assign key_next_o[(i*32)+31:(i*32)] = key_col_next[i];
		end
	endgenerate
	
	//Only for word indices that are multiples of 4
	aes_key_first_col aes_key_w3(
		.key_w3_i(key_col[3]),
		.key_rcon_i(key_rcon_i),
		.key_w3_next_o(key_col_w3),
		.key_rcon_o(key_rcon_next)
	);
	assign key_col_next[0] = key_col[0] ^ key_col_w3;

	assign key_col_next[1] = key_col_next[0] ^ key_col[1];
	assign key_col_next[2] = key_col_next[1] ^ key_col[2];
	assign key_col_next[3] = key_col_next[2] ^ key_col[3];
	
	assign key_rcon_o = key_rcon_next;

endmodule