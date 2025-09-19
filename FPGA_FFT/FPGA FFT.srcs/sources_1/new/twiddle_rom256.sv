`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/19/2025 01:44:21 AM
// Design Name: 
// Module Name: twiddle_rom256
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

module twiddle_rom256 #(parameter W=16, A=7)(
  input  logic clk,
  input  logic [A-1:0] addr,
  output logic signed [W-1:0] wr, wi
);
  logic signed [W-1:0] rom_wr [0:(1<<A)-1];
  logic signed [W-1:0] rom_wi [0:(1<<A)-1];

  initial begin
    $readmemh("data/tw_wr.mem", rom_wr);
    $readmemh("data/tw_wi.mem", rom_wi);
  end

  always_ff @(posedge clk) begin
    wr <= rom_wr[addr];
    wi <= rom_wi[addr];
  end
endmodule
