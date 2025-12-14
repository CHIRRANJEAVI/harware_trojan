`timescale 1ns/1ps

module tb_aes_replay_detection;

  import aes_pkg::*;
  import aes_reg_pkg::*;

  logic clk_i, rst_ni;
  aes_reg2hw_t reg2hw;
  aes_hw2reg_t hw2reg;

  localparam time CLK = 10ns;
  always #(CLK/2) clk_i = ~clk_i;

  // DUT
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
    .alert_recov_o(),
    .alert_fatal_o(),
    .reg2hw(reg2hw),
    .hw2reg(hw2reg)
  );

  logic [NumRegsData-1:0][31:0] prev_ct;
  bit prev_valid;

  task reset_dut;
    reg2hw = '0;
    prev_valid = 0;
    rst_ni = 0;
    repeat (5) @(posedge clk_i);
    rst_ni = 1;
  endtask

  task start_encrypt;
    reg2hw.trigger.start.q = 1'b1;
    @(posedge clk_i);
    reg2hw.trigger.start.q = 1'b0;
  endtask

  task wait_done;
    wait (hw2reg.status.output_valid.q);
    @(posedge clk_i);
  endtask

  initial begin
    clk_i = 0;
    reset_dut();

    // Fixed key
    foreach (reg2hw.key_share0[i])
      reg2hw.key_share0[i].q = 32'h01234567;

    // AES configuration
    reg2hw.ctrl.op.q   = AES_ENC;
    reg2hw.ctrl.mode.q = AES_ECB;

    $display("🔍 Running AES ciphertext replay detection test...");

    for (int i = 0; i < 500; i++) begin
      // Different plaintext each iteration
      foreach (reg2hw.data_in[j])
        reg2hw.data_in[j].q = i * 32'h01010101 + j;

      start_encrypt();
      wait_done();

      if (prev_valid) begin
        if (hw2reg.data_out === prev_ct) begin
          $fatal(
            "\n🚨 AES TROJAN DETECTED 🚨\n"
            "Ciphertext replay detected!\n"
            "Iteration: %0d\n"
            "Ciphertext: %h\n",
            i, hw2reg.data_out
          );
        end
      end

      prev_ct    = hw2reg.data_out;
      prev_valid = 1'b1;
    end

    $display("❌ ERROR: No replay detected (unexpected)");
    $finish;
  end

endmodule
