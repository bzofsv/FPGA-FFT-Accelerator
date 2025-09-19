`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/19/2025 01:37:55 AM
// Design Name: 
// Module Name: uart_tx
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

// uart_tx.sv
module uart_tx #(
  parameter int CLK_HZ = 100_000_000,
  parameter int BAUD   = 115200
)(
  input  logic clk, rstn,
  input  logic send,
  input  logic [7:0] data,
  output logic tx,
  output logic busy
);
  localparam int DIV = CLK_HZ / BAUD;
  logic [15:0] divcnt;
  logic tick;

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin divcnt <= 0; tick <= 1'b0; end
    else if (divcnt == DIV-1) begin divcnt <= 0; tick <= 1'b1; end
    else begin divcnt <= divcnt + 1; tick <= 1'b0; end
  end

  typedef enum logic [1:0] {IDLE, START, DATA, STOP} st_t;
  st_t st;
  logic [2:0] bitn; logic [7:0] sh;

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin tx <= 1'b1; busy <= 1'b0; st <= IDLE; bitn <= 0; sh <= 0; end
    else if (tick) begin
      case (st)
        IDLE:  begin
                 if (send) begin sh <= data; st <= START; busy <= 1'b1; tx <= 1'b0; end
                 else begin tx <= 1'b1; busy <= 1'b0; end
               end
        START: begin st <= DATA; bitn <= 0; end
        DATA:  begin tx <= sh[0]; sh <= {1'b0, sh[7:1]};
                       if (bitn == 3'd7) st <= STOP; else bitn <= bitn + 1; end
        STOP:  begin tx <= 1'b1; st <= IDLE; busy <= 1'b0; end
      endcase
    end
  end
endmodule
