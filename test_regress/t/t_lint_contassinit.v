// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%h exp=%h (%s !== %s)\n", `__FILE__, `__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

package contassinit_pkg;
  timeunit 1ns; timeprecision 1ps;
  localparam int TILE = 0;
  localparam int VISIBILITY = 1;
endpackage

interface trigger_sink (
    input clk,
    input triggers[3]
);
  wire [2:0] seen = {triggers[2], triggers[1], triggers[0]};
endinterface

module t;
  timeunit 1ns; timeprecision 1ps;
  bit clk = 0;
  always #5 clk = ~clk;
  bit valid, ready, end_of_tile;
  event visibility_ev, render_ev;
  logic original[3];
  logic scalar_end, scalar_visibility, scalar_render;

  trigger_sink original_sink (
      clk,
      original
  );
  trigger_sink scalar_sink (
      clk,
      '{0: scalar_end, 1: scalar_visibility, 2: scalar_render, default: 1'b0}
  );
  assign original[0] = valid && ready && end_of_tile;
  assign scalar_end = valid && ready && end_of_tile;
  initial
    forever begin
      original[1] = 0;
      @visibility_ev;
      original[1] = 1;
      @(posedge clk);
    end
  initial
    forever begin
      original[2] = 0;
      @render_ev;
      original[2] = 1;
      @(posedge clk);
    end
  initial
    forever begin
      scalar_visibility = 0;
      @visibility_ev;
      scalar_visibility = 1;
      @(posedge clk);
    end
  initial
    forever begin
      scalar_render = 0;
      @render_ev;
      scalar_render = 1;
      @(posedge clk);
    end

  // Typedef, descending outer and ascending inner ranges, with nonzero bounds.
  typedef logic matrix_t[3:1][5:7];
  matrix_t matrix;
  assign matrix[3][5] = scalar_end;
  initial
    forever begin
      matrix[1][6] = 0;
      @visibility_ev;
      matrix[1][6] = 1;
      @(posedge clk);
    end
  // A dynamic inner select covers only its static outer row, not matrix[3].
  initial begin
    for (int i = 5; i <= 7; ++i) matrix[2][i] = 1'b0;
  end

  // Ascending outer and descending inner ranges, including negative bounds.
  logic reverse_axes[7:9][-2:-4];
  assign reverse_axes[9][-2] = scalar_end;
  initial
    forever begin
      reverse_axes[7][-3] = 0;
      @render_ev;
      reverse_axes[7][-3] = 1;
      @(posedge clk);
    end

  // Distinct unpacked fields within the same array element remain independent.
  typedef struct {
    logic x;
    logic y;
  } fields_t;
  typedef fields_t fields_alias_t;
  fields_alias_t fields[3];
  assign fields[1].x = scalar_end;
  initial
    forever begin
      fields[1].y = 0;
      @visibility_ev;
      fields[1].y = 1;
      @(posedge clk);
    end

  // The same independent-field rule applies when an unpacked struct is the root.
  fields_alias_t root_fields;
  assign root_fields.x = scalar_end;
  initial
    forever begin
      root_fields.y = 0;
      @visibility_ev;
      root_fields.y = 1;
      @(posedge clk);
    end

  typedef struct {
    logic elements[3];
    logic side;
  } nested_t;
  nested_t root_nested;
  assign root_nested.elements[0] = scalar_end;
  initial
    forever begin
      root_nested.elements[1] = 0;
      @visibility_ev;
      root_nested.elements[1] = 1;
      @(posedge clk);
    end
  initial
    forever begin
      root_nested.elements[2] = 0;
      @render_ev;
      root_nested.elements[2] = 1;
      @(posedge clk);
    end
  initial root_nested.side = 0;

  // Unsigned two-bit 3 is a valid element, unlike signed two-bit -1.
  logic narrow_index[4];
  assign narrow_index[0] = scalar_end;
  initial narrow_index[2'b11] = 0;

  // A whole packed root has one continuous driver, not unpacked-prefix tracking.
  typedef struct packed {
    logic [4:0] left;
    logic [6:0] right;
  } packed_root_t;
  packed_root_t packed_root;
  assign packed_root = '{left: {5{valid}}, right: {7{ready}}};

  int checks;
  task automatic check(input bit [2:0] expected);
    #1;
    `checkh(original_sink.seen, expected);
    `checkh(scalar_sink.seen, expected);
    `checkh(matrix[3][5], expected[0]);
    `checkh(matrix[1][6], expected[1]);
    `checkh(matrix[2][5], 1'b0);
    `checkh(matrix[2][6], 1'b0);
    `checkh(matrix[2][7], 1'b0);
    `checkh(reverse_axes[9][-2], expected[0]);
    `checkh(reverse_axes[7][-3], expected[2]);
    `checkh(fields[1].x, expected[0]);
    `checkh(fields[1].y, expected[1]);
    `checkh(root_fields.x, expected[0]);
    `checkh(root_fields.y, expected[1]);
    `checkh(root_nested.elements[0], expected[0]);
    `checkh(root_nested.elements[1], expected[1]);
    `checkh(root_nested.elements[2], expected[2]);
    `checkh(root_nested.side, 1'b0);
    `checkh(narrow_index[0], expected[0]);
    `checkh(narrow_index[3], 1'b0);
    `checkh(packed_root.left, {5{valid}});
    `checkh(packed_root.right, {7{ready}});
    checks++;
  endtask

  initial begin
    check(3'b000);
    valid = 1;
    ready = 1;
    end_of_tile = 1;
    check(3'b001);
    ready = 0;
    check(3'b000);
    for (int i = 0; i < 10; ++i) begin
      @(negedge clk);
      ->visibility_ev;
      check(3'b010);
      @(posedge clk);
      check(3'b000);
      @(negedge clk);
      ->render_ev;
      check(3'b100);
      @(posedge clk);
      check(3'b000);
      @(negedge clk);
      ready = 1;
      ->visibility_ev; ->render_ev;
      check(3'b111);
      @(posedge clk);
      check(3'b001);
      ready = 0;
      check(3'b000);
    end
    `checkh(checks, 73);
    $display("PASS original array and scalar-pattern inputs: %0d settled checks", checks);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // Test: parameter indices select disjoint elements, as literal indices do
  localparam int RENDER = 2;
  logic param_triggers[3];
  assign param_triggers[contassinit_pkg::TILE] = end_of_tile;
  initial
    forever begin
      param_triggers[contassinit_pkg::VISIBILITY] = 1'b1;
      param_triggers[RENDER] = 1'b0;
      @(posedge clk);
    end
  initial begin
    // The source changes at time 1, so observe once its continuous value has settled
    #2;
    `checkh(param_triggers[0], end_of_tile);
    `checkh(param_triggers[1], 1'b1);
    `checkh(param_triggers[2], 1'b0);
  end

  // Test: parameter indices of nonzero-based ascending and descending ranges
  localparam int FIRST = 7;
  logic ascending_triggers[7:9];
  assign ascending_triggers[FIRST] = end_of_tile;
  initial begin
    ascending_triggers[FIRST+1] = 1'b1;
    ascending_triggers[FIRST+2] = 1'b0;
    #2;
    `checkh(ascending_triggers[7], end_of_tile);
    `checkh(ascending_triggers[8], 1'b1);
    `checkh(ascending_triggers[9], 1'b0);
  end
  logic descending_triggers[9:7];
  assign descending_triggers[FIRST] = end_of_tile;
  initial begin
    descending_triggers[FIRST+1] = 1'b1;
    descending_triggers[FIRST+2] = 1'b0;
    #2;
    `checkh(descending_triggers[7], end_of_tile);
    `checkh(descending_triggers[8], 1'b1);
    `checkh(descending_triggers[9], 1'b0);
  end

  // Test: unary and conditional operators of parameters fold as constants
  localparam int NEG = -1;
  localparam bit USE_LAST = 1'b1;
  logic operator_triggers[3];
  assign operator_triggers[USE_LAST ? 2 : 0] = end_of_tile;
  initial begin
    operator_triggers[-NEG] = 1'b1;
    #2;
    `checkh(operator_triggers[1], 1'b1);
    `checkh(operator_triggers[2], end_of_tile);
  end
endmodule
