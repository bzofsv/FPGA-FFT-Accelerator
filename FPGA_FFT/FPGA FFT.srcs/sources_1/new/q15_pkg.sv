`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/19/2025 01:35:38 AM
// Design Name: 
// Module Name: q15_pkg
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

package q15_pkg;
  parameter int W = 16;

  function automatic logic signed [W-1:0] sat_q15(input logic signed [W:0] x);
    if (x >  16'sh7FFF) return 16'sh7FFF;
    if (x < -16'sh8000) return -16'sh8000;
    return x[15:0];
  endfunction

  function automatic logic signed [W-1:0] mul_q15(
      input logic signed [W-1:0] a, b);
    logic signed [31:0] p;
    logic signed [16:0] r;
    begin
      p = a * b;                   // 32-bit prod
      r = (p[30:15]) + p[14];      // round-to-nearest
      return sat_q15(r);
    end
  endfunction

  function automatic void cmul_q15(
      input  logic signed [W-1:0] ar, ai, br, bi,
      output logic signed [W-1:0] pr, pi);
    logic signed [W-1:0] rr, ri;
    begin
      rr = mul_q15(ar, br) - mul_q15(ai, bi);
      ri = mul_q15(ar, bi) + mul_q15(ai, br);
      pr = rr; pi = ri;
    end
  endfunction
endpackage
