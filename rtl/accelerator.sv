// SHA256 Accelerator Core
module accelerator (
    input  logic         clk,         // Clock input
    input  logic         wb_rst_i,    // Reset signal (active high)

    input  logic [31:0]  control,     // Control signal: GO bit triggers the computation
    output logic         overflow,    // Not used here (always 0)
    output logic         done,        // Signals that hashing is complete

    input  logic [31:0]  msg_word [0:15],   // 512-bit message block (16 x 32-bit words)
    input  logic [31:0]  state_in [0:7],    // Initial SHA256 state (8 x 32-bit words)
    output logic [31:0]  state_out [0:7]    // Output SHA256 state (after processing one block)
);

// GO bit position in the control register
localparam GO_BIT = 0;

// Detect if control register's GO bit is set
wire go = control[GO_BIT];

// Internal latch to track start signal (GO)
logic go_latched;
always_ff @(posedge clk or posedge wb_rst_i) begin
    if (wb_rst_i)
        go_latched <= 0;                        // Reset: clear GO latch
    else if (go && state == IDLE)
        go_latched <= 1;                        // Latch GO if we’re in IDLE
    else if (state == DONE)
        go_latched <= 0;                        // Clear latch after we’re DONE
end

// Working registers (SHA256 requires 8 temp variables)
logic [31:0] a, b, c, d, e, f, g, h;

// Temporary variables used in compression step
logic [31:0] t1, t2;

// Constants (K values from SHA256 spec)
logic [31:0] k [0:63];

// Message schedule array (m[0..63])
logic [31:0] m [0:63];

// Round counter (0–63)
logic [6:0] round;

// FSM states for SHA256 processing
typedef enum logic [2:0] {
    IDLE,       // Waiting for GO
    LOAD,       // Load message + state
    EXPAND,     // Expand 16 message words to 64
    COMPRESS,   // 64 compression rounds
    DONE        // Finalize and write output
} state_t;
state_t state;

// Overflow not used here
assign overflow = 1'b0;

// ---- SHA256 Constants ----
initial begin
    k[ 0] = 32'h428a2f98; k[ 1] = 32'h71374491; k[ 2] = 32'hb5c0fbcf; k[ 3] = 32'he9b5dba5;
    k[ 4] = 32'h3956c25b; k[ 5] = 32'h59f111f1; k[ 6] = 32'h923f82a4; k[ 7] = 32'hab1c5ed5;
    k[ 8] = 32'hd807aa98; k[ 9] = 32'h12835b01; k[10] = 32'h243185be; k[11] = 32'h550c7dc3;
    k[12] = 32'h72be5d74; k[13] = 32'h80deb1fe; k[14] = 32'h9bdc06a7; k[15] = 32'hc19bf174;
    k[16] = 32'he49b69c1; k[17] = 32'hefbe4786; k[18] = 32'h0fc19dc6; k[19] = 32'h240ca1cc;
    k[20] = 32'h2de92c6f; k[21] = 32'h4a7484aa; k[22] = 32'h5cb0a9dc; k[23] = 32'h76f988da;
    k[24] = 32'h983e5152; k[25] = 32'ha831c66d; k[26] = 32'hb00327c8; k[27] = 32'hbf597fc7;
    k[28] = 32'hc6e00bf3; k[29] = 32'hd5a79147; k[30] = 32'h06ca6351; k[31] = 32'h14292967;
    k[32] = 32'h27b70a85; k[33] = 32'h2e1b2138; k[34] = 32'h4d2c6dfc; k[35] = 32'h53380d13;
    k[36] = 32'h650a7354; k[37] = 32'h766a0abb; k[38] = 32'h81c2c92e; k[39] = 32'h92722c85;
    k[40] = 32'ha2bfe8a1; k[41] = 32'ha81a664b; k[42] = 32'hc24b8b70; k[43] = 32'hc76c51a3;
    k[44] = 32'hd192e819; k[45] = 32'hd6990624; k[46] = 32'hf40e3585; k[47] = 32'h106aa070;
    k[48] = 32'h19a4c116; k[49] = 32'h1e376c08; k[50] = 32'h2748774c; k[51] = 32'h34b0bcb5;
    k[52] = 32'h391c0cb3; k[53] = 32'h4ed8aa4a; k[54] = 32'h5b9cca4f; k[55] = 32'h682e6ff3;
    k[56] = 32'h748f82ee; k[57] = 32'h78a5636f; k[58] = 32'h84c87814; k[59] = 32'h8cc70208;
    k[60] = 32'h90befffa; k[61] = 32'ha4506ceb; k[62] = 32'hbef9a3f7; k[63] = 32'hc67178f2;
end

// ---- SHA256 Helper Functions ----
// Rotation and bitwise logic operations

function logic [31:0] ROTR(input logic [31:0] x, input int n);
    return (x >> n) | (x << (32 - n));
endfunction

function logic [31:0] EP0(input logic [31:0] x);
    return ROTR(x,2) ^ ROTR(x,13) ^ ROTR(x,22);
endfunction

function logic [31:0] EP1(input logic [31:0] x);
    return ROTR(x,6) ^ ROTR(x,11) ^ ROTR(x,25);
endfunction

function logic [31:0] CH(input logic [31:0] x, y, z);
    return (x & y) ^ (~x & z);
endfunction

function logic [31:0] MAJ(input logic [31:0] x, y, z);
    return (x & y) ^ (x & z) ^ (y & z);
endfunction

function logic [31:0] SIG0(input logic [31:0] x);
    return ROTR(x,7) ^ ROTR(x,18) ^ (x >> 3);
endfunction

function logic [31:0] SIG1(input logic [31:0] x);
    return ROTR(x,17) ^ ROTR(x,19) ^ (x >> 10);
endfunction

// ---- SHA256 FSM ----
always_ff @(posedge clk or posedge wb_rst_i) begin
    if (wb_rst_i) begin
        done <= 0;
        round <= 0;
        state <= IDLE;
    end else begin
        done <= 0;  // Default

        case (state)
            IDLE: begin
                if (go_latched)
                    state <= LOAD;  // Start hashing
            end

            LOAD: begin
                // Clear entire m[] array
                for (int i = 0; i < 64; i++) m[i] <= 32'h0;

                // Load first 16 words from input
                for (int i = 0; i < 16; i++) m[i] <= msg_word[i];

                // Initialize working variables (a-h) from input state
                a <= state_in[0]; b <= state_in[1]; c <= state_in[2]; d <= state_in[3];
                e <= state_in[4]; f <= state_in[5]; g <= state_in[6]; h <= state_in[7];

                round <= 16;  // Next: compute m[16] to m[63]
                state <= EXPAND;
            end

            EXPAND: begin
                if (round < 64) begin
                    // Compute the extended message schedule
                    m[round] <= SIG1(m[round-2]) + m[round-7] + SIG0(m[round-15]) + m[round-16];
                    round <= round + 1;
                end else begin
                    round <= 0;
                    state <= COMPRESS;
                end
            end

            COMPRESS: begin
                if (round < 64) begin
                    // Perform one round of SHA256 compression
                    t1 = h + EP1(e) + CH(e,f,g) + k[round] + m[round];
                    t2 = EP0(a) + MAJ(a,b,c);

                    // Shift values and update working variables
                    h <= g;
                    g <= f;
                    f <= e;
                    e <= d + t1;
                    d <= c;
                    c <= b;
                    b <= a;
                    a <= t1 + t2;

                    round <= round + 1;
                end else begin
                    state <= DONE;
                end
            end

            DONE: begin
                // Add working variables back to the original state to produce the final state
                state_out[0] <= a + state_in[0];
                state_out[1] <= b + state_in[1];
                state_out[2] <= c + state_in[2];
                state_out[3] <= d + state_in[3];
                state_out[4] <= e + state_in[4];
                state_out[5] <= f + state_in[5];
                state_out[6] <= g + state_in[6];
                state_out[7] <= h + state_in[7];

                done <= 1;          // Signal that hash is ready
                state <= IDLE;      // Go back to waiting
            end
        endcase
    end
end

endmodule
