#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <psp_api.h>  // For performance counters and RISC-V specific support

// ------------------------
// Type aliases for clarity
// ------------------------
#define uchar unsigned char
#define uint unsigned int

// ------------------------
// Helper macro to add bit lengths safely (handles 64-bit value using two 32-bit ints)
// ------------------------
#define DBL_INT_ADD(a,b,c) if (a > 0xffffffff - (c)) ++b; a += c;

// ------------------------
// Register address map for accelerator 0 (base = 0x80001300)
// ------------------------
#define REG_BASE0                0x80001300
#define REG_CONTROL(base)        (base + 0x00)
#define REG_MSG_BASE(base)       (base + 0x04)
#define REG_STATE_IN_BASE(base)  (base + 0x44)
#define REG_STATE_OUT_BASE(base) (base + 0x64)

// Read/write macros to memory-mapped registers
#define READ_REG(addr) (*(volatile unsigned *) (addr))
#define WRITE_REG(addr, val) (*(volatile unsigned *) (addr) = (val))

// Control register bits
#define CTRL_GO    0x00000001u
#define CTRL_DONE  0x80000000u

// ------------------------
// SHA256 context struct (RAM-side state)
// ------------------------
typedef struct {
    uchar data[64];     // 512-bit message block
    uint datalen;       // Number of bytes currently in data[]
    uint bitlen[2];     // Total message length in bits (hi/lo)
    uint state[8];      // SHA256 state (A-H)
} SHA256_CTX;

// ------------------------
// Send one 512-bit block to the accelerator
// ------------------------
void SHA256Transform(SHA256_CTX *ctx, uchar data[]) {
    uint m[16];
    uint base = REG_BASE0;

    // Parse 64 bytes of message into 16 32-bit words
    for (int i = 0, j = 0; i < 16; ++i, j += 4) {
        m[i] = (data[j] << 24) | (data[j+1] << 16) | (data[j+2] << 8) | (data[j+3]);
        WRITE_REG(REG_MSG_BASE(base) + i * 4, m[i]);  // Write to accelerator input
    }

    // Write current SHA256 state
    for (int i = 0; i < 8; i++) {
        WRITE_REG(REG_STATE_IN_BASE(base) + i * 4, ctx->state[i]);
    }

    // Trigger accelerator to begin processing
    WRITE_REG(REG_CONTROL(base), 0);        // Clear control register
    WRITE_REG(REG_CONTROL(base), CTRL_GO);  // Set GO bit

    // Wait for DONE bit to be set by hardware
    while ((READ_REG(REG_CONTROL(base)) & CTRL_DONE) == 0) {}

    // Read the updated SHA256 state from accelerator
    for (int i = 0; i < 8; i++) {
        ctx->state[i] = READ_REG(REG_STATE_OUT_BASE(base) + i * 4);
    }
}

// ------------------------
// Initialize SHA256 state constants
// ------------------------
void SHA256Init(SHA256_CTX *ctx) {
    memset(ctx, 0, sizeof(SHA256_CTX));
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
}

// ------------------------
// Process input data in 64-byte blocks
// ------------------------
void SHA256Update(SHA256_CTX *ctx, uchar *data, uint len) {
    uint i;
    for (i = 0; i < len; ++i) {
        ctx->data[ctx->datalen++] = data[i];

        // When a full 64-byte block is filled, send it to accelerator
        if (ctx->datalen == 64) {
            SHA256Transform(ctx, ctx->data);
            DBL_INT_ADD(ctx->bitlen[0], ctx->bitlen[1], 512);  // Add 512 bits
            ctx->datalen = 0;
        }
    }
}

// ------------------------
// Add padding and finalize the hash
// ------------------------
void SHA256Final(SHA256_CTX *ctx, uchar hash[]) {
    uint i = ctx->datalen;

    // Update total bit length
    DBL_INT_ADD(ctx->bitlen[0], ctx->bitlen[1], ctx->datalen * 8);

    // Append padding: 0x80 followed by zeros
    ctx->data[i++] = 0x80;
    if (i > 56) {
        while (i < 64) ctx->data[i++] = 0x00;
        SHA256Transform(ctx, ctx->data);  // Process current block
        i = 0;
    }
    while (i < 56) ctx->data[i++] = 0x00;

    // Append total length (64 bits, big-endian)
    ctx->data[63] = ctx->bitlen[0];
    ctx->data[62] = ctx->bitlen[0] >> 8;
    ctx->data[61] = ctx->bitlen[0] >> 16;
    ctx->data[60] = ctx->bitlen[0] >> 24;
    ctx->data[59] = ctx->bitlen[1];
    ctx->data[58] = ctx->bitlen[1] >> 8;
    ctx->data[57] = ctx->bitlen[1] >> 16;
    ctx->data[56] = ctx->bitlen[1] >> 24;

    // Final block
    SHA256Transform(ctx, ctx->data);

    // Convert state to final hash output (32 bytes)
    for (i = 0; i < 4; ++i) {
        hash[i]      = (ctx->state[0] >> (24 - i * 8)) & 0xff;
        hash[i + 4]  = (ctx->state[1] >> (24 - i * 8)) & 0xff;
        hash[i + 8]  = (ctx->state[2] >> (24 - i * 8)) & 0xff;
        hash[i + 12] = (ctx->state[3] >> (24 - i * 8)) & 0xff;
        hash[i + 16] = (ctx->state[4] >> (24 - i * 8)) & 0xff;
        hash[i + 20] = (ctx->state[5] >> (24 - i * 8)) & 0xff;
        hash[i + 24] = (ctx->state[6] >> (24 - i * 8)) & 0xff;
        hash[i + 28] = (ctx->state[7] >> (24 - i * 8)) & 0xff;
    }
}

// ------------------------
// One-shot SHA256 interface: input a string, return hex digest
// ------------------------
char* SHA256(char* data) {
    SHA256_CTX ctx;
    unsigned char hash[32];
    char* hashStr = malloc(65);  // 64 chars + null terminator
    if (!hashStr) return NULL;

    SHA256Init(&ctx);
    SHA256Update(&ctx, (uchar *)data, strlen(data));
    SHA256Final(&ctx, hash);

    // Convert binary hash to readable hex string
    for (int i = 0; i < 32; i++) {
        sprintf(hashStr + i * 2, "%02x", hash[i]);
    }
    hashStr[64] = '\0';

    return hashStr;
}

// ------------------------
// Main Function (Testbench)
// ------------------------
int main() {
    // Array of 20 strings to hash
    char secrets[20][256] = {
        "I used to play piano by ear, but now I use my hands.",
        "Why don't scientists trust atoms? Because they make up everything.",
        "I'm reading a book about anti-gravity. It's impossible to put down.",
        "I told my wife she was drawing her eyebrows too high. She looked surprised.",
        "Why do seagulls fly over the sea? Because if they flew over the bay, they'd be bagels!",
        "I have a photographic memory, but I always forget to bring the film.",
        "I used to be a baker, but I couldn't raise the dough.",
        "I'm reading a book on the history of glue. I just can't seem to put it down.",
        "Why don't oysters give to charity? Because they're shellfisha!",
        "I told my wife she was overreacting. She just rolled her eyes and left the room.",
        "I'm addicted to brake fluid, but I can stop anytime.",
        "Why don't scientists trust atoms? Because they're always up to something.",
        "I used to be indecisive, but now I'm not sure.",
        "I'm a huge fan of whiteboards. They're re-markable.",
        "Why don't skeletons fight each other? They don't have the guts.",
        "I'm not lazy, I'm just on energy-saving mode.",
        "Why don't ants get sick? Because they have tiny ant-bodies!",
        "The future, the present, and the past walked into a bar. It was tense.",
        "Why did the hipster burn his tongue? He drank his coffee before it was cool.",
        "The identity of the creator of Bitcoin, known by the pseudonym Satoshi Nakamoto, is still unknown..."
    };

    unsigned int cyc_beg, cyc_end;
    char *array[20];

    // Enable performance monitoring
    pspMachinePerfMonitorEnableAll();
    pspMachinePerfCounterSet(D_PSP_COUNTER0, D_CYCLES_CLOCKS_ACTIVE);
    cyc_beg = pspMachinePerfCounterGet(D_PSP_COUNTER0);  // Start timing

    // Run SHA256 on all 20 strings using hardware accelerator
    for (int i = 0; i < 20; i++) {
        array[i] = SHA256(secrets[i]);
    }

    cyc_end = pspMachinePerfCounterGet(D_PSP_COUNTER0);  // Stop timing

    // Print results
    for (int i = 0; i < 20; i++) {
        printf("public key %d: %s\n", i, array[i]);
        free(array[i]);  // Free memory after use
    }

    printf("\nPerformance Summary\n");
    printf("Total Cycles = %d\n", cyc_end - cyc_beg);  // Show total execution time

    return 0;
}
