// =====================================
// Top-Level SHA256 Accelerator Wrapper
// - Connects everything: Wishbone bus ↔ Register File ↔ Accelerator Cores
// - Supports dual-core SHA256 for higher throughput
// =====================================
module accelerator_top (
	input					wb_clk_i,     // System clock

	// WISHBONE bus interface
	input	logic			wb_rst_i,     // Reset signal
	input	logic			wb_stb_i,     // Strobe (valid transaction)
	input	logic	[2:0]	wb_cti_i,     // Cycle Type Identifier (burst, classic, etc.)
	input	logic	[1:0]	wb_bte_i,     // Burst Type Extension
	input	logic			wb_cyc_i,     // Cycle valid signal
	input	logic	[3:0]	wb_sel_i,     // Byte select (which bytes are active)
	input	logic			wb_we_i,      // Write enable
	input	logic	[7:0]	wb_adr_i,     // Address (within accelerator address space)
	input	logic	[31:0]	wb_dat_i,     // Data to write
	output	logic	[31:0]	wb_dat_o,     // Data to read

	output	logic			wb_ack_o,     // Acknowledge signal
	output	logic			wb_err_o,     // Error signal
	output	logic			wb_rty_o,     // Retry signal
	output	logic			int_o         // Optional interrupt (currently unused)
);

// ------------------------------
// Parameters (can be set at compile time)
// ------------------------------
parameter SIM = 0;
parameter debug = 0;

// ------------------------------
// Internal Wires
// ------------------------------
// For data routing between WISHBONE and register file
logic	[31:0]	wb_data_reg_out;
logic	[31:0]	wb_data_reg_in;
logic	[7:0]	wb_adr_int;
logic			we_o, re_o;  // Write/read enable for registers

// Accelerator control/status wires
logic			overflow0, done0;
logic			overflow1, done1;
logic	[31:0]	control0, control1;

// Accelerator input and output buffers for each core
logic	[31:0]	msg_word0  [0:15];
logic	[31:0]	state_in0  [0:7];
logic	[31:0]	state_out0 [0:7];

logic	[31:0]	msg_word1  [0:15];
logic	[31:0]	state_in1  [0:7];
logic	[31:0]	state_out1 [0:7];

// ------------------------------
// Optional: Include ILA for Debug (only in debug builds)
// ------------------------------
`ifdef INCLUDE_ILA
ila_accelerator ila_accelerator (
	.clk(wb_clk_i),
	.probe0(we_o),
	.probe1(re_o),
	.probe2(control0),
	.probe3(msg_word0[0]),
	.probe4(state_in0[0]),
	.probe5(state_out0[0]),
	.probe6(control1),
	.probe7(msg_word1[0]),
	.probe8({31'b0, overflow0 | overflow1})
);
`endif

// ------------------------------
// WISHBONE to Register Bridge
// ------------------------------
// This module handles bus protocol and simplifies register reads/writes
accelerator_wb wb_interface (
	.clk				(wb_clk_i),
	.wb_rst_i			(wb_rst_i),
	.wb_we_i			(wb_we_i),
	.wb_stb_i			(wb_stb_i),
	.wb_cti_i			(wb_cti_i),
	.wb_bte_i			(wb_bte_i),
	.wb_cyc_i			(wb_cyc_i),
	.wb_ack_o			(wb_ack_o),
	.wb_sel_i			(wb_sel_i),
	.wb_adr_i			(wb_adr_i),
	.wb_dat_i			(wb_dat_i),
	.wb_dat_o			(wb_dat_o),
	.wb_err_o			(wb_err_o),
	.wb_rty_o			(wb_rty_o),
	.wb_adr_reg			(wb_adr_int),
	.wb_data_reg_in		(wb_data_reg_in),
	.wb_data_reg_out	(wb_data_reg_out),
	.we_o				(we_o),
	.re_o				(re_o)
);

// ------------------------------
// Register File (accessible by WISHBONE)
// Handles writing to accelerator inputs and reading results
// ------------------------------
accelerator_regs regs (
	.clk		(wb_clk_i),
	.wb_rst_i	(wb_rst_i),
	.wb_addr_i	(wb_adr_int),
	.wb_dat_i	(wb_data_reg_out),
	.wb_dat_o	(wb_data_reg_in),
	.wb_we_i	(we_o),
	.wb_re_i	(re_o),

	// Accelerator 0
	.control0	(control0),
	.done0		(done0),
	.overflow0	(overflow0),
	.msg_word0	(msg_word0),
	.state_in0	(state_in0),
	.state_out0	(state_out0),

	// Accelerator 1
	.control1	(control1),
	.done1		(done1),
	.overflow1	(overflow1),
	.msg_word1	(msg_word1),
	.state_in1	(state_in1),
	.state_out1	(state_out1)
);

// ------------------------------
// Accelerator Core 0
// Processes SHA256 for messages using its own buffer
// ------------------------------
accelerator accelerator0 (
	.clk		(wb_clk_i),
	.wb_rst_i	(wb_rst_i),
	.control	(control0),
	.done		(done0),
	.overflow	(overflow0),
	.msg_word	(msg_word0),
	.state_in	(state_in0),
	.state_out	(state_out0)
);

// ------------------------------
// Accelerator Core 1
// Identical to Core 0 but can be used in parallel for performance
// ------------------------------
accelerator accelerator1 (
	.clk		(wb_clk_i),
	.wb_rst_i	(wb_rst_i),
	.control	(control1),
	.done		(done1),
	.overflow	(overflow1),
	.msg_word	(msg_word1),
	.state_in	(state_in1),
	.state_out	(state_out1)
);

// ------------------------------
// Optional: Interrupt line (not used for now)
// Can be extended to int_o = done0 | done1 for interrupt-based polling
// ------------------------------
assign int_o = 1'b0;

endmodule
