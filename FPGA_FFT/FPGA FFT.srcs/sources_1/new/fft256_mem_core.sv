`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/19/2025 01:42:22 AM
// Design Name: 
// Module Name: fft256_mem_core
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// fft256_mem_core.sv
// Iterative radix-2 DIT, in-place, N=256, per-stage >>1 scaling (matches Python golden)
// Reads/writes two BRAMs (Re/Im). After start, asserts done when the full FFT is written back.

module fft256_mem_core #(
  parameter int W = 16,    // Q1.15 width
  parameter int A = 8      // address bits: 2^A = 256
)(
  input  logic clk,
  input  logic rstn,
  input  logic start,

  // BRAM Re/Im controls (to two instances of ram_dual)
  output logic                 ram_we_a,
  output logic                 ram_we_b,
  output logic [A-1:0]         ram_addr_a,
  output logic [A-1:0]         ram_addr_b,
  output logic signed [W-1:0]  ram_din_a_r,
  output logic signed [W-1:0]  ram_din_a_i,
  output logic signed [W-1:0]  ram_din_b_r,
  output logic signed [W-1:0]  ram_din_b_i,
  input  logic signed [W-1:0]  ram_dout_a_r,
  input  logic signed [W-1:0]  ram_dout_a_i,
  input  logic signed [W-1:0]  ram_dout_b_r,
  input  logic signed [W-1:0]  ram_dout_b_i,

  output logic busy,
  output logic done
);

  import q15_pkg::*;

  // -----------------------------
  // Parameters / local constants
  // -----------------------------
  localparam int N = (1 << A);     // 256

  // -----------------------------
  // Stage / loop counters
  // -----------------------------
  logic [2:0]  s;                  // stage 0..7
  logic [8:0]  m;                  // 2,4,...,256  (needs 9 bits for 256)
  logic [7:0]  half;               // m/2 (max 128)
  logic [7:0]  stride;             // N/m (128..1)

  logic [7:0]  k0;                 // block base index (0..255 step m)
  logic [7:0]  j;                  // butterfly index inside block (0..half-1)

  // -----------------------------
  // Addresses / twiddle control
  // -----------------------------
  wire [A-1:0] addrA = k0 + j;           // a-index
  wire [A-1:0] addrB = k0 + j + half;    // b-index

  logic  [6:0] tw_addr;                  // 0..127
  logic signed [W-1:0] wr, wi;           // twiddle (Q1.15)

  // Twiddle ROM (make sure this file exists in project)
  twiddle_rom256 #(.W(W), .A(7)) UROM (
    .clk (clk),
    .addr(tw_addr),
    .wr  (wr),
    .wi  (wi)
  );

  // -----------------------------
  // Data path registers
  // -----------------------------
  logic signed [W-1:0] ar, ai;     // a sample
  logic signed [W-1:0] br, bi;     // b sample
  logic signed [W-1:0] tr, ti;     // t = b * W
  logic signed [W-1:0] ur, ui;     // u = a + t  (>>1)
  logic signed [W-1:0] vr, vi;     // v = a - t  (>>1)

  // -----------------------------
  // FSM
  // -----------------------------
  typedef enum logic [3:0] {
    IDLE,     // wait for start
    ADDR,     // drive addresses for this butterfly
    READ,     // capture BRAM read data (1-cycle later)
    BUTTER,   // compute t,u,v
    WRITE,    // write back u,v
    NEXTJ,    // next butterfly in block
    NEXTK,    // next block
    NEXTS,    // next stage
    FINISH
  } state_t;

  state_t st;

  always_comb begin
    // m = 2^(s+1)
    m      = 9'(1) << (s + 1);
    half   = m[8:1];               // m / 2
    stride = N / m;                // N is power of two
    tw_addr = ( (j * stride) & 8'h7F );
  end

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      ram_we_a   <= 1'b0;
      ram_we_b   <= 1'b0;
      ram_addr_a <= '0;
      ram_addr_b <= '0;
      ram_din_a_r <= '0; ram_din_a_i <= '0;
      ram_din_b_r <= '0; ram_din_b_i <= '0;
    end else begin
      // default (no write) each cycle
      ram_we_a   <= 1'b0;
      ram_we_b   <= 1'b0;

      unique case (st)
        ADDR: begin
          ram_addr_a <= addrA;
          ram_addr_b <= addrB;
        end
        READ: begin
          // addresses already set; capture happens below into ar/ai/br/bi
        end
        WRITE: begin
          ram_addr_a  <= addrA;
          ram_addr_b  <= addrB;
          ram_din_a_r <= ur;  ram_din_a_i <= ui;
          ram_din_b_r <= vr;  ram_din_b_i <= vi;
          ram_we_a    <= 1'b1;
          ram_we_b    <= 1'b1;
        end
        default: begin end
      endcase
    end
  end

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      st   <= IDLE;
      s    <= '0;
      j    <= '0;
      k0   <= '0;
      busy <= 1'b0;
      done <= 1'b0;

      ar <= '0; ai <= '0; br <= '0; bi <= '0;
      tr <= '0; ti <= '0; ur <= '0; ui <= '0; vr <= '0; vi <= '0;
    end else begin
      done <= 1'b0; // default

      unique case (st)
        IDLE: begin
          if (start) begin
            busy <= 1'b1;
            s    <= 3'd0;
            j    <= 8'd0;
            k0   <= 8'd0;
            st   <= ADDR;
          end
        end

        ADDR: begin
          st <= READ;
        end

        READ: begin
          // capture current a,b from BRAM outputs
          ar <= ram_dout_a_r;  ai <= ram_dout_a_i;
          br <= ram_dout_b_r;  bi <= ram_dout_b_i;
          st <= BUTTER;
        end

        BUTTER: begin
          // t = b * W
          cmul_q15(br, bi, wr, wi, tr, ti);
          // u = a + t; v = a - t; per-stage >> 1 to control growth
          ur <= (ar + tr) >>> 1;
          ui <= (ai + ti) >>> 1;
          vr <= (ar - tr) >>> 1;
          vi <= (ai - ti) >>> 1;
          st <= WRITE;
        end

        WRITE: begin
          // write-back happens via BRAM control process
          st <= NEXTJ;
        end

        NEXTJ: begin
          if (j == (half - 1)) begin
            j  <= 8'd0;
            st <= NEXTK;
          end else begin
            j  <= j + 8'd1;
            st <= ADDR;
          end
        end

        NEXTK: begin
          if (k0 >= (N[7:0] - m[7:0])) begin
            k0 <= 8'd0;
            st <= NEXTS;
          end else begin
            k0 <= k0 + m[7:0];
            st <= ADDR;
          end
        end

        NEXTS: begin
          if (s == 3'd7) begin
            st <= FINISH;
          end else begin
            s  <= s + 3'd1;
            st <= ADDR;
          end
        end

        FINISH: begin
          busy <= 1'b0;
          done <= 1'b1;
          st   <= IDLE;
        end

        default: st <= IDLE;
      endcase
    end
  end

endmodule
