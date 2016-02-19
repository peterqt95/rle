/* ECE111 Project 2: RLE
 * Author: Peter Tran A11163016
 * 		   Derek Tran A10543575
 * 
 */
module rle (
	clk, 		
	nreset, 	
	start,
	message_addr,	
	message_size, 	
	rle_addr, 	
	rle_size, 	
	done, 		
	port_A_clk,
    port_A_data_in,
    port_A_data_out,
    port_A_addr,
    port_A_we
	);

input	clk;
input	nreset;
// Initializes the RLE module

input	start;
// Tells RLE to start compressing the given frame

input 	[31:0] message_addr;
// Starting address of the plaintext frame
// i.e., specifies from where RLE must read the plaintext frame

input	[31:0] message_size;
// Length of the plain text in bytes

input	[31:0] rle_addr;
// Starting address of the ciphertext frame
// i.e., specifies where RLE must write the ciphertext frame

input   [31:0] port_A_data_out;
// read data from the dpsram (plaintext)

output  [31:0] port_A_data_in;
// write data to the dpsram (ciphertext)

output  [15:0] port_A_addr;
// address of dpsram being read/written

output  port_A_clk;
// clock to dpsram (drive this with the input clk)

output  port_A_we;
// read/write selector for dpsram

output	[31:0] rle_size;
// Length of the compressed text in bytes

output	done; // done is a signal to indicate that encryption of the frame is complete


reg [1:0] STATE;
parameter [1:0] s_finish = 0,
				s_read = 1,
				s_compress = 2,
				s_write = 3;

reg [15:0] read_offset; // offset memory read address
reg [15:0] write_offset; // offset memory write address
reg [31:0] to_ram;  // write to the dps
reg [7:0] current_total; // number of consecutive numbers that appear 
reg [7:0] current_value; // the value of the current data being looked at  
reg first; // indicate that this is our first time compressing
reg empty; // indicate if we have no more values that were read in
reg write_complete;
reg [1:0] read_count; //offset to read each part of the input
wire message_complete; // indicate moving onto the next message
reg ready; // ready to write
reg delay; // delay the signal to let chars load in

reg [7:0] curr_char; //the value we are looking at 
reg [7:0] char3, char2, char1, char0; // input from port_A_data_out
reg [31:0] rle_size; // size of our length encoding
reg which; // determine if we need to overlay 2 outputs together (i.e 00000028 & 00002801 --> 28010028)
reg done;

assign port_A_clk = clk; // clk to dpsram
assign port_A_we = (STATE==s_write)?1:0; // 1 = write, 0 = read
assign port_A_addr = (STATE==s_write)?(rle_addr + write_offset):(message_addr + read_offset); // offset where to read from
assign port_A_data_in = to_ram; // what we are writing to the dpsram
assign message_complete = (read_offset >= message_size); // if we increment past our message size, move onto the next message
 
always @ (posedge clk)
begin
	if(!nreset | start)
		begin
			STATE <= s_read;
			read_offset <= 0;
			write_offset <= 0;
			first <= 1;
			current_value <= 0;
			current_total <= 0;
			empty <= 1;
			to_ram <= 0;
			read_count <= 0;
			ready <= 0;
			write_complete <= 0;
			rle_size <= 0;

			delay <= 0;
			{char3, char2, char1, char0} <= 0;
			which <= 0;
			done <= 0;
		end
	else
		begin
			case(STATE)
				s_read:
					begin
						// read in value from dpsram
						read_offset <= read_offset + 4;
						{char3, char2, char1, char0} <= port_A_data_out;
						empty <= 0;
						if(!ready)
							STATE <= s_compress;
						else
							STATE <= s_write;
					end
				s_compress:
					begin
						if(first)
							begin
								// first run, just store values and update counter
								current_value <= char0;
								current_total <= 1;
								read_count <= 1;
								first <= 0;
							end
						else
							begin
								if(!delay)
									begin
										// delay the clock to allow character to load in
										delay <= 1;
										case(read_count)
											0:
												begin
													curr_char <= char0;
												end
											1:
												begin
													curr_char <= char1;
												end
											2:
												begin
													curr_char <= char2;
												end
											3:
												begin
													curr_char <= char3;
												end
										endcase
										//edge case rle_testbench2
										if((curr_char == 0) & (message_complete) & (read_count == 0) & which == 1)
											begin
												STATE <= s_write;
											end
									end
								else
									begin
										delay <= 0;
										if(curr_char == current_value)
											begin
												// update current number of consecutive values that appear
												current_total <= current_total + 1;
											end
										else if(curr_char != current_value)
											begin
												// if new value, concatenate value/# of appearence to write to dps
												// and determine if we are ready to write yet
												current_value <= curr_char;
												current_total <= 1;
												if(!which)
													begin
														to_ram[15:0] <= {current_value, current_total};
														which <= 1;

													end
												else 
													begin
														to_ram[31:16] <= {current_value, current_total};
														ready <= 1;
														STATE <= s_write;
													end
												rle_size <= rle_size + 2;
											end
													
											if(read_count < 3)
												begin
													read_count <= read_count + 1;
												end
											else
												begin
													empty <= 1;
													read_count <= 0;
													if(!message_complete)
														begin
															STATE <= s_read;
														end
												end
									end
							end
					end
				s_write:
					begin
						//write to dpsram
						write_offset <= write_offset + 4;
						to_ram <= 0;
						ready <= 0;
						which <= 0;
						if(message_complete & empty)
							begin
								STATE <= s_finish;
							end
						else if (empty)
							begin
								STATE <= s_read;
							end
						else
							begin
								STATE <= s_compress;
							end
					end
				s_finish:
					begin
						done <= 1;
					end
			endcase
		end
end

endmodule