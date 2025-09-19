`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/19/2025 01:40:57 AM
// Design Name: 
// Module Name: ram_dual
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
module ram_dual #(
  parameter int W = 16,
  parameter int A = 8,
  parameter string INIT_FILE = ""    
)(
  input  logic                 clk,
  input  logic [A-1:0]         a_addr, input logic a_we,
  input  logic signed [W-1:0]  a_din,  output logic signed [W-1:0] a_dout,
  input  logic [A-1:0]         b_addr, input logic b_we,
  input  logic signed [W-1:0]  b_din,  output logic signed [W-1:0] b_dout
);
  (* ram_style="block" *) logic signed [W-1:0] mem[0:(1<<A)-1];

  initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

  always_ff @(posedge clk) begin
    if (a_we) mem[a_addr] <= a_din;  a_dout <= mem[a_addr];
    if (b_we) mem[b_addr] <= b_din;  b_dout <= mem[b_addr];
  end
endmodule
