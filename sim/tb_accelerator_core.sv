`timescale 1ns/1ps

module tb_accelerator_core;

  logic clk;
  logic rst;
  logic [31:0] control;
  logic        done;
  logic        overflow;

  logic [31:0] msg_word [0:15];
  logic [31:0] state_in [0:7];
  logic [31:0] state_out [0:7];
  logic [31:0] golden_hash [0:7];
  logic [31:0] block_0 [0:15];
  logic [31:0] hash_0 [0:7];

  always #5 clk = ~clk;

  accelerator dut (
    .clk(clk),
    .wb_rst_i(rst),
    .control(control),
    .done(done),
    .overflow(overflow),
    .msg_word(msg_word),
    .state_in(state_in),
    .state_out(state_out)
  );

  localparam logic [31:0] SHA256_INIT_STATE [0:7] = '{
    32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
    32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
  };

  task automatic compare_output(string label);
    int mismatches = 0;
    $display(">>> %s", label);
    for (int i = 0; i < 8; i++) begin
      if (state_out[i] !== golden_hash[i]) begin
        $display("❌ word[%0d]: got %08x, expected %08x", i, state_out[i], golden_hash[i]);
        mismatches++;
      end else begin
        $display("✅ word[%0d] = %08x", i, state_out[i]);
      end
    end
    if (mismatches == 0)
      $display("✅ PASS: %s\n", label);
    else
      $display("❌ FAIL: %s with %0d mismatches\n", label, mismatches);
  endtask

  task automatic run_test(string label);
    foreach (state_in[i]) state_in[i] = SHA256_INIT_STATE[i];
    #10 control[0] = 1'b1;
    wait (done == 1); #10;
    control = 0;
    compare_output(label);
  endtask

  task automatic load_input_and_expected(string label);
    for (int i = 0; i < 16; i++) msg_word[i] = block_0[i];
    for (int i = 0; i < 8; i++)  golden_hash[i] = hash_0[i];
    run_test(label);
  endtask

  initial begin
    clk = 0;
    rst = 1;
    control = 0;
    #20 rst = 0;

    // Fill block_0 and hash_0 with Static Joke data
    block_0 = '{
      32'h49207573, 32'h65642074, 32'h6f20706c, 32'h61792070,
      32'h69616e6f, 32'h20627920, 32'h6561722c, 32'h20627574,
      32'h206e6f77, 32'h20492075, 32'h7365206d, 32'h79206861,
      32'h6e64732e, 32'h80000000, 32'h00000000, 32'h000001a0
    };

    hash_0 = '{
      32'h233b5713, 32'hd3f244af, 32'hf9055b5d, 32'hf200cd6d,
      32'h62a55ffa, 32'h81a04e93, 32'h26541bc9, 32'h51fe5ae6
    };

    load_input_and_expected("Static Joke [C-integrated]");

    $display("✅ SHA256Transform-only accelerator verification completed.");
    $finish;
  end

endmodule
