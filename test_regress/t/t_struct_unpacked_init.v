// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv, expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%s exp=%s\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
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

  typedef struct {
    s_t initialized = '{m_lo: 4'h9, m_mid: 94'h123, m_hi: 4'h2};
    s_t ordinary;
    bit [6:0] lanes[2] = '{7'd9, 7'd11};
  } nested_t;
  typedef struct {
    int queue_member[$];
    bit zero;
    bit [6:0] initialized_leaf = 7'd5;
    s_t initialized_nested = '{m_lo: 4'h9, m_mid: 94'h123, m_hi: 4'h2};
    s_t ordinary_nested;
    bit [6:0] initialized_lanes[2] = '{7'd9, 7'd11};
  } unsupported_default_t;

  int calls = 0;
  function automatic int invalid_index();
    calls++;
    return 3;
  endfunction

  initial begin
    s_t fixed_a[3];
    s_t dynamic_a[];
    s_t queue_a[$];
    s_t matrix[2][3];
    s_t copy;
    s_t slice_a[2];
    nested_t nested[3];
    bit [6:0] zeros[3];
    string string_zeros[3];
    real real_zeros[3];
    unsupported_default_t unsupported[2][3];
    unsupported_default_t selected_defaults[3];
    int index;
    int inner_index;
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

    // Nonexistent entries use declaration-initialized member values, not leaf-type zeroes
    // (IEEE 1800-2023 7.4.5, Table 7-1 and 7.2.2).
    dynamic_a = new[3];
    for (int n = 0; n < 3; n++) begin
      fixed_a[n] = '{m_lo: 4'(n + 1), m_mid: 94'(n + 10), m_hi: 4'(n + 5)};
      dynamic_a[n] = fixed_a[n];
      queue_a.push_back(fixed_a[n]);
      nested[n].initialized = fixed_a[n];
      nested[n].ordinary = fixed_a[n];
      nested[n].lanes = '{7'd3, 7'd4};
      zeros[n] = 7'(n + 17);
      selected_defaults[n].initialized_leaf = 7'(n + 1);
      selected_defaults[n].initialized_nested = fixed_a[n];
      selected_defaults[n].ordinary_nested = fixed_a[n];
      selected_defaults[n].initialized_lanes = '{7'd3, 7'd4};
    end
    matrix[0][0] = fixed_a[0];
    for (int step = 0; step < 5; step++) begin
      index = step - 1;
      inner_index = step % 2;
      copy = fixed_a[index];
      slice_a = fixed_a[index+:2];
      if (index < 0 || index >= 3) begin
        `checkh(fixed_a[index].m_lo, P);
        `checkh(fixed_a[index].m_mid, ~94'h0);
        `checkh(fixed_a[index].m_hi, 4'h0);
        `checkh(fixed_a[index].m_lo[2:0], 3'h5);
        `checkh(copy.m_lo, P);
        `checkh(copy.m_mid, ~94'h0);
        `checkh(copy.m_hi, 4'h0);
        `checkh(dynamic_a[index].m_lo, P);
        `checkh(dynamic_a[index].m_mid, ~94'h0);
        `checkh(queue_a[index].m_lo, P);
        `checkh(queue_a[index].m_mid, ~94'h0);
        `checkh(nested[index].initialized.m_lo, 4'h9);
        `checkh(nested[index].initialized.m_mid, 94'h123);
        `checkh(nested[index].initialized.m_hi, 4'h2);
        `checkh(nested[index].ordinary.m_lo, P);
        `checkh(nested[index].ordinary.m_mid, ~94'h0);
        `checkh(nested[index].lanes[inner_index], inner_index == 0 ? 7'd9 : 7'd11);
        `checkh(zeros[index], 7'd0);
        // Unrelated queue storage must not hide an initialized selected member.
        `checkh(selected_defaults[index].initialized_leaf, 7'd5);
        `checkh(selected_defaults[index].initialized_leaf[2:0], 3'h5);
        `checkh(selected_defaults[index].initialized_nested.m_lo, 4'h9);
        `checkh(selected_defaults[index].initialized_nested.m_mid, 94'h123);
        `checkh(selected_defaults[index].ordinary_nested.m_lo, P);
        `checkh(selected_defaults[index].initialized_lanes[inner_index],
                inner_index == 0 ? 7'd9 : 7'd11);
        `checks(string_zeros[index], "");
        `checkh($realtobits(real_zeros[index]), 64'd0);
        fixed_a[index].m_lo = 4'hf;
        dynamic_a[index].m_lo = 4'hf;
        selected_defaults[index].initialized_leaf = 7'd63;
        `checkh(selected_defaults[0].initialized_leaf, 7'd1);
        `checkh(selected_defaults[index].initialized_leaf, 7'd5);
        // Queue [$+1] writes append; only the negative index is a no-op.
        if (index < 0) queue_a[index].m_lo = 4'hf;
        `checkh(fixed_a[0].m_lo, 4'h1);
        `checkh(dynamic_a[0].m_lo, 4'h1);
        `checkh(queue_a[0].m_lo, 4'h1);
        `checkh(queue_a.size(), 3);
        `checkh(fixed_a[index].m_lo, P);
        `checkh(dynamic_a[index].m_lo, P);
        `checkh(queue_a[index].m_lo, P);
      end
      else begin
        `checkh(fixed_a[index].m_lo, 4'(index + 1));
        `checkh(copy.m_mid, 94'(index + 10));
        `checkh(copy.m_hi, 4'(index + 5));
        `checkh(dynamic_a[index].m_lo, 4'(index + 1));
        `checkh(queue_a[index].m_lo, 4'(index + 1));
        `checkh(nested[index].initialized.m_lo, 4'(index + 1));
        `checkh(nested[index].lanes[inner_index], inner_index == 0 ? 7'd3 : 7'd4);
        `checkh(zeros[index], 7'(index + 17));
        `checkh(selected_defaults[index].initialized_leaf, 7'(index + 1));
        `checkh(selected_defaults[index].initialized_nested.m_lo, 4'(index + 1));
        `checkh(selected_defaults[index].initialized_lanes[inner_index],
                inner_index == 0 ? 7'd3 : 7'd4);
      end
      if (index == 0 || index == 1) begin
        `checkh(slice_a[0].m_lo, 4'(index + 1));
        `checkh(slice_a[1].m_lo, 4'(index + 2));
      end
      else begin
        `checkh(slice_a[0].m_lo, P);
        `checkh(slice_a[1].m_lo, P);
        `checkh(slice_a[0].m_mid, ~94'h0);
        `checkh(slice_a[1].m_mid, ~94'h0);
      end
    end
    index = 2;
    inner_index = 0;
    `checkh(matrix[index][inner_index].m_lo, P);
    `checkh(matrix[index][inner_index].m_mid, ~94'h0);
    // Preserve the existing scalar fallback when a containing aggregate has no
    // representable queue default in this builder; this does not add queue-value support.
    `checkh(unsupported[index][inner_index].zero, 1'b0);
    index = 0;
    inner_index = 3;
    `checkh(matrix[index][inner_index].m_lo, P);
    `checkh(fixed_a[invalid_index()].m_lo, P);
    `checkh(calls, 1);

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
