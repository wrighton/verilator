// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A defparam in a generate block gives its value only if the block is built, also to an instance
// outside the block

module leaf #(
    parameter int P = 61
);
endmodule

module mid;
  leaf u_leaf ();
endmodule

module wrap #(
    parameter int PICK = 0
);
  // Instance before and after the block
  leaf u_before ();
  if (PICK == 1) begin : g_if
    defparam u_before.P = 7;
    defparam u_after.P = 8;
  end
  leaf u_after ();

  // In a case generate
  leaf u_case ();
  case (PICK)
    1: begin : g_case
      defparam u_case.P = 9;
    end
    default: ;
  endcase

  // Two in one block: the last one in the source text
  leaf u_two ();
  if (PICK == 1) begin : g_two
    defparam u_two.P = 10;
    defparam u_two.P = 11;
  end

  // Two loop iterations: the last one
  leaf u_for ();
  for (genvar i = 0; i < PICK * 2; ++i) begin : g_for
    defparam u_for.P = 20 + i;
  end
  leaf u_for2 ();
  for (genvar i = 0; i < PICK; ++i) begin : g_for2
    defparam u_for2.P = 30;
    defparam u_for2.P = 31;
  end

  // With one outside the block, after and before it
  leaf u_mix_after ();
  if (PICK == 1) begin : g_mix_after
    defparam u_mix_after.P = 2;
    defparam u_mix_after.P = 3;
  end
  defparam u_mix_after.P = 4;
  leaf u_mix_before ();
  defparam u_mix_before.P = 4;
  if (PICK == 1) begin : g_mix_before
    defparam u_mix_before.P = 2;
    defparam u_mix_before.P = 3;
  end

  // To an instance in another generate block
  if (1) begin : g_other
    leaf u_in ();
  end
  if (PICK == 1) begin : g_to_other
    defparam g_other.u_in.P = 12;
  end

  // In each branch, to an instance in the branch
  if (PICK == 1) begin : g_in1
    mid u_mid ();
    defparam u_mid.u_leaf.P = 15;
  end
  else begin : g_in0
    mid u_mid ();
    defparam u_mid.u_leaf.P = 16;
  end

  // Two blocks, one built
  leaf u_branch ();
  if (PICK == 1) begin : g_one
    defparam u_branch.P = 13;
  end
  else begin : g_zero
    defparam u_branch.P = 14;
  end
endmodule

module t;
  wrap #(.PICK(0)) u0 ();
  wrap #(.PICK(1)) u1 ();

  initial begin
    `checkd(u0.u_before.P, 61);
    `checkd(u1.u_before.P, 7);
    `checkd(u0.u_after.P, 61);
    `checkd(u1.u_after.P, 8);
    `checkd(u0.u_case.P, 61);
    `checkd(u1.u_case.P, 9);
    `checkd(u0.u_two.P, 61);
    `checkd(u1.u_two.P, 11);
    `checkd(u0.u_for.P, 61);
    `checkd(u1.u_for.P, 21);
    `checkd(u0.u_for2.P, 61);
    `checkd(u1.u_for2.P, 31);
    `checkd(u0.g_in0.u_mid.u_leaf.P, 16);
    `checkd(u1.g_in1.u_mid.u_leaf.P, 15);
    `checkd(u0.u_mix_after.P, 4);
    `checkd(u1.u_mix_after.P, 4);
    `checkd(u0.u_mix_before.P, 4);
    `checkd(u1.u_mix_before.P, 3);
    `checkd(u0.g_other.u_in.P, 61);
    `checkd(u1.g_other.u_in.P, 12);
    `checkd(u0.u_branch.P, 14);
    `checkd(u1.u_branch.P, 13);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
