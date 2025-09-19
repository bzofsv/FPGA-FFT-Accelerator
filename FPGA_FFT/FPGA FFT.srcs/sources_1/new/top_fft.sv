`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/19/2025 01:33:50 AM
// Design Name: 
// Module Name: top_fft
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

// top_fft.sv
module top_fft(
  input  logic        CLK100MHZ,   // constrain to N15 in .xdc
  input  logic        RESETn,      // active-low button (fill pin in XDC)
  output logic        UART_TX      // fill pin in XDC (USB-UART)
);
  import q15_pkg::*;
  localparam int W = 16;
  localparam int A = 8;     // 2^8 = 256
  localparam int N = 256;

  // clock & reset
  logic clk = CLK100MHZ;
  logic rstn;
  always_ff @(posedge clk) rstn <= RESETn;

  logic [A-1:0] a_addr, b_addr;
  logic         a_we, b_we;
  logic signed [W-1:0] a_din_r, a_din_i, a_dout_r, a_dout_i;
  logic signed [W-1:0] b_din_r, b_din_i, b_dout_r, b_dout_i;

ram_dual #(.W(W), .A(A), .INIT_FILE("./data/stim256_re.mem")) ram_re (/* ports unchanged */);
ram_dual #(.W(W), .A(A), .INIT_FILE("./data/stim256_im.mem")) ram_im (/* ports unchanged */);

  logic start, busy, done;
  fft256_mem_core #(.W(W), .A(A)) u_fft (
    .clk(clk), .rstn(rstn), .start(start),
    .ram_we_a(a_we), .ram_we_b(b_we),
    .ram_addr_a(a_addr), .ram_addr_b(b_addr),
    .ram_din_a_r(a_din_r), .ram_din_a_i(a_din_i),
    .ram_din_b_r(b_din_r), .ram_din_b_i(b_din_i),
    .ram_dout_a_r(a_dout_r), .ram_dout_a_i(a_dout_i),
    .ram_dout_b_r(b_dout_r), .ram_dout_b_i(b_dout_i),
    .busy(busy), .done(done)
  );

  logic        tx_busy, tx_send;
  logic [7:0]  tx_data;
  uart_tx #(.CLK_HZ(100_000_000), .BAUD(115200)) u_uart (
    .clk(clk), .rstn(rstn), .send(tx_send), .data(tx_data),
    .tx(UART_TX), .busy(tx_busy)
  );

  function automatic [7:0] hexchar(input [3:0] nib);
    hexchar = (nib < 10) ? (8'd48 + nib) : (8'd55 + nib); // 0-9,A-F
  endfunction

  function automatic [31:0] mag2(input signed [W-1:0] xr, xi);
    mag2 = (xr * xr) + (xi * xi);
  endfunction

  typedef enum logic [2:0] {IDLE, KSEL, READ, FMT, SEND, NEXTK} rstate_t;
  rstate_t rs;
  logic [7:0] k;
  logic [31:0] m2;
  logic [4:0]  out_idx;        // sequence over: "k,", 8 hex, "\r", "\n"
  logic [7:0]  out_byte;

  logic started;
  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin started <= 1'b0; start <= 1'b0; end
    else if(!started) begin started <= 1'b1; start <= 1'b1; end
    else start <= 1'b0;
  end

  // readout
  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      rs <= IDLE; k <= 0; out_idx <= 0; tx_send <= 1'b0;
    end else begin
      tx_send <= 1'b0;
      case (rs)
        IDLE:   if (done) rs <= KSEL;
        KSEL:   begin a_addr <= k; b_addr <= k; rs <= READ; end
        READ:   begin
                  m2 <= mag2(a_dout_r, a_dout_i);
                  out_idx <= 0;
                  rs <= FMT;
                end
        FMT: begin
          // build byte for position out_idx
          unique case (out_idx)
            0:  out_byte <= hexchar({4'b0000, k[7:4]}[3:0]); // high nibble of k
            1:  out_byte <= hexchar(k[3:0]);
            2:  out_byte <= 8'd44;                           // ','
            3:  out_byte <= hexchar(m2[31:28]);
            4:  out_byte <= hexchar(m2[27:24]);
            5:  out_byte <= hexchar(m2[23:20]);
            6:  out_byte <= hexchar(m2[19:16]);
            7:  out_byte <= hexchar(m2[15:12]);
            8:  out_byte <= hexchar(m2[11:8]);
            9:  out_byte <= hexchar(m2[7:4]);
            10: out_byte <= hexchar(m2[3:0]);
            11: out_byte <= 8'd13;                           // '\r'
            12: out_byte <= 8'd10;                           // '\n'
            default: out_byte <= 8'd10;
          endcase
          rs <= SEND;
        end
        SEND: if (!tx_busy) begin tx_send <= 1'b1; tx_data <= out_byte; rs <= NEXTK; end
        NEXTK: begin
          if (out_idx < 12) begin out_idx <= out_idx + 1; rs <= FMT; end
          else if (k == 8'd255) rs <= IDLE;
          else begin k <= k + 1; rs <= KSEL; end
        end
      endcase
    end
  end
endmodule
