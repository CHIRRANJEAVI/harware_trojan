`timescale 1ns/1ps

module tb_aes_periodic_bitflip_detect;

  import aes_pkg::*;
  import aes_reg_pkg::*;

  logic clk_i;
  logic rst_ni;

  localparam time CLK_PERIOD = 10ns;

  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  aes_reg2hw_t reg2hw;
  aes_hw2reg_t hw2reg;

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

  // Reference ciphertext
  logic [NumRegsData-1:0][31:0] ref_ct;
  logic ref_valid;

  task automatic reset_env;
    reg2hw = '0;
    ref_valid = 0;
    rst_ni = 0;
    repeat (5) @(posedge clk_i);
    rst_ni = 1;
  endtask

  task automatic start_encrypt;
    reg2hw.ctrl.start.q = 1'b1;
    @(posedge clk_i);
    reg2hw.ctrl.start.q = 1'b0;
  endtask

  task automatic wait_for_output;
    wait (hw2reg.status.output_valid.q);
    @(posedge clk_i);
  endtask

  // -------------------------
  // TEST
  // -------------------------
  initial begin
    clk_i = 0;
    reset_env();

    // Fixed AES config
    reg2hw.ctrl.mode.q = AES_ECB;
    reg2hw.ctrl.op.q   = AES_ENC;

    // Fixed key
    foreach (reg2hw.key_share0[i])
      reg2hw.key_share0[i].q = 32'h01234567;

    // Fixed plaintext
    foreach (reg2hw.data_in[i])
      reg2hw.data_in[i].q = 32'h89ABCDEF;

    $display("🔍 Running repeated identical encryptions...");

    for (int i = 0; i < 300; i++) begin
      start_encrypt();
      wait_for_output();

      if (!ref_valid) begin
        ref_ct = hw2reg.data_out;
        ref_valid = 1;
      end else begin
        if (hw2reg.data_out !== ref_ct) begin
          $fatal(
            "\n🚨 TROJAN DETECTED 🚨\n"
            "Ciphertext mismatch at iteration %0d\n"
            "Expected: %h\n"
            "Observed: %h\n",
            i, ref_ct, hw2reg.data_out
          );
        end
      end
    end

    $display("❌ ERROR: No mismatch detected (unexpected)");
    $finish;
  end

endmodule
