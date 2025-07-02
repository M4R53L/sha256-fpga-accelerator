// =====================================
// Register File for Dual SHA256 Accelerators
// Handles reads/writes to accelerator input/output via memory-mapped registers
// Supports 2 cores (core 0 at base 0x80001300, core 1 at 0x80001500)
// =====================================
module accelerator_regs
#(parameter SIM = 0)
 (
	input	logic					clk,         // Clock
	input	logic					wb_rst_i,    // Reset (active high)

	// Wishbone input interface
	input	logic	[7:0]			wb_addr_i,   // Register address (offset)
	input	logic	[31:0]			wb_dat_i,    // Data to write
	output	logic	[31:0]			wb_dat_o,    // Data to read
	input	logic					wb_we_i,     // Write enable
	input	logic					wb_re_i,     // Read enable

	// Accelerator 0 input/output
	input	logic					overflow0,
	input	logic					done0,
	output	logic	[31:0]			control0,
	output	logic	[31:0]			msg_word0 [0:15],  // 512-bit input block
	output	logic	[31:0]			state_in0 [0:7],   // Input hash state
	input	logic	[31:0]			state_out0 [0:7],  // Output hash state

	// Accelerator 1 input/output
	input	logic					overflow1,
	input	logic					done1,
	output	logic	[31:0]			control1,
	output	logic	[31:0]			msg_word1 [0:15],
	output	logic	[31:0]			state_in1 [0:7],
	input	logic	[31:0]			state_out1 [0:7]
);

// ----------------------------------
// Constants
// ----------------------------------
localparam REG_CONTROL  = 8'h00;   // Control register offset
localparam REG_STATUS   = 8'h84;   // Status register offset
localparam ADDR_BASE1   = 8'h200;  // Base address offset for core 1

localparam GO_BIT       = 0;
localparam DONE_BIT     = 31;

// ----------------------------------
// Address decoding
// ----------------------------------
// sel0 = true if accessing core 0
// sel1 = true if accessing core 1
logic sel0 = (wb_addr_i < ADDR_BASE1);
logic sel1 = (wb_addr_i >= ADDR_BASE1);

// Internal shadow registers to hold result after accelerator is done
logic [31:0] latched_state_out0 [0:7];
logic [31:0] latched_state_out1 [0:7];

// ----------------------------------
// READ logic: connect CPU to register file
// ----------------------------------
always_comb begin
	wb_dat_o = 32'h0;  // Default read value

	if (sel0) begin  // Accessing core 0
		case (wb_addr_i)
			REG_CONTROL: wb_dat_o = control0;
			REG_STATUS:  wb_dat_o = {31'b0, overflow0};

			// msg_word0[0–15]
			8'h04,8'h08,8'h0C,8'h10,8'h14,8'h18,8'h1C,8'h20,
			8'h24,8'h28,8'h2C,8'h30,8'h34,8'h38,8'h3C,8'h40:
				wb_dat_o = msg_word0[(wb_addr_i - 8'h04) >> 2];

			// state_in0[0–7]
			8'h44,8'h48,8'h4C,8'h50,8'h54,8'h58,8'h5C,8'h60:
				wb_dat_o = state_in0[(wb_addr_i - 8'h44) >> 2];

			// latched_state_out0[0–7]
			8'h64,8'h68,8'h6C,8'h70,8'h74,8'h78,8'h7C,8'h80:
				wb_dat_o = latched_state_out0[(wb_addr_i - 8'h64) >> 2];
		endcase
	end else begin  // Accessing core 1
		case (wb_addr_i - ADDR_BASE1)
			REG_CONTROL: wb_dat_o = control1;
			REG_STATUS:  wb_dat_o = {31'b0, overflow1};

			// msg_word1[0–15]
			8'h04,8'h08,8'h0C,8'h10,8'h14,8'h18,8'h1C,8'h20,
			8'h24,8'h28,8'h2C,8'h30,8'h34,8'h38,8'h3C,8'h40:
				wb_dat_o = msg_word1[((wb_addr_i - ADDR_BASE1 - 8'h04) >> 2)];

			// state_in1[0–7]
			8'h44,8'h48,8'h4C,8'h50,8'h54,8'h58,8'h5C,8'h60:
				wb_dat_o = state_in1[((wb_addr_i - ADDR_BASE1 - 8'h44) >> 2)];

			// latched_state_out1[0–7]
			8'h64,8'h68,8'h6C,8'h70,8'h74,8'h78,8'h7C,8'h80:
				wb_dat_o = latched_state_out1[((wb_addr_i - ADDR_BASE1 - 8'h64) >> 2)];
		endcase
	end
end

// ----------------------------------
// WRITE logic and DONE latching
// ----------------------------------
always_ff @(posedge clk or posedge wb_rst_i) begin
	if (wb_rst_i) begin
		// Clear all registers on reset
		control0 <= 32'b0;
		control1 <= 32'b0;

		foreach (msg_word0[i]) msg_word0[i] <= 0;
		foreach (msg_word1[i]) msg_word1[i] <= 0;

		foreach (state_in0[i]) state_in0[i] <= 0;
		foreach (state_in1[i]) state_in1[i] <= 0;

		foreach (latched_state_out0[i]) latched_state_out0[i] <= 0;
		foreach (latched_state_out1[i]) latched_state_out1[i] <= 0;

	end else begin
		// ----------- WRITE TO REGISTERS ------------
		if (wb_we_i) begin
			if (sel0) begin  // Core 0
				case (wb_addr_i)
					REG_CONTROL: begin
						control0[GO_BIT] <= wb_dat_i[GO_BIT];   // Start signal
						control0[DONE_BIT] <= 1'b0;             // Clear done flag
					end
					// msg_word0[0–15]
					8'h04,8'h08,8'h0C,8'h10,8'h14,8'h18,8'h1C,8'h20,
					8'h24,8'h28,8'h2C,8'h30,8'h34,8'h38,8'h3C,8'h40:
						msg_word0[(wb_addr_i - 8'h04) >> 2] <= wb_dat_i;

					// state_in0[0–7]
					8'h44,8'h48,8'h4C,8'h50,8'h54,8'h58,8'h5C,8'h60:
						state_in0[(wb_addr_i - 8'h44) >> 2] <= wb_dat_i;
				endcase
			end else begin  // Core 1
				case (wb_addr_i - ADDR_BASE1)
					REG_CONTROL: begin
						control1[GO_BIT] <= wb_dat_i[GO_BIT];
						control1[DONE_BIT] <= 1'b0;
					end
					// msg_word1[0–15]
					8'h04,8'h08,8'h0C,8'h10,8'h14,8'h18,8'h1C,8'h20,
					8'h24,8'h28,8'h2C,8'h30,8'h34,8'h38,8'h3C,8'h40:
						msg_word1[((wb_addr_i - ADDR_BASE1 - 8'h04) >> 2)] <= wb_dat_i;

					// state_in1[0–7]
					8'h44,8'h48,8'h4C,8'h50,8'h54,8'h58,8'h5C,8'h60:
						state_in1[((wb_addr_i - ADDR_BASE1 - 8'h44) >> 2)] <= wb_dat_i;
				endcase
			end
		end

		// ----------- LATCH DONE RESULTS ------------
		if (done0) begin
			control0[DONE_BIT] <= 1'b1;  // Set done bit
			control0[GO_BIT] <= 1'b0;    // Clear GO
			for (int i = 0; i < 8; i++)  // Save result into output registers
				latched_state_out0[i] <= state_out0[i];
		end

		if (done1) begin
			control1[DONE_BIT] <= 1'b1;
			control1[GO_BIT] <= 1'b0;
			for (int i = 0; i < 8; i++)
				latched_state_out1[i] <= state_out1[i];
		end
	end
end

endmodule
