// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  parameter P = 4'h5;

  typedef struct {  // Must be unpacked -- existing error check
    // Update ctor_var_reset to check instead of making a constructor
    bit [3:0] m_lo = P;
    bit [93:0] m_mid = '1;  // Wide
    bit [3:0] m_hi;
  } s_t;
  s_t s;

  typedef real numeric_t;
  localparam numeric_t REAL_P = 1.25;
  typedef struct {
    real value = 1.25;
    numeric_t parameterized = REAL_P;
    real negative = -2.5;
    real negative_zero = -0.0;
    real fraction = 1.0e-12;
    real zero;
    bit [6:0] guard7 = 7'h55;
    bit [32:0] q33 = 33'h1_0000_0001;
    bit [64:0] bits65 = 65'h1_2345_6789_abcd_ef01;
  } real_s;

  class RealHolder;
    real_s value;
    real_s values[2];
  endclass

  function automatic real local_real_default();
    real_s local_value;
    real result = local_value.value;
    local_value.value = 9.75;
    return result;
  endfunction

  real_s real_value;
  real_s real_values[2];

  initial begin
    begin
      automatic RealHolder holder = new;
      automatic real_s explicit_value = '{3.75, 4.5, -4.25, 0.0, 0.0, 0.0, 7'h00, 33'h0, 65'h0};
      `checkh($realtobits(real_value.value), $realtobits(1.25));
      `checkh($realtobits(real_value.parameterized), $realtobits(1.25));
      `checkh($realtobits(real_values[1].negative), $realtobits(-2.5));
      `checkh($realtobits(real_values[0].negative_zero), 64'h8000_0000_0000_0000);
      `checkh($realtobits(real_value.fraction), $realtobits(1.0e-12));
      `checkh($realtobits(real_value.zero), 64'h0);
      `checkh(real_value.guard7, 7'h55);
      `checkh(real_values[1].q33, 33'h1_0000_0001);
      `checkh(real_values[0].bits65, 65'h1_2345_6789_abcd_ef01);
      `checkh($realtobits(holder.value.value), $realtobits(1.25));
      `checkh($realtobits(holder.values[1].parameterized), $realtobits(1.25));
      `checkh($realtobits(holder.values[0].negative), $realtobits(-2.5));
      `checkh($realtobits(holder.value.negative_zero), 64'h8000_0000_0000_0000);
      `checkh($realtobits(local_real_default()), $realtobits(1.25));
      `checkh($realtobits(local_real_default()), $realtobits(1.25));
      `checkh($realtobits(explicit_value.value), $realtobits(3.75));
      `checkh($realtobits(explicit_value.negative_zero), 64'h0);
      `checkh(explicit_value.guard7, 7'h00);
    end
    $display("%p", s);
    `checkh(s.m_lo, 4'h5);
    `checkh(s.m_mid, ~94'h0);
    `checkh(s.m_hi, 4'h0);
    s.m_mid = 94'ha;
    s.m_hi = 4'hb;
    $display("%p", s);
    `checkh(s.m_lo, 4'h5);
    `checkh(s.m_mid, 94'ha);
    `checkh(s.m_hi, 4'hb);

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
