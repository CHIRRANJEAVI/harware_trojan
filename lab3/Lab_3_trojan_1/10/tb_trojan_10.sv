`timescale 1ns/1ps

module tb_aes_output_valid_width_check;

  import aes_pkg::*;
  import aes_reg_pkg::*;

  logic clk_i;
  logic rst_ni;

  localparam time CLK_PERIOD = 10ns;

  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // DUT signals
  aes_reg2hw_t reg2hw;
  aes_hw2reg_t hw2reg;

  logic alert_recov_o, alert_fatal_o;

  aes_core dut (
    .clk_i,
    .rst_ni,
    .rst_shadowed_ni(rst_ni),
    .entropy_clearing_req_o(),
    .entropy_clearing_ack_i(1'b0),
    .entropy_clearing_i('0),
    .entropy_masking_req_o(),
    .entropy_masking_ack_i(1'b0),
    .entropy_masking_i('0),
    .keymgr_key_i('0),
    .lc_escalate_en_i('0),
    .shadowed_storage_err_i(1'b0),
    .shadowed_update_err_i(1'b0),
    .intg_err_alert_i(1'b0),
    .alert_recov_o(alert_recov_o),
    .alert_fatal_o(alert_fatal_o),
    .reg2hw(reg2hw),
    .hw2reg(hw2reg)
  );

  // -------------------------
  // Pulse width measurement
  // -------------------------
  int pulse_widths[$];
  int curr_width;
  bit measuring;

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      measuring  <= 0;
      curr_width <= 0;
    end else begin
      if (hw2reg.status.output_valid.q) begin
        measuring  <= 1;
        curr_width <= curr_width + 1;
      end else if (measuring) begin
        pulse_widths.push_back(curr_width);
        measuring  <= 0;
        curr_width <= 0;
      end
    end
  end

  task automatic reset_env;
    reg2hw = '0;
    pulse_widths.delete();
    rst_ni = 0;
    repeat (5) @(posedge clk_i);
    rst_ni = 1;
  endtask

  task automatic run_encryptions(int count);
    repeat (count) begin
      reg2hw.ctrl.start.q = 1'b1;
      @(posedge clk_i);
      reg2hw.ctrl.start.q = 1'b0;
      wait (hw2reg.status.output_valid.q);
      wait (!hw2reg.status.output_valid.q);
    end
  endtask

  function automatic bit has_width_jitter();
    foreach (pulse_widths[i]) begin
      if (pulse_widths[i] != pulse_widths[0])
        return 1;
    end
    return 0;
  endfunction

  // -------------------------
  // TEST
  // -------------------------
  initial begin
    clk_i = 0;

    // -------------------------
    // Baseline
    // -------------------------
    reset_env();

    reg2hw.ctrl.mode.q = AES_ECB;
    reg2hw.ctrl.op.q   = AES_ENC;

    // Normal key
    foreach (reg2hw.key_share0[i])
      reg2hw.key_share0[i].q = 32'h00000000;

    run_encryptions(5);

    if (has_width_jitter())
      $fatal("❌ Jitter detected in baseline — design unstable");

    $display("✅ Baseline pulse width stable");

    // -------------------------
    // Trojan trigger attempt
    // -------------------------
    reset_env();

    reg2hw.ctrl.mode.q = AES_ECB;
    reg2hw.ctrl.op.q   = AES_ENC;

    // Trojan trigger key
    foreach (reg2hw.key_share0[i])
      reg2hw.key_share0[i].q = 32'hA5A5A5A5;

    run_encryptions(6);

    if (!has_width_jitter())
      $fatal("❌ No pulse-width jitter detected — Trojan NOT detected");

    $display("🚨 TROJAN DETECTED: output_valid pulse width modulated");

    $finish;
  end

endmodule
